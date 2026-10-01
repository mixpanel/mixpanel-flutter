# Example App

A demo app for the Mixpanel Flutter Session Replay SDK.

## Setup

### 1. Set the Mixpanel token

The example app reads your Mixpanel project token via `--dart-define-from-file` at compile time.

1. Copy the env template:
   ```bash
   cp local.env.template local.env
   ```

2. Edit `local.env` and replace `your_mixpanel_token_here` with your Mixpanel project token.

> `local.env` is gitignored and will not be committed.

### 2. Running on a real iOS device

To run on a physical iOS device, you also need to configure code signing:

1. Copy the xcconfig template:
   ```bash
   cp ios/LocalDevelopment.xcconfig.template ios/LocalDevelopment.xcconfig
   ```

2. Edit `ios/LocalDevelopment.xcconfig` and replace `YOUR_TEAM_ID_HERE` with your Apple Development Team ID.

   To find your Team ID: open Xcode > Settings > Accounts, select your team, and look for the Team ID.

> `LocalDevelopment.xcconfig` is gitignored and will not be committed.

### Running the app

**From VS Code:** Select the "example" launch configuration and press F5. The token is picked up automatically via `--dart-define-from-file=local.env` in the repo's `.vscode/launch.json`. Changes to `local.env` need a full restart, not a hot reload.

**From the command line** (run from this `example/` directory):
```bash
flutter run --dart-define-from-file=local.env
```

### Web validation

The browser validation suite runs capture, masking, route-replacement, storage,
and upload correctness checks by default. CI uses this mode.

Heavy raster stress, the animation performance control, and capture benchmarks
are opt-in for controlled local runs. Add
`--dart-define=RUN_WEB_STRESS_TESTS=true` when running
`integration_test/web_validation_test.dart` with the web validation driver.
Performance budgets remain enforced by default in those opt-in runs.
