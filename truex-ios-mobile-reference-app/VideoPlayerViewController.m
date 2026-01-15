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

@interface VideoPlayerViewController ()

@property (nonatomic, strong) InfillionAdManager *adManager;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) NSMutableDictionary *videoMap;
@property (nonatomic, strong) AVPlayerItem *contentPlayerItem;

// Ad break state
@property (nonatomic, assign) BOOL inAdBreak;
@property (nonatomic, assign) int adBreakIndex;
@property (nonatomic, assign) int currentAdIndexInBreak;
@property (nonatomic, assign) Float64 resumeTime;
@property (nonatomic, assign) BOOL snappingBack;
@property (nonatomic, assign) Float64 adBreakPausePosition;

// Time observer tokens for cleanup
@property (nonatomic, strong) NSMutableArray *timeObservers;

@end

@implementation VideoPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.resumeTime = -1;

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
    NSLog(@"DEBUG: viewDidAppear START - timestamp: %f", CACurrentMediaTime());
    [self loadAdBreaksFromJSON];
    NSLog(@"DEBUG: viewDidAppear END - timestamp: %f", CACurrentMediaTime());
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
    NSLog(@"Ad Manager: Video Started");
}

- (void)videoEnded {
    NSLog(@"Ad Manager: Video Ended");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)adBreakStarted {
    NSLog(@"DEBUG: adBreakStarted START - timestamp: %f", CACurrentMediaTime());
    NSLog(@"Ad Manager: Ad Break Started");
    self.requiresLinearPlayback = YES;

    // Store current position to resume from after all ads complete
    self.adBreakPausePosition = CMTimeGetSeconds(self.player.currentTime);
    NSLog(@"DEBUG: Storing pause position: %f - timestamp: %f", self.adBreakPausePosition, CACurrentMediaTime());

    // Reset ad index for new break
    self.currentAdIndexInBreak = 0;

    // Start playing ads in sequence (Infillion and standard)
    [self playNextAdInBreak];

    NSLog(@"DEBUG: adBreakStarted END - timestamp: %f", CACurrentMediaTime());
}

// Play the next ad in the current break
- (void)playNextAdInBreak {
    NSLog(@"DEBUG: playNextAdInBreak START - index: %d - timestamp: %f", self.currentAdIndexInBreak, CACurrentMediaTime());

    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];

    // Check if there are more ads to play
    if (self.currentAdIndexInBreak >= ads.count) {
        // No more ads, resume content
        NSLog(@"DEBUG: No more ads in break, resuming content - timestamp: %f", CACurrentMediaTime());
        [self resumeContentAfterAds];
        return;
    }

    NSDictionary* ad = [ads objectAtIndex:self.currentAdIndexInBreak];
    NSString* adSystem = [ad objectForKey:@"adSystem"];
    InfillionAdType adType = InfillionAdTypeFromString(adSystem);

    NSLog(@"DEBUG: Playing ad at index %d - type: %@ (raw: %@) - timestamp: %f",
          self.currentAdIndexInBreak, InfillionAdTypeToString(adType), adSystem, CACurrentMediaTime());

    // Increment index for next ad
    self.currentAdIndexInBreak++;

    if (IsInfillionAd(adType)) {
        // Play interactive Infillion ad (TrueX or IDVx)
        [self playInfillionAd:ad adType:adType];
    } else {
        // Play standard video ad (e.g., GDFP)
        [self playStandardVideoAd:ad];
    }

    NSLog(@"DEBUG: playNextAdInBreak END - timestamp: %f", CACurrentMediaTime());
}

// Play an interactive Infillion ad (TrueX or IDVx)
- (void)playInfillionAd:(NSDictionary*)ad adType:(InfillionAdType)adType {
    NSLog(@"DEBUG: playInfillionAd START - timestamp: %f", CACurrentMediaTime());

    [self.player pause];
    [self resetAdManager];

    NSString* slotType = (self.adBreakPausePosition < 1) ? @"preroll" : @"midroll";

    // Create the InfillionAdManager
    self.adManager = [[InfillionAdManager alloc] init];
    self.adManager.delegate = self;

    // Get the configuration based on ad type
    NSString *vastConfigUrl = nil;
    NSDictionary *adParameters = nil;

    if (adType == InfillionAdTypeTruex) {
        vastConfigUrl = [ad objectForKey:@"description"];
        NSLog(@"Ad Manager: Starting TrueX ad with URL: %@", vastConfigUrl);
    } else {
        adParameters = [ad objectForKey:@"adParameters"];
        NSLog(@"Ad Manager: Starting IDVx ad");
    }

    // Start the Infillion ad
    [self.adManager startAdOnView:self.view
                    vastConfigUrl:vastConfigUrl
                     adParameters:adParameters
                         slotType:slotType
                           adType:adType];

    NSLog(@"DEBUG: playInfillionAd END - timestamp: %f", CACurrentMediaTime());
}

// Play a standard video ad by loading its mediaFile URL
- (void)playStandardVideoAd:(NSDictionary*)ad {
    NSString* mediaFile = [ad objectForKey:@"mediaFile"];
    NSString* title = [ad objectForKey:@"title"];

    NSLog(@"DEBUG: playStandardVideoAd START - title: %@, mediaFile: %@ - timestamp: %f",
          title, mediaFile, CACurrentMediaTime());

    if (mediaFile == nil) {
        NSLog(@"DEBUG: No mediaFile for ad, skipping to next - timestamp: %f", CACurrentMediaTime());
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
    NSLog(@"DEBUG: Creating AVPlayerItem with URL: %@ - timestamp: %f", adUrl, CACurrentMediaTime());
    AVPlayerItem* adPlayerItem = [AVPlayerItem playerItemWithURL:adUrl];
    NSLog(@"DEBUG: AVPlayerItem created, status: %ld - timestamp: %f", (long)adPlayerItem.status, CACurrentMediaTime());

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
    NSLog(@"DEBUG: Replacing player item - timestamp: %f", CACurrentMediaTime());
    [self.player replaceCurrentItemWithPlayerItem:adPlayerItem];
    NSLog(@"DEBUG: Player item replaced, calling play - timestamp: %f", CACurrentMediaTime());
    [self.player play];
    NSLog(@"DEBUG: Player rate after play: %f - timestamp: %f", self.player.rate, CACurrentMediaTime());

    NSLog(@"DEBUG: playStandardVideoAd END - timestamp: %f", CACurrentMediaTime());
}

// KVO observer for player item status
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
        NSLog(@"DEBUG: AVPlayerItem status changed to: %ld - timestamp: %f", (long)playerItem.status, CACurrentMediaTime());
        if (playerItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"DEBUG: AVPlayerItem FAILED with error: %@ - timestamp: %f", playerItem.error, CACurrentMediaTime());
        } else if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
            NSLog(@"DEBUG: AVPlayerItem ready to play - timestamp: %f", CACurrentMediaTime());
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
    NSLog(@"DEBUG: standardVideoAdDidFail - error: %@ - timestamp: %f", notification.userInfo, CACurrentMediaTime());

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
    NSLog(@"DEBUG: standardVideoAdDidFinish START - timestamp: %f", CACurrentMediaTime());

    // Remove observers for this notification
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:notification.object];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                  object:notification.object];

    NSLog(@"DEBUG: standardVideoAdDidFinish - calling playNextAdInBreak - timestamp: %f", CACurrentMediaTime());
    // Play the next ad in the break
    [self playNextAdInBreak];
}

- (void)adBreakEnded {
    NSLog(@"Ad Manager: Ad Break Ended");
    self.requiresLinearPlayback = NO;
}

// Resume content playback after all ads complete
- (void)resumeContentAfterAds {
    NSLog(@"DEBUG: resumeContentAfterAds START - restoring to position %f - timestamp: %f",
          self.adBreakPausePosition, CACurrentMediaTime());

    // Mark the ad break as completed BEFORE restoring content
    // This prevents the periodic observer from re-triggering the ad break
    [self markCurrentAdBreakAsCompleted];

    // Restore the content player item
    if (self.contentPlayerItem != nil) {
        [self.player replaceCurrentItemWithPlayerItem:self.contentPlayerItem];

        // Seek to the stored pause position
        CMTime resumeTime = CMTimeMakeWithSeconds(self.adBreakPausePosition, NSEC_PER_SEC);
        [self.player seekToTime:resumeTime completionHandler:^(BOOL finished) {
            if (finished) {
                NSLog(@"DEBUG: Content restored and seeked to %f - timestamp: %f",
                      self.adBreakPausePosition, CACurrentMediaTime());
            }
        }];
    }

    // End the ad break and resume playback
    [self helperEndAdBreak];
    [self.player play];

    NSLog(@"DEBUG: resumeContentAfterAds END - timestamp: %f", CACurrentMediaTime());
}

// MARK: - InfillionAdManagerDelegate Methods

- (void)infillionAdDidStart:(NSString *)campaignName {
    // User has started their ad engagement
    NSLog(@"Infillion: onAdStarted: %@", campaignName);
}

- (void)infillionAdDidComplete:(BOOL)receivedCredit {
    // User has finished the Infillion engagement
    NSLog(@"DEBUG: infillionAdDidComplete START - receivedCredit=%@ - timestamp: %f", receivedCredit ? @"YES" : @"NO", CACurrentMediaTime());
    NSLog(@"Infillion: onAdComplete: receivedCredit=%@", receivedCredit ? @"YES" : @"NO");

    [self resetAdManager];

    if (receivedCredit) {
        // TrueX only: User earned credit, skip ALL remaining ads in the break
        NSLog(@"DEBUG: User earned credit, skipping remaining ads and resuming content - timestamp: %f", CACurrentMediaTime());

        // Mark the ad break as completed to prevent re-triggering
        [self markCurrentAdBreakAsCompleted];

        // Determine resume position
        Float64 resumePosition = self.adBreakPausePosition;
        if (self.resumeTime != -1) {
            // Custom snap back logic - user was seeking, return to their original position
            resumePosition = self.resumeTime;
            self.resumeTime = -1;
        }

        // Restore the content player item before seeking
        if (self.contentPlayerItem != nil) {
            [self.player replaceCurrentItemWithPlayerItem:self.contentPlayerItem];
        }

        // Seek to the resume position and play
        CMTime resumeTime = CMTimeMakeWithSeconds(resumePosition, NSEC_PER_SEC);
        [self.player seekToTime:resumeTime completionHandler:^(BOOL finished) {
            if (finished) {
                NSLog(@"DEBUG: Content resumed at position %f after credit - timestamp: %f",
                      resumePosition, CACurrentMediaTime());
            }
        }];

        [self helperEndAdBreak];
        [self.player play];
    } else {
        // No credit received - play the next ad in the break (Infillion or standard)
        NSLog(@"DEBUG: No credit, playing next ad in break - timestamp: %f", CACurrentMediaTime());
        [self playNextAdInBreak];
    }

    NSLog(@"DEBUG: infillionAdDidComplete END - timestamp: %f", CACurrentMediaTime());
}

- (void)infillionAdPopupWebsite:(NSString *)url {
    // User wants to open an external link in the Infillion ad
    NSLog(@"Infillion: onPopupWebsite: %@", url);

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
    NSLog(@"Infillion: onOptIn: %@, %li", campaignName, (long)adId);
}

- (void)infillionAdDidOptOut:(BOOL)userInitiated {
    // User has opted out of the engagement, show standard ads
    NSLog(@"Infillion: onOptOut: userInitiated=%@", userInitiated ? @"YES" : @"NO");
}

- (void)infillionAdSkipCardShown {
    // Displayed a Skip Card
    NSLog(@"Infillion: onSkipCardShown");
}

- (void)infillionAdUserCancel {
    // User backs out of the interactive ad unit after having opted in.
    NSLog(@"Infillion: onUserCancel");
}

- (void)infillionAdUserCancelStream {
    // User wants to cancel the stream
    NSLog(@"Infillion: onUserCancelStream");
}

// MARK: - Helper Functions / JSON Loading

// Load ad breaks from JSON file
- (void)loadAdBreaksFromJSON {
    NSLog(@"DEBUG: loadAdBreaksFromJSON START - timestamp: %f", CACurrentMediaTime());
    if (self.videoMap != nil) {
        NSLog(@"DEBUG: loadAdBreaksFromJSON EARLY RETURN (videoMap exists) - timestamp: %f", CACurrentMediaTime());
        return;
    }
    self.inAdBreak = NO;
    self.adBreakIndex = 0;

    // Load the JSON from bundle
    NSLog(@"DEBUG: Loading JSON from bundle - timestamp: %f", CACurrentMediaTime());
    NSString *path = [[NSBundle mainBundle] pathForResource:@"adbreaks" ofType:@"json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSLog(@"DEBUG: JSON loaded from bundle - timestamp: %f", CACurrentMediaTime());

    if (!data) {
        [self alertWithTitle:@"Error" message:@"Failed to load adbreaks.json." completion:nil];
        return;
    }

    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error) {
        NSLog(@"Error parsing adbreaks.json: %@", error);
        [self alertWithTitle:@"Error" message:@"Failed to parse adbreaks.json." completion:nil];
        return;
    }

    // Map the JSON to our internal format
    self.videoMap = [@{} mutableCopy];
    [self.videoMap setObject:json[@"streamUrl"] forKey:@"url"];
    [self.videoMap setObject:json[@"streamDuration"] forKey:@"duration"];

    // Convert adBreaks array to our format
    NSMutableArray *adbreaks = [@[] mutableCopy];
    for (NSDictionary *adBreak in json[@"adBreaks"]) {
        NSMutableDictionary *mappedBreak = [@{} mutableCopy];

        // Convert timeOffsetMs (milliseconds string) to timeOffset (seconds int)
        NSString *timeOffsetMs = adBreak[@"timeOffsetMs"];
        int timeOffset = [timeOffsetMs intValue] / 1000;
        [mappedBreak setObject:@(timeOffset) forKey:@"timeOffset"];

        // Calculate total duration from ads
        int totalDuration = 0;
        NSMutableArray *ads = [@[] mutableCopy];
        for (NSDictionary *ad in adBreak[@"ads"]) {
            NSMutableDictionary *mappedAd = [ad mutableCopy];
            totalDuration += [ad[@"duration"] intValue];
            [ads addObject:mappedAd];
        }
        [mappedBreak setObject:@(totalDuration) forKey:@"duration"];
        [mappedBreak setObject:ads forKey:@"ads"];
        [mappedBreak setObject:adBreak[@"breakId"] forKey:@"id"];

        [adbreaks addObject:mappedBreak];
    }
    [self.videoMap setObject:adbreaks forKey:@"adbreaks"];

    NSLog(@"DEBUG: About to call setupStream - timestamp: %f", CACurrentMediaTime());
    [self setupStream];
    NSLog(@"DEBUG: setupStream returned - timestamp: %f", CACurrentMediaTime());
    // Note: play, videoStarted, and helperStartAdBreak are now called
    // in setupStream after the asset is ready to play
    NSLog(@"DEBUG: loadAdBreaksFromJSON END - timestamp: %f", CACurrentMediaTime());
}

// Set up the video stream
- (void)setupStream {
    NSLog(@"DEBUG: setupStream START - timestamp: %f", CACurrentMediaTime());

    // Show loading indicator while asset loads
    [self.loadingIndicator startAnimating];

    NSURL* url = [NSURL URLWithString:[self.videoMap objectForKey:@"url"]];
    NSLog(@"DEBUG: Creating AVAsset with URL: %@ - timestamp: %f", url, CACurrentMediaTime());
    AVAsset* asset = [AVAsset assetWithURL:url];
    NSLog(@"DEBUG: AVAsset created - timestamp: %f", CACurrentMediaTime());
    NSArray* assetKeys = @[ @"playable", @"duration" ];
    __weak typeof(self) weakSelf = self;

    // Load asset asynchronously before creating the player
    NSLog(@"DEBUG: Starting async asset load for keys: %@ - timestamp: %f", assetKeys, CACurrentMediaTime());
    [asset loadValuesAsynchronouslyForKeys:assetKeys completionHandler:^{
        NSLog(@"DEBUG: Asset async load COMPLETION HANDLER fired - timestamp: %f", CACurrentMediaTime());
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"DEBUG: Inside main queue dispatch - timestamp: %f", CACurrentMediaTime());

            // Hide loading indicator
            [weakSelf.loadingIndicator stopAnimating];

            // Check if the view controller is still valid
            if (weakSelf == nil || weakSelf.videoMap == nil) {
                NSLog(@"DEBUG: Early return - weakSelf or videoMap is nil - timestamp: %f", CACurrentMediaTime());
                return;
            }

            // Check the status of the playable key
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:@"playable" error:&error];
            NSLog(@"DEBUG: Playable key status: %ld - timestamp: %f", (long)status, CACurrentMediaTime());

            if (status == AVKeyValueStatusFailed) {
                NSLog(@"DEBUG: Failed to load asset: %@ - timestamp: %f", error, CACurrentMediaTime());
                [weakSelf alertWithTitle:@"Error" message:@"Failed to load video stream." completion:nil];
                return;
            }

            if (status != AVKeyValueStatusLoaded) {
                NSLog(@"DEBUG: Asset not loaded, status: %ld - timestamp: %f", (long)status, CACurrentMediaTime());
                return;
            }

            // Asset is ready, create the player
            NSLog(@"DEBUG: Asset ready, creating AVPlayerItem - timestamp: %f", CACurrentMediaTime());
            AVPlayerItem* playerItem = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:assetKeys];
            NSLog(@"DEBUG: AVPlayerItem created - timestamp: %f", CACurrentMediaTime());

            // Store content playerItem for restoration after ads
            weakSelf.contentPlayerItem = playerItem;

            weakSelf.player = [AVPlayer playerWithPlayerItem:playerItem];
            NSLog(@"DEBUG: AVPlayer created and assigned - timestamp: %f", CACurrentMediaTime());

            // Show player controls now that asset is ready
            weakSelf.showsPlaybackControls = YES;

            // Set up observers and start playback
            NSLog(@"DEBUG: About to call setupStreamObserversWithAsset - timestamp: %f", CACurrentMediaTime());
            [weakSelf setupStreamObserversWithAsset:asset];
            NSLog(@"DEBUG: setupStreamObserversWithAsset returned - timestamp: %f", CACurrentMediaTime());

            NSLog(@"DEBUG: About to call player.play - timestamp: %f", CACurrentMediaTime());
            [weakSelf.player play];
            NSLog(@"DEBUG: player.play returned - timestamp: %f", CACurrentMediaTime());

            // The Boundary Time Observer doesn't like 0s, thus I am firing these events manually
            NSLog(@"DEBUG: About to call videoStarted - timestamp: %f", CACurrentMediaTime());
            [weakSelf videoStarted];
            NSLog(@"DEBUG: videoStarted returned - timestamp: %f", CACurrentMediaTime());

            NSLog(@"DEBUG: About to call helperStartAdBreak - timestamp: %f", CACurrentMediaTime());
            [weakSelf helperStartAdBreak];
            NSLog(@"DEBUG: helperStartAdBreak returned - timestamp: %f", CACurrentMediaTime());
        });
    }];
    NSLog(@"DEBUG: setupStream END (async load started) - timestamp: %f", CACurrentMediaTime());
}

- (void)setupStreamObserversWithAsset:(AVAsset*)asset {
    NSLog(@"DEBUG: setupStreamObserversWithAsset START - timestamp: %f", CACurrentMediaTime());
    __weak typeof(self) weakSelf = self;

    // Initialize array to store observer tokens for cleanup
    self.timeObservers = [@[] mutableCopy];
    id observer;

    // Set Up Video Events
    // Ad Break Observer
    NSLog(@"DEBUG: Setting up ad break observers - timestamp: %f", CACurrentMediaTime());
    NSMutableArray* adBreakStartTimes = [@[] mutableCopy];
    NSMutableArray* adBreakEndTimes = [@[] mutableCopy];
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        int duration = [[adbreak valueForKey:@"duration"] intValue];

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
    NSLog(@"DEBUG: About to access asset.duration - timestamp: %f", CACurrentMediaTime());
    CMTime assetDuration = asset.duration;
    NSLog(@"DEBUG: asset.duration accessed: %f seconds - timestamp: %f", CMTimeGetSeconds(assetDuration), CACurrentMediaTime());
    observer = [self.player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:assetDuration]]
                                                      queue:dispatch_get_main_queue()
                                                 usingBlock:^{
                                                     [weakSelf videoEnded];
                                                 }];
    [self.timeObservers addObject:observer];

    NSLog(@"DEBUG: Adding periodic time observer - timestamp: %f", CACurrentMediaTime());
    observer = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                                         queue:dispatch_get_main_queue()
                                                    usingBlock:^(CMTime time) {
        if (weakSelf.player.rate != 0) {
            NSDictionary* currentAdBreak = [weakSelf currentAdBreak];
            if (currentAdBreak != nil) {
                if (!weakSelf.inAdBreak) {
                    weakSelf.snappingBack = YES;
                    // Snap Video Position back to the beginning of Ad Break
                    int timeOffset = [[currentAdBreak valueForKey:@"timeOffset"] intValue];
                    [weakSelf.player seekToTime:CMTimeMake(timeOffset, 1) completionHandler:^(BOOL finished) {
                        if (finished) {
                            [weakSelf helperStartAdBreak];
                        }
                    }];
                } else {
                    weakSelf.snappingBack = NO;
                }
            } else {
                if (weakSelf.inAdBreak) {
                    if (!weakSelf.snappingBack){
                        [weakSelf helperEndAdBreak];
                    }
                } else {
                    // snap back to the last ad break if it wasn't played
                    int currentAdBreakIndex = [weakSelf currentAdBreakIndex];
                    if (weakSelf.adBreakIndex != currentAdBreakIndex) {
                        weakSelf.snappingBack = YES;
                        NSDictionary* adBreakToPlay = [weakSelf adBreakAtIndex:currentAdBreakIndex];
                        weakSelf.resumeTime = CMTimeGetSeconds(weakSelf.player.currentTime);
                        int timeOffset = [[adBreakToPlay valueForKey:@"timeOffset"] intValue];
                        [weakSelf.player seekToTime:CMTimeMake(timeOffset, 1) completionHandler:^(BOOL finished) {
                            if (finished) {
                                [weakSelf helperStartAdBreak];
                            }
                        }];
                    }
                }
            }
        }
    }];
    [self.timeObservers addObject:observer];
    NSLog(@"DEBUG: setupStreamObserversWithAsset END - timestamp: %f", CACurrentMediaTime());
}

- (NSDictionary*)currentAdBreak {
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        // Skip completed ad breaks
        BOOL completed = [[adbreak valueForKey:@"completed"] boolValue];
        if (completed) {
            continue;
        }

        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        int duration = [[adbreak valueForKey:@"duration"] intValue];
        if ((timeOffset <= currentTime) && (currentTime < (timeOffset+duration))){
            return [adbreak copy];
        }
    }
    return nil;
}

- (NSDictionary*)adBreakAtIndex:(int)index {
    return [[self.videoMap objectForKey:@"adbreaks"] objectAtIndex:(NSUInteger)index];
}

// Mark the current ad break as completed to prevent re-triggering
- (void)markCurrentAdBreakAsCompleted {
    // Find the ad break we're currently in based on the stored pause position
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        int duration = [[adbreak valueForKey:@"duration"] intValue];
        // Use the pause position to identify the ad break, since we may have already resumed
        if ((timeOffset <= self.adBreakPausePosition) && (self.adBreakPausePosition < (timeOffset + duration))) {
            [adbreak setValue:@YES forKey:@"completed"];
            NSLog(@"DEBUG: Marked ad break at timeOffset %d as completed - timestamp: %f", timeOffset, CACurrentMediaTime());
            return;
        }
    }
    // Fallback: if pause position doesn't match, mark by index
    if (self.adBreakIndex >= 0 && self.adBreakIndex < [[self.videoMap objectForKey:@"adbreaks"] count]) {
        NSMutableDictionary* adbreak = [[self.videoMap objectForKey:@"adbreaks"] objectAtIndex:self.adBreakIndex];
        [adbreak setValue:@YES forKey:@"completed"];
        NSLog(@"DEBUG: Marked ad break at index %d as completed (fallback) - timestamp: %f", self.adBreakIndex, CACurrentMediaTime());
    }
}

- (int)currentAdBreakIndex {
    int index = -1;
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        if (currentTime < timeOffset){
            return index;
        }
        index++;
    }
    return index;
}

- (void)helperStartAdBreak {
    NSLog(@"DEBUG: helperStartAdBreak START - self.inAdBreak=%d - timestamp: %f", self.inAdBreak, CACurrentMediaTime());
    if (!self.inAdBreak) {
        self.inAdBreak = YES;
        NSLog(@"DEBUG: helperStartAdBreak calling adBreakStarted - timestamp: %f", CACurrentMediaTime());
        [self adBreakStarted];
        NSLog(@"DEBUG: helperStartAdBreak adBreakStarted returned - timestamp: %f", CACurrentMediaTime());
    }
    NSLog(@"DEBUG: helperStartAdBreak END - timestamp: %f", CACurrentMediaTime());
}

- (void)helperEndAdBreak {
    if (self.inAdBreak) {
        self.inAdBreak = NO;
        [self adBreakEnded];
        self.adBreakIndex = [self currentAdBreakIndex];
    }

}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message completion:(void (^)(void))completionCallback;
{
    NSLog(@"alertWithTitle: %@: %@", title, message);
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
