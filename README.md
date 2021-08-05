# Overview

This project contains sample source code that demonstrates how to integrate the true[X]
Ad Renderer in iOS. This document will step through the various pieces of code that make
the integration work, so that the same basic ideas can be replicated in a real production app.

This reference app covers the essential work. It assumes your app already have a working ad manager.

~~For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-mobile-integrations/~~ (OUTDATED)

# Access the true[X] Ad Renderer Library

One can get the true[X] Ad Renderer either by the 
[non-standard CocoaPods integration](https://guides.cocoapods.org/making/private-cocoapods.html): 
[TrueX CocoaPods](https://github.com/socialvibe/cocoapod-specs) 
```
source 'https://github.com/socialvibe/cocoapod-specs.git'

target 'your-app' do
    pod 'TruexAdRenderer-iOS', '3.2'
end
```
or direct download and have added to your project appropriately.

# Steps
The following steps are a guideline for the true[X] Ad Renderer integration. This assumes you have setup the true[X] Ad Renderer dependency above to access the renderer. The starting/key points referenced in each step can be searched in the code for reference. EG. Searching for [2], will direct you to the engagement start.
 
### [1] - Look for true[X] companions for a given ad
For simplicity, this sample app uses a fake ad manager that reads a fake vmap from a remote location (the vmap is also included in the repo).  The important part here is determining if a given ad, which should be the first ad in a pod, is a true[X] ad.  This can vary depending on how the ads are returned by the server.  Here in this fake vmap we have an ad system field.

### [2] - Prepare to enter the engagement
Once as have a valid true[X] ad, first we pause playback.  Then we initialize true[X] Ad Renderer by allocating the `TruexAdRenderer`, and calls `initWithUrl:adParameters:slotType`.  One also needs to setup delegate for interfacing with the true[X] Ad Renderer events later on.  Note that by initializing true[X] Ad Renderer, the renderer will initialize and verify it has a valid ad payload, and it fires a callback when it is ready to start.  Calling `start:` will display the true[X] ad, which you can call right after the init call-- we will start as soon as the preload is completed.  In addition, there is an optional callback in the `initWithUrl` method, as well as a delegate method to indicate the init has been completed. 
After the renderer has started, it will communicate various delegates.

### [3] - Respond to onAdFreePod
There are a handful of key ad events that TAR will message to the host app.  The first key event is `onAdFreePod`.  Once a user fulfills the requirements to earn credit for the ad, also called true[ATTENTION], this event is fired, and a flag keeps track of this in the code.  It is important to note that `onAdFreePod` can be acquired before the user exits the engagement, and the host app should wait for a terminating event to proceed. In this reference app, we seek over the ad break at this point.

### [4] - Respond to renderer terminating events
There are three ways the renderer can finish:

1. There were no ads available. (`onNoAdsAvailable`)
2. The ad had an error. (`onAdError`)
3. The viewer has completed the engagement. (`onCompletion`)

In `onCompletion`, note that if the user has gained credit from earlier, we want to skip all the other ad returned in the pod and resume the stream.  Otherwise we need to play the other ads in the pod.  In all three of these cases, the renderer will have removed itself from view.

### [5] - Other delegate/callback method
See the code for other ad events that are fired.  Some events are for any custom purposes if needed, otherwise there is nothing the host app is required to do (eg. `onAdStarted`).  The `onPopupWebsite` event is for handling any user interactions that would prompt a pop up.  It is important to pause/resume the ad renderer based off the user actions to preserve proper states when switching to another app, as shown in the code.