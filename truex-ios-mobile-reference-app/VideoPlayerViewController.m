//
//  VideoPlayerViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "VideoPlayerViewController.h"
#import "WebViewViewController.h"

@interface VideoPlayerViewController ()

@property NSMutableDictionary* videoMap;
//@property TruexAdRenderer* activeAdRenderer;

@end

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
    [self fetchVmapFromServer];
}

- (void)viewWillDisappear:(BOOL)animated {
//    [self resetActiveAdRenderer];
}

- (void)pause {
    NSLog(@"sunnysideMobile: pausing renderer");
//    [self.activeAdRenderer pause];
}

- (void)resume {
    NSLog(@"sunnysideMobile: resuming renderer");
//    [self.activeAdRenderer resume];
}

- (void)resetActiveAdRenderer {
//    if (self.activeAdRenderer) {
//        [self.activeAdRenderer stop];
//    }
//    self.activeAdRenderer = nil;
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
    _inAdBreak = YES;
    
    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];
    NSDictionary* firstAd = [ads objectAtIndex:0];
    
    BOOL isTruexAd = [[firstAd objectForKey:@"system"] isEqualToString:@"truex"];
    if (isTruexAd) {
//        [self.player pause];
        // TrueX Flow
    }
}

- (void)adBreakEnded {
    NSLog(@"VideoLifeCycle: Ad Break Ended");
//    self.requiresLinearPlayback = NO;
    _inAdBreak = NO;
}

// MARK: - TRUEX DELEGATE METHODS
- (void)onAdStarted:(NSString*)campaignName {
    NSLog(@"sunnysideMobile: onAdStarted: %@", campaignName);
    [self seekOverFirstAd];
}

- (void)onAdCompleted:(NSInteger)timeSpent {
    NSLog(@"sunnysideMobile: onAdCompleted: %ld", (long)timeSpent);
    //    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onAdError:(NSString*)errorMessage {
    NSLog(@"sunnysideMobile: onAdError: %@", errorMessage);
    //    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onNoAdsAvailable {
    NSLog(@"sunnysideMobile: onNoAdsAvailable");
    //    [self resetActiveAdRenderer];
    [self.player play];
}

- (void)onAdFreePod {
    NSLog(@"sunnysideMobile: onAdFreePod");
    [self seekOverCurrentAdBreak];
}

- (void)onPopupWebsite:(NSString *)url {
    NSLog(@"sunnysideMobile: onPopupWebsite: %@", url);
//    [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url] options:@{} completionHandler:nil];
    
    UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    WebViewViewController* newViewController = [storyBoard instantiateViewControllerWithIdentifier:@"webviewVC"];
    newViewController.url = [NSURL URLWithString:url];
    newViewController.modalPresentationStyle = UIModalPresentationPopover;
    [self presentViewController:newViewController animated:YES completion:nil];
}

// @optional
-(void) onOptIn:(NSString*)campaignName adId:(NSInteger)adId {
    NSLog(@"sunnysideMobile: onOptIn: %@, %li", campaignName, (long)adId);
    
}

-(void) onOptOut:(BOOL)userInitiated {
    NSLog(@"sunnysideMobile: userInitiated: %@", userInitiated? @"true": @"false");
}

-(void) onSkipCardShown {
    NSLog(@"sunnysideMobile: onSkipCardShown");
}

-(void) onUserCancel {
    NSLog(@"sunnysideMobile: onUserCancel");
}

// MARK: - Helper Functions

// Simulating video server call
- (void)fetchVmapFromServer {
    // NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithContentsOfURL:[[NSURL alloc] initWithString:@""]];
    NSData* vmapData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"vmap" ofType:@"xml"]];
    NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithData:vmapData];
    [xmlparser setDelegate:self];
    
    BOOL success = [xmlparser parse];
    if (success) {
        [self setupStream];
        [self.player play];
        
        // The Boundary Time Observer doesn't like 0s, thus I am firing these event manually. Your video/ad framework should already handle these
        [self videoStarted];
        [self adBreakStarted];
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
                                          // Use weak reference to self
                                          [weakSelf adBreakStarted];
                                      }];
    
    // Ad Break End Event
    [self.player addBoundaryTimeObserverForTimes:adBreakEndTimes
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          // Use weak reference to self
                                          [weakSelf adBreakEnded];
                                      }];
    
    // Video Start Event
    [self.player addBoundaryTimeObserverForTimes:@[@0]
                                           queue:dispatch_get_main_queue()
                                      usingBlock:^{
                                          // Use weak reference to self
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
    
    // Snap Video Position back to the beginning of Ad Break
    [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.5, NSEC_PER_SEC)
                                              queue:dispatch_get_main_queue()
                                         usingBlock:^(CMTime time) {
        if (!_inAdBreak && weakSelf.player.rate != 0) {
            NSDictionary* currentAdBreak = [weakSelf currentAdBreak];
            if (currentAdBreak != nil) {
                NSDictionary* currentAdBreak = [weakSelf currentAdBreak];
                int timeOffset = [[currentAdBreak valueForKey:@"timeOffset"] intValue];
                [weakSelf.player seekToTime:CMTimeMake(timeOffset, 1)];
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
