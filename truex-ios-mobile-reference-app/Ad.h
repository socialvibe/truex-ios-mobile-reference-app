//
//  Ad.h
//  truex-ios-mobile-reference-app
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Ad : NSObject

@property (nonatomic, copy, nullable) NSString *adId;
@property (nonatomic, copy, nullable) NSString *adSystem;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *wrapperUrl;
@property (nonatomic, copy, nullable) NSString *mediaFile;
@property (nonatomic, assign) int duration;
@property (nonatomic, strong, nullable) NSDictionary *adParameters; // Resolved from wrapper

- (BOOL)isInfillionAd;  // adSystem == "trueX" || "IDVx"
- (BOOL)isTrueXAd;
- (BOOL)isIDVxAd;

@end

NS_ASSUME_NONNULL_END
