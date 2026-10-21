// RPT.x : "Send logs", SpringBoard half. Spec: specs/SEND-LOGS-0.7.9.md. Switch: report (kill switch file Backport162.off.report). Setup: RPT_Setup().
// No hooks (plain C / Objective-C, no Logos groups): the Settings pane (Backport162Prefs bundle) only asks, this file does the work.
//
// Protocol (nothing carries data, the answer travels through CFPreferences):
//   Settings  --Darwin notification com.infernowolf19.backport162.report.request-->  SpringBoard (this file)
//   SpringBoard collects, gzips, writes <jbroot>/var/mobile/Library/Caches/Backport162Reports/report-<id>.txt.gz, uploads it to GitHub (only when the user typed a repository + token),
//   then writes the keys reportStatus (ok | error), reportMessage, reportID, reportURL, reportFile, reportTime into the domain com.infernowolf19.backport162
//   (kCFPreferencesCurrentUser, kCFPreferencesAnyHost) and posts com.infernowolf19.backport162.report.done.
// NOTHING runs without that request, i.e. without the user pressing "Send logs now". The token is read from the preferences at the moment of the upload and is never logged, never stored in
// the report, never published.
//
// Guards, in the order of the job (each says what it protects against):
//   * the request is handled on the main queue only to test an atomic flag and hop to a private serial queue: SpringBoard's main thread never reads files or waits for the network;
//   * gRPTRunning (atomic): a second request while a job runs is ignored, the first job's "done" answers both (Settings has its own double-tap guard);
//   * gRPTSerial: RPT_Finish publishes + clears the flag exactly once per job, even if an exception escapes after it ran (a stale second call must not clear the flag of a NEWER job);
//   * switch + 5 s rate limit: answered as an error (Settings never waits for nothing);
//   * every file read is capped, every read treats errors as data ("(cannot read: errno N)" in the section) and never throws;
//   * the whole job is inside @try/@finally: whatever happens Settings gets an answer and the flag is cleared;
//   * the upload is ONE NSURLSession task with a completion handler on its own queue, waited for with a 130 s semaphore timeout on the private queue (never the main thread).

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <notify.h>
#import <zlib.h>
#import <stdatomic.h>
#import <mach-o/dyld.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <fcntl.h>
#import <dirent.h>
#import <errno.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>
#import "BP.h"
#import "BPDaemon.h"      // kBPDWDirs / BPDW_FILE: the directories the daemon halves write Backport162.daemon.log to (same list G2D.x ingests)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

#define RPT_DOMAIN CFSTR("com.infernowolf19.backport162")
#define RPT_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static const char kRPTRequestName[] = "com.infernowolf19.backport162.report.request";
static const char kRPTDoneName[]    = "com.infernowolf19.backport162.report.done";

// Hard caps (bytes). The report is built in memory: 2 + 1 + 0.25 + 0.125 MiB of logs + 4 x 0.2 MiB of crash reports + a few KiB of text, about 4.3 MiB,
// the gzip is at most kRPTGzCap, base64 + the JSON body add 2 x 1.34 x kRPTGzCap in the (never reached in practice) worst case: peak well below 12 MiB.
enum {
    kRPTLogTail      = 2 * 1024 * 1024,
    kRPTLog1Tail     = 1 * 1024 * 1024,
    kRPTDaemonTail   = 256 * 1024,
    kRPTOwnCrashTail = 128 * 1024,
    kRPTCrashFileCap = 200 * 1024,
    kRPTCrashMax     = 4,
    kRPTCrashDays    = 3,
    kRPTScanMax      = 2000,                 // directory entries looked at per crash directory
    kRPTStatusCap    = 6 * 1024 * 1024,      // dpkg status file: only searched for our stanza
    kRPTGzCap        = 4 * 1024 * 1024,
    kRPTKeepReports  = 5,
};

// ---------------------------------------------------------------- state

static _Atomic uint32_t gRPTRunning;         // 0 / 1: a job is in flight
static _Atomic uint32_t gRPTSerial;          // bumped by every job that starts
static uint64_t gRPTLastStart;               // uptime ns of the last job start; only touched inside the running region (serialised by gRPTRunning)
static dispatch_queue_t gRPTQueue;
static int gRPTToken;

// ---------------------------------------------------------------- small helpers

static NSData *RPT_Utf8(NSString *s) {
    NSData *d = [(s ?: @"") dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    return d ?: [NSData data];
}

static NSString *RPT_CapString(NSString *s, NSUInteger max) {
    if (!s) return nil;
    if (s.length <= max) return s;
    NSRange r = [s rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, max)];   // do not cut a surrogate pair / combining sequence
    return [s substringWithRange:r];
}

static NSString *RPT_Trim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// owner/name, both parts [A-Za-z0-9_.-]+ (the regex ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$), and neither part "." / ".." (they would walk out of /repos/<owner>/<name>).
static BOOL RPT_ValidRepo(NSString *repo) {
    if (repo.length < 3 || repo.length > 200) return NO;
    BOOL slash = NO;
    NSUInteger partLen = 0, dots = 0;
    for (NSUInteger i = 0; i < repo.length; i++) {
        unichar c = [repo characterAtIndex:i];
        if (c == '/') {
            if (slash || partLen == 0 || dots == partLen) return NO;       // second slash / empty owner / owner "." or ".."
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

// A header value must be printable ASCII without blanks (a pasted token with an inner space / newline would make a broken Authorization header).
static BOOL RPT_ValidToken(NSString *t) {
    if (t.length < 8 || t.length > 255) return NO;
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c < 0x21 || c > 0x7e) return NO;
    }
    return YES;
}

static NSString *RPT_PrefString(CFStringRef key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(key, RPT_DOMAIN);
    NSString *s = nil;
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID()) s = [(__bridge NSString *)v copy];
        CFRelease(v);
    }
    return s;
}

static NSString *RPT_Sysctl(const char *name) {
    char buf[256] = {0};
    size_t n = sizeof buf - 1;
    if (sysctlbyname(name, buf, &n, NULL, 0) != 0) return @"?";
    buf[sizeof buf - 1] = 0;
    return [NSString stringWithUTF8String:buf] ?: @"?";
}

// ---------------------------------------------------------------- reading files

// Reads at most `cap` bytes of a plain file: the LAST cap bytes when `tail` (the part of a log that matters), else the first. Never throws; every failure comes back as *err.
// The result is nil only when the file cannot be opened; a read error halfway returns what was read (and *err). *fileSize is the size when the read started (-1 unknown).
// A tail starts at a line boundary. O_NONBLOCK + S_ISREG: a FIFO / device at that path can never block the job.
static NSData *RPT_ReadRange(const char *path, size_t cap, BOOL tail, long long *fileSize, int *err) {
    if (fileSize) *fileSize = -1;
    if (err) *err = 0;
    if (!path || !path[0]) { if (err) *err = EINVAL; return nil; }
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) { if (err) *err = errno; return nil; }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        if (err) *err = (errno ? errno : EINVAL);
        close(fd);
        return nil;
    }
    long long size = (long long)st.st_size;
    if (fileSize) *fileSize = size;
    size_t want = size > 0 ? (size_t)size : 0;
    off_t start = 0;
    if (want > cap) {
        want = cap;
        if (tail) start = (off_t)(size - (long long)cap);
    }
    if (want == 0) { close(fd); return [NSData data]; }
    NSMutableData *buf = [NSMutableData dataWithLength:want];
    if (!buf) { if (err) *err = ENOMEM; close(fd); return nil; }
    size_t got = 0;
    uint8_t *p = (uint8_t *)buf.mutableBytes;
    while (got < want) {
        ssize_t n = pread(fd, p + got, want - got, start + (off_t)got);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (err) *err = errno;
            break;
        }
        if (n == 0) break;                                   // the file shrank while we read
        got += (size_t)n;
    }
    close(fd);
    [buf setLength:got];
    if (tail && start > 0 && got > 0) {                      // we cut into a line: drop the partial first line (looked for in the first 4 KiB only)
        size_t look = got < 4096 ? got : 4096;
        const uint8_t *nl = memchr(p, '\n', look);
        if (nl) [buf replaceBytesInRange:NSMakeRange(0, (NSUInteger)(nl - p) + 1) withBytes:NULL length:0];
    }
    return buf;
}

// ---------------------------------------------------------------- the report as a list of sections

@interface BPRPTSection : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSData *data;               // body bytes, never nil
@property (nonatomic) long long fileSize;                 // size on disk when it came from a file, else -1
@property (nonatomic) unsigned long long droppedBytes;    // bytes of the file that are NOT in data
@property (nonatomic) BOOL trimmable;                     // a log tail: the oldest half may be dropped to fit the size cap
@property (nonatomic) BOOL fromHead;                      // data is the beginning of the file (crash reports), not the end
@property (nonatomic) BOOL trimmedForSize;
- (BOOL)trimHalf;
@end

@implementation BPRPTSection
- (BOOL)trimHalf {
    NSUInteger n = self.data.length;
    if (!self.trimmable || n < 8192) return NO;
    const uint8_t *b = (const uint8_t *)self.data.bytes;
    NSUInteger cut = n / 2, lim = (cut + 4096 < n) ? cut + 4096 : n;
    for (NSUInteger i = cut; i < lim; i++) if (b[i] == '\n') { cut = i + 1; break; }     // keep whole lines
    NSData *kept = [self.data subdataWithRange:NSMakeRange(cut, n - cut)];
    self.data = kept ?: [NSData data];
    self.droppedBytes += cut;
    self.trimmedForSize = YES;
    return YES;
}
@end

static BPRPTSection *RPT_TextSection(NSString *name, NSString *text) {
    BPRPTSection *s = [[BPRPTSection alloc] init];
    s.name = name;
    s.data = RPT_Utf8(text);
    s.fileSize = -1;
    return s;
}

// A section from a file. Missing / unreadable files still produce a section that says so (the absence of a log is information too).
static BPRPTSection *RPT_FileSection(NSString *name, NSString *path, size_t cap, BOOL tail) {
    long long size = -1;
    int err = 0;
    NSData *d = RPT_ReadRange(path.fileSystemRepresentation, cap, tail, &size, &err);
    BPRPTSection *s = [[BPRPTSection alloc] init];
    s.name = name;
    s.fileSize = size;
    s.fromHead = !tail;
    s.trimmable = tail;
    if (!d) {
        s.data = RPT_Utf8([NSString stringWithFormat:@"(%@: %s)\n", err == ENOENT ? @"not found" : @"cannot read", strerror(err)]);
        s.trimmable = NO;
        return s;
    }
    s.data = d;
    if (d.length == 0) s.data = RPT_Utf8(err ? [NSString stringWithFormat:@"(empty or unreadable: %s)\n", strerror(err)] : @"(empty)\n");
    // a partial read (error halfway) keeps what was read; the heading shows the missing bytes
    if (size > 0 && (long long)d.length < size) s.droppedBytes = (unsigned long long)(size - (long long)d.length);
    if (d.length == 0) s.trimmable = NO;
    return s;
}

// ---------------------------------------------------------------- system section

static NSString *RPT_PackageVersion(void) {
  @autoreleasepool {                                    // the status file (up to 6 MiB) must not live until the end of the job
    NSString *p = ROOT_PATH_NS(@"/Library/dpkg/status");
    long long size = -1;
    int err = 0;
    NSData *d = RPT_ReadRange(p.fileSystemRepresentation, kRPTStatusCap, NO, &size, &err);
    if (!d.length) return [NSString stringWithFormat:@"unknown (cannot read the dpkg status file: %s)", strerror(err ? err : ENOENT)];
    const char *b = (const char *)d.bytes;
    size_t n = d.length;
    static const char key[] = "Package: com.infernowolf19.backport162\n";      // the trailing newline keeps ...backport162bbd out
    const size_t klen = sizeof key - 1;
    const char *hit = NULL, *from = b;
    size_t left = n;
    while (left >= klen) {
        const char *m = (const char *)memmem(from, left, key, klen);
        if (!m) break;
        if (m == b || m[-1] == '\n') { hit = m; break; }                      // a line start, not the tail of another field
        from = m + 1;
        left = n - (size_t)(from - b);
    }
    if (!hit) return (size > (long long)n) ? @"unknown (not in the first 6 MiB of the dpkg status file)" : @"unknown (package not in the dpkg status file)";
    size_t rest = n - (size_t)(hit - b);
    const char *end = (const char *)memmem(hit, rest, "\n\n", 2);
    size_t stanza = end ? (size_t)(end - hit) : rest;
    const char *v = (const char *)memmem(hit, stanza, "\nVersion: ", 10);
    if (!v) return @"unknown (no Version line)";
    v += 10;
    size_t room = stanza - (size_t)(v - hit), len = 0;
    while (len < room && len < 64 && v[len] != '\n' && v[len] != '\r') len++;
    NSString *s = [[NSString alloc] initWithBytes:v length:len encoding:NSUTF8StringEncoding];
    return s.length ? s : @"unknown (empty Version)";
  }
}

static NSString *RPT_SystemText(NSString *reportID, NSString *tmpDir, BOOL debugOn, NSString *pkgVersion) {
    NSMutableString *t = [NSMutableString string];
    time_t now = time(NULL);
    struct tm tmv;
    char tb[64] = {0};
    if (localtime_r(&now, &tmv)) strftime(tb, sizeof tb, "%Y-%m-%d %H:%M:%S %z", &tmv);
    NSString *tz = @"?";
    @try { tz = [[NSTimeZone localTimeZone] name] ?: @"?"; } @catch (NSException *e) { tz = @"?"; }
    [t appendFormat:@"report id: %@\n", reportID];
    [t appendFormat:@"time: %s (time zone %@)\n", tb, tz];
    [t appendFormat:@"package: com.infernowolf19.backport162 %@\n", pkgVersion];
    [t appendFormat:@"build: %@ (kern.osversion), kernel %@\n", RPT_Sysctl("kern.osversion"), RPT_Sysctl("kern.osrelease")];
    [t appendFormat:@"device: %@ (hw.machine)\n", RPT_Sysctl("hw.machine")];
    NSString *osv = @"?";
    @try { osv = [[NSProcessInfo processInfo] operatingSystemVersionString] ?: @"?"; } @catch (NSException *e) { osv = @"?"; }
    [t appendFormat:@"system: %@\n", osv];
    struct timeval bt = {0, 0};
    size_t btl = sizeof bt;
    if (sysctlbyname("kern.boottime", &bt, &btl, NULL, 0) == 0 && bt.tv_sec > 0 && now >= bt.tv_sec) {
        long long up = (long long)(now - bt.tv_sec);
        [t appendFormat:@"uptime: %lld s (%lldd %02lld:%02lld:%02lld)\n", up, up / 86400, (up / 3600) % 24, (up / 60) % 60, up % 60];
    } else [t appendString:@"uptime: ?\n"];
    [t appendFormat:@"process: pid %d\n", (int)getpid()];
    [t appendFormat:@"debug log enabled: %@ (%@/Backport162.debug %@)\n", debugOn ? @"yes" : @"NO", tmpDir, debugOn ? @"exists" : @"does not exist"];
    if (!debugOn) [t appendString:@"  Without Backport162.debug the log is sparse: only the lines that are always written (start-up, errors, crash recorder). Create the file, reproduce the problem, then send the report.\n"];
    // switch files (names only)
    [t appendString:@"switch / flag files in the tmp directory (names only):\n"];
    int count = 0;
    DIR *d = opendir(tmpDir.fileSystemRepresentation);
    if (d) {
        struct dirent *e;
        NSMutableArray *names = [NSMutableArray array];
        int seen = 0;
        while ((e = readdir(d)) != NULL && seen++ < kRPTScanMax) {
            if (strncmp(e->d_name, "Backport162.", 12) != 0) continue;
            NSString *nm = [NSString stringWithUTF8String:e->d_name];
            if (nm) [names addObject:nm];
        }
        closedir(d);
        [names sortUsingSelector:@selector(compare:)];
        for (NSString *nm in names) { [t appendFormat:@"  %@\n", nm]; count++; }
    } else [t appendFormat:@"  (cannot list %@: %s)\n", tmpDir, strerror(errno)];
    if (count == 0) [t appendString:@"  (none)\n"];
    // loaded dylibs (names only)
    [t appendString:@"loaded Backport162 images:\n"];
    int imgs = 0;
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "Backport162")) { [t appendFormat:@"  %s\n", nm]; imgs++; }
    }
    if (imgs == 0) [t appendString:@"  (none found)\n"];
    return t;
}

// ---------------------------------------------------------------- crash reports

@interface BPRPTCrashFile : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) time_t mtime;
@property (nonatomic) long long size;
@end
@implementation BPRPTCrashFile
@end

// SpringBoard-0000-00-00-000000.ips, backboardd_2022-...crash: process name, a separator, anything, then .ips / .crash.
static BOOL RPT_CrashNameWanted(const char *nm) {
    static const char *const procs[] = { "SpringBoard", "backboardd", "pointeruid", "mediaserverd", "audiomxd", "Preferences" };
    size_t L = strlen(nm);
    BOOL ext = (L > 4 && strcmp(nm + L - 4, ".ips") == 0) || (L > 6 && strcmp(nm + L - 6, ".crash") == 0);
    if (!ext) return NO;
    for (size_t i = 0; i < sizeof procs / sizeof procs[0]; i++) {
        size_t pl = strlen(procs[i]);
        if (strncmp(nm, procs[i], pl) == 0 && (nm[pl] == '-' || nm[pl] == '_' || nm[pl] == '.')) return YES;
    }
    return NO;
}

static void RPT_ScanCrashDir(const char *dir, time_t cutoff, NSMutableArray *out) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    int seen = 0;
    while ((e = readdir(d)) != NULL && seen++ < kRPTScanMax) {
        if (e->d_name[0] == '.' || !RPT_CrashNameWanted(e->d_name)) continue;
        char p[1100];
        if (snprintf(p, sizeof p, "%s/%s", dir, e->d_name) >= (int)sizeof p) continue;
        struct stat st;
        if (stat(p, &st) != 0 || !S_ISREG(st.st_mode) || st.st_mtime < cutoff) continue;
        BPRPTCrashFile *f = [[BPRPTCrashFile alloc] init];
        f.path = [NSString stringWithUTF8String:p];
        f.name = [NSString stringWithUTF8String:e->d_name];
        f.mtime = st.st_mtime;
        f.size = (long long)st.st_size;
        if (f.path && f.name) [out addObject:f];
    }
    closedir(d);
}

static void RPT_AddCrashSections(NSMutableArray *sections) {
    time_t now = time(NULL);
    time_t cutoff = now - (time_t)kRPTCrashDays * 86400;
    NSMutableArray *found = [NSMutableArray array];
    RPT_ScanCrashDir("/var/mobile/Library/Logs/CrashReporter", cutoff, found);
    RPT_ScanCrashDir("/var/mobile/Library/Logs/CrashReporter/Retired", cutoff, found);
    [found sortUsingComparator:^NSComparisonResult(BPRPTCrashFile *a, BPRPTCrashFile *b) {
        if (a.mtime == b.mtime) return NSOrderedSame;
        return a.mtime > b.mtime ? NSOrderedAscending : NSOrderedDescending;       // newest first
    }];
    NSMutableString *idx = [NSMutableString string];
    [idx appendFormat:@"crash reports of the last %d days for SpringBoard, backboardd, pointeruid, mediaserverd, audiomxd, Preferences (CrashReporter and CrashReporter/Retired): %lu found, newest %d included\n",
        (int)kRPTCrashDays, (unsigned long)found.count, (int)kRPTCrashMax];
    NSUInteger shown = 0;
    for (BPRPTCrashFile *f in found) {
        if (shown++ >= 20) { [idx appendString:@"  ...\n"]; break; }
        struct tm tmv;
        char tb[40] = {0};
        time_t mt = f.mtime;
        if (localtime_r(&mt, &tmv)) strftime(tb, sizeof tb, "%Y-%m-%d %H:%M:%S", &tmv);
        [idx appendFormat:@"  %s  %9lld bytes  %@\n", tb, f.size, f.name];
    }
    if (found.count == 0) [idx appendString:@"  (none)\n"];
    [sections addObject:RPT_TextSection(@"crash report index", idx)];
    NSUInteger take = found.count < (NSUInteger)kRPTCrashMax ? found.count : (NSUInteger)kRPTCrashMax;
    for (NSUInteger i = 0; i < take; i++) {
        BPRPTCrashFile *f = found[i];
        BPRPTSection *s = RPT_FileSection([NSString stringWithFormat:@"crash report %@", f.name], f.path, kRPTCrashFileCap, NO);
        s.trimmable = NO;                                                           // the head (exception, crashed thread) is what matters
        [sections addObject:s];
    }
}

// ---------------------------------------------------------------- assemble + gzip

static NSData *RPT_BuildDocument(NSString *reportID, NSArray<BPRPTSection *> *sections, BOOL debugOn) {
    NSMutableData *doc = [NSMutableData dataWithCapacity:(NSUInteger)(4 * 1024 * 1024)];
    BOOL trimmed = NO;
    for (BPRPTSection *s in sections) if (s.trimmedForSize) trimmed = YES;
    NSMutableString *h = [NSMutableString string];
    [h appendFormat:@"Backport162 report %@ (format 1)\n", reportID];
    [h appendString:@"Made by the Send logs button of Settings > Backport162. Contains: the tweak's log files, crash reports of the last days, and the system section below. Contains NO token and NO preferences.\n"];
    if (!debugOn) [h appendString:@"NOTE: Backport162.debug did not exist when this report was made, so the log is sparse (only the always-written lines).\n"];
    if (trimmed) [h appendString:@"TRUNCATED FOR SIZE: the compressed report would have exceeded 4 MiB; the oldest bytes of the logs marked below were dropped first.\n"];
    [h appendString:@"sections:\n"];
    for (BPRPTSection *s in sections) [h appendFormat:@"  %@ (%lu bytes)\n", s.name, (unsigned long)s.data.length];
    [h appendString:@"\n"];
    [doc appendData:RPT_Utf8(h)];
    for (BPRPTSection *s in sections) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"===== %@ (%lu bytes", s.name, (unsigned long)s.data.length];
        if (s.droppedBytes > 0 && s.fileSize >= 0)
            [line appendFormat:@"; the file has %lld bytes, %llu %@ not included%@", s.fileSize, s.droppedBytes, s.fromHead ? @"trailing" : @"leading (oldest)", s.trimmedForSize ? @", part of it dropped to fit the size cap" : @""];
        else if (s.trimmedForSize)
            [line appendFormat:@"; oldest %llu bytes dropped to fit the size cap", s.droppedBytes];
        [line appendString:@") =====\n"];
        [doc appendData:RPT_Utf8(line)];
        [doc appendData:s.data];
        const uint8_t *b = (const uint8_t *)s.data.bytes;
        if (s.data.length == 0 || b[s.data.length - 1] != '\n') [doc appendBytes:"\n" length:1];
        [doc appendBytes:"\n" length:1];
    }
    [doc appendData:RPT_Utf8(@"===== end of report =====\n")];
    return doc;
}

// gzip (RFC 1952) in one deflate call: windowBits 15 + 16. nil on any zlib error (*zerr = the zlib code).
static NSData *RPT_Gzip(NSData *in, int *zerr) {
    if (zerr) *zerr = Z_OK;
    if (!in || in.length == 0 || in.length > 0x7fffffffu) { if (zerr) *zerr = Z_DATA_ERROR; return nil; }
    z_stream zs;
    memset(&zs, 0, sizeof zs);
    int rc = deflateInit2(&zs, 6, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    if (rc != Z_OK) { if (zerr) *zerr = rc; return nil; }
    uLong bound = deflateBound(&zs, (uLong)in.length) + 64;
    NSMutableData *out = [NSMutableData dataWithLength:(NSUInteger)bound];
    if (!out) { deflateEnd(&zs); if (zerr) *zerr = Z_MEM_ERROR; return nil; }
    zs.next_in = (Bytef *)in.bytes;                    // zlib does not write to the input
    zs.avail_in = (uInt)in.length;
    zs.next_out = (Bytef *)out.mutableBytes;
    zs.avail_out = (uInt)bound;
    rc = deflate(&zs, Z_FINISH);
    uLong produced = zs.total_out;
    deflateEnd(&zs);                                   // always, success or not
    if (rc != Z_STREAM_END) { if (zerr) *zerr = (rc == Z_OK ? Z_BUF_ERROR : rc); return nil; }
    [out setLength:(NSUInteger)produced];
    return out;
}

// ---------------------------------------------------------------- local file

static NSString *RPT_ReportsDir(void) { return ROOT_PATH_NS(@"/var/mobile/Library/Caches/Backport162Reports"); }

// Keeps the kRPTKeepReports newest report-*.txt.gz (never `keep`) and removes leftovers of an interrupted write (*.tmp).
static void RPT_Prune(NSString *dir, NSString *keep) {
    DIR *d = opendir(dir.fileSystemRepresentation);
    if (!d) return;
    NSMutableArray *files = [NSMutableArray array];
    struct dirent *e;
    int seen = 0;
    while ((e = readdir(d)) != NULL && seen++ < kRPTScanMax) {
        size_t L = strlen(e->d_name);
        char p[1100];
        if (snprintf(p, sizeof p, "%s/%s", dir.fileSystemRepresentation, e->d_name) >= (int)sizeof p) continue;
        if (L > 4 && strcmp(e->d_name + L - 4, ".tmp") == 0 && strncmp(e->d_name, "report-", 7) == 0) { (void)unlink(p); continue; }
        if (strncmp(e->d_name, "report-", 7) != 0 || L < 8 + 7 || strcmp(e->d_name + L - 7, ".txt.gz") != 0) continue;
        struct stat st;
        if (stat(p, &st) != 0 || !S_ISREG(st.st_mode)) continue;
        BPRPTCrashFile *f = [[BPRPTCrashFile alloc] init];       // same small record type: path + mtime
        f.path = [NSString stringWithUTF8String:p];
        f.name = [NSString stringWithUTF8String:e->d_name];
        f.mtime = st.st_mtime;
        if (f.path && f.name) [files addObject:f];
    }
    closedir(d);
    [files sortUsingComparator:^NSComparisonResult(BPRPTCrashFile *a, BPRPTCrashFile *b) {
        if (a.mtime == b.mtime) return [b.name compare:a.name];
        return a.mtime > b.mtime ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSUInteger kept = 0;
    for (BPRPTCrashFile *f in files) {
        if ([f.path isEqualToString:keep] || kept < (NSUInteger)kRPTKeepReports) { kept++; continue; }
        (void)unlink(f.path.fileSystemRepresentation);
    }
}

// Writes dir/report-<id>.txt.gz (0644, dir 0755) through a .tmp file + rename. Returns the path, or nil with *msg describing the failure.
static NSString *RPT_WriteLocal(NSData *gz, NSString *reportID, NSString **msg) {
    NSString *dir = RPT_ReportsDir();
    NSError *e = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions : @(0755) } error:&e]) {
        BOOL isDir = NO;
        if (!([fm fileExistsAtPath:dir isDirectory:&isDir] && isDir)) { if (msg) *msg = [NSString stringWithFormat:@"cannot create %@: %@", dir, e.localizedDescription ?: @"?"]; return nil; }
    }
    (void)chmod(dir.fileSystemRepresentation, 0755);
    NSString *final = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"report-%@.txt.gz", reportID]];
    NSString *tmp = [final stringByAppendingString:@".tmp"];
    int fd = open(tmp.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) { if (msg) *msg = [NSString stringWithFormat:@"cannot write %@: %s", tmp, strerror(errno)]; return nil; }
    const uint8_t *p = (const uint8_t *)gz.bytes;
    size_t left = gz.length;
    int werr = 0;
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n < 0) { if (errno == EINTR) continue; werr = errno; break; }
        p += n; left -= (size_t)n;
    }
    if (werr == 0 && fsync(fd) != 0 && errno != EINVAL && errno != ENOTSUP) werr = errno;      // fsync is best effort on some file systems
    close(fd);
    if (werr != 0) { (void)unlink(tmp.fileSystemRepresentation); if (msg) *msg = [NSString stringWithFormat:@"cannot write the report file: %s", strerror(werr)]; return nil; }
    (void)chmod(tmp.fileSystemRepresentation, 0644);
    if (rename(tmp.fileSystemRepresentation, final.fileSystemRepresentation) != 0) {
        int re = errno;
        (void)unlink(tmp.fileSystemRepresentation);
        if (msg) *msg = [NSString stringWithFormat:@"cannot move the report file into place: %s", strerror(re)];
        return nil;
    }
    RPT_Prune(dir, final);
    return final;
}

// ---------------------------------------------------------------- publishing the answer

static void RPT_SetPref(CFStringRef key, id value) {                    // value nil removes the key
    CFPreferencesSetValue(key, (__bridge CFPropertyListRef)value, RPT_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// The ONLY place that answers a request. Once per job (gRPTSerial): writes the keys, clears the running flag, THEN posts "done" (so a quick second press is not refused as "running").
static void RPT_Finish(uint32_t serial, NSString *status, NSString *message, NSString *reportID, NSString *url, NSString *file) {
    if (atomic_load(&gRPTRunning) != 1 || atomic_load(&gRPTSerial) != serial) return;      // already answered, or this call belongs to an older job
    @try {
        RPT_SetPref(CFSTR("reportStatus"), status ?: @"error");
        RPT_SetPref(CFSTR("reportMessage"), RPT_CapString(message, 600) ?: @"");
        RPT_SetPref(CFSTR("reportID"), reportID);
        RPT_SetPref(CFSTR("reportURL"), url);
        RPT_SetPref(CFSTR("reportFile"), file);
        RPT_SetPref(CFSTR("reportTime"), @((double)time(NULL)));
        CFPreferencesSynchronize(RPT_DOMAIN, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    } @catch (NSException *e) {
        RPT_LOG(@"[rpt] cannot publish the result: %@", e.name);
    }
    RPT_LOG(@"[rpt] finished: %@ id=%@ message=%@", status, reportID ?: @"-", RPT_CapString(message, 200));
    uint32_t expected = 1;
    atomic_compare_exchange_strong(&gRPTRunning, &expected, 0u);
    (void)notify_post(kRPTDoneName);
}

// ---------------------------------------------------------------- upload

// PUT https://api.github.com/repos/<repo>/contents/reports/<date>/<id>.txt.gz. Fills `result` with ok (NSNumber), message, url. Blocks the calling (private) queue up to 130 s.
static void RPT_Upload(NSString *repo, NSString *token, NSString *reportID, NSString *dateDir, NSData *gz, NSMutableDictionary *result) {
    result[@"ok"] = @NO;
    NSData *b64 = [gz base64EncodedDataWithOptions:0];                                // NSData in, NSData out: no intermediate NSString copies
    if (!b64) { result[@"message"] = @"cannot encode the report (out of memory?)"; return; }
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/contents/reports/%@/%@.txt.gz", repo, dateDir, reportID]];
    if (!url) { result[@"message"] = @"repository name does not make a valid URL"; return; }
    NSMutableData *body = [NSMutableData dataWithCapacity:b64.length + 160];
    [body appendData:RPT_Utf8([NSString stringWithFormat:@"{\"message\":\"report %@\",\"content\":\"", reportID])];        // reportID is [0-9a-f-]: no JSON escaping needed
    [body appendData:b64];
    b64 = nil;
    [body appendBytes:"\"}" length:2];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    req.HTTPMethod = @"PUT";
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"2022-11-28" forHTTPHeaderField:@"X-GitHub-Api-Version"];
    [req setValue:@"Backport162" forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 30;
    cfg.timeoutIntervalForResource = 120;
    cfg.waitsForConnectivity = NO;
    cfg.HTTPCookieStorage = nil;
    cfg.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSMutableDictionary *box = [NSMutableDictionary dictionary];                      // written by the completion handler only; read only after the semaphore fired
    NSURLSessionUploadTask *task = [session uploadTaskWithRequest:req fromData:body completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        @try {
            if (error) {
                box[@"message"] = [NSString stringWithFormat:@"%@ (no network?)", error.localizedDescription ?: @"network error"];
            } else {
                NSHTTPURLResponse *http = [resp isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)resp : nil;
                long long code = http ? (long long)http.statusCode : -1;
                NSString *ghMessage = nil, *htmlURL = nil;
                if (data.length > 0 && data.length < 256 * 1024) {
                    id j = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
                    if ([j isKindOfClass:[NSDictionary class]]) {
                        id m = ((NSDictionary *)j)[@"message"];
                        if ([m isKindOfClass:[NSString class]]) ghMessage = RPT_CapString(m, 200);
                        id c = ((NSDictionary *)j)[@"content"];
                        id u = [c isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)c)[@"html_url"] : nil;
                        if ([u isKindOfClass:[NSString class]]) htmlURL = u;
                    }
                }
                RPT_LOG(@"[rpt] upload answered HTTP %lld%@", code, ghMessage ? [@": " stringByAppendingString:ghMessage] : @"");   // status + message only, never the body or the token
                if (code == 201 || code == 200) {
                    box[@"ok"] = @YES;
                    if (htmlURL) box[@"url"] = htmlURL;
                } else if (code == 401 || code == 403) box[@"message"] = @"token rejected or missing Contents write permission";
                else if (code == 404) box[@"message"] = @"repository not found or the token cannot see it";
                else if (code == 409 || code == 422) box[@"message"] = @"file already exists / conflict, press again";
                else if (code == 413) box[@"message"] = @"report too large";
                else box[@"message"] = ghMessage ? [NSString stringWithFormat:@"HTTP %lld (%@)", code, ghMessage] : [NSString stringWithFormat:@"HTTP %lld", code];
            }
        } @catch (NSException *e) {
            box[@"message"] = @"unreadable answer from GitHub";
        }
        dispatch_semaphore_signal(sem);
    }];
    if (!task) { [session invalidateAndCancel]; result[@"message"] = @"cannot start the upload"; return; }
    [task resume];
    long waited = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(130 * NSEC_PER_SEC)));
    if (waited != 0) {                                                                // the late completion (if any) only touches `box`, which is not read any more
        [task cancel];
        [session invalidateAndCancel];
        result[@"message"] = @"upload timed out (no network?)";
        return;
    }
    [session finishTasksAndInvalidate];
    NSDictionary *snapshot = [box copy];
    if ([snapshot[@"ok"] boolValue]) {
        result[@"ok"] = @YES;
        if (snapshot[@"url"]) result[@"url"] = snapshot[@"url"];
    } else result[@"message"] = snapshot[@"message"] ?: @"upload failed";
}

// ---------------------------------------------------------------- the job

static BOOL RPT_FileExists(NSString *path) { return path.length && access(path.fileSystemRepresentation, F_OK) == 0; }

static void RPT_RunJobBody(uint32_t serial) {
    // switch + kill switch: a user who switched the feature off still gets an answer
    if (!BP_OnName("report")) {
        RPT_Finish(serial, @"error", @"disabled: Backport162.off.report (or Backport162.off) exists in the tmp directory of the jailbreak root", nil, nil, nil);
        return;
    }
    uint64_t t0 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (gRPTLastStart != 0 && t0 - gRPTLastStart < 5ull * NSEC_PER_SEC) {
        RPT_Finish(serial, @"error", @"two requests less than 5 s apart: wait a moment and press again", nil, nil, nil);
        return;
    }
    gRPTLastStart = t0;

    time_t now = time(NULL);
    struct tm tmv;
    char idbuf[48] = {0}, datebuf[16] = {0};
    if (!localtime_r(&now, &tmv)) memset(&tmv, 0, sizeof tmv);
    strftime(idbuf, sizeof idbuf, "%Y%m%d-%H%M%S", &tmv);
    strftime(datebuf, sizeof datebuf, "%Y-%m-%d", &tmv);
    NSString *reportID = [NSString stringWithFormat:@"%s-%04x", idbuf, (unsigned)arc4random_uniform(0x10000)];
    NSString *dateDir = [NSString stringWithUTF8String:datebuf] ?: @"unknown-date";
    RPT_LOG(@"[rpt] collecting report %@", reportID);

    // ---- (1) collect, every piece capped
    NSString *tmpDir = ROOT_PATH_NS(@"/tmp");
    BOOL debugOn = RPT_FileExists([tmpDir stringByAppendingPathComponent:@"Backport162.debug"]);
    NSMutableArray<BPRPTSection *> *sections = [NSMutableArray array];
    NSString *pkg = RPT_PackageVersion();
    [sections addObject:RPT_TextSection(@"system", RPT_SystemText(reportID, tmpDir, debugOn, pkg))];
    [sections addObject:RPT_FileSection(@"Backport162.crash (own crash recorder)", [tmpDir stringByAppendingPathComponent:@"Backport162.crash"], kRPTOwnCrashTail, YES)];
    [sections addObject:RPT_FileSection(@"Backport162.log", [tmpDir stringByAppendingPathComponent:@"Backport162.log"], kRPTLogTail, YES)];
    [sections addObject:RPT_FileSection(@"Backport162.log.1", [tmpDir stringByAppendingPathComponent:@"Backport162.log.1"], kRPTLog1Tail, YES)];
    {
        NSString *daemonPath = nil;                                                    // first directory of the daemons' list that has the file (read only)
        for (int i = 0; i < BPDW_DIR_COUNT; i++) {
            char p[300];
            snprintf(p, sizeof p, "%s/%s", kBPDWDirs[i], BPDW_FILE);
            struct stat st;
            if (stat(p, &st) == 0) { daemonPath = [NSString stringWithUTF8String:p]; break; }
        }
        if (daemonPath) [sections addObject:RPT_FileSection([NSString stringWithFormat:@"Backport162.daemon.log (%@)", daemonPath], daemonPath, kRPTDaemonTail, YES)];
        else [sections addObject:RPT_TextSection(@"Backport162.daemon.log", @"(not found in any of the daemon log directories)\n")];
    }
    RPT_AddCrashSections(sections);

    // ---- (2) assemble + gzip, dropping the oldest log bytes until it fits
    NSData *gz = nil;
    int zerr = 0;
    for (int pass = 0; pass < 10; pass++) {
        @autoreleasepool {
            NSData *doc = RPT_BuildDocument(reportID, sections, debugOn);
            gz = RPT_Gzip(doc, &zerr);
        }
        if (!gz) { RPT_Finish(serial, @"error", [NSString stringWithFormat:@"compression failed (zlib %d)", zerr], reportID, nil, nil); return; }
        if (gz.length <= (NSUInteger)kRPTGzCap) break;
        BOOL any = NO;
        for (BPRPTSection *s in sections) if ([s trimHalf]) any = YES;
        if (!any) break;
        gz = nil;
    }
    if (!gz || gz.length > (NSUInteger)kRPTGzCap) { RPT_Finish(serial, @"error", @"report too large even after dropping the oldest log bytes", reportID, nil, nil); return; }
    sections = nil;

    // ---- (3) local file (kept even when the upload fails: "Share report..." in Settings)
    NSString *wmsg = nil;
    NSString *file = RPT_WriteLocal(gz, reportID, &wmsg);
    if (!file) RPT_LOG(@"[rpt] %@", wmsg);

    // ---- (4) upload, only with a valid repository + token
    CFPreferencesAppSynchronize(RPT_DOMAIN);                                          // Settings wrote the fields from another process: drop our cached copy
    NSString *repo = RPT_Trim(RPT_PrefString(CFSTR("reportRepo")) ?: @"");
    NSString *token = RPT_Trim(RPT_PrefString(CFSTR("reportToken")) ?: @"");
    NSString *tail = file ? @"" : [NSString stringWithFormat:@" (%@)", wmsg ?: @"no local copy"];
    if (repo.length == 0 || token.length == 0) {
        RPT_Finish(serial, @"error", [@"no token / repository set: report saved only on the device, use Share" stringByAppendingString:tail], reportID, nil, file);
        return;
    }
    if (!RPT_ValidRepo(repo)) {
        RPT_Finish(serial, @"error", [@"repository is not owner/name: report saved only on the device, use Share" stringByAppendingString:tail], reportID, nil, file);
        return;
    }
    if (!RPT_ValidToken(token)) {
        RPT_Finish(serial, @"error", [@"token has blanks or unusual characters: report saved only on the device, use Share" stringByAppendingString:tail], reportID, nil, file);
        return;
    }
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    RPT_Upload(repo, token, reportID, dateDir, gz, result);
    token = nil;
    NSUInteger gzLen = gz.length;
    gz = nil;
    if ([result[@"ok"] boolValue]) {
        NSString *msg = [NSString stringWithFormat:@"uploaded %lu KiB to %@ (reports/%@/%@.txt.gz)", (unsigned long)((gzLen + 1023) / 1024), repo, dateDir, reportID];
        RPT_Finish(serial, @"ok", msg, reportID, result[@"url"], file);
    } else {
        NSString *m = result[@"message"] ?: @"upload failed";
        RPT_Finish(serial, @"error", [NSString stringWithFormat:@"%@%@", m, file ? @": report saved on the device, use Share" : tail], reportID, nil, file);
    }
}

static void RPT_RunJob(uint32_t serial) {
    @try {
        @autoreleasepool { RPT_RunJobBody(serial); }
    } @catch (NSException *e) {
        RPT_LOG(@"[rpt] exception %@", e.name);
    } @finally {
        RPT_Finish(serial, @"error", @"internal error while collecting the report", nil, nil, nil);      // no-op when the job already answered
    }
}

// Main queue: only an atomic test and a hop to the private queue.
static void RPT_OnRequest(void) {
    uint32_t expected = 0;
    if (!atomic_compare_exchange_strong(&gRPTRunning, &expected, 1u)) {
        RPT_LOG(@"[rpt] request ignored: a report is already being collected");
        return;
    }
    uint32_t serial = atomic_fetch_add(&gRPTSerial, 1u) + 1u;
    dispatch_queue_t q = gRPTQueue;
    if (!q) {                                                  // cannot happen after RPT_Setup; never leave the flag set
        uint32_t one = 1;
        atomic_compare_exchange_strong(&gRPTRunning, &one, 0u);
        return;
    }
    dispatch_async(q, ^{ RPT_RunJob(serial); });
}

void RPT_Setup(void) {
    @try {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
            gRPTQueue = dispatch_queue_create("com.infernowolf19.backport162.report", attr);
            uint32_t st = notify_register_dispatch(kRPTRequestName, &gRPTToken, dispatch_get_main_queue(), ^(int token) { RPT_OnRequest(); });
            if (st != NOTIFY_STATUS_OK) BP_Log(@"[rpt] cannot register for %s (status %u)", kRPTRequestName, (unsigned)st);
            else RPT_LOG(@"[rpt] listening for the Send logs request");
        });
    } @catch (NSException *e) {
        BP_Log(@"[rpt] setup failed: %@", e.name);
    }
}

#pragma clang diagnostic pop
