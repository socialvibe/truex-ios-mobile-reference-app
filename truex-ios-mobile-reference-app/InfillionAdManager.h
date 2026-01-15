//
//  InfillionAdManager.h
//  truex-ios-mobile-reference-app
//
//  Manages the TruexAdRenderer for Infillion interactive ads (TrueX and IDVx).
//
//  Infillion provides two types of interactive ad experiences:
//
//  TrueX Ads:
//  - Present an interactive choice card where users opt-in to engage with branded content
//  - When users complete the interaction, they earn an ad credit that skips the entire ad break
//  - Fires AD_FREE_POD event when credit is earned
//  - Configuration: Uses VAST config URL (description field)
//
//  IDVx Ads:
//  - Interactive ads that start automatically without requiring opt-in
//  - Play inline with other ads in the break sequence
//  - Never earn ad credits - always continue to next ad after completion
//  - Never fire AD_FREE_POD event
//  - Configuration: Uses adParameters JSON
//
//  This class handles event processing from the TruexAdRenderer and notifies the delegate
//  when the ad experience finishes, indicating whether credit was earned (TrueX only).
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "InfillionAdType.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Delegate protocol for InfillionAdManager events
 */
@protocol InfillionAdManagerDelegate <NSObject>

@required
/**
 * Called when the ad has started
 * @param campaignName The name of the ad campaign
 */
- (void)infillionAdDidStart:(NSString *)campaignName;

/**
 * Called when the ad has completed (success, error, or no ads)
 * @param receivedCredit YES if user earned credit (TrueX only), NO otherwise
 */
- (void)infillionAdDidComplete:(BOOL)receivedCredit;

@optional
/**
 * Called when a popup website is requested
 * @param url The URL to open
 */
- (void)infillionAdPopupWebsite:(NSString *)url;

/**
 * Called when user opts in to the engagement
 * @param campaignName The campaign name
 * @param adId The ad identifier
 */
- (void)infillionAdDidOptIn:(NSString *)campaignName adId:(NSInteger)adId;

/**
 * Called when user opts out of the engagement
 * @param userInitiated YES if user explicitly opted out
 */
- (void)infillionAdDidOptOut:(BOOL)userInitiated;

/**
 * Called when a skip card is shown
 */
- (void)infillionAdSkipCardShown;

/**
 * Called when user cancels the ad after opting in
 */
- (void)infillionAdUserCancel;

/**
 * Called when user wants to cancel the stream
 */
- (void)infillionAdUserCancelStream;

@end

/**
 * Manager class for Infillion interactive ads (TrueX and IDVx)
 */
@interface InfillionAdManager : NSObject

/**
 * Static flag to control whether user cancel stream is supported
 * Default is YES
 */
@property (class, nonatomic) BOOL supportsUserCancelStream;

/**
 * The delegate to receive ad events
 */
@property (nonatomic, weak, nullable) id<InfillionAdManagerDelegate> delegate;

/**
 * Initialize the manager
 */
- (instancetype)init;

/**
 * Start displaying an Infillion interactive engagement
 *
 * @param baseView The view in which to display the interactive engagement
 * @param vastConfigUrl VAST config URL for TrueX ads (pass for TrueX, nil for IDVx)
 * @param adParameters JSON configuration for IDVx ads (pass for IDVx, nil for TrueX)
 * @param slotType The slot type ("preroll" or "midroll")
 * @param adType TRUEX or IDVX
 */
- (void)startAdOnView:(UIView *)baseView
        vastConfigUrl:(nullable NSString *)vastConfigUrl
         adParameters:(nullable NSDictionary *)adParameters
             slotType:(NSString *)slotType
               adType:(InfillionAdType)adType;

/**
 * Pause the ad renderer (call when app goes to background)
 */
- (void)pause;

/**
 * Resume the ad renderer (call when app comes to foreground)
 */
- (void)resume;

/**
 * Stop and cleanup the ad renderer
 */
- (void)stop;

@end

NS_ASSUME_NONNULL_END
