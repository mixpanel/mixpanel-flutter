# Sample Flutter Application for Mixpanel Integration

This folder contains a sample application demonstrating how you can use Mixpanel in your Flutter apps.

## Setup

- You need to set up the Flutter development environment
https://flutter.dev/docs/get-started/install
- In the root folder of the sample application, run from the command line `$ flutter pub get`
- To run the application, in the root folder of the sample application, run from the command line `$ flutter run` or in Android Studio, open `example/lib/main.dart` and run.

## Use your Mixpanel Token

Replace `Your Mixpanel Token` value in `analytics.dart` that you'll need to update before you can send data to Mixpanel.

### For Your Mixpanel Token
- Log in to your account at https://www.mixpanel.com
- Select the project you'll be working with
- Click the gear link at the top right to show the project settings dialog
- Copy the "Token" string from the dialog

Change the value of "token" in app.json to the value you copied from the web page.

## Getting More Information
The Mixpanel Flutter integration API documentation is available on the Mixpanel website.
https://developer.mixpanel.com/docs/flutter