//
//  InfillionAdType.h
//  truex-ios-mobile-reference-app
//
//  Types of ads supported by the reference app.
//
//  REGULAR: Traditional non-interactive video ads
//
//  TRUEX: Interactive choice card ads
//    - User opts in via choice card
//    - Completing interaction earns credit to skip entire ad break
//    - Fires AD_FREE_POD event when credit earned
//
//  IDVX: Interactive inline ads
//    - Starts automatically without opt-in
//    - Plays inline with other ads in the break
//    - Never earns credit, always continues to next ad
//

#import <Foundation/Foundation.h>

/**
 * Ad types supported by the Infillion ad renderer
 */
typedef NS_ENUM(NSInteger, InfillionAdType) {
    InfillionAdTypeRegular,  // Traditional video ads
    InfillionAdTypeTruex,    // Interactive choice card with ad credit
    InfillionAdTypeIDVx      // Interactive without credit, plays inline
};

/**
 * Convert ad system string to InfillionAdType
 * @param adSystem The ad system identifier ("trueX", "IDVx", or other)
 * @return The corresponding InfillionAdType
 */
NS_INLINE InfillionAdType InfillionAdTypeFromString(NSString *adSystem) {
    if ([adSystem isEqualToString:@"trueX"]) {
        return InfillionAdTypeTruex;
    } else if ([adSystem isEqualToString:@"IDVx"]) {
        return InfillionAdTypeIDVx;
    } else {
        return InfillionAdTypeRegular;
    }
}

/**
 * Check if the ad type is an Infillion interactive ad (TrueX or IDVx)
 * @param adType The ad type to check
 * @return YES if TrueX or IDVx, NO otherwise
 */
NS_INLINE BOOL IsInfillionAd(InfillionAdType adType) {
    return adType == InfillionAdTypeTruex || adType == InfillionAdTypeIDVx;
}

/**
 * Convert InfillionAdType to string for logging
 * @param adType The ad type
 * @return String representation
 */
NS_INLINE NSString* InfillionAdTypeToString(InfillionAdType adType) {
    switch (adType) {
        case InfillionAdTypeTruex:
            return @"TRUEX";
        case InfillionAdTypeIDVx:
            return @"IDVX";
        case InfillionAdTypeRegular:
        default:
            return @"REGULAR";
    }
}
