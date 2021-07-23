//
//  WebViewViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/22/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import <WebKit/WebKit.h>
#import "WebViewViewController.h"

@interface WebViewViewController ()
@property (weak, nonatomic) IBOutlet WKWebView *mainWebView;

@end

@implementation WebViewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    if (self.url) {
        NSURLRequest* request = [[NSURLRequest alloc] initWithURL:self.url];
        [self.mainWebView loadRequest:request];
    }
}
//
//- (void)viewWillDisappear:(BOOL)animated {
//    [super viewWillDisappear:animated];
//    if (self.isBeingDismissed) {
//        if (self.onDismiss) {
//            self.onDismiss();
//        }
//    }
//}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed) {
        if (self.onDismiss) {
            self.onDismiss();
        }
    }
}
/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
