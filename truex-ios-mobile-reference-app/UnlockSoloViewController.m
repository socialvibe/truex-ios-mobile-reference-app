//
//  UnlockSoloViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by kyle on 9/27/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "UnlockSoloViewController.h"
#import "WebViewViewController.h"
#import "InfillionAdManager.h"
#import "InfillionAdType.h"

@interface UnlockSoloViewController ()

@property (nonatomic, strong) InfillionAdManager *adManager;
@property (nonatomic, strong) NSString *vastConfigUrl;

@property (weak, nonatomic) IBOutlet UISwitch *unlocked;

@end

@implementation UnlockSoloViewController

// VAST config URL for the solo ad experience
// This should be pointing to your ad server, where a TrueX ad is booked.
NSString *const SOLO_AD_SERVER = @"https://qa-get.truex.com/5075c46a8e5a48a206318d4ecfb5cc70101e0bcf/vast/solo?dimension_2=1&stream_position=midroll&stream_id=[stream_id]&network_user_id=[user_id]";

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
    // Prepare the VAST config URL with macros replaced
    [self prepareVastConfigUrl];
}

- (void)viewDidDisappear:(BOOL)animated {
    [self resetAdManager];
}

- (void)prepareVastConfigUrl {
    if (self.vastConfigUrl != nil) {
        return;
    }
    NSString *url = SOLO_AD_SERVER;
    url = [url stringByReplacingOccurrencesOfString:@"[stream_id]" withString:[[NSUUID UUID] UUIDString]];
    // Replacing user_id with random UUID here for testing, please use the real user ID from the system.
    // Usually this will be filled out by your ad server, or you will fill in your internal ID
    url = [url stringByReplacingOccurrencesOfString:@"[user_id]" withString:[[NSUUID UUID] UUIDString]];
    self.vastConfigUrl = url;
    NSLog(@"[TrueX] Prepared VAST config URL: %@", self.vastConfigUrl);
}

- (IBAction)unlockWithTruex:(id)sender {
    if (self.unlocked.on) {
        [self alertWithTitle:@"Unlocked" message:@"Already Unlocked" completion:nil];
        return;
    }

    if (!self.vastConfigUrl) {
        [self alertWithTitle:@"Not Ready" message:@"Preparing ad URL" completion:nil];
        return;
    }

    // Start the TrueX engagement
    [self resetAdManager];

    // Create the InfillionAdManager
    self.adManager = [[InfillionAdManager alloc] init];
    self.adManager.delegate = self;

    // Start as TrueX ad with VAST config URL
    NSLog(@"[TrueX] Starting TrueX solo ad with URL: %@", self.vastConfigUrl);
    [self.adManager startAdOnView:self.view
                    vastConfigUrl:self.vastConfigUrl
                     adParameters:nil
                         slotType:@"midroll"
                           adType:InfillionAdTypeTruex];
}

- (IBAction)onBackPressed:(id)sender {
    [self resetAdManager];
    [self dismissViewControllerAnimated:YES completion:nil];
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

// MARK: - InfillionAdManagerDelegate Methods

- (void)infillionAdDidStart:(NSString *)campaignName {
    // User has started their ad engagement
    NSLog(@"[TrueX] onAdStarted: %@", campaignName);
}

- (void)infillionAdDidComplete:(BOOL)receivedCredit {
    // User has finished the Infillion engagement
    NSLog(@"[TrueX] onAdComplete: receivedCredit=%@", receivedCredit ? @"YES" : @"NO");

    if (receivedCredit) {
        // User earned credit, unlock the content
        [self.unlocked setOn:YES];
    }

    [self resetAdManager];
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

// MARK: - Helper Functions

- (void)alertWithTitle:(NSString*)title message:(NSString*)message completion:(void (^)(void))completionCallback {
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
