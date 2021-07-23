//
//  VideoPlayerViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "VideoPlayerViewController.h"
#import "WebViewViewController.h"
#import <TruexAdRenderer/TruexAdRenderer.h>

@interface VideoPlayerViewController ()

@property NSMutableDictionary* videoMap;
@property TruexAdRenderer* activeAdRenderer;

@end

// internal state for the fake ad manager
BOOL _inAdBreak = NO;

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
}

- (void)viewDidAppear:(BOOL)animated {
    if (self.videoMap == nil) {
        [self fetchVmapFromServer];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [self resetActiveAdRenderer];
    self.videoMap = nil;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return (self.activeAdRenderer != nil);
}

- (BOOL)prefersStatusBarHidden {
    return (self.activeAdRenderer != nil);
}

- (void)pause {
    NSLog(@"truex: pausing renderer");
    [self.activeAdRenderer pause];
}

- (void)resume {
    NSLog(@"truex: resuming renderer");
    [self.activeAdRenderer resume];
}

- (void)resetActiveAdRenderer {
    if (self.activeAdRenderer) {
        [self.activeAdRenderer stop];
    }
    self.activeAdRenderer = nil;
}

// MARK: - Video Life Cycle Callbacks
- (void)videoStarted {
    NSLog(@"VideoLifeCycle: Video Started");
}

- (void)videoEnded {
    NSLog(@"VideoLifeCycle: Video Ended");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)adBreakStarted {
    NSLog(@"VideoLifeCycle: Ad Break Started");
//    self.requiresLinearPlayback = YES;
    
    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];
    NSDictionary* firstAd = [ads objectAtIndex:0];
    
    BOOL isTruexAd = [[firstAd objectForKey:@"system"] isEqualToString:@"truex"];
    if (isTruexAd) {
        [self.player pause];
        [self resetActiveAdRenderer];
        // TrueX Flow
        NSString* slotType = (CMTimeGetSeconds(self.player.currentTime) == 0) ? @"PREROLL" : @"MIDROLL";
        self.activeAdRenderer = [[TruexAdRenderer alloc] initWithUrl:@"https://media.truex.com/placeholder.js"
                                                        adParameters:@{
                                                            @"vast_config_url": [firstAd objectForKey:@"url"]
                                                        }
                                                            slotType:slotType];
        self.activeAdRenderer.delegate = self;
        [self.activeAdRenderer start:self.view];
        [self seekOverFirstAd];
    }
}

- (void)adBreakEnded {
    NSLog(@"VideoLifeCycle: Ad Break Ended");
//    self.requiresLinearPlayback = NO;
}

// MARK: - TRUEX DELEGATE METHODS
- (void)onAdStarted:(NSString*)campaignName {
    NSLog(@"truex: onAdStarted: %@", campaignName);
}

- (void)onAdCompleted:(NSInteger)timeSpent {
    NSLog(@"truex: onAdCompleted: %ld", (long)timeSpent);
    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onAdError:(NSString*)errorMessage {
    NSLog(@"truex: onAdError: %@", errorMessage);
    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onNoAdsAvailable {
    NSLog(@"truex: onNoAdsAvailable");
    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onAdFreePod {
    NSLog(@"truex: onAdFreePod");
    [self seekOverCurrentAdBreak];
    [self helperEndAdBreak];
}

- (void)onPopupWebsite:(NSString *)url {
    NSLog(@"truex: onPopupWebsite: %@", url);
    // Open the URL in Safari
    // [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url] options:@{} completionHandler:nil];
    
    // Or open with your existing in app webview
    UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    WebViewViewController* newViewController = [storyBoard instantiateViewControllerWithIdentifier:@"webviewVC"];
    newViewController.url = [NSURL URLWithString:url];
    newViewController.modalPresentationStyle = UIModalPresentationPopover;
    __weak typeof(self) weakSelf = self;
    newViewController.onDismiss = ^(void) {
        [weakSelf.activeAdRenderer resume];
    };
    [self.activeAdRenderer pause];
    [self presentViewController:newViewController animated:YES completion:nil];
}

// @optional
-(void) onOptIn:(NSString*)campaignName adId:(NSInteger)adId {
    NSLog(@"truex: onOptIn: %@, %li", campaignName, (long)adId);
    
}

-(void) onOptOut:(BOOL)userInitiated {
    NSLog(@"truex: userInitiated: %@", userInitiated? @"true": @"false");
}

-(void) onSkipCardShown {
    NSLog(@"truex: onSkipCardShown");
}

-(void) onUserCancel {
    NSLog(@"truex: onUserCancel");
}

// MARK: - Helper Functions

// Simulating video server call
- (void)fetchVmapFromServer {
    _inAdBreak = NO;
    
    // Fetch the xml from server
    // NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithContentsOfURL:[[NSURL alloc] initWithString:@""]];
    
    // Or use the hardcoded copy
    NSData* vmapData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"vmap" ofType:@"xml"]];
    NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithData:vmapData];
    
    [xmlparser setDelegate:self];
    BOOL success = [xmlparser parse];
    if (success) {
        [self setupStream];
        [self.player play];
        
        // The Boundary Time Observer doesn't like 0s, thus I am firing these event manually. Your video/ad framework should already handle these
        [self videoStarted];
        [self helperStartAdBreak];
    } else {
        [self alertWithTitle:@"Error" message:@"Failed to fetch vmap." completion:nil];
    }
}

// Simulating your existing ad framework
- (void)setupStream {
    NSURL* url = [NSURL URLWithString:[self.videoMap objectForKey:@"url"]];
    AVAsset* asset = [AVAsset assetWithURL:url];
    NSArray* assetKeys = @[ @"playable" ];
    AVPlayerItem* playerItem = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:assetKeys];
    __weak typeof(self) weakSelf = self;
    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    
    // Set Up Video Events
    // Ad Break Observer
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
    [self.player addBoundaryTimeObserverForTimes:adBreakStartTimes
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          [weakSelf helperStartAdBreak];
                                      }];
    
    // Ad Break End Event
    [self.player addBoundaryTimeObserverForTimes:adBreakEndTimes
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          [weakSelf helperEndAdBreak];
                                      }];
    
    // Video Start Event
    [self.player addBoundaryTimeObserverForTimes:@[@0]
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          [weakSelf videoStarted];
                                      }];
    // Video End Event
    CMTime assetDuration = asset.duration;
    [self.player addBoundaryTimeObserverForTimes:@[[NSValue valueWithCMTime:assetDuration]]
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          // Use weak reference to self
                                          [weakSelf videoEnded];
                                      }];
    
    [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                              queue:dispatch_get_main_queue()
                                         usingBlock:^(CMTime time) {
        if (weakSelf.player.rate != 0) {
            NSDictionary* currentAdBreak = [weakSelf currentAdBreak];
            if (currentAdBreak != nil) {
                if (!_inAdBreak) {
                    // Snap Video Position back to the beginning of Ad Break
                    NSDictionary* currentAdBreak = [weakSelf currentAdBreak];
                    int timeOffset = [[currentAdBreak valueForKey:@"timeOffset"] intValue];
                    [weakSelf.player seekToTime:CMTimeMake(timeOffset, 1)];
                    // Boundary Time Observer won't fire for time 0, thus, hardcoding here
                    // Your ad framework would had handled this
                    [weakSelf helperStartAdBreak];
                }
            } else {
                // Help fires adBreakEnded event if somehow it was missed
                [weakSelf helperEndAdBreak];
            }
        }
    }];
}

- (NSDictionary*)currentAdBreak {
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        int duration = [[adbreak valueForKey:@"duration"] intValue];
        if ((timeOffset <= currentTime) && (currentTime < (timeOffset+duration))){
            return [adbreak copy];
        }
    }
    return nil;
}

- (void)helperStartAdBreak {
    if (!_inAdBreak) {
        _inAdBreak = YES;
        [self adBreakStarted];
    }
}

- (void)helperEndAdBreak {
    if (_inAdBreak) {
        _inAdBreak = NO;
        [self adBreakEnded];
    }
    
}

- (void)seekOverFirstAd {
    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];
    NSDictionary* firstAd = [ads objectAtIndex:0];
    int duration = [[firstAd valueForKey:@"duration"] intValue];
    [self.player seekToTime:CMTimeAdd(self.player.currentTime, CMTimeMake(duration, 1))];
}

- (void)seekOverCurrentAdBreak {
    NSDictionary* currentAdBreak = [self currentAdBreak];
    int duration = [[currentAdBreak valueForKey:@"duration"] intValue];
    [self.player seekToTime:CMTimeAdd(self.player.currentTime, CMTimeMake(duration, 1))];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"notVmap"]) {
        self.videoMap = [attributeDict mutableCopy];
        NSMutableArray* adbreaks = [@[] mutableCopy];
        [self.videoMap setObject:adbreaks forKey:@"adbreaks"];
    } else if ([elementName isEqualToString:@"adbreak"]) {
        NSMutableDictionary* adbreak = [attributeDict mutableCopy];
        NSMutableArray* ads = [@[] mutableCopy];
        [adbreak setObject:ads forKey:@"ads"];
        [[self.videoMap valueForKey:@"adbreaks"] addObject:adbreak];
    } else if ([elementName isEqualToString:@"ad"]) {
        NSMutableDictionary* ad = [attributeDict mutableCopy];
        NSMutableArray* adbreaks = [self.videoMap valueForKey:@"adbreaks"];
        NSMutableDictionary* adbreak = [adbreaks objectAtIndex:([adbreaks count] - 1)];
        [[adbreak valueForKey:@"ads"] addObject:ad];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    [self alertWithTitle:@"Error" message:@"Failed to fetch vmap." completion:nil];
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
    [self presentViewController:alert animated:YES completion:completionCallback];
}

@end
