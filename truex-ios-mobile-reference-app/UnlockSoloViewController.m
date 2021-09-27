//
//  UnlockSoloViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by kyle on 9/27/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "UnlockSoloViewController.h"
#import "WebViewViewController.h"
#import <TruexAdRenderer/TruexAdRenderer.h>

@interface UnlockSoloViewController ()

@property TruexAdRenderer* activeAdRenderer;
@property NSMutableDictionary* vastDictionary;

@property (weak, nonatomic) IBOutlet UISwitch *unlocked;

// internal states
@property NSMutableDictionary* currentPointer;

@end

// internal state for the fake ad manager
BOOL _vastReady = NO;


@implementation UnlockSoloViewController

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
    // Helper function to fetch ad to vastDictionary
    // This should be pointing to your ad server, where a true[X] ad is booked.
    [self fetchAd:@"https://qa-get.truex.com/5075c46a8e5a48a206318d4ecfb5cc70101e0bcf/vast/solo?dimension_2=1&stream_position=midroll&stream_id=[stream_id]&network_user_id=[user_id]"];
}

- (void)viewDidDisappear:(BOOL)animated {
    [self resetActiveAdRenderer];
}

- (IBAction)unlockWithTruex:(id)sender {
    if (self.unlocked.on) {
        [self alertWithTitle:@"Unlocked" message:@"Already Unlocked" completion:nil];
        return;
    }
    
    if (!_vastReady || !self.vastDictionary) {
        [self alertWithTitle:@"Not Ready" message:@"Downloading VAST" completion:nil];
        return;
    }
    
    // [1] - Look for true[X] in ads
    // Here we use a fake ad manager, which parse the VAST XML directly into a dictionary.
    @try {
        // Just checking the 1st ad here to simplify the flow.
        NSMutableDictionary* currentAd = self.vastDictionary[@"Ad"][0][@"InLine"][0];
        BOOL isTruexAd = [self isTruexAd: currentAd];
        if (isTruexAd) {
            // [2] - Prepare to enter the engagement
            [self resetActiveAdRenderer];
            
            // Getting the adParameter from current ad, probably will look different in your Ad Framework.
            NSString* adParametersString = currentAd[@"Creatives"][0][@"Creative"][0][@"Linear"][0][@"AdParameters"][0][@"CDATA"];
            NSError *jsonError;
            NSData *adParametersData = [adParametersString dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *adParameters = [NSJSONSerialization JSONObjectWithData:adParametersData
                                                                         options:NSJSONReadingMutableContainers
                                                                           error:&jsonError];
            if (jsonError) {
                [self alertWithTitle:@"Error" message:@"Failed to parse adParametersData into JSON" completion:nil];
                return;
            }
            
            self.activeAdRenderer = [[TruexAdRenderer alloc] initWithUrl:@"https://media.truex.com/placeholder.js"
                                                            adParameters:adParameters
                                                                slotType:@"midroll"];
            self.activeAdRenderer.delegate = self;
            [self.activeAdRenderer start:self.view];
        } else {
            [self alertWithTitle:@"Not true[X] ad" message:@"Something went wrong, playing fallback ads." completion:nil];
        }
    } @catch(id anException) {
        [self alertWithTitle:@"Error" message:@"Failed to parse the 1st ad" completion:nil];
    }
}

- (BOOL)isTruexAd:(NSMutableDictionary *)currentAd {
    NSString* adSystem = currentAd[@"AdSystem"][0][@"characters"];
    return [adSystem isEqualToString:@"trueX"];
}

- (IBAction)onBackPressed:(id)sender {
    [self resetActiveAdRenderer];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    // true[X] - Hide home indicator during true[X] Ad
    return (self.activeAdRenderer != nil);
}

- (BOOL)prefersStatusBarHidden {
    // true[X] - Hide the status bar during true[X] Ad
    return (self.activeAdRenderer != nil);
}

- (void)pause {
    // true[X] - Besure to pasue and resume the true[X] Ad Renderer
    [self.activeAdRenderer pause];
}

- (void)resume {
    [self.activeAdRenderer resume];
}

- (void)resetActiveAdRenderer {
    if (self.activeAdRenderer) {
        [self.activeAdRenderer stop];
    }
    self.activeAdRenderer = nil;
}



// MARK: - TRUEX DELEGATE METHODS
// [5] - Other delegate method
- (void)onAdStarted:(NSString*)campaignName {
    // true[X] - User has started their ad engagement
    NSLog(@"truex: onAdStarted: %@", campaignName);
}

// [4] - Respond to renderer terminating events
- (void)onAdCompleted:(NSInteger)timeSpent {
    // true[X] - User has finished the true[X] engagement, resume the video stream
    NSLog(@"truex: onAdCompleted: %ld", (long)timeSpent);
    [self resetActiveAdRenderer];
}

// [4]
- (void)onAdError:(NSString*)errorMessage {
    // true[X] - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
    NSLog(@"truex: onAdError: %@", errorMessage);
    [self resetActiveAdRenderer];
    [self alertWithTitle:@"onAdError" message:@"Something went wrong, playing fallback ads." completion:nil];
}

// [4]
- (void)onNoAdsAvailable {
    // true[X] - TruexAdRenderer has no ads ready to present, resume with standard ads
    NSLog(@"truex: onNoAdsAvailable");
    [self resetActiveAdRenderer];
    [self alertWithTitle:@"onNoAdsAvailable" message:@"Something went wrong, playing fallback ads." completion:nil];
}

// [3] - Respond to onAdFreePod
- (void)onAdFreePod {
    // true[X] - User has met engagement requirements, skips past remaining pod ads
    NSLog(@"truex: onAdFreePod");
    [self.unlocked setOn:YES];
}

// [5] - Other delegate method
- (void)onPopupWebsite:(NSString *)url {
    // true[X] - User wants to open an external link in the true[X] ad

    NSLog(@"truex: onPopupWebsite: %@", url);
    // Open URL with the SFSafariViewController
    // SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString: url]];
    // svc.delegate = self;
    // svc.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    // [self presentViewController:svc animated:YES completion:nil];
    // [self.activeAdRenderer pause];
    
    // Or, open the URL directly in Safari
    // [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url] options:@{} completionHandler:nil];
    
    // Or, open with the existing in-app webview
     UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
     WebViewViewController* newViewController = [storyBoard instantiateViewControllerWithIdentifier:@"webviewVC"];
     newViewController.url = [NSURL URLWithString:url];
     newViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
     __weak typeof(self) weakSelf = self;
     newViewController.onDismiss = ^(void) {
         // true[X] - You will need to pause and remume the true[X] Ad Renderer
         [weakSelf.activeAdRenderer resume];
     };
     [self.activeAdRenderer pause];
     [self presentViewController:newViewController animated:YES completion:nil];
}

// When using SFSafariViewController for onPopupWebsite
//- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
//    // true[X] - You will need remume the true[X] Ad Renderer after safariViewController
//    if (self.activeAdRenderer) {
//        [self.activeAdRenderer resume];
//    }
//}


// MARK: - Helper Functions / Fake Ad Framework
- (void)fetchAd:(NSString *)url {
    if (self.vastDictionary != nil) {
        return;
    }
    url = [url stringByReplacingOccurrencesOfString:@"[stream_id]" withString:[[NSUUID UUID] UUIDString]];
    // replacing user_id with random UUID here for testing, please user the real user ID from the system.
    url = [url stringByReplacingOccurrencesOfString:@"[user_id]" withString:[[NSUUID UUID] UUIDString]];
    
    // Fetch the xml from server
    NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithContentsOfURL:[[NSURL alloc] initWithString:url]];
    
    // Or use the hardcoded copy
    // NSData* vastSoloData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"vast_solo" ofType:@"xml"]];
    // NSXMLParser *xmlparser = [[NSXMLParser alloc] initWithData:vastSoloData];
    
    [xmlparser setDelegate:self];
    BOOL success = [xmlparser parse];
    if (success) {
//        // Print vastDictionary as JSON string to help with debug.
//        NSError *error;
//        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.vastDictionary
//                                                           options:NSJSONWritingPrettyPrinted && NSJSONWritingSortedKeys
//                                                             error:&error];
//        if (!jsonData) {
//            NSLog(@"Got an error: %@", error);
//        } else {
//            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
//            NSLog(@"vastDictionary: %@", jsonString);
//        }
        _vastReady = YES;
        NSLog(@"fetchAd: ready");
    } else {
        [self alertWithTitle:@"Error" message:@"Failed to fetch vmap." completion:nil];
    }
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    NSMutableDictionary* parent = self.currentPointer;
    self.currentPointer = [attributeDict mutableCopy];
    
    if (parent) {
        [self.currentPointer setObject:parent forKey:@"parent"];
        NSMutableArray* siblings = [parent objectForKey:elementName];
        if (!siblings) {
            [parent setObject:[[NSMutableArray alloc] initWithArray:@[]] forKey:elementName];
            siblings = [parent objectForKey:elementName];
        }
        [siblings addObject:self.currentPointer];
    }
    
    // setting the root
    if (!self.vastDictionary) {
        self.vastDictionary = self.currentPointer;
    }
}

- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)CDATABlock {
    if (self.currentPointer) {
        [self.currentPointer setObject:[[NSString alloc] initWithData:CDATABlock encoding:NSUTF8StringEncoding] forKey:@"CDATA"];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.currentPointer) {
        [self.currentPointer setObject:string forKey:@"characters"];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    if (self.currentPointer) {
        NSMutableDictionary* parent = [self.currentPointer objectForKey:@"parent"];
        [self.currentPointer removeObjectForKey:@"parent"];
        self.currentPointer = parent;
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    [self alertWithTitle:@"Error" message:@"Failed to fetch VAST." completion:nil];
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
