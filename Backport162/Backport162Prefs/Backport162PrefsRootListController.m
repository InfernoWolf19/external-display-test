// The Settings pane of Backport162: two text fields, two buttons. UI only; SpringBoard (RPT.x) does the work.
//
// Rules this file follows (it lives inside Preferences.app, a bug here must never take Settings down):
//   * every entry point is wrapped in @try, nothing is force unwrapped, a failure ends in an alert or in nothing, never in a crash;
//   * all UI work is on the main thread (Darwin notifications are delivered on the main queue, timers are main queue blocks);
//   * blocks capture a weak self only; the Darwin observer is cancelled in viewDidDisappear and dealloc;
//   * one request at a time (_busy), one answer per request (_run generation + the _busy test in the handlers);
//   * the token is only ever read from the preferences to test that it is not empty. It is never logged, never shown, never copied anywhere.
//
// Protocol (RPT.x header and specs/SEND-LOGS-0.7.9.md):
//   post  com.infernowolf19.backport162.report.request   (no data; ".request.local" for "Share instead": SpringBoard then never uploads)
//   wait  com.infernowolf19.backport162.report.done      (170 s), then read reportStatus / reportMessage / reportID / reportURL / reportFile / reportTime from CFPreferences.
#import "Backport162PrefsRootListController.h"
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>
#import <time.h>

#define BP_DOMAIN CFSTR("com.infernowolf19.backport162")
static const char kBPRequestName[] = "com.infernowolf19.backport162.report.request";
static const char kBPLocalName[]   = "com.infernowolf19.backport162.report.request.local";     // "Share instead": same job, SpringBoard never uploads
static const char kBPDoneName[]    = "com.infernowolf19.backport162.report.done";
// SpringBoard needs < 10 s to collect and at most 130 s for the upload (RPT.x: semaphore); 170 s leaves a margin for a slow disk.
static const NSTimeInterval kBPWaitSeconds = 170.0;

// ---------------------------------------------------------------- preferences access (CFPreferences, same domain as the fields' `defaults` key)

// Copy of a preference value, or nil. CFBridgingRelease hands the +1 of CFPreferencesCopyAppValue to ARC.
static id BPPrefObject(NSString *key) {
    if (key.length == 0) return nil;
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, BP_DOMAIN);
    return v ? CFBridgingRelease(v) : nil;
}
static NSString *BPPrefString(NSString *key) {
    id v = BPPrefObject(key);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}
static NSString *BPTrimmed(NSString *s) {
    return [(s ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// owner/name, both parts [A-Za-z0-9_.-]+ (same test as RPT.x; SpringBoard validates again, this one only gives the early message).
static BOOL BPValidRepo(NSString *repo) {
    if (repo.length < 3 || repo.length > 200) return NO;
    BOOL slash = NO;
    NSUInteger partLen = 0, dots = 0;
    for (NSUInteger i = 0; i < repo.length; i++) {
        unichar c = [repo characterAtIndex:i];
        if (c == '/') {
            if (slash || partLen == 0 || dots == partLen) return NO;
            slash = YES; partLen = 0; dots = 0;
            continue;
        }
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '.' || c == '-';
        if (!ok) return NO;
        partLen++;
        if (c == '.') dots++;
    }
    return slash && partLen > 0 && dots != partLen;
}

// A report file Settings may offer to share: where SpringBoard puts them, readable by this process, not empty, not huge. (The path comes from a preference: do not trust it blindly.)
static BOOL BPShareableFile(NSString *path) {
    if (path.length == 0 || path.length > 1000) return NO;
    if ([path rangeOfString:@"/../"].location != NSNotFound || [path hasSuffix:@"/.."]) return NO;
    if ([path rangeOfString:@"/Backport162Reports/report-"].location == NSNotFound || ![path hasSuffix:@".txt.gz"]) return NO;
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) return NO;
    if (st.st_size <= 0 || st.st_size > 16 * 1024 * 1024) return NO;
    return access(path.fileSystemRepresentation, R_OK) == 0;
}

// ---------------------------------------------------------------- the controller

@implementation Backport162PrefsRootListController {
    BOOL _busy;                   // a request is in flight (set at the tap, cleared by an answer / timeout / leaving the pane)
    BOOL _shareOnly;              // the request was made with "Share instead": an answer with a report file goes straight to the share sheet
    BOOL _observing;
    BOOL _loadingSpecifiers;      // re-entrancy guard of -specifiers (setSpecifiers: may ask for them again)
    int _notifyToken;
    NSUInteger _run;              // generation: a timeout / answer of an older request is ignored
    double _requestTime;          // seconds since 1970 at the request; an answer older than that (reportTime) is a leftover
    UIActivityIndicatorView *_spinner;
}

- (NSArray *)specifiers {
    NSArray *s = nil;
    if (_loadingSpecifiers) return @[];
    @try {
        s = [super specifiers];
        if (s.count == 0) {
            _loadingSpecifiers = YES;
            s = [self loadSpecifiersFromPlistName:@"Root" target:self];
            if (s.count > 0) [self setSpecifiers:s];
        }
    } @catch (NSException *e) {
        s = nil;
    }
    _loadingSpecifiers = NO;
    return s ?: @[];          // an empty pane is better than a crash of Settings
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    @try {
        if (_busy) [self bp_finishWaitingRestoreUI];       // the job keeps running in SpringBoard; its answer is kept in the preferences ("Share last report...")
        [self bp_stopObserving];
    } @catch (NSException *e) {}
}

- (void)dealloc {
    if (_observing) { notify_cancel(_notifyToken); _observing = NO; }       // dealloc: no UI, no messages to self
}

// ---------------------------------------------------------------- actions (selectors named in Root.plist, 'action' key)

- (void)sendLogsNow:(id)sender {
    @try {
        if (![NSThread isMainThread]) {
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf sendLogsNow:sender]; });
            return;
        }
        if (_busy) return;                                  // double tap
        _busy = YES;
        [self.view endEditing:YES];                         // commit the text field that is still being edited
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf bp_validateAndStart]; });      // next turn of the run loop: the field has stored its text
    } @catch (NSException *e) {
        _busy = NO;
    }
}

- (void)shareLastReport:(id)sender {
    @try {
        if (_busy) return;
        CFPreferencesAppSynchronize(BP_DOMAIN);
        NSString *file = BPPrefString(@"reportFile");
        if (!BPShareableFile(file)) {
            [self bp_alertTitle:@"No report to share" message:@"There is no report on this device yet (or Settings cannot read it). Press Send logs now first." actions:nil];
            return;
        }
        [self bp_shareFile:file];
    } @catch (NSException *e) {}
}

// ---------------------------------------------------------------- starting a request

- (void)bp_validateAndStart {
    @try {
        if (!_busy) return;
        CFPreferencesAppSynchronize(BP_DOMAIN);
        NSString *repo = BPTrimmed(BPPrefString(@"reportRepo"));
        NSString *token = BPTrimmed(BPPrefString(@"reportToken"));
        NSString *problem = nil;
        if (repo.length == 0 || token.length == 0) problem = @"Repository (owner/name) and Token are not both filled in.";
        else if (!BPValidRepo(repo)) problem = @"The repository must look like owner/name (letters, digits, - _ . only).";
        token = nil;
        if (problem) {
            _busy = NO;
            __weak typeof(self) weakSelf = self;
            UIAlertAction *share = [UIAlertAction actionWithTitle:@"Share instead" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                typeof(self) s = weakSelf;
                if (s && !s->_busy) { s->_busy = YES; [s bp_beginShareOnly:YES]; }
            }];
            [self bp_alertTitle:@"Cannot upload" message:[problem stringByAppendingString:@" You can still collect the report on the device and share it by hand."] actions:@[share]];
            return;
        }
        [self bp_beginShareOnly:NO];
    } @catch (NSException *e) {
        _busy = NO;
    }
}

// _busy is YES on entry. Observer first, then the request, so the answer cannot be missed.
- (void)bp_beginShareOnly:(BOOL)shareOnly {
    @try {
        _shareOnly = shareOnly;
        _requestTime = (double)time(NULL);
        NSUInteger run = ++_run;
        [self bp_setWaitingUI:YES];
        if (![self bp_startObserving]) {
            [self bp_finishWaitingRestoreUI];
            [self bp_alertTitle:@"Cannot send" message:@"Settings could not listen for the answer of SpringBoard." actions:nil];
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBPWaitSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) s = weakSelf;
            if (s && s->_busy && s->_run == run) [s bp_timeout];
        });
        (void)notify_post(shareOnly ? kBPLocalName : kBPRequestName);
    } @catch (NSException *e) {
        [self bp_finishWaitingRestoreUI];
    }
}

- (BOOL)bp_startObserving {
    if (_observing) return YES;
    __weak typeof(self) weakSelf = self;
    uint32_t st = notify_register_dispatch(kBPDoneName, &_notifyToken, dispatch_get_main_queue(), ^(int token) {
        [weakSelf bp_didReceiveDone];
    });
    _observing = (st == NOTIFY_STATUS_OK);
    return _observing;
}

- (void)bp_stopObserving {
    if (!_observing) return;
    notify_cancel(_notifyToken);
    _observing = NO;
}

// ---------------------------------------------------------------- the answer

// The result keys, or nil when there is no answer newer than the request.
- (NSDictionary *)bp_freshResult {
    CFPreferencesAppSynchronize(BP_DOMAIN);
    id t = BPPrefObject(@"reportTime");
    double when = [t isKindOfClass:[NSNumber class]] ? [t doubleValue] : 0;
    if (when + 1.0 < _requestTime) return nil;                // left over from an earlier request
    NSString *status = BPPrefString(@"reportStatus");
    if (status.length == 0) return nil;
    NSMutableDictionary *r = [NSMutableDictionary dictionary];
    r[@"status"] = status;
    NSString *v;
    if ((v = BPPrefString(@"reportMessage"))) r[@"message"] = v;
    if ((v = BPPrefString(@"reportID"))) r[@"id"] = v;
    if ((v = BPPrefString(@"reportURL"))) r[@"url"] = v;
    if ((v = BPPrefString(@"reportFile"))) r[@"file"] = v;
    return r;
}

- (void)bp_didReceiveDone {
    @try {
        if (!_busy) return;                                   // twice, or after a timeout / leaving the pane
        NSDictionary *r = [self bp_freshResult];
        if (!r) return;                                       // an older job's answer: keep waiting
        [self bp_finishWaitingRestoreUI];
        [self bp_presentResult:r];
    } @catch (NSException *e) {
        [self bp_finishWaitingRestoreUI];
    }
}

- (void)bp_timeout {
    @try {
        if (!_busy) return;
        NSDictionary *r = [self bp_freshResult];               // the notification may have been held back while Settings was in the background
        [self bp_finishWaitingRestoreUI];
        if (r) { [self bp_presentResult:r]; return; }
        [self bp_alertTitle:@"No answer" message:@"SpringBoard did not answer: is Backport162 loaded? Respring and try again." actions:nil];
    } @catch (NSException *e) {
        [self bp_finishWaitingRestoreUI];
    }
}

- (void)bp_presentResult:(NSDictionary *)r {
    NSString *status = r[@"status"], *message = r[@"message"] ?: @"", *rid = r[@"id"], *file = r[@"file"];
    BOOL shareable = BPShareableFile(file);
    __weak typeof(self) weakSelf = self;
    if ([status isEqualToString:@"ok"] && rid.length > 0) {
        NSString *body = [NSString stringWithFormat:@"Tell the assistant this report id:\n%@\n\n%@", rid, message];
        UIAlertAction *copy = [UIAlertAction actionWithTitle:@"Copy id" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            @try { [UIPasteboard generalPasteboard].string = rid; } @catch (NSException *e) {}
        }];
        [self bp_alertTitle:[NSString stringWithFormat:@"Report %@ sent", rid] message:body actions:@[copy]];
        return;
    }
    if (_shareOnly && shareable) { [self bp_shareFile:file]; return; }        // "Share instead": the report is what was asked for
    NSMutableArray *actions = [NSMutableArray array];
    if (shareable) {
        [actions addObject:[UIAlertAction actionWithTitle:@"Share report…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf bp_shareFile:file];
        }]];
    }
    NSString *body = message.length ? message : @"The report could not be sent.";
    if (rid.length) body = [body stringByAppendingFormat:@"\n\nReport id: %@", rid];
    [self bp_alertTitle:@"Report not sent" message:body actions:actions];
}

// ---------------------------------------------------------------- UI helpers (main thread)

// Spinner in the navigation bar + the Send button greyed out and renamed. All of it is optional decoration: any failure is swallowed.
- (void)bp_setWaitingUI:(BOOL)waiting {
    @try {
        if (waiting) {
            if (!_spinner) _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [_spinner startAnimating];
            self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_spinner];
        } else {
            [_spinner stopAnimating];
            self.navigationItem.rightBarButtonItem = nil;
        }
        PSSpecifier *send = [self specifierForID:@"BP162_SEND"];
        if (send) {
            [send setProperty:@(!waiting) forKey:@"enabled"];
            [send setName:waiting ? @"Working…" : @"Send logs now"];
            [self reloadSpecifier:send animated:NO];
        }
    } @catch (NSException *e) {}
}

// Ends the waiting state: no pending timeout/answer can match this request any more.
- (void)bp_finishWaitingRestoreUI {
    _busy = NO;
    _run++;
    [self bp_stopObserving];
    [self bp_setWaitingUI:NO];
}

// The controller to present from: the top of the presented chain, an alert in the way is dismissed first. nil when the pane is not on screen.
- (UIViewController *)bp_presenter {
    if (!self.viewIfLoaded.window) return nil;
    UIViewController *v = self;
    for (int i = 0; i < 8 && v.presentedViewController; i++) {
        if ([v.presentedViewController isKindOfClass:[UIAlertController class]]) { [v dismissViewControllerAnimated:NO completion:nil]; break; }
        v = v.presentedViewController;
    }
    return v;
}

- (void)bp_alertTitle:(NSString *)title message:(NSString *)message actions:(NSArray<UIAlertAction *> *)extra {
    @try {
        UIViewController *p = [self bp_presenter];
        if (!p) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        for (UIAlertAction *x in extra) [a addAction:x];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [p presentViewController:a animated:YES completion:nil];
    } @catch (NSException *e) {}
}

// Share sheet for the report. The file is copied into Settings' own temporary directory first: the share extensions cannot read the jailbreak root.
// On the iPad the sheet is a popover and MUST have a source (a missing source raises an exception that would take Settings down).
- (void)bp_shareFile:(NSString *)path {
    @try {
        if (!BPShareableFile(path)) return;
        UIViewController *p = [self bp_presenter];
        if (!p) return;
        NSString *use = path;
        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:[path lastPathComponent]];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:copy error:NULL];
        if ([fm copyItemAtPath:path toPath:copy error:NULL]) use = copy;
        NSURL *url = [NSURL fileURLWithPath:use];
        if (!url) return;
        UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
        UIPopoverPresentationController *pop = avc.popoverPresentationController;
        if (pop) {
            CGRect b = self.view.bounds;
            pop.sourceView = self.view;
            pop.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMidY(b), 1.0, 1.0);
            pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        [p presentViewController:avc animated:YES completion:nil];
    } @catch (NSException *e) {}
}

@end
