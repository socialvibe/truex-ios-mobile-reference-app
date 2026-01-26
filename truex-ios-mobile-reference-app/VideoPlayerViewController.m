//
//  VideoPlayerViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "VideoPlayerViewController.h"
#import "WebViewViewController.h"
#import "InfillionAdManager.h"
#import "InfillionAdType.h"
#import "VmapParser.h"

// Helper class to parse AdParameters from VAST XML response
@interface VastAdParametersParserDelegate : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSString *adParametersJson;
@property (nonatomic, strong) NSMutableString *currentElementValue;
@property (nonatomic, assign) BOOL inLinear;
@end

@implementation VastAdParametersParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    self.currentElementValue = [NSMutableString string];
    if ([elementName isEqualToString:@"Linear"]) {
        self.inLinear = YES;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentElementValue appendString:string];
}

- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)CDATABlock {
    NSString *cdataString = [[NSString alloc] initWithData:CDATABlock encoding:NSUTF8StringEncoding];
    if (cdataString) {
        [self.currentElementValue appendString:cdataString];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"Linear"]) {
        self.inLinear = NO;
    } else if ([elementName isEqualToString:@"AdParameters"] && self.inLinear) {
        NSString *value = [self.currentElementValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value.length > 0 && !self.adParametersJson) {
            self.adParametersJson = value;
        }
    }
}

@end

@interface VideoPlayerViewController ()

@property (nonatomic, strong) InfillionAdManager *adManager;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) VideoMap *videoMap;
@property (nonatomic, strong) AVPlayerItem *contentPlayerItem;

// Ad break state
@property (nonatomic, assign) BOOL inAdBreak;
@property (nonatomic, assign) BOOL snappingBack;
@property (nonatomic, assign) Float64 adBreakPausePosition;

// Time observer tokens for cleanup
@property (nonatomic, strong) NSMutableArray *timeObservers;

@end

@implementation VideoPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(pause)
                                               name:UIApplicationWillResignActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(resume)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];

    // Hide player controls until asset is loaded
    self.showsPlaybackControls = NO;

    // Create loading indicator
    if (@available(iOS 13.0, *)) {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    } else {
        self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    }
    self.loadingIndicator.color = [UIColor whiteColor];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingIndicator.hidesWhenStopped = YES;
    [self.view addSubview:self.loadingIndicator];
    [NSLayoutConstraint activateConstraints:@[
        [self.loadingIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSLog(@"[TrueX] viewDidAppear START - timestamp: %f", CACurrentMediaTime());
    [self loadAdBreaksFromVMAP];
    NSLog(@"[TrueX] viewDidAppear END - timestamp: %f", CACurrentMediaTime());
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self.loadingIndicator stopAnimating];
    [self resetAdManager];

    // Clean up time observers
    for (id observer in self.timeObservers) {
        [self.player removeTimeObserver:observer];
    }
    [self.timeObservers removeAllObjects];

    // Clean up regular ad notification observer
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];

    self.contentPlayerItem = nil;
    self.videoMap = nil;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    // Hide home indicator during Infillion Ad
    return (self.adManager != nil);
}

- (BOOL)prefersStatusBarHidden {
    // Hide the status bar during Infillion Ad
    return (self.adManager != nil);
}

- (void)pause {
    // Pause the Infillion Ad Renderer
    [self.adManager pause];
}

- (void)resume {
    [self.adManager resume];
}

- (void)resetAdManager {
    if (self.adManager) {
        [self.adManager stop];
    }
    self.adManager = nil;
}

// MARK: - Fake Ad Manager's Video Life Cycle Callbacks
- (void)videoStarted {
    NSLog(@"[TrueX] Video Started");
}

- (void)videoEnded {
    NSLog(@"[TrueX] Video Ended");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)adBreakStarted {
    NSLog(@"[TrueX] adBreakStarted START - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] Ad Break Started");
    self.requiresLinearPlayback = YES;

    // Store current position to resume from after all ads complete
    self.adBreakPausePosition = CMTimeGetSeconds(self.player.currentTime);
    NSLog(@"[TrueX] Storing pause position: %f - timestamp: %f", self.adBreakPausePosition, CACurrentMediaTime());

    // Reset ad index for new break
    AdBreak *currentAdBreak = [self currentAdBreak];
    if (currentAdBreak) {
        currentAdBreak.currentAdIndex = 0;
    }

    // Resolve wrapper URLs for all Infillion ads in this break before playing
    [self resolveWrappersForCurrentBreakWithCompletion:^{
        NSLog(@"[TrueX] Wrapper resolution complete, starting ad playback - timestamp: %f", CACurrentMediaTime());
        [self playNextAdInBreak];
    }];

    NSLog(@"[TrueX] adBreakStarted END - timestamp: %f", CACurrentMediaTime());
}

// Resolve all wrapper URLs for Infillion ads in the current break
- (void)resolveWrappersForCurrentBreakWithCompletion:(void (^)(void))completion {
    AdBreak *currentAdBreak = [self currentAdBreak];
    if (!currentAdBreak) {
        completion();
        return;
    }

    NSArray<Ad *> *ads = currentAdBreak.ads;
    if (!ads || ads.count == 0) {
        completion();
        return;
    }

    // Find all Infillion ads with wrapper URLs that need resolution
    NSMutableArray<Ad *> *adsToResolve = [NSMutableArray array];
    for (Ad *ad in ads) {
        if ([ad isInfillionAd] && ad.wrapperUrl && !ad.adParameters) {
            [adsToResolve addObject:ad];
        }
    }

    if (adsToResolve.count == 0) {
        completion();
        return;
    }

    NSLog(@"[TrueX] Resolving %lu wrapper URLs - timestamp: %f", (unsigned long)adsToResolve.count, CACurrentMediaTime());

    // Use dispatch group to wait for all resolutions
    dispatch_group_t group = dispatch_group_create();

    for (Ad *ad in adsToResolve) {
        dispatch_group_enter(group);
        NSString *wrapperUrl = ad.wrapperUrl;

        [self resolveWrapperUrl:wrapperUrl completion:^(NSDictionary *adParameters) {
            if (adParameters) {
                ad.adParameters = adParameters;
                NSLog(@"[TrueX] Resolved wrapper for ad %@ - timestamp: %f", ad.adId, CACurrentMediaTime());
            } else {
                NSLog(@"[TrueX] Failed to resolve wrapper for ad %@ - timestamp: %f", ad.adId, CACurrentMediaTime());
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        completion();
    });
}

// Fetch a wrapper URL and extract adParameters from the VAST response
- (void)resolveWrapperUrl:(NSString *)urlString completion:(void (^)(NSDictionary *adParameters))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"[TrueX] Invalid wrapper URL: %@", urlString);
        completion(nil);
        return;
    }

    NSLog(@"[TrueX] Fetching wrapper URL: %@ - timestamp: %f", urlString, CACurrentMediaTime());

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[TrueX] Error fetching wrapper: %@", error);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
            return;
        }

        // Parse VAST XML to extract AdParameters
        NSDictionary *adParameters = [self parseAdParametersFromVastData:data];

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(adParameters);
        });
    }];
    [task resume];
}

// Parse AdParameters JSON from VAST XML data
- (NSDictionary *)parseAdParametersFromVastData:(NSData *)data {
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];

    // Use a helper class for parsing
    VastAdParametersParserDelegate *parserDelegate = [[VastAdParametersParserDelegate alloc] init];
    parser.delegate = parserDelegate;

    if ([parser parse] && parserDelegate.adParametersJson) {
        NSError *jsonError = nil;
        NSDictionary *params = [NSJSONSerialization JSONObjectWithData:[parserDelegate.adParametersJson dataUsingEncoding:NSUTF8StringEncoding]
                                                               options:0
                                                                 error:&jsonError];
        if (params && !jsonError) {
            return params;
        }
        NSLog(@"[TrueX] Error parsing AdParameters JSON: %@", jsonError);
    }

    return nil;
}

// Play the next ad in the current break
- (void)playNextAdInBreak {
    AdBreak *currentAdBreak = [self currentAdBreak];
    Ad *ad = [currentAdBreak currentAd];

    NSLog(@"[TrueX] playNextAdInBreak START - index: %d - timestamp: %f", currentAdBreak.currentAdIndex, CACurrentMediaTime());

    // Check if there are more ads to play
    if (!ad) {
        // No more ads, resume content
        NSLog(@"[TrueX] No more ads in break, resuming content - timestamp: %f", CACurrentMediaTime());
        [self resumeContentAfterAds];
        return;
    }

    InfillionAdType adType = InfillionAdTypeFromString(ad.adSystem);

    NSLog(@"[TrueX] Playing ad at index %d - type: %@ (raw: %@) - timestamp: %f",
          currentAdBreak.currentAdIndex, InfillionAdTypeToString(adType), ad.adSystem, CACurrentMediaTime());

    // Advance to next ad for the next call
    [currentAdBreak nextAd];

    if ([ad isInfillionAd]) {
        // Play interactive Infillion ad (TrueX or IDVx)
        [self playInfillionAd:ad adType:adType];
    } else {
        // Play standard video ad (e.g., GDFP)
        [self playStandardVideoAd:ad];
    }

    NSLog(@"[TrueX] playNextAdInBreak END - timestamp: %f", CACurrentMediaTime());
}

// Play an interactive Infillion ad (TrueX or IDVx)
- (void)playInfillionAd:(Ad *)ad adType:(InfillionAdType)adType {
    NSLog(@"[TrueX] playInfillionAd START - timestamp: %f", CACurrentMediaTime());

    [self.player pause];
    [self resetAdManager];

    NSString* slotType = (self.adBreakPausePosition < 1) ? @"preroll" : @"midroll";

    // Create the InfillionAdManager
    self.adManager = [[InfillionAdManager alloc] init];
    self.adManager.delegate = self;

    // Get adParameters (resolved from wrapper URL when ad break started)
    NSDictionary *adParameters = ad.adParameters;

    if (!adParameters) {
        NSLog(@"[TrueX] No adParameters for ad %@, skipping", ad.adId);
        [self playNextAdInBreak];
        return;
    }

    NSLog(@"[TrueX] Starting %@ ad with adParameters", InfillionAdTypeToString(adType));

    // Start the Infillion ad (vastConfigUrl is nil, using adParameters)
    [self.adManager startAdOnView:self.view
                    vastConfigUrl:nil
                     adParameters:adParameters
                         slotType:slotType
                           adType:adType];

    NSLog(@"[TrueX] playInfillionAd END - timestamp: %f", CACurrentMediaTime());
}

// Play a standard video ad by loading its mediaFile URL
- (void)playStandardVideoAd:(Ad *)ad {
    NSString* mediaFile = ad.mediaFile;
    NSString* title = ad.title;

    NSLog(@"[TrueX] playStandardVideoAd START - title: %@, mediaFile: %@ - timestamp: %f",
          title, mediaFile, CACurrentMediaTime());

    if (mediaFile == nil) {
        NSLog(@"[TrueX] No mediaFile for ad, skipping to next - timestamp: %f", CACurrentMediaTime());
        [self playNextAdInBreak];
        return;
    }

    // Remove any existing observers
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                  object:nil];

    // Create player item for the ad
    NSURL* adUrl = [NSURL URLWithString:mediaFile];
    NSLog(@"[TrueX] Creating AVPlayerItem with URL: %@ - timestamp: %f", adUrl, CACurrentMediaTime());
    AVPlayerItem* adPlayerItem = [AVPlayerItem playerItemWithURL:adUrl];
    NSLog(@"[TrueX] AVPlayerItem created, status: %ld - timestamp: %f", (long)adPlayerItem.status, CACurrentMediaTime());

    // Listen for when the ad finishes
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(standardVideoAdDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:adPlayerItem];

    // Listen for errors
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(standardVideoAdDidFail:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:adPlayerItem];

    // Add KVO for status changes
    [adPlayerItem addObserver:self
                   forKeyPath:@"status"
                      options:NSKeyValueObservingOptionNew
                      context:nil];

    // Swap to the ad video and play
    NSLog(@"[TrueX] Replacing player item - timestamp: %f", CACurrentMediaTime());
    [self.player replaceCurrentItemWithPlayerItem:adPlayerItem];
    NSLog(@"[TrueX] Player item replaced, calling play - timestamp: %f", CACurrentMediaTime());
    [self.player play];
    NSLog(@"[TrueX] Player rate after play: %f - timestamp: %f", self.player.rate, CACurrentMediaTime());

    NSLog(@"[TrueX] playStandardVideoAd END - timestamp: %f", CACurrentMediaTime());
}

// KVO observer for player item status
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
        NSLog(@"[TrueX] AVPlayerItem status changed to: %ld - timestamp: %f", (long)playerItem.status, CACurrentMediaTime());
        if (playerItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"[TrueX] AVPlayerItem FAILED with error: %@ - timestamp: %f", playerItem.error, CACurrentMediaTime());
        } else if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
            NSLog(@"[TrueX] AVPlayerItem ready to play - timestamp: %f", CACurrentMediaTime());
        }
        // Remove observer after status is determined
        @try {
            [playerItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
            // Observer already removed
        }
    }
}

// Called when a standard video ad fails to play
- (void)standardVideoAdDidFail:(NSNotification*)notification {
    NSLog(@"[TrueX] standardVideoAdDidFail - error: %@ - timestamp: %f", notification.userInfo, CACurrentMediaTime());

    // Remove observers
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:notification.object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                  object:notification.object];

    // Skip to next ad
    [self playNextAdInBreak];
}

// Called when a standard video ad finishes playing
- (void)standardVideoAdDidFinish:(NSNotification*)notification {
    NSLog(@"[TrueX] standardVideoAdDidFinish START - timestamp: %f", CACurrentMediaTime());

    // Remove observers for this notification
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:notification.object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                  object:notification.object];

    NSLog(@"[TrueX] standardVideoAdDidFinish - calling playNextAdInBreak - timestamp: %f", CACurrentMediaTime());
    // Play the next ad in the break
    [self playNextAdInBreak];
}

- (void)adBreakEnded {
    NSLog(@"[TrueX] Ad Break Ended");
    self.requiresLinearPlayback = NO;
}

// Resume content playback after ads complete
- (void)resumeContentAfterAds {
    NSLog(@"[TrueX] resumeContentAfterAds START - restoring to position %f - timestamp: %f", self.adBreakPausePosition, CACurrentMediaTime());

    // Mark the ad break as completed BEFORE restoring content
    // This prevents the periodic observer from re-triggering the ad break
    [self markCurrentAdBreakAsCompleted];

    // Restore the content player item
    if (self.contentPlayerItem != nil) {
        [self.player replaceCurrentItemWithPlayerItem:self.contentPlayerItem];

        // Seek to the resume position, then play
        CMTime seekTime = CMTimeMakeWithSeconds(self.adBreakPausePosition, NSEC_PER_SEC);
        __weak typeof(self) weakSelf = self;
        [self.player seekToTime:seekTime completionHandler:^(BOOL finished) {
            NSLog(@"[TrueX] Content restored and seeked to %f (finished=%@) - timestamp: %f",
                  weakSelf.adBreakPausePosition, finished ? @"YES" : @"NO", CACurrentMediaTime());
            // End the ad break and resume playback after seek completes
            [weakSelf helperEndAdBreak];
            [weakSelf.player play];
            NSLog(@"[TrueX] resumeContentAfterAds - playback resumed - timestamp: %f", CACurrentMediaTime());
        }];
    } else {
        // No content player item, just end the ad break
        NSLog(@"[TrueX] resumeContentAfterAds - no contentPlayerItem, ending ad break - timestamp: %f", CACurrentMediaTime());
        [self helperEndAdBreak];
    }

    NSLog(@"[TrueX] resumeContentAfterAds END - timestamp: %f", CACurrentMediaTime());
}

// MARK: - InfillionAdManagerDelegate Methods

- (void)infillionAdDidStart:(NSString *)campaignName {
    // User has started their ad engagement
    NSLog(@"[TrueX] onAdStarted: %@", campaignName);
}

- (void)infillionAdDidComplete:(BOOL)receivedCredit {
    // User has finished the Infillion engagement
    NSLog(@"[TrueX] infillionAdDidComplete START - receivedCredit=%@ - timestamp: %f", receivedCredit ? @"YES" : @"NO", CACurrentMediaTime());
    NSLog(@"[TrueX] onAdComplete: receivedCredit=%@", receivedCredit ? @"YES" : @"NO");

    [self resetAdManager];

    if (receivedCredit) {
        // TrueX only: User earned credit, skip ALL remaining ads in the break
        NSLog(@"[TrueX] User earned credit, skipping remaining ads and resuming content - timestamp: %f", CACurrentMediaTime());

        [self resumeContentAfterAds];
    } else {
        // No credit received - play the next ad in the break (Infillion or standard)
        NSLog(@"[TrueX] No credit, playing next ad in break - timestamp: %f", CACurrentMediaTime());
        [self playNextAdInBreak];
    }

    NSLog(@"[TrueX] infillionAdDidComplete END - timestamp: %f", CACurrentMediaTime());
}

- (void)infillionAdPopupWebsite:(NSString *)url {
    // User wants to open an external link in the Infillion ad
    NSLog(@"[TrueX] onPopupWebsite: %@", url);

    // Open with the existing in-app webview
    UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    WebViewViewController* newViewController = [storyBoard instantiateViewControllerWithIdentifier:@"webviewVC"];
    newViewController.url = [NSURL URLWithString:url];
    newViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    __weak typeof(self) weakSelf = self;
    newViewController.onDismiss = ^(void) {
        // Resume the Infillion Ad Renderer
        [weakSelf.adManager resume];
    };
    [self.adManager pause];
    [self presentViewController:newViewController animated:YES completion:nil];
}

// MARK: @optional InfillionAdManagerDelegate methods

- (void)infillionAdDidOptIn:(NSString *)campaignName adId:(NSInteger)adId {
    // This event is triggered when a user decides opt-in to the interactive ad
    NSLog(@"[TrueX] onOptIn: %@, %li", campaignName, (long)adId);
}

- (void)infillionAdDidOptOut:(BOOL)userInitiated {
    // User has opted out of the engagement, show standard ads
    NSLog(@"[TrueX] onOptOut: userInitiated=%@", userInitiated ? @"YES" : @"NO");
}

- (void)infillionAdSkipCardShown {
    // Displayed a Skip Card
    NSLog(@"[TrueX] onSkipCardShown");
}

- (void)infillionAdUserCancel {
    // User backs out of the interactive ad unit after having opted in.
    NSLog(@"[TrueX] onUserCancel");
}

- (void)infillionAdUserCancelStream {
    // User wants to cancel the stream
    NSLog(@"[TrueX] onUserCancelStream");
}

// MARK: - Helper Functions / JSON Loading

// Stream configuration
static NSString *const STREAM_URL = @"https://ctv.truex.com/assets/reference-app-stream-no-ads-720p.mp4";
static NSInteger const STREAM_DURATION = 1320;

// Load ad breaks from VMAP file
- (void)loadAdBreaksFromVMAP {
    NSLog(@"[TrueX] loadAdBreaksFromVMAP START - timestamp: %f", CACurrentMediaTime());
    if (self.videoMap != nil) {
        NSLog(@"[TrueX] loadAdBreaksFromVMAP EARLY RETURN (videoMap exists) - timestamp: %f", CACurrentMediaTime());
        return;
    }
    self.inAdBreak = NO;

    // Parse VMAP from bundle
    NSLog(@"[TrueX] Parsing VMAP from bundle - timestamp: %f", CACurrentMediaTime());
    NSError *error = nil;
    self.videoMap = [VmapParser parseVmapFromBundleResource:@"vmap"
                                                  streamUrl:STREAM_URL
                                             streamDuration:STREAM_DURATION
                                                      error:&error];

    if (error || !self.videoMap) {
        NSLog(@"[TrueX] Error parsing vmap.xml: %@", error);
        [self alertWithTitle:@"Error" message:@"Failed to parse vmap.xml." completion:nil];
        return;
    }

    NSLog(@"[TrueX] VMAP parsed successfully - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] About to call setupStream - timestamp: %f", CACurrentMediaTime());
    [self setupStream];
    NSLog(@"[TrueX] setupStream returned - timestamp: %f", CACurrentMediaTime());
    NSLog(@"[TrueX] loadAdBreaksFromVMAP END - timestamp: %f", CACurrentMediaTime());
}

// Set up the video stream
- (void)setupStream {
    NSLog(@"[TrueX] setupStream START - timestamp: %f", CACurrentMediaTime());

    // Show loading indicator while asset loads
    [self.loadingIndicator startAnimating];

    NSURL* url = [NSURL URLWithString:self.videoMap.url];
    NSLog(@"[TrueX] Creating AVAsset with URL: %@ - timestamp: %f", url, CACurrentMediaTime());
    AVAsset* asset = [AVAsset assetWithURL:url];
    NSLog(@"[TrueX] AVAsset created - timestamp: %f", CACurrentMediaTime());
    NSArray* assetKeys = @[ @"playable", @"duration" ];
    __weak typeof(self) weakSelf = self;

    // Load asset asynchronously before creating the player
    NSLog(@"[TrueX] Starting async asset load for keys: %@ - timestamp: %f", assetKeys, CACurrentMediaTime());
    [asset loadValuesAsynchronouslyForKeys:assetKeys completionHandler:^{
        NSLog(@"[TrueX] Asset async load COMPLETION HANDLER fired - timestamp: %f", CACurrentMediaTime());
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[TrueX] Inside main queue dispatch - timestamp: %f", CACurrentMediaTime());

            // Hide loading indicator
            [weakSelf.loadingIndicator stopAnimating];

            // Check if the view controller is still valid
            if (weakSelf == nil || weakSelf.videoMap == nil) {
                NSLog(@"[TrueX] Early return - weakSelf or videoMap is nil - timestamp: %f", CACurrentMediaTime());
                return;
            }

            // Check the status of the playable key
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:@"playable" error:&error];
            NSLog(@"[TrueX] Playable key status: %ld - timestamp: %f", (long)status, CACurrentMediaTime());

            if (status == AVKeyValueStatusFailed) {
                NSLog(@"[TrueX] Failed to load asset: %@ - timestamp: %f", error, CACurrentMediaTime());
                [weakSelf alertWithTitle:@"Error" message:@"Failed to load video stream." completion:nil];
                return;
            }

            if (status != AVKeyValueStatusLoaded) {
                NSLog(@"[TrueX] Asset not loaded, status: %ld - timestamp: %f", (long)status, CACurrentMediaTime());
                return;
            }

            // Asset is ready, create the player
            NSLog(@"[TrueX] Asset ready, creating AVPlayerItem - timestamp: %f", CACurrentMediaTime());
            AVPlayerItem* playerItem = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:assetKeys];
            NSLog(@"[TrueX] AVPlayerItem created - timestamp: %f", CACurrentMediaTime());

            // Store content playerItem for restoration after ads
            weakSelf.contentPlayerItem = playerItem;

            weakSelf.player = [AVPlayer playerWithPlayerItem:playerItem];
            NSLog(@"[TrueX] AVPlayer created and assigned - timestamp: %f", CACurrentMediaTime());

            // Show player controls now that asset is ready
            weakSelf.showsPlaybackControls = YES;

            // Set up observers and start playback
            NSLog(@"[TrueX] About to call setupStreamObserversWithAsset - timestamp: %f", CACurrentMediaTime());
            [weakSelf setupStreamObserversWithAsset:asset];
            NSLog(@"[TrueX] setupStreamObserversWithAsset returned - timestamp: %f", CACurrentMediaTime());

            NSLog(@"[TrueX] About to call player.play - timestamp: %f", CACurrentMediaTime());
            [weakSelf.player play];
            NSLog(@"[TrueX] player.play returned - timestamp: %f", CACurrentMediaTime());

            // The Boundary Time Observer doesn't like 0s, thus I am firing these events manually
            NSLog(@"[TrueX] About to call videoStarted - timestamp: %f", CACurrentMediaTime());
            [weakSelf videoStarted];
            NSLog(@"[TrueX] videoStarted returned - timestamp: %f", CACurrentMediaTime());

            NSLog(@"[TrueX] About to call helperStartAdBreak - timestamp: %f", CACurrentMediaTime());
            [weakSelf helperStartAdBreak];
            NSLog(@"[TrueX] helperStartAdBreak returned - timestamp: %f", CACurrentMediaTime());
        });
    }];
    NSLog(@"[TrueX] setupStream END (async load started) - timestamp: %f", CACurrentMediaTime());
}

- (void)setupStreamObserversWithAsset:(AVAsset*)asset {
    NSLog(@"[TrueX] setupStreamObserversWithAsset START - timestamp: %f", CACurrentMediaTime());
    __weak typeof(self) weakSelf = self;

    // Initialize array to store observer tokens for cleanup
    self.timeObservers = [@[] mutableCopy];
    id observer;

    // Set Up Video Events
    // Ad Break Observer
    NSLog(@"[TrueX] Setting up ad break observers - timestamp: %f", CACurrentMediaTime());
    NSMutableArray* adBreakStartTimes = [@[] mutableCopy];
    NSMutableArray* adBreakEndTimes = [@[] mutableCopy];
    for (AdBreak *adBreak in self.videoMap.adBreaks) {
        int timeOffset = adBreak.timeOffsetSeconds;
        int duration = [adBreak duration];

        CMTime adbreakStart = CMTimeMake(timeOffset, 1);
        CMTime adbreakEnd = CMTimeMake(timeOffset + duration, 1);
        [adBreakStartTimes addObject:[NSValue valueWithCMTime:adbreakStart]];
        [adBreakEndTimes addObject:[NSValue valueWithCMTime:adbreakEnd]];
    }
    // Ad Break Start Event
    observer = [self.player addBoundaryTimeObserverForTimes:adBreakStartTimes
                                                      queue:dispatch_get_main_queue()
                                                 usingBlock:^{
                                                     [weakSelf helperStartAdBreak];
                                                 }];
    [self.timeObservers addObject:observer];

    // Ad Break End Event
    observer = [self.player addBoundaryTimeObserverForTimes:adBreakEndTimes
                                                      queue:dispatch_get_main_queue()
                                                 usingBlock:^{
                                                     [weakSelf helperEndAdBreak];
                                                 }];
    [self.timeObservers addObject:observer];

    // Video End Event
    NSLog(@"[TrueX] About to access asset.duration - timestamp: %f", CACurrentMediaTime());
    CMTime assetDuration = asset.duration;
    NSLog(@"[TrueX] asset.duration accessed: %f seconds - timestamp: %f", CMTimeGetSeconds(assetDuration), CACurrentMediaTime());
    observer = [self.player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:assetDuration]]
                                                      queue:dispatch_get_main_queue()
                                                 usingBlock:^{
                                                     [weakSelf videoEnded];
                                                 }];
    [self.timeObservers addObject:observer];

    NSLog(@"[TrueX] Adding periodic time observer - timestamp: %f", CACurrentMediaTime());
    observer = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                         queue:dispatch_get_main_queue()
                                                    usingBlock:^(CMTime time) {
        if (weakSelf.player.rate != 0) {
            if (weakSelf.inAdBreak) {
                // Check if we've left the ad break region
                if (!weakSelf.snappingBack) {
                    AdBreak *currentAdBreak = [weakSelf currentAdBreak];
                    if (currentAdBreak == nil) {
                        [weakSelf helperEndAdBreak];
                    }
                }
            } else {
                // Check if we missed an ad break (user seeked past it)
                AdBreak *missedAdBreak = [weakSelf firstMissedAdBreak];
                if (missedAdBreak != nil) {
                    weakSelf.snappingBack = YES;
                    int timeOffset = missedAdBreak.timeOffsetSeconds;
                    [weakSelf.player seekToTime:CMTimeMake(timeOffset, 1) completionHandler:^(BOOL finished) {
                        weakSelf.snappingBack = NO;
                        if (finished) {
                            [weakSelf helperStartAdBreak];
                        }
                    }];
                }
            }
        }
    }];
    [self.timeObservers addObject:observer];
    NSLog(@"[TrueX] setupStreamObserversWithAsset END - timestamp: %f", CACurrentMediaTime());
}

- (AdBreak *)currentAdBreak {
    for (AdBreak *adBreak in self.videoMap.adBreaks) {
        // Skip completed ad breaks
        if (adBreak.completed) {
            continue;
        }

        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = adBreak.timeOffsetSeconds;
        int duration = [adBreak duration];
        if ((timeOffset <= currentTime) && (currentTime < (timeOffset + duration))) {
            return adBreak;
        }
    }
    return nil;
}

// Returns the ad break at current position only if it hasn't been started yet
- (AdBreak *)currentUnstartedAdBreak {
    for (AdBreak *adBreak in self.videoMap.adBreaks) {
        // Skip started or completed ad breaks
        if (adBreak.started || adBreak.completed) {
            continue;
        }

        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = adBreak.timeOffsetSeconds;
        int duration = [adBreak duration];
        if ((timeOffset <= currentTime) && (currentTime < (timeOffset + duration))) {
            return adBreak;
        }
    }
    return nil;
}

// Returns the first ad break that should have played but hasn't started yet
- (AdBreak *)firstMissedAdBreak {
    int currentTime = CMTimeGetSeconds(self.player.currentTime);
    for (AdBreak *adBreak in self.videoMap.adBreaks) {
        if (adBreak.started || adBreak.completed) {
            continue;
        }
        int timeOffset = adBreak.timeOffsetSeconds;
        if (timeOffset <= currentTime) {
            return adBreak;
        }
    }
    return nil;
}

// Mark the current ad break as completed to prevent re-triggering
- (void)markCurrentAdBreakAsCompleted {
    // Find the ad break we're currently in based on the stored pause position
    for (AdBreak *adBreak in self.videoMap.adBreaks) {
        int timeOffset = adBreak.timeOffsetSeconds;
        int duration = [adBreak duration];
        // Use the pause position to identify the ad break, since we may have already resumed
        if ((timeOffset <= self.adBreakPausePosition) && (self.adBreakPausePosition < (timeOffset + duration))) {
            adBreak.completed = YES;
            NSLog(@"[TrueX] Marked ad break at timeOffset %d as completed - timestamp: %f", timeOffset, CACurrentMediaTime());
            return;
        }
    }
}

- (void)helperStartAdBreak {
    NSLog(@"[TrueX] helperStartAdBreak START - self.inAdBreak=%d - timestamp: %f", self.inAdBreak, CACurrentMediaTime());
    if (!self.inAdBreak) {
        // Only start if there's an ad break that hasn't been started yet
        AdBreak *adBreak = [self currentUnstartedAdBreak];
        if (adBreak != nil) {
            // Mark the ad break as started to prevent re-triggering
            adBreak.started = YES;
            self.inAdBreak = YES;
            NSLog(@"[TrueX] helperStartAdBreak calling adBreakStarted - timestamp: %f", CACurrentMediaTime());
            [self adBreakStarted];
            NSLog(@"[TrueX] helperStartAdBreak adBreakStarted returned - timestamp: %f", CACurrentMediaTime());
        }
    }
    NSLog(@"[TrueX] helperStartAdBreak END - timestamp: %f", CACurrentMediaTime());
}

- (void)helperEndAdBreak {
    if (self.inAdBreak) {
        self.inAdBreak = NO;
        [self adBreakEnded];
    }
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message completion:(void (^)(void))completionCallback;
{
    NSLog(@"[TrueX] alertWithTitle: %@: %@", title, message);
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                   message:message
                                   preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
       handler:^(UIAlertAction * action) {}];

    [alert addAction:defaultAction];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:completionCallback];
    });
}

@end
