// Y32Proto.x : delta sweep pass 3, persistence of the 16.2 layout attribute fields in the recents protobuf (F3).  Setup: constructor.  Log prefix "[y32]".
//
//  y24_protoextras  Recent app layouts are persisted by SBRecentAppLayoutsPersister as PROTOBUF (found by scanning the 16.0 text: -[SBRecentAppLayoutsPersister _enqueueDiskWrite] /
//                   syncToDiskSynchronously call -[SBAppLayout protobufRepresentation], -_loadRecents calls +[SBAppLayout appLayoutWithProtobufRepresentation:]), not as plist: the plist side channel
//                   of G2B.m (referenceBounds / semanticSizeType keys) therefore did NOT cover them.  16.2 SBPBDisplayItemLayoutAttributes (readFrom: 0x1c778d360 ..., writeTo: 0x1c778db80)
//                   has six more fields than the 16.0 class (0x1c62f0a68 / 0x1c62f0fb8; the tags of the nine common fields c..14 are identical in both builds, so old files stay readable):
//                       0x15 referenceBoundsWidthForSize (double)       0x16 referenceBoundsHeightForSize (double)       0x17 semanticSizeTypeForSize (int32)
//                       0x1a referenceBoundsWidthBeforeOverlapping (double)  0x1b referenceBoundsHeightBeforeOverlapping (double)  0x1c semanticSizeTypeBeforeOverlapping (int32)
//                   (16.2 -[SBDisplayItemLayoutAttributes protobufRepresentation] 0x1c75d05fc stores the size of the reference bounds and the semantic types; +layoutAttributesWithProtobufRepresentation:
//                   0x1c75d0434 builds the attributed sizes back, an empty reference size means unspecified.)  Ported on top of the 16.0 classes:
//                     * -[SBDisplayItemLayoutAttributes protobufRepresentation]: the six values are taken from the plist representation (G2B.x keeps the extras there) and attached to the pb object;
//                     * -[SBPBDisplayItemLayoutAttributes writeTo:]: after the 16.0 fields the six fields are written with the 16.2 tags;
//                     * -[SBPBDisplayItemLayoutAttributes readFrom:]: the bytes of the message ([position, length) of the PBDataReader, which is bounded to the sub message) are scanned for the six
//                       tags before the 16.0 reader (which skips unknown tags) runs; the values are attached to the pb object;
//                     * +[SBDisplayItemLayoutAttributes layoutAttributesWithProtobufRepresentation:]: when the pb object carries values the result is rebuilt through the G2B.x plist initializer
//                       (initWithPlistRepresentation: reads the same keys), the reference bounds are (0, 0, width, height) as in 16.2.
// Needs a device: resize a window, respring, open the switcher: the recents keep their window sizes relative to the reference bounds (observable through Backport162.debug logs "[y32]").

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY32OrigRep, gY32OrigFromRep, gY32OrigWrite, gY32OrigRead;
static char kY32Extras;
typedef void (*Y32_WriteDoubleFn)(id, double, unsigned int);
typedef void (*Y32_WriteInt32Fn)(id, int, unsigned int);

// extras dictionary of a pb object: rw, rh (size), st, bw, bh (before overlapping), bt
static NSDictionary *Y32_Extras(id pb) { return objc_getAssociatedObject(pb, &kY32Extras); }

static double Y32_Num(NSDictionary *d, NSString *k) { return [d[k] isKindOfClass:[NSNumber class]] ? [d[k] doubleValue] : 0; }

static id Y32_Rep(id self, SEL _cmd) {
    id pb = gY32OrigRep ? ((id (*)(id, SEL))gY32OrigRep)(self, _cmd) : nil;
    if (!pb || !BP_OnName("y24_protoextras") || !BPY_Responds(self, "plistRepresentation")) return pb;
    id plist = BPY_SEND(id, (), self, "plistRepresentation");
    if (![plist isKindOfClass:[NSDictionary class]]) return pb;
    NSDictionary *d = plist;
    if (!d[@"referenceBounds"] && !d[@"referenceBoundsBeforeOverlapping"] && !d[@"semanticSizeType"] && !d[@"semanticSizeTypeBeforeOverlapping"]) return pb;      // no extras: nothing to add
    CGRect r1 = CGRectNull, r2 = CGRectNull;
    if ([d[@"referenceBounds"] isKindOfClass:[NSDictionary class]]) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)d[@"referenceBounds"], &r1);
    if ([d[@"referenceBoundsBeforeOverlapping"] isKindOfClass:[NSDictionary class]]) CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)d[@"referenceBoundsBeforeOverlapping"], &r2);
    NSDictionary *e = @{ @"rw": @(CGRectIsNull(r1) ? 0 : r1.size.width), @"rh": @(CGRectIsNull(r1) ? 0 : r1.size.height), @"st": d[@"semanticSizeType"] ?: @0,
                         @"bw": @(CGRectIsNull(r2) ? 0 : r2.size.width), @"bh": @(CGRectIsNull(r2) ? 0 : r2.size.height), @"bt": d[@"semanticSizeTypeBeforeOverlapping"] ?: @0 };
    objc_setAssociatedObject(pb, &kY32Extras, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return pb;
}

static void Y32_Write(id self, SEL _cmd, id writer) {
    if (gY32OrigWrite) ((void (*)(id, SEL, id))gY32OrigWrite)(self, _cmd, writer);
    NSDictionary *e = BP_OnName("y24_protoextras") ? Y32_Extras(self) : nil;
    if (!e) return;
    static Y32_WriteDoubleFn wd; static Y32_WriteInt32Fn wi; static dispatch_once_t once;
    dispatch_once(&once, ^{ wd = (Y32_WriteDoubleFn)dlsym(RTLD_DEFAULT, "PBDataWriterWriteDoubleField"); wi = (Y32_WriteInt32Fn)dlsym(RTLD_DEFAULT, "PBDataWriterWriteInt32Field");
        if (!wd || !wi) BP_Log(@"[y32] GUARD(protoextras) PBDataWriterWriteDoubleField / Int32Field do not resolve: the extra fields are not written"); });
    if (!wd || !wi) return;
    wd(writer, Y32_Num(e, @"rw"), 0x15);
    wd(writer, Y32_Num(e, @"rh"), 0x16);
    wi(writer, (int)Y32_Num(e, @"st"), 0x17);
    wd(writer, Y32_Num(e, @"bw"), 0x1a);
    wd(writer, Y32_Num(e, @"bh"), 0x1b);
    wi(writer, (int)Y32_Num(e, @"bt"), 0x1c);
}

// protobuf scan of [pos, end) for the six tags
static BOOL Y32_Varint(const unsigned char *b, unsigned long long *p, unsigned long long end, unsigned long long *out) {
    unsigned long long v = 0; int shift = 0;
    while (*p < end && shift < 70) { unsigned char c = b[(*p)++]; v |= (unsigned long long)(c & 0x7f) << shift; if (!(c & 0x80)) { *out = v; return YES; } shift += 7; }
    return NO;
}
static NSDictionary *Y32_Scan(id reader) {
    Ivar ipos = class_getInstanceVariable(object_getClass(reader), "_pos"), ilen = class_getInstanceVariable(object_getClass(reader), "_length"), ibytes = class_getInstanceVariable(object_getClass(reader), "_bytes");
    if (!ipos || !ilen || !ibytes) { Y17_GuardOnce("protoextras", reader, "_pos / _length / _bytes"); return nil; }
    char *base = (char *)(__bridge void *)reader;
    unsigned long long pos = *(unsigned long long *)(base + ivar_getOffset(ipos)), end = *(unsigned long long *)(base + ivar_getOffset(ilen));
    const unsigned char *bytes = *(const unsigned char **)(base + ivar_getOffset(ibytes));
    if (!bytes || pos >= end) return nil;
    NSMutableDictionary *e = [NSMutableDictionary dictionary];
    while (pos < end) {
        unsigned long long key;
        if (!Y32_Varint(bytes, &pos, end, &key)) break;
        unsigned long long field = key >> 3; int wire = key & 7;
        if (wire == 1) {
            if (pos + 8 > end) break;
            double dv; memcpy(&dv, bytes + pos, 8); pos += 8;
            if (field == 0x15) e[@"rw"] = @(dv); else if (field == 0x16) e[@"rh"] = @(dv); else if (field == 0x1a) e[@"bw"] = @(dv); else if (field == 0x1b) e[@"bh"] = @(dv);
        } else if (wire == 0) {
            unsigned long long v; if (!Y32_Varint(bytes, &pos, end, &v)) break;
            if (field == 0x17) e[@"st"] = @((int)v); else if (field == 0x1c) e[@"bt"] = @((int)v);
        } else if (wire == 5) { if (pos + 4 > end) break; pos += 4; }
        else if (wire == 2) { unsigned long long n; if (!Y32_Varint(bytes, &pos, end, &n) || pos + n > end) break; pos += n; }
        else break;
    }
    return e.count ? e : nil;
}
static BOOL Y32_Read(id self, SEL _cmd, id reader) {
    NSDictionary *e = BP_OnName("y24_protoextras") ? Y32_Scan(reader) : nil;
    BOOL r = gY32OrigRead ? ((BOOL (*)(id, SEL, id))gY32OrigRead)(self, _cmd, reader) : NO;
    if (r && e) objc_setAssociatedObject(self, &kY32Extras, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return r;
}

static id Y32_FromRep(id cls, SEL _cmd, id pb) {
    id a = gY32OrigFromRep ? ((id (*)(id, SEL, id))gY32OrigFromRep)(cls, _cmd, pb) : nil;
    NSDictionary *e = (a && pb && BP_OnName("y24_protoextras")) ? Y32_Extras(pb) : nil;
    if (!e || !BPY_Responds(a, "plistRepresentation") || ![(id)cls instancesRespondToSelector:sel_registerName("initWithPlistRepresentation:")]) return a;
    id plist = BPY_SEND(id, (), a, "plistRepresentation");
    if (![plist isKindOfClass:[NSDictionary class]]) return a;
    NSMutableDictionary *m = [plist mutableCopy];
    double rw = Y32_Num(e, @"rw"), rh = Y32_Num(e, @"rh"), bw = Y32_Num(e, @"bw"), bh = Y32_Num(e, @"bh");
    if (rw > 0 && rh > 0) { CFDictionaryRef d = CGRectCreateDictionaryRepresentation(CGRectMake(0, 0, rw, rh)); if (d) { m[@"referenceBounds"] = (__bridge NSDictionary *)d; CFRelease(d); } }
    if (bw > 0 && bh > 0) { CFDictionaryRef d = CGRectCreateDictionaryRepresentation(CGRectMake(0, 0, bw, bh)); if (d) { m[@"referenceBoundsBeforeOverlapping"] = (__bridge NSDictionary *)d; CFRelease(d); } }
    m[@"semanticSizeType"] = @((long long)Y32_Num(e, @"st"));
    m[@"semanticSizeTypeBeforeOverlapping"] = @((long long)Y32_Num(e, @"bt"));
    id b = ((id (*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
    b = ((id (*)(id, SEL, id))objc_msgSend)(b, sel_registerName("initWithPlistRepresentation:"), m);
    BPY_LOG(@"[y32] layout attributes restored from the protobuf with the 16.2 reference fields (%@)", e);
    return b ?: a;
}

__attribute__((constructor)) static void Y32_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class attr = NSClassFromString(@"SBDisplayItemLayoutAttributes"), pb = NSClassFromString(@"SBPBDisplayItemLayoutAttributes");
        Class meta = attr ? object_getClass((id)attr) : Nil;
        if (!attr || !pb || !class_getInstanceMethod(attr, sel_registerName("protobufRepresentation")) || !class_getInstanceMethod(meta, sel_registerName("layoutAttributesWithProtobufRepresentation:")) ||
            !class_getInstanceMethod(pb, sel_registerName("writeTo:")) || !class_getInstanceMethod(pb, sel_registerName("readFrom:"))) {
            BP_Log(@"[y32] GUARD(protoextras) SBDisplayItemLayoutAttributes / SBPBDisplayItemLayoutAttributes protobuf methods missing: not installed");
            return;
        }
        gY32OrigRep = BPX_Replace(attr, "protobufRepresentation", (IMP)Y32_Rep);
        gY32OrigFromRep = BPX_Replace(meta, "layoutAttributesWithProtobufRepresentation:", (IMP)Y32_FromRep);
        gY32OrigWrite = BPX_Replace(pb, "writeTo:", (IMP)Y32_Write);
        gY32OrigRead = BPX_Replace(pb, "readFrom:", (IMP)Y32_Read);
        BP_Log(@"[y32] installed y24_protoextras");
    }
}
#pragma clang diagnostic pop
