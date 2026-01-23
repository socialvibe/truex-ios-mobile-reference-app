//
//  AdBreak.h
//  truex-ios-mobile-reference-app
//

#import <Foundation/Foundation.h>
#import "Ad.h"

NS_ASSUME_NONNULL_BEGIN

@interface AdBreak : NSObject

@property (nonatomic, copy, nullable) NSString *breakId;
@property (nonatomic, assign) int timeOffsetSeconds;
@property (nonatomic, copy) NSArray<Ad *> *ads;

// State tracking (matches Android pattern)
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) int currentAdIndex;

- (nullable Ad *)currentAd;
- (nullable Ad *)nextAd;  // Increments index and returns next ad (or nil)
- (void)reset;
- (int)duration; // Sum of all ad durations

@end

NS_ASSUME_NONNULL_END
