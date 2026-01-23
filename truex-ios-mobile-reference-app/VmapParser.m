//
//  VmapParser.m
//  truex-ios-mobile-reference-app
//

#import "VmapParser.h"

@implementation VideoMap

- (instancetype)init {
    self = [super init];
    if (self) {
        _adBreaks = @[];
    }
    return self;
}

@end

@interface VmapParserDelegate : NSObject <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableArray<AdBreak *> *adBreaks;
@property (nonatomic, strong) AdBreak *currentAdBreak;
@property (nonatomic, strong) NSMutableArray<Ad *> *currentAds;
@property (nonatomic, strong) Ad *currentAd;
@property (nonatomic, strong) NSMutableString *currentElementValue;
@property (nonatomic, strong) NSString *currentAdSystem;
@property (nonatomic, assign) BOOL inWrapper;
@property (nonatomic, assign) BOOL inInLine;
@property (nonatomic, assign) BOOL inLinear;

@end

@implementation VmapParserDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _adBreaks = [NSMutableArray array];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {

    self.currentElementValue = [NSMutableString string];

    if ([elementName isEqualToString:@"vmap:AdBreak"]) {
        self.currentAdBreak = [[AdBreak alloc] init];
        self.currentAds = [NSMutableArray array];

        NSString *breakId = attributeDict[@"breakId"];
        NSString *timeOffset = attributeDict[@"timeOffset"];

        if (breakId) {
            self.currentAdBreak.breakId = breakId;
        }

        // Parse timeOffset - can be "start", "end", or "HH:MM:SS.mmm"
        int timeOffsetSeconds = 0;
        if ([timeOffset isEqualToString:@"start"]) {
            timeOffsetSeconds = 0;
        } else if ([timeOffset isEqualToString:@"end"]) {
            timeOffsetSeconds = -1; // Will need special handling
        } else if (timeOffset) {
            timeOffsetSeconds = [self parseTimeOffset:timeOffset];
        }
        self.currentAdBreak.timeOffsetSeconds = timeOffsetSeconds;
    }
    else if ([elementName isEqualToString:@"Ad"]) {
        self.currentAd = [[Ad alloc] init];
        self.inWrapper = NO;
        self.inInLine = NO;
        self.inLinear = NO;
        self.currentAdSystem = nil;

        NSString *adId = attributeDict[@"id"];
        if (adId) {
            self.currentAd.adId = adId;
        }
    }
    else if ([elementName isEqualToString:@"Wrapper"]) {
        self.inWrapper = YES;
    }
    else if ([elementName isEqualToString:@"InLine"]) {
        self.inInLine = YES;
    }
    else if ([elementName isEqualToString:@"Linear"]) {
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

    NSString *value = [self.currentElementValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([elementName isEqualToString:@"vmap:AdBreak"]) {
        if (self.currentAdBreak && self.currentAds.count > 0) {
            self.currentAdBreak.ads = [self.currentAds copy];
            [self.adBreaks addObject:self.currentAdBreak];
        }
        self.currentAdBreak = nil;
        self.currentAds = nil;
    }
    else if ([elementName isEqualToString:@"Ad"]) {
        if (self.currentAd && self.currentAd.adSystem) {
            [self.currentAds addObject:self.currentAd];
        }
        self.currentAd = nil;
    }
    else if ([elementName isEqualToString:@"Wrapper"]) {
        self.inWrapper = NO;
    }
    else if ([elementName isEqualToString:@"InLine"]) {
        self.inInLine = NO;
    }
    else if ([elementName isEqualToString:@"Linear"]) {
        self.inLinear = NO;
    }
    else if ([elementName isEqualToString:@"AdSystem"]) {
        self.currentAdSystem = value;
        self.currentAd.adSystem = value;
    }
    else if ([elementName isEqualToString:@"AdTitle"]) {
        self.currentAd.title = value;
    }
    else if ([elementName isEqualToString:@"VASTAdTagURI"]) {
        // Wrapper URL for TrueX and IDVx
        if (self.inWrapper && value.length > 0) {
            self.currentAd.wrapperUrl = value;
        }
    }
    else if ([elementName isEqualToString:@"Duration"]) {
        if (self.inLinear && value.length > 0) {
            int durationSeconds = [self parseTimeOffset:value];
            self.currentAd.duration = durationSeconds;
        }
    }
    else if ([elementName isEqualToString:@"MediaFile"]) {
        if (self.inLinear && value.length > 0 && !self.currentAd.mediaFile) {
            self.currentAd.mediaFile = value;
        }
    }
}

// Parse time format "HH:MM:SS" or "HH:MM:SS.mmm" to seconds
- (int)parseTimeOffset:(NSString *)timeString {
    NSArray *components = [timeString componentsSeparatedByString:@":"];
    if (components.count >= 3) {
        int hours = [components[0] intValue];
        int minutes = [components[1] intValue];

        // Handle seconds with optional milliseconds
        NSString *secondsStr = components[2];
        float seconds = [secondsStr floatValue];

        return hours * 3600 + minutes * 60 + (int)seconds;
    }
    return 0;
}

@end

@implementation VmapParser

+ (VideoMap *)parseVmapFromBundleResource:(NSString *)resourceName
                                streamUrl:(NSString *)streamUrl
                           streamDuration:(NSInteger)streamDuration
                                    error:(NSError **)error {

    NSString *path = [[NSBundle mainBundle] pathForResource:resourceName ofType:@"xml"];
    if (!path) {
        if (error) {
            *error = [NSError errorWithDomain:@"VmapParser"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"VMAP resource not found"}];
        }
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"VmapParser"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to read VMAP file"}];
        }
        return nil;
    }

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    VmapParserDelegate *delegate = [[VmapParserDelegate alloc] init];
    parser.delegate = delegate;

    if (![parser parse]) {
        if (error) {
            *error = parser.parserError ?: [NSError errorWithDomain:@"VmapParser"
                                                               code:3
                                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse VMAP XML"}];
        }
        return nil;
    }

    // Build the VideoMap object
    VideoMap *videoMap = [[VideoMap alloc] init];
    videoMap.url = streamUrl;
    videoMap.duration = streamDuration;
    videoMap.adBreaks = [delegate.adBreaks copy];

    return videoMap;
}

@end
