// BPLoc.h : fallback localisation of the strings that iPadOS 16.2's SpringBoard.loctable has and 16.0's lacks (gap G8, specs/GAPS-IMPLEMENTED-0.7.9.md).
// 16.2 reads them with -[NSBundle localizedStringForKey:value:table:@"SpringBoard"] on the main bundle (SpringBoard.app/SpringBoard.loctable); the 16.0 file has no such keys.
// BPLoc_String() asks the real table first (so a bundle that does carry the keys wins), then the table embedded from the 16.2 loctable (BPL10N.h, 41 languages), then the 16.0 key
// with the same wording (optional), then the English literal.
#import <Foundation/Foundation.h>
#import "BPL10N.h"

// loctable language code for a BCP-47 tag of -[NSLocale preferredLanguages] ("zh-Hant-HK" -> zh_HK ...), the candidate list for one tag: [specific, base]
static inline NSArray<NSString *> *BPLoc_Candidates(NSString *tag) {
    NSString *t = [tag stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    NSArray<NSString *> *p = [t componentsSeparatedByString:@"-"];
    NSString *lang = p.count ? p[0].lowercaseString : @"";
    NSString *script = nil, *region = nil;
    for (NSUInteger i = 1; i < p.count; i++) {
        NSString *c = p[i];
        if (c.length == 4 && !script) script = c.lowercaseString;
        else if ((c.length == 2 || (c.length == 3 && [c characterAtIndex:0] >= '0' && [c characterAtIndex:0] <= '9')) && !region) region = c.uppercaseString;
    }
    if ([lang isEqualToString:@"nb"] || [lang isEqualToString:@"nn"]) lang = @"no";
    if ([lang isEqualToString:@"iw"]) lang = @"he";
    if ([lang isEqualToString:@"in"]) lang = @"id";
    NSString *specific = nil;
    if ([lang isEqualToString:@"zh"]) {
        if ([region isEqualToString:@"HK"] || [region isEqualToString:@"MO"]) specific = @"zh_HK";
        else if ([script isEqualToString:@"hant"] || [region isEqualToString:@"TW"]) specific = @"zh_TW";
        else specific = @"zh_CN";
    } else if ([lang isEqualToString:@"pt"]) {
        specific = [region isEqualToString:@"PT"] ? @"pt_PT" : @"pt";
    } else if ([lang isEqualToString:@"es"]) {
        specific = (region && ![region isEqualToString:@"ES"]) ? @"es_419" : @"es";
    } else if ([lang isEqualToString:@"en"]) {
        specific = [region isEqualToString:@"GB"] ? @"en_GB" : ([region isEqualToString:@"AU"] ? @"en_AU" : @"en");
    } else if ([lang isEqualToString:@"fr"]) {
        specific = [region isEqualToString:@"CA"] ? @"fr_CA" : @"fr";
    } else {
        specific = lang;
    }
    return [specific isEqualToString:lang] ? @[ specific ] : @[ specific, lang ];
}

// The text of `key` (a 16.2-only SpringBoard.loctable key) for the user's language.
static inline NSString *BPLoc_String(NSString *key, NSString *key160, NSString *english) {
    NSBundle *b = [NSBundle mainBundle];
    NSString *s = [b localizedStringForKey:key value:@"" table:@"SpringBoard"];
    if (s.length && ![s isEqualToString:key]) return s;                                // a bundle that has the key itself (16.2-style table)
    NSDictionary *table = BPL10N_Table();
    for (NSString *tag in [NSLocale preferredLanguages]) {
        for (NSString *code in BPLoc_Candidates(tag)) {
            NSString *e = table[code][key];
            if (e.length) return e;
        }
    }
    NSString *en = table[@"en"][key];
    if (en.length) return en;
    if (key160.length) {
        s = [b localizedStringForKey:key160 value:@"" table:@"SpringBoard"];
        if (s.length && ![s isEqualToString:key160]) return s;
    }
    return english;
}
