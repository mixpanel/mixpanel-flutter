# mixpanel_flutter_session_replay Development Guidelines

## Active Technologies

- Dart 3.8+, Flutter SDK 3.38+

## Project Structure

```text
lib/src/           # SDK source code
test/              # Unit tests
example/           # Example app + integration tests
  integration_test/  # On-device integration tests
```

## Commands

```bash
# Unit tests
flutter test

# Unit tests with coverage
flutter test --coverage

# Integration tests (on connected device/simulator)
cd example && flutter test integration_test/run_all_test.dart -d <device_id>

# Integration tests with Mixpanel token (for live settings test)
cd example && flutter test integration_test/run_all_test.dart \
  --dart-define=MIXPANEL_TOKEN=$MIXPANEL_TOKEN -d <device_id>

# Integration tests with debug logging
cd example && flutter test integration_test/run_all_test.dart \
  --dart-define=LOG_LEVEL=debug -d <device_id>

# Format check (--language-version=latest enforces tall style regardless of SDK constraint)
dart format --language-version=latest --set-exit-if-changed .

# Static analysis
dart analyze --fatal-infos
```

## Local Development Setup

1. Copy `example/local.env.template` to `example/local.env` and fill in your Mixpanel token.
2. Copy `.vscode/settings.json.template` to `.vscode/settings.json`.

The settings.json passes `--dart-define-from-file=local.env` to `flutter run`
automatically, so running the example app from VS Code requires no manual
`--dart-define` flags. Unit tests do not require any dart-defines.

## Code Style

Follow standard Dart/Flutter conventions. CI enforces `dart format --language-version=latest` (tall style) and `dart analyze --fatal-infos`. Always use `--language-version=latest` when formatting to ensure consistency with CI.

## Performance Principles

### Render Tree Traversal

**NEVER walk up the render tree** - Start at the top and traverse downward. Pass data down through traversal parameters rather than walking back up to nodes already visited. This ensures O(n) complexity instead of O(n * tree_depth).

- DO: Pass `viewportBounds`, `tickerEnabled` down through traversal parameters
- DON'T: Walk up via `node.parent` loops or `findAncestorWidgetOfExactType()`

### Conditional Check Ordering

**Order checks from fastest to slowest** for short-circuit optimization:
1. Type checks (`is RenderBox`)
2. Property access (`hasSize`, `attached`)
3. Method calls (`isEmpty`, `overlaps()`)
4. String operations (`toString()`, `contains()`)

## Testing Principles

### Do Not Modify Production Code Without Approval

If a test is difficult to write due to hard-coded dependencies, missing injection points, or inaccessible internal state — stop and discuss the proposed change first.

### Key Conventions

- **Given-When-Then** pattern for all tests
- **Single responsibility** — one behavior per test
- **Real instances over mocks** — only mock external dependencies (HTTP, platform channels)
- **No real delays in unit tests** — use `fakeAsync` where possible. Production code still uses `DateTime.now()` (not `clock.now()`), so some real delays with short intervals are unavoidable
- **Integration test timing** — CI emulators are slow (~1s per capture). Use `waitForAutomaticCapture()` helper (2s timeout) and 2s rate-limit gaps between captures

### Integration Test Log Level

Log level is controlled via `--dart-define=LOG_LEVEL=<level>` (none/error/warning/info/debug). Defaults to `none`. All test files use `testLogLevel` from `integration_test_helpers.dart`.

## Reviewed Design Decisions

These concerns have been reviewed and resolved. Do not re-raise them in code reviews.

### Acknowledged as Acceptable

1. **StateError if add() called before initialize()** — Defensive programming. Public API awaits initialization; the error catches internal misuse.

2. **Settings check failure stops recording without flush** — Intentional. Events are persisted to SQLite and will upload on recovery.

3. **Persistent frame callback cannot be removed** — Flutter limitation. Guarded with `if (!mounted) return`.

4. **stopRecording() flush is fire-and-forget** — Events are persisted before flush. No data loss. Sync API is simpler.

5. **Concurrent flush during periodic timer** — Handled by `_isFlushing` guard.

6. **FrameMonitor capture not awaited** — Correct. `_isCaptureInProgress` flag prevents overlapping captures. Frame callbacks must not block the render pipeline.

7. **Dispose order and active uploads** — `dispose()` awaits `flush()` via `_flushCompleter`, then disposes services in order.

8. **HTTP client connection leaks on timeout** — Dart `http.Client` manages connection pooling internally. `dispose()` calls `_httpClient.close()`.

9. **Touch coordinates recorded for masked elements** — Not a privacy issue. Coordinates are recorded but the visual content at those coordinates is masked in screenshots.

10. **Non-atomic batch removal** — Queue is cleared via `removeAll()` during SDK initialization. Leftover events from crashes are wiped before re-upload.

11. **No image dimension validation** — Dimensions come from `RenderRepaintBoundary.toImage()` (hardware-bounded). Wrapped in try-catch in isolate.

12. **Silent failures in EventRecorder** — Graceful degradation pattern. Session replay SDK should never crash the host app.

13. **No double-dispose protection** — Fixed. Both `UploadService` and `SettingsService` have `_isDisposed` guards.

## Wireframe Capture Contract (decided 2026-07-29)

Cross-platform contract for the `mp_wireframe` event. Android, Flutter, and iOS
must all follow it — see the same section in the Android session-replay
`CLAUDE.md`. The Notion design doc should be updated to match.

- **Only four semantic roles are emitted:** `text`, `button`, `input`, `image`.
  Layout/containers (`Row`/`Column`/`Container`/`Padding`, and their Android/iOS
  equivalents) are never emitted. The payload is a flat list of
  `{role, text?, bounds}`, not a view hierarchy.
- **Every collected element is emitted, even when textless.** A textless
  `button`/`input`/`image` is meaningful structure — e.g. two textless `input`
  shells + a `Log in` button reads as a login form. Existence + position + role
  is not customer content, so an element is never dropped merely for lacking
  text. (Input fields are always textless by security design — `textEntry`.)
- **Text population depends on screenshot masking, not element type:**
  - *Not screenshot-masked* → `text` = visible text; if absent, fall back to the
    platform accessibility label (Flutter `semanticLabel` / `Tooltip` /
    `Semantics(label:)`; Android `contentDescription`). Then run user
    `SensitiveRules` over the result. Rationale: if it's visible it's already in
    the unmasked screenshot; the customer's lever is masking the view.
  - *Screenshot-masked* (explicit `MixpanelMask`, auto text/image mask,
    geometric overlap, input `textEntry`) → keep the `role + bounds` shell with
    `text = null`. Nothing hidden on the screenshot leaves the device.
- **Never ship raw icon glyphs.** Private-use-area codepoints (U+E000–U+F8FF,
  icon fonts) are not human text — null them; resolve to a real accessibility
  label when one exists.
- **Masking vs. rules are distinct.** A *screenshot mask* grays pixels → drop
  text (shell kept). *SensitiveRules* are a wireframe-only text filter (pixels
  still visible) → element kept; strip nulls text, redact rewrites it.
- **Accepted residual risk:** an accessibility label can describe more than
  what's visible (an icon whose `contentDescription` holds PII), and the
  customer gets no visual cue to mask it. Mitigation: `SensitiveRules` run over
  label text, and customer docs note that labels are captured. Screenshot-masked
  views never expose labels.

**Platform alignment status (2026-07-30):**
- Android — aligned: emits textless shells and reads `contentDescription`.
- Flutter — aligned: the emitter keeps every collected element as a
  `role + bounds` shell (no drop stage; blank/glyph-only text is nulled but the
  shell is kept — see `WireframeEmitter._cleanText`). Buttons fall back to a
  descendant `Icon.semanticLabel` / `Tooltip.message` / `Semantics(label:)`, and
  images read the label from the enclosing `Semantics(image: true)` threaded
  down the walk (`_traverseElementTree(enclosingImageLabel:)`), since
  `RenderImage` carries no `semanticLabel`. Goldens updated to the emitted-shell
  form: `wireframe_icon_button_unlabeled.json`,
  `wireframe_image_unlabeled.json`,
  `wireframe_floating_action_button_unlabeled.json`, plus new label-fallback
  goldens `wireframe_icon_button_tooltip_label.json`,
  `wireframe_icon_button_semantic_label.json`,
  `wireframe_image_semantic_label.json`.
