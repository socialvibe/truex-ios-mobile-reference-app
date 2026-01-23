//
//  AdBreak.m
//  truex-ios-mobile-reference-app
//

#import "AdBreak.h"

@implementation AdBreak

- (instancetype)init {
    self = [super init];
    if (self) {
        _ads = @[];
        _currentAdIndex = 0;
        _started = NO;
        _completed = NO;
    }
    return self;
}

- (Ad *)currentAd {
    if (self.currentAdIndex < self.ads.count) {
        return self.ads[self.currentAdIndex];
    }
    return nil;
}

- (Ad *)nextAd {
    self.currentAdIndex++;
    return [self currentAd];
}

- (void)reset {
    self.currentAdIndex = 0;
    self.started = NO;
    self.completed = NO;
}

- (int)duration {
    int total = 0;
    for (Ad *ad in self.ads) {
        total += ad.duration;
    }
    return total;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<AdBreak: %@ offset=%d duration=%d ads=%lu started=%@ completed=%@>",
            self.breakId, self.timeOffsetSeconds, [self duration],
            (unsigned long)self.ads.count,
            self.started ? @"YES" : @"NO",
            self.completed ? @"YES" : @"NO"];
}

@end
