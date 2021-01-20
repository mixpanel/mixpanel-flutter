<div align="center" style="text-align: center">
  <img src="https://github.com/mixpanel/mixpanel-android/blob/assets/mixpanel.png?raw=true" alt="Mixpanel React Native Library" height="150"/>
</div>

#####
# Table of Contents

<!-- MarkdownTOC -->
- [Introduction](#introduction)
- [Quick Start Guide](#quick-start-guide)
    - [Installation](#installation)
    - [Integration](#integration)
- [I want to know more!](#i-want-to-know-more)

<!-- /MarkdownTOC -->


# Introduction
Welcome to the official Mixpanel Flutter library.
The Mixpanel Flutter library is an open-source project, and we'd love to see your contributions!
We'd also love for you to come and work with us! Check out **[Jobs](https://mixpanel.com/jobs/#openings)** for details

# Quick Start Guide

Check out our **[official documentation](https://developer.mixpanel.com/docs/flutter)** for more in depth information on installing and using Mixpanel on Flutter.

<a name="installation"></a>
## Installation
### Prerequisite
- [Setup development environment for Flutter](https://flutter.dev/docs/get-started/install)
### Steps
1. Depend on it
Add this to your package's pubspec.yaml file:
```
   dependencies:
      mixpanel_flutter: ^1.0.0
```
2. Install it
You can install packages from the command line:
with Flutter:
```
   $ flutter pub get
```
3. Import it
Now in your Dart code, you can use:
```
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
```
## Integration
### Initialization
To start tracking with the library you must first initialize with your project token. To initialize the library, first add `import 'package:mixpanel_flutter/mixpanel_flutter.dart';` and call `Mixpanel.init(token);` with your project token as it's argument.
```dart
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
...
class _YourClassState extends State<YourClass> {
  Mixpanel _mixpanel;

  @override
  void initState() {
   super.initState();
   initMixpanel();
  }

  Future<void> initMixpanel() async {
   _mixpanel = await Mixpanel.init("5d9d3df08d1c34a272abf23d892820bf",
               optOutTrackingDefault: false);
  }
...
```
Once you've called this method once, you can access `mixpanel` throughout the rest of your application.
### Tracking
Once you've initialized the library, Mixpanel will <a href="https://mixpanel.com/help/questions/articles/which-common-mobile-events-can-mixpanel-collect-on-my-behalf-automatically" target="_blank">automatically collect common mobile events</a>. You can enable/ disable automatic collection through your <a href="https://mixpanel.com/help/questions/articles/how-do-i-enable-common-mobile-events-if-i-have-already-implemented-mixpanel" target="_blank">project settings</a>.
With the `mixpanel` object created in [the last step](#integration) a call to `track` is all you need to send additional events to Mixpanel.
```js
// Track with event-name
mixpanel.track('Sent Message');
// Track with event-name and property
mixpanel.track('Plan Selected', properties: {'Plan': 'Premium'});;
```
You're done! You've successfully integrated the Mixpanel React Native SDK into your app. To stay up to speed on important SDK releases and updates, star or watch our repository on [Github](https://github.com/mixpanel/mixpanel-flutter).

<a name="i-want-to-know-more"></a>
# I want to know more!

No worries, here are some links that you will find useful:
* **[Sample app](https://github.com/mixpanel/mixpanel-flutter/tree/master/example)**
* **[Full API Reference](https://developer.mixpanel.com/docs/flutter)**

Have any questions? Reach out to Mixpanel [Support](https://help.mixpanel.com/hc/en-us/requests/new) to speak to someone smart, quickly.