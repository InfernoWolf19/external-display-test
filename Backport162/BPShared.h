// Declarations shared between the Backport162 translation units (G1C.x uses group 2's per-VC state and id builders).
#ifndef BP_SHARED_H
#define BP_SHARED_H
#import <Foundation/Foundation.h>

// State that 16.2 keeps in new ivars of SBFluidSwitcherViewController (G2.x keeps it in an associated object).
@interface BP162VCState : NSObject
@property (nonatomic, copy) NSArray *idsInStrip;
@property (nonatomic, copy) NSArray *idsInSwitcher;
@property (nonatomic) unsigned long long idsGeneration;
@end

BP162VCState *BP_G2_VCStateFor(id vc);
NSArray *BP_G2_ComputeSwitcherIds(id vc, id stageLayout, NSArray *strip);
NSArray *BP_G2_ComputeStripIds(id vc, id stageLayout, NSArray *prev, NSUInteger cap);

#endif
