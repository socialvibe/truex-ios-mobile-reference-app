//
//  VmapParser.h
//  truex-ios-mobile-reference-app
//

#import <Foundation/Foundation.h>
#import "Ad.h"
#import "AdBreak.h"

NS_ASSUME_NONNULL_BEGIN

@interface VideoMap : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, copy) NSArray<AdBreak *> *adBreaks;
@end

@interface VmapParser : NSObject

// Parse VMAP XML data and return a VideoMap object with Ad and AdBreak models
+ (VideoMap * _Nullable)parseVmapFromBundleResource:(NSString *)resourceName
                                          streamUrl:(NSString *)streamUrl
                                     streamDuration:(NSInteger)streamDuration
                                              error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
