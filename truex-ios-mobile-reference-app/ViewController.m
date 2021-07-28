//
//  ViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "ViewController.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    // Optional, request ad tracking
    // See: https://developer.apple.com/documentation/apptrackingtransparency
    [self requestTrackingClicked];
}

- (void)requestTrackingClicked {
    if (@available(iOS 14.0, *))
    {
        [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
            NSLog(@"%@", status == ATTrackingManagerAuthorizationStatusAuthorized? @"ATTrackingManagerAuthorizationStatusAuthorized YES": @"ATTrackingManagerAuthorizationStatusAuthorized NO");
        }];
    }
}

@end
