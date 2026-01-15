//
//  InfillionAdManager.m
//  truex-ios-mobile-reference-app
//

#import "InfillionAdManager.h"
#import <TruexAdRenderer/TruexAdRenderer.h>
#import <TruexAdRenderer/TruexShared.h>

static BOOL _supportsUserCancelStream = YES;

@interface InfillionAdManager () <TruexAdRendererDelegate>

@property (nonatomic, strong) TruexAdRenderer *truexAdRenderer;
@property (nonatomic, assign) BOOL didReceiveCredit;

@end

@implementation InfillionAdManager

#pragma mark - Class Properties

+ (BOOL)supportsUserCancelStream {
    return _supportsUserCancelStream;
}

+ (void)setSupportsUserCancelStream:(BOOL)value {
    _supportsUserCancelStream = value;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _didReceiveCredit = NO;
    }
    return self;
}

#pragma mark - Public Methods

- (void)startAdOnView:(UIView *)baseView
        vastConfigUrl:(NSString *)vastConfigUrl
         adParameters:(NSDictionary *)adParameters
             slotType:(NSString *)slotType
               adType:(InfillionAdType)adType {

    NSLog(@"DEBUG: InfillionAdManager startAdOnView START - timestamp: %f", CACurrentMediaTime());
    NSLog(@"InfillionAdManager: startAd called - adType: %@, URL: %@, Has adParameters: %@",
          InfillionAdTypeToString(adType),
          vastConfigUrl,
          adParameters != nil ? @"YES" : @"NO");

    self.didReceiveCredit = NO;

    // Configure options
    NSLog(@"DEBUG: Configuring TruexAdOptions - timestamp: %f", CACurrentMediaTime());
    TruexAdOptions options;
    options.userAdvertisingId = nil;
    // Only TrueX ads support user cancel stream, IDVx ads should not
    BOOL isTrueXAd = (adType == InfillionAdTypeTruex);
    options.supportsUserCancelStream = isTrueXAd && [InfillionAdManager supportsUserCancelStream];
    options.appId = nil;
    options.enableWebViewDebugging = NO;
    NSLog(@"DEBUG: TruexAdOptions configured - timestamp: %f", CACurrentMediaTime());

    NSLog(@"InfillionAdManager: Creating TruexAdRenderer with supportsUserCancelStream=%@",
          options.supportsUserCancelStream ? @"YES" : @"NO");

    // Initialize renderer based on ad type
    if (adParameters != nil) {
        // IDVx ad - pass adParameters directly using new method
        NSLog(@"DEBUG: About to init TruexAdRenderer with adParameters (IDVx) - timestamp: %f", CACurrentMediaTime());
        self.truexAdRenderer = [[TruexAdRenderer alloc] initWithVastConfigJson:adParameters
                                                                       options:options
                                                                      delegate:self];
        NSLog(@"DEBUG: TruexAdRenderer init with adParameters DONE - timestamp: %f", CACurrentMediaTime());
    } else {
        // TrueX ad - use VAST URL
        NSLog(@"DEBUG: About to init TruexAdRenderer with vastConfigUrl (TrueX) - timestamp: %f", CACurrentMediaTime());
        self.truexAdRenderer = [[TruexAdRenderer alloc] initWithVastConfigUrl:vastConfigUrl
                                                                      options:options
                                                                     delegate:self];
        NSLog(@"DEBUG: TruexAdRenderer init with vastConfigUrl DONE - timestamp: %f", CACurrentMediaTime());
    }

    // Start the ad immediately
    NSLog(@"DEBUG: About to call truexAdRenderer.start - timestamp: %f", CACurrentMediaTime());
    [self.truexAdRenderer start:baseView];
    NSLog(@"DEBUG: truexAdRenderer.start returned - timestamp: %f", CACurrentMediaTime());
    NSLog(@"DEBUG: InfillionAdManager startAdOnView END - timestamp: %f", CACurrentMediaTime());
}

- (void)pause {
    [self.truexAdRenderer pause];
}

- (void)resume {
    [self.truexAdRenderer resume];
}

- (void)stop {
    NSLog(@"InfillionAdManager: Stopping and cleaning up");
    if (self.truexAdRenderer) {
        [self.truexAdRenderer stop];
        self.truexAdRenderer = nil;
    }
}

#pragma mark - TruexAdRendererDelegate Required Methods

- (void)onAdStarted:(NSString *)campaignName {
    NSLog(@"DEBUG: onAdStarted CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"InfillionAdManager: onAdStarted: %@", campaignName);
    if ([self.delegate respondsToSelector:@selector(infillionAdDidStart:)]) {
        [self.delegate infillionAdDidStart:campaignName];
    }
}

- (void)onAdCompleted:(NSInteger)timeSpent {
    NSLog(@"DEBUG: onAdCompleted CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"InfillionAdManager: onAdCompleted: %ld", (long)timeSpent);
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onAdError:(NSString *)errorMessage {
    NSLog(@"DEBUG: onAdError CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"InfillionAdManager: onAdError: %@", errorMessage);
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onNoAdsAvailable {
    NSLog(@"DEBUG: onNoAdsAvailable CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"InfillionAdManager: onNoAdsAvailable");
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onAdFreePod {
    // TrueX ads only: User completed the interactive experience and earned credit
    // This event allows skipping the entire ad break and returning to content
    // IDVx ads never fire this event - they always play inline and continue to next ad
    NSLog(@"InfillionAdManager: onAdFreePod - User earned credit");
    self.didReceiveCredit = YES;
}

- (void)onPopupWebsite:(NSString *)url {
    NSLog(@"InfillionAdManager: onPopupWebsite: %@", url);
    if ([self.delegate respondsToSelector:@selector(infillionAdPopupWebsite:)]) {
        [self.delegate infillionAdPopupWebsite:url];
    }
}

#pragma mark - TruexAdRendererDelegate Optional Methods

- (void)onOptIn:(NSString *)campaignName adId:(NSInteger)adId {
    NSLog(@"InfillionAdManager: onOptIn: %@, adId: %ld", campaignName, (long)adId);
    if ([self.delegate respondsToSelector:@selector(infillionAdDidOptIn:adId:)]) {
        [self.delegate infillionAdDidOptIn:campaignName adId:adId];
    }
}

- (void)onOptOut:(BOOL)userInitiated {
    NSLog(@"InfillionAdManager: onOptOut: userInitiated=%@", userInitiated ? @"YES" : @"NO");
    if ([self.delegate respondsToSelector:@selector(infillionAdDidOptOut:)]) {
        [self.delegate infillionAdDidOptOut:userInitiated];
    }
}

- (void)onSkipCardShown {
    NSLog(@"InfillionAdManager: onSkipCardShown");
    if ([self.delegate respondsToSelector:@selector(infillionAdSkipCardShown)]) {
        [self.delegate infillionAdSkipCardShown];
    }
}

- (void)onUserCancel {
    NSLog(@"InfillionAdManager: onUserCancel");
    if ([self.delegate respondsToSelector:@selector(infillionAdUserCancel)]) {
        [self.delegate infillionAdUserCancel];
    }
}

- (void)onUserCancelStream {
    // User backed out of the choice card, which means backing out of the entire video
    NSLog(@"InfillionAdManager: onUserCancelStream - didReceiveCredit=%@",
          self.didReceiveCredit ? @"YES" : @"NO");

    if ([self.delegate respondsToSelector:@selector(infillionAdUserCancelStream)]) {
        [self.delegate infillionAdUserCancelStream];
    }

    // For stream cancellation, we don't provide credit
    [self notifyCompletionWithCredit:NO];
}

#pragma mark - Private Methods

- (void)notifyCompletionWithCredit:(BOOL)receivedCredit {
    NSLog(@"InfillionAdManager: notifyCompletion - receivedCredit=%@",
          receivedCredit ? @"YES" : @"NO");
    if ([self.delegate respondsToSelector:@selector(infillionAdDidComplete:)]) {
        [self.delegate infillionAdDidComplete:receivedCredit];
    }
}

@end
