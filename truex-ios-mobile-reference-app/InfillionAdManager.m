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

    NSLog(@"[TrueX] InfillionAdManager startAdOnView START - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] startAd called - adType: %@, URL: %@, Has adParameters: %@",
          InfillionAdTypeToString(adType),
          vastConfigUrl,
          adParameters != nil ? @"YES" : @"NO");

    self.didReceiveCredit = NO;

    // Configure options
    NSLog(@"[TrueX] Configuring TruexAdOptions - timestamp: %f", CACurrentMediaTime());
    TruexAdOptions options;
    options.userAdvertisingId = nil;
    // Only TrueX ads support user cancel stream, IDVx ads should not
    BOOL isTrueXAd = (adType == InfillionAdTypeTruex);
    options.supportsUserCancelStream = isTrueXAd && [InfillionAdManager supportsUserCancelStream];
    options.appId = nil;
    options.enableWebViewDebugging = NO;
    NSLog(@"[TrueX] TruexAdOptions configured - timestamp: %f", CACurrentMediaTime());

    NSLog(@"[TrueX] Creating TruexAdRenderer with supportsUserCancelStream=%@",
          options.supportsUserCancelStream ? @"YES" : @"NO");

    // Initialize renderer based on ad type
    if (adParameters != nil) {
        // IDVx ad - pass adParameters directly using new method
        NSLog(@"[TrueX] About to init TruexAdRenderer with adParameters (IDVx) - timestamp: %f", CACurrentMediaTime());
        self.truexAdRenderer = [[TruexAdRenderer alloc] initWithVastConfigJson:adParameters
                                                                       options:options
                                                                      delegate:self];
        NSLog(@"[TrueX] TruexAdRenderer init with adParameters DONE - timestamp: %f", CACurrentMediaTime());
    } else {
        // TrueX ad - use VAST URL
        NSLog(@"[TrueX] About to init TruexAdRenderer with vastConfigUrl (TrueX) - timestamp: %f", CACurrentMediaTime());
        self.truexAdRenderer = [[TruexAdRenderer alloc] initWithVastConfigUrl:vastConfigUrl
                                                                      options:options
                                                                     delegate:self];
        NSLog(@"[TrueX] TruexAdRenderer init with vastConfigUrl DONE - timestamp: %f", CACurrentMediaTime());
    }

    // Start the ad immediately
    NSLog(@"[TrueX] About to call truexAdRenderer.start - timestamp: %f", CACurrentMediaTime());
    [self.truexAdRenderer start:baseView];
    NSLog(@"[TrueX] truexAdRenderer.start returned - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] InfillionAdManager startAdOnView END - timestamp: %f", CACurrentMediaTime());
}

- (void)pause {
    [self.truexAdRenderer pause];
}

- (void)resume {
    [self.truexAdRenderer resume];
}

- (void)stop {
    NSLog(@"[TrueX] Stopping and cleaning up");
    if (self.truexAdRenderer) {
        [self.truexAdRenderer stop];
        self.truexAdRenderer = nil;
    }
}

#pragma mark - TruexAdRendererDelegate Required Methods

- (void)onAdStarted:(NSString *)campaignName {
    NSLog(@"[TrueX] onAdStarted CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] onAdStarted: %@", campaignName);
    if ([self.delegate respondsToSelector:@selector(infillionAdDidStart:)]) {
        [self.delegate infillionAdDidStart:campaignName];
    }
}

- (void)onAdCompleted:(NSInteger)timeSpent {
    NSLog(@"[TrueX] onAdCompleted CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] onAdCompleted: %ld", (long)timeSpent);
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onAdError:(NSString *)errorMessage {
    NSLog(@"[TrueX] onAdError CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] onAdError: %@", errorMessage);
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onNoAdsAvailable {
    NSLog(@"[TrueX] onNoAdsAvailable CALLBACK received - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] onNoAdsAvailable");
    [self notifyCompletionWithCredit:self.didReceiveCredit];
}

- (void)onAdFreePod {
    // TrueX ads only: User completed the interactive experience and earned credit
    // This event allows skipping the entire ad break and returning to content
    // IDVx ads never fire this event - they always play inline and continue to next ad
    NSLog(@"[TrueX] onAdFreePod - User earned credit");
    self.didReceiveCredit = YES;
}

- (void)onPopupWebsite:(NSString *)url {
    NSLog(@"[TrueX] onPopupWebsite: %@", url);
    if ([self.delegate respondsToSelector:@selector(infillionAdPopupWebsite:)]) {
        [self.delegate infillionAdPopupWebsite:url];
    }
}

#pragma mark - TruexAdRendererDelegate Optional Methods

- (void)onOptIn:(NSString *)campaignName adId:(NSInteger)adId {
    NSLog(@"[TrueX] onOptIn: %@, adId: %ld", campaignName, (long)adId);
    if ([self.delegate respondsToSelector:@selector(infillionAdDidOptIn:adId:)]) {
        [self.delegate infillionAdDidOptIn:campaignName adId:adId];
    }
}

- (void)onOptOut:(BOOL)userInitiated {
    NSLog(@"[TrueX] onOptOut: userInitiated=%@", userInitiated ? @"YES" : @"NO");
    if ([self.delegate respondsToSelector:@selector(infillionAdDidOptOut:)]) {
        [self.delegate infillionAdDidOptOut:userInitiated];
    }
}

- (void)onSkipCardShown {
    NSLog(@"[TrueX] onSkipCardShown");
    if ([self.delegate respondsToSelector:@selector(infillionAdSkipCardShown)]) {
        [self.delegate infillionAdSkipCardShown];
    }
}

- (void)onUserCancel {
    NSLog(@"[TrueX] onUserCancel");
    if ([self.delegate respondsToSelector:@selector(infillionAdUserCancel)]) {
        [self.delegate infillionAdUserCancel];
    }
}

- (void)onUserCancelStream {
    // User backed out of the choice card, which means backing out of the entire video
    NSLog(@"[TrueX] onUserCancelStream - didReceiveCredit=%@",
          self.didReceiveCredit ? @"YES" : @"NO");

    if ([self.delegate respondsToSelector:@selector(infillionAdUserCancelStream)]) {
        [self.delegate infillionAdUserCancelStream];
    }

    // For stream cancellation, we don't provide credit
    [self notifyCompletionWithCredit:NO];
}

#pragma mark - Private Methods

- (void)notifyCompletionWithCredit:(BOOL)receivedCredit {
    NSLog(@"[TrueX] notifyCompletion - receivedCredit=%@",
          receivedCredit ? @"YES" : @"NO");
    if ([self.delegate respondsToSelector:@selector(infillionAdDidComplete:)]) {
        [self.delegate infillionAdDidComplete:receivedCredit];
    }
}

@end
