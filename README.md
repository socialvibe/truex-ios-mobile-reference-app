# Overview

This project contains sample source code that demonstrates how to integrate Infillion's interactive ad renderer in iOS. This document will step through the various pieces of code that make the integration work, so that the same basic ideas can be replicated in a real production app.

**Infillion interactive ads** include:
* **TrueX ads** - Interactive choice card experiences that allow users to skip an entire ad break by engaging with branded content
* **IDVx ads** - Interactive ads that start automatically and play inline with other ads in the break

This reference app covers the essential work. It assumes your app already has a working ad manager.

For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-mobile-integrations/

# Access the Infillion Ad Renderer Library

The Infillion Ad Renderer can be integrated via Swift Package Manager (recommended) or CocoaPods.

## Swift Package Manager (Recommended)

Add the [TruexAdRenderer-iOS-Swift-Package](https://github.com/socialvibe/TruexAdRenderer-iOS-Swift-Package) repository to your project:

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/socialvibe/TruexAdRenderer-iOS-Swift-Package`
3. Select version `4.1.0` or later

## CocoaPods

Alternatively, use the [non-standard CocoaPods integration](https://guides.cocoapods.org/making/private-cocoapods.html) with the [TrueX CocoaPods spec repository](https://github.com/socialvibe/cocoapod-specs):

```
source 'https://github.com/socialvibe/cocoapod-specs.git'

target 'your-app' do
    pod 'TruexAdRenderer-iOS', '4.1.0'
end
```

# Implementation Details

## Ad Break Configuration

Ad break configuration is maintained in `adbreaks.json`. Key fields:
* `streamUrl`: URL of the main video content
* `streamDuration`: total length of the video in seconds
* `adBreaks`: array of ad break objects, each with:
  * `breakId`: identifier for the ad break (e.g., "preroll", "midroll-1")
  * `timeOffsetMs`: when the ad break should trigger in milliseconds
  * `ads`: array of ad objects, each with:
    * `adSystem`: ad type ("trueX", "IDVx", or "GDFP")
    * `description`: VAST config URL for TrueX ads
    * `adParameters`: JSON configuration for IDVx ads
    * `mediaFile`: URL for standard video ads
    * `duration`: length of the ad in seconds

## Infillion Interactive Ads

This reference app demonstrates both types of Infillion interactive ads:

### TrueX Ads
TrueX ads present an **interactive choice card** where users can **opt-in** to engage with branded content. The user makes an active choice to interact with the ad. If the user completes the interaction, they earn an **ad credit that skips the entire ad break**, and the main video resumes immediately. If the user opts out or ignores the choice card, standard fallback ads play instead.

**Key characteristics:**
- **Opt-in via choice card** - User must actively choose to engage
- **Skips entire ad break** - Successful engagement bypasses all remaining ads in the pod
- **Configuration**: Uses the `description` field containing a VAST config URL

### IDVx Ads
IDVx ads are **interactive ads** that start **automatically without requiring opt-in**. Unlike TrueX ads which require users to opt-in via a choice card, IDVx ads begin playing automatically. While no opt-in is required to start, users can interact with the ad content throughout its duration. IDVx ads **play inline with other ads** in the ad break. After an IDVx ad completes, the next ad in the sequence plays.

**Key characteristics:**
- **Automatic start** - No opt-in required, begins playing automatically
- **Interactive throughout** - Users can interact with ad content for its duration
- **Plays inline** - Completes and continues to next ad in the pod
- **Configuration**: Uses the `adParameters` field containing JSON configuration

## Key Components

* **`InfillionAdManager`** - Wrapper class that manages the `TruexAdRenderer` for both TrueX and IDVx ads
* **`InfillionAdType`** - Enum defining ad types (TrueX, IDVx, Regular) with helper functions
* **`VideoPlayerViewController`** - Main view controller that handles video playback and ad break management

# Integration Steps

The following steps are a guideline for the Infillion Ad Renderer integration. This assumes you have setup the Ad Renderer dependency above. The starting/key points referenced in each step can be searched in the code for reference.

### [1] - Identify Infillion ads in an ad break
For simplicity, this sample app uses a fake ad manager that reads ad break configuration from a local JSON file (`adbreaks.json`). The important part is determining if a given ad is an Infillion interactive ad (TrueX or IDVx). This can vary depending on how ads are returned by the server. In this example, the JSON has an `adSystem` attribute that indicates the ad type.

The `InfillionAdType` helper functions (`InfillionAdTypeFromString`, `IsInfillionAd`) are used to identify and categorize ads.

### [2] - Start the Infillion ad
When an Infillion ad is encountered, the `InfillionAdManager` is used to start the ad:

1. Pause the main video playback
2. Create an `InfillionAdManager` instance and set its delegate
3. Call `startAdOnView:vastConfigUrl:adParameters:slotType:adType:` with the appropriate configuration:
   - For **TrueX ads**: pass the VAST config URL in `vastConfigUrl`
   - For **IDVx ads**: pass the JSON configuration in `adParameters`

The `InfillionAdManager` internally creates a `TruexAdRenderer` and calls the appropriate initialization method based on the ad type.

### [3] - Respond to ad completion
The `InfillionAdManagerDelegate` protocol provides callbacks for ad events:

* **`infillionAdDidComplete:receivedCredit:`** - Called when the ad finishes
  - If `receivedCredit` is `YES` (TrueX only): Skip all remaining ads in the break and resume content
  - If `receivedCredit` is `NO`: Play the next ad in the sequence

* **`infillionAdDidStart:`** - Called when the ad begins playing
* **`infillionAdPopupWebsite:`** - Called when the user taps a link; pause the ad and show a web view

### [4] - Handle the ad break flow
The `VideoPlayerViewController` manages the sequential playback of ads in a break:

1. When an ad break starts, `playNextAdInBreak` is called
2. For each ad, check the `adSystem` to determine how to play it:
   - **Infillion ads** (TrueX/IDVx): Use `InfillionAdManager`
   - **Standard video ads** (GDFP): Load the `mediaFile` URL directly into the player
3. When an ad completes, increment the ad index and call `playNextAdInBreak` again
4. When all ads are done, call `resumeContentAfterAds` to restore the main video

**Note**: This reference app supports multiple interactive ads per ad break (TrueX, IDVx) with fallback ads, showing how different ad types can be sequenced in a single ad pod.

### [5] - Other delegate methods
See the code for other ad events that are fired. Some events are for custom purposes if needed:
* `infillionAdDidOptIn:adId:` - User opted into the TrueX engagement
* `infillionAdDidOptOut:` - User opted out of the engagement
* `infillionAdSkipCardShown` - Skip card was displayed
* `infillionAdUserCancel` - User cancelled the engagement
* `infillionAdUserCancelStream` - User wants to cancel the video stream

The `infillionAdPopupWebsite:` event is for handling user interactions that open external links. It is important to pause/resume the ad renderer when switching to another view, as shown in the code.
