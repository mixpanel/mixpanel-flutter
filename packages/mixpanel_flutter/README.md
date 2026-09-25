<div align="center" style="text-align: center">
  <img src="https://user-images.githubusercontent.com/71290498/231855731-2d3774c3-dc41-4595-abfb-9c49f5f84103.png" alt="Mixpanel Flutter SDK" height="150"/>
</div>

##### _September 16, 2026_ - [v2.14.0](https://github.com/mixpanel/mixpanel-flutter/releases/tag/v2.14.0)

# Table of Contents

<!-- MarkdownTOC -->

- [Introduction](#introduction)
- [Quick Start Guide](#quick-start-guide)
  - [Install Mixpanel](#1-install-mixpanel)
  - [Initialize Mixpanel](#2-initialize-mixpanel)
  - [Send Data](#3-send-data)
  - [Check for Success](#4-check-for-success)
- [I want to know more!](#i-want-to-know-more)

<!-- /MarkdownTOC -->

# Introduction

Welcome to the official Mixpanel Flutter SDK.
The Mixpanel Flutter SDK is an open-source project, and we'd love to see your contributions!
We'd also love for you to come and work with us! Check out **[Jobs](https://mixpanel.com/jobs/#openings)** for details

# Quick Start Guide

Check out our **[official documentation](https://developer.mixpanel.com/docs/flutter)** for more in depth information on installing and using Mixpanel on Flutter.

## 1. Install Mixpanel

### Prerequisites

- [Setup development environment for Flutter](https://flutter.dev/docs/get-started/install)

### Steps

1. Depend on it \
   Add this to your package's pubspec.yaml file:

```
   dependencies:
      mixpanel_flutter: 2.14.0
```

2. Install it \
   You can install packages from the command line:

```
   $ flutter pub get
```

3. Import it \
   Now in your Dart code, you can use:

```
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
```

#### Flutter Web Support

Please add the following snippet to your `web/index.html` inside `<head></head>` in your Flutter project.

```
<script src="./assets/packages/mixpanel_flutter/assets/mixpanel.js"></script>
```

## 2. Initialize Mixpanel

To start tracking with the SDK you must first initialize with your project token. To initialize the SDK, first add `import 'package:mixpanel_flutter/mixpanel_flutter.dart';` and call `Mixpanel.init(token, trackAutomaticEvents);` with your project token and automatic events setting as it's arguments. You can find your token in [project settings](https://mixpanel.com/settings/project).

```dart
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
...
class _YourClassState extends State<YourClass> {
  Mixpanel mixpanel;

  @override
  void initState() {
    super.initState();
    initMixpanel();
  }

  Future<void> initMixpanel() async {
    mixpanel = await Mixpanel.init("Your Mixpanel Token", trackAutomaticEvents: false);
  }
...
```

Once you've called this method once, you can access `mixpanel` throughout the rest of your application.

### Custom Proxy or Data Residency

To route data to a specific Mixpanel regional endpoint (EU, India) or a custom proxy, pass the optional `serverURL` parameter at initialization:

```dart
mixpanel = await Mixpanel.init(
  "Your Mixpanel Token",
  trackAutomaticEvents: false,
  serverURL: "https://api-eu.mixpanel.com", // or https://api-in.mixpanel.com
);
```

You can also update the endpoint at runtime using `setServerURL()`.

## 3. Send Data

Once you've initialized the SDK, Mixpanel will <a href="https://mixpanel.com/help/questions/articles/which-common-mobile-events-can-mixpanel-collect-on-my-behalf-automatically" target="_blank">automatically collect common mobile events</a>. You can enable/disable automatic collection through your project settings.
With the `mixpanel` object created in [the last step](#2-initialize-mixpanel) a call to `track` is all you need to send additional events to Mixpanel.

```dart
// Track with event-name
mixpanel.track('Sent Message');
// Track with event-name and property
mixpanel.track('Plan Selected', properties: {'Plan': 'Premium'});
```

You're done! You've successfully integrated the Mixpanel Flutter SDK into your app. To stay up to speed on important SDK releases and updates, star or watch our repository on [GitHub](https://github.com/mixpanel/mixpanel-flutter).

## 4. Check for Success

[Open up Events in Mixpanel](https://mixpanel.com/report/events) to view incoming events.
Once data hits our API, it generally takes ~60 seconds for it to be processed, stored, and queryable in your project.

👋 👋 Tell us about the Mixpanel developer experience! [https://www.mixpanel.com/devnps](https://www.mixpanel.com/devnps) 👍 👎

# FAQ

**I want to stop tracking an event/event property in Mixpanel. Is that possible?**

Yes, in Lexicon, you can intercept and drop incoming events or properties. Mixpanel won’t store any new data for the event or property you select to drop. [See this article for more information](https://help.mixpanel.com/hc/en-us/articles/360001307806#dropping-events-and-properties).

**I have a test user I would like to opt out of tracking. How do I do that?**

Mixpanel’s client-side tracking library contains the [optOutTracking()](https://mixpanel.github.io/mixpanel-flutter/mixpanel_flutter/Mixpanel/optOutTracking.html) method, which will set the user’s local opt-out state to “true” and will prevent data from being sent from a user’s device. More detailed instructions can be found in the section, [Opting users out of tracking](https://developer.mixpanel.com/docs/flutter#opting-users-out-of-tracking).

**Why aren't my events showing up?**

First, make sure your test device has internet access. To preserve battery life and customer bandwidth, the Mixpanel library doesn't send the events you record immediately. Instead, it sends batches to the Mixpanel servers every 60 seconds while your application is running, as well as when the application transitions to the background. You can call [flush()](https://mixpanel.github.io/mixpanel-flutter/mixpanel_flutter/Mixpanel/flush.html) manually if you want to force a flush at a particular moment.

```
mixpanel.flush();
```

If your events are still not showing up after 60 seconds, check if you have opted out of tracking. You can also enable Mixpanel debugging and logging, it allows you to see the debug output from the Mixpanel library. To enable it, call [setLoggingEnabled](https://mixpanel.github.io/mixpanel-flutter/mixpanel_flutter/Mixpanel/setLoggingEnabled.html) to true, then run your iOS project with Xcode or android project with Android Studio. The logs should be available in the console.

```
mixpanel.setLoggingEnabled(true);
```

**Starting with iOS 14.5, do I need to request the user’s permission through the AppTrackingTransparency framework to use Mixpanel?**

No, Mixpanel does not use IDFA so it does not require user permission through the AppTrackingTransparency(ATT) framework.

**If I use Mixpanel, how do I answer app privacy questions for the App Store?**

Please refer to our [Apple App Developer Privacy Guidance](https://mixpanel.com/legal/app-store-privacy-details/)

# I want to know more!

No worries, here are some links that you will find useful:

- **[Sample app](https://github.com/mixpanel/mixpanel-flutter/tree/main/packages/mixpanel_flutter/example)**
- **[Full API Reference](https://developer.mixpanel.com/docs/flutter)**

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/mixpanel/mixpanel-flutter)

Have any questions? Reach out to Mixpanel [Support](https://help.mixpanel.com/hc/en-us/requests/new) to speak to someone smart, quickly.


### SDK requirements

The next analytics release requires Flutter 3.19.0 or later (Dart 3.3.0 or
later). This package requirement applies even when automatic capture is disabled.
Automatic targeting uses `Semantics.identifier`, available from Flutter 3.19.
Applications on older Flutter versions must upgrade Flutter or remain on an
earlier analytics release.

### Manual frustration signals (Beta)

> **Autocapture is in beta.** Autocapture — `$mp_click`, `$mp_rage_click` and
> `$mp_dead_click`, and the `mixpanel.autocapture` API — may contain issues, and
> its API and the properties it captures may change in a future release before
> general availability. Pin your SDK version if you build reports on autocaptured events.

Use `mixpanel.autocapture.trackClick`, `trackRageClick`, or `trackDeadClick`
when your application has already detected the corresponding interaction:

```dart
await mixpanel.autocapture.trackClick(const ClickEvent(
  x: 120,
  y: 240,
  elementId: 'checkout_button',
  tagName: 'ElevatedButton',
  role: 'Button',
));
```

Coordinates are in the owning Flutter view's logical pixels. Supply a static
identifier without personal data; do not use accessibility labels, input values,
or visible text. Optional metadata and extra properties are developer-supplied
and are not automatically sanitized. Blank identifiers or nonfinite coordinates
are ignored. Typed click metadata and `$mp_autocapture: true` override conflicting
extra properties. Events use the existing analytics transport and its opt-out
handling.

These methods emit one event each. They do not observe gestures or automatically
detect rage/dead clicks. Automatic capture is still under development for SDK-30.
The example app's **Manual Frustration Signals** page provides test fixtures.

### Automatic frustration signals (Beta, Android/iOS/macOS/web)

> **Autocapture is in beta.** Autocapture — `$mp_click`, `$mp_rage_click` and
> `$mp_dead_click`, and the `mixpanel.autocapture` API — may contain issues, and
> its API and the properties it captures may change in a future release before
> general availability. Pin your SDK version if you build reports on autocaptured events.

Requires Flutter 3.19 / Dart 3.3. No additional package is needed. Capture is off
unless `autocaptureOptions` is supplied at initialization:

```dart
final mixpanel = await Mixpanel.init(
  'YOUR_PROJECT_TOKEN',
  trackAutomaticEvents: false,
  autocaptureOptions: const AutocaptureOptions(
    clickOptions: ClickOptions(enabled: true),
    rageClickOptions: RageClickOptions(
      enabled: true, clickThreshold: 4, timeWindow: Duration(seconds: 1), radius: 44,
    ),
    deadClickOptions: DeadClickOptions(enabled: true, timeWindow: Duration(milliseconds: 500)),
  ),
);
runApp(MixpanelAutocaptureWidget(
  instance: mixpanel,
  child: const MaterialApp(home: MyHomePage()),
));
```

Place one wrapper above the app's navigators. The wrapper accepts a null
instance during asynchronous initialization and preserves child state when
capture changes.

A rage click means four accepted taps within a rolling 1,000 ms window and
44 logical pixels of the latest tap. Emitting clears the burst history. A dead
click means an eligible control's screen showed no meaningful change 500 ms
after the tap. Only the state at the deadline is compared; scroll, focus and
window-size changes cancel the check early. Thresholds are configurable through
`AutocaptureOptions`. Any new
accepted tap cancels the previous pending dead check, even a noninteractive tap.
Manual signal APIs remain independent of these detectors.

Metadata contains logical coordinates, canonical widget type/role, structural
ancestry, and either a developer-supplied `Semantics(identifier: 'checkout')` or
a structural fallback ID. Do not put personal data in identifiers. Labels,
editable values, passwords, widget keys, and arbitrary widget descriptions are
never used as event metadata. Noneditable display text is compared transiently
in memory to detect responses; neither that text nor its digest is transmitted,
logged, or persisted. Structural fallback IDs can change with layout changes.

Automatic dead detection is conservative: text entry and feedback controls are
ineligible. Visible platform views, textures, and app-owned CustomPaint surfaces
suppress automatic dead detection for the observed view because their responses
cannot be reliably inspected. Missing/over-budget snapshots also suppress it.
Material border/ripple feedback does not itself count as a meaningful response.
Use manual APIs for app-detected signals on unsupported surfaces. Custom render
objects and raw-pointer response handlers require further coverage validation;
this experimental observer is not a general pixel-difference detector.

Autocaptured events use the analytics opt-out handling: nothing is sent while
tracking is opted out. Navigation changes the screen and so cancels a pending
dead check; backgrounding and disposal also cancel it. Automatic capture currently does nothing on
Windows or Linux, and does not observe keyboard or assistive-technology activation.


Automatic pointer capture accepts primary touch/mouse taps lasting at most
500 ms (including exactly 500 ms). Stylus and inverted-stylus
input are not captured in this Beta. iPad trackpad clicks delivered by Flutter
as mouse/touch events follow the same rules.

Target lookup follows hit-test render ancestry. Response checks retain a bounded
view traversal; exceeding the node/depth budget suppresses affected signals and
emits one generic diagnostic per process. This protects app responsiveness but
means exceptionally complex visible views can lack automatic dead-click events.

Autocapture time windows accept `Duration` values from 1 millisecond to 1 minute,
including microsecond precision within that range. The rage threshold must be
2–100 and radius must be finite and 0–100000 logical pixels. Debug assertions
check threshold/radius at construction and durations when detectors consume them
(the configuration constructors remain `const`). In release builds, detectors
clamp out-of-range values and use radius 44 for nonfinite values.
