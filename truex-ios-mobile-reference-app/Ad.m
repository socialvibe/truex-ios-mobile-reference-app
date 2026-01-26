//
//  Ad.m
//  truex-ios-mobile-reference-app
//

#import "Ad.h"

@implementation Ad

- (BOOL)isInfillionAd {
    return [self isTrueXAd] || [self isIDVxAd];
}

- (BOOL)isTrueXAd {
    return [self.adSystem isEqualToString:@"trueX"];
}

- (BOOL)isIDVxAd {
    return [self.adSystem isEqualToString:@"IDVx"];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Ad: %@ (%@) duration=%d>", self.adId, self.adSystem, self.duration];
}

@end
