# SDK-30 autocapture context

Confirmed with Rahul on 2026-09-14. These decisions supersede conflicting
proposals in the older implementation plans. This is the implementation
contract, not a claim that automatic detection is complete.

## Current state

Branch: `rahulraveendran-sdk-30-mobile-sr-frustration-signals-flutter`.
Implemented: manual APIs, automatic observation/targeting, rage/dead detectors,
consent/lifecycle integration, example fixtures and tests. Experimental; device
and performance validation and custom-rendering hardening remain before release.

## Confirmed behavior

- Ship inside analytics; Flutter >=3.19.0 / Dart >=3.3.0. No new package or
  publishing workflow now. Keep boundaries suitable for extraction before launch
  as described in `docs/SDK30_PACKAGE_BOUNDARY.md`.
- Android and iOS first; shared Dart logic should allow later web/macOS work.
- Require one root MixpanelAutocaptureWidget, not wrappers on individual controls.
- Explicit opt-in. Click, rage and dead are independently configurable; all
  three default on once opted in. Disabling click emission must not disable
  the other detectors.
- Click/rage include non-interactive targets; dead detection requires an
  eligible interactive target.
- Resolve the nearest interactive parent when tapping its text/icon, even if
  that leaf has its own identifier. Do not walk past a nearer interactive target.
- Use a static explicit Semantics.identifier or structural fallback. No labels,
  visible text, input values or widget key values in automatic event metadata.
  Semantics.identifier is exposed to accessibility/test tooling but is not a
  spoken accessibility label. Developer-supplied IDs can still contain PII;
  document static values and do not claim arbitrary strings are sanitized.
- Defer the public exclusion wrapper. Keep internal eligibility extensible.
- Match Android rage behavior: four taps in the rolling 1000 ms window within
  44 logical pixels of the current tap; clear after emission.
- Dead timeout defaults to 500 ms and is configurable. A later response does
  not retract an event already emitted.
- A meaningful change anywhere in the owning view cancels its pending check.
  Non-editable displayed text changes count, including same-size replacements.
  Compare locally; never send, log or persist text or derived response hashes.
  Editable and secure input values remain excluded from comparison.
- Every newly accepted tap cancels the old pending check before eligibility
  evaluation. Only eligible new taps start a replacement.
- Text fields, switches, checkboxes, radio controls, sliders and pickers are
  excluded from dead detection; they remain eligible for click/rage events.

## Unobservable responses: unknown, never assumed dead

Skip automatic dead-click detection when response observation is unreliable.
Examples include WebViews, embedded native/platform views, textures and
custom-painted surfaces whose meaningful state is unavailable to the observer.
This includes a target that can trigger a response in such a surface: an
unchanged Flutter tree alone does not prove that the response was absent.

Keep response-observation capability separate from interactivity. An enabled
button can be interactive while its response is unobservable. Do not infer
capability from the presence of an identifier or tap handler.

Represent observation failure/unsupported coverage separately from a successfully
captured unchanged state. A missing baseline, a detached root, a failed snapshot,
or traversal-budget exhaustion must suppress automatic dead events. Never
compare two empty/fallback snapshots and conclude the tap was dead.

This suppression does not by itself suppress click/rage events when their
pointer and target metadata can be obtained safely. If the target/pointer
itself cannot be resolved safely, do not fabricate one.

Manual trackClick/trackRageClick/trackDeadClick remain available: the app must
supply accurate metadata and decide whether the named signal occurred. Manual
APIs do not start automatic detectors.

Acceptance coverage required during implementation:
- Unsupported native/WebView/custom-painted response emits no automatic dead
  event, including when no ordinary Flutter frame/state change occurs.
- Missing baseline, snapshot failure and traversal limits emit no dead event.
- A supported no-op button still emits after the deadline; capability failure
  must not be confused with the normal unchanged-state result.
- Click/rage remain independent where capture is reliable.
- Manual dead emission still sends exactly one event for an app-detected signal.

## Native source findings and parity process

Android DeadClickDetector uses layout/scroll listeners for pure XML plus
snapshots containing TextView text. Compose/mixed screens use snapshots without
those layout listeners to avoid ripple cancellation. It does not treat every
onDraw as meaningful response. Flutter must likewise distinguish a redraw/ripple
from meaningful state change.

For newly found Android/iOS parity issues: ask Rahul which behavior is intended,
then file the other platform's fix in Linear assigned to Rahul. Do not silently
choose a new parity contract.

Filed iOS fixes (both assigned to Rahul):
- SDK-166: reset rage history after emission to match Android.
- SDK-167: cancel pending dead check before eligibility to match Android.

## Implementation status (2026-09-14)

Implemented in the analytics package: optional AutocaptureOptions at init,
MixpanelAutocaptureWidget, built-in MixpanelAutocaptureNavigatorObserver, public
manual signal APIs, and separate resolver/response/rage/dead/controller modules.
No new production dependency or publishing workflow. Example opts in explicitly.
Automatic capture is platform-gated to Android/iOS; manual APIs are unchanged by
that gate. Future package extraction moves the observer/detectors behind the
controller's event sink and consent boundary.

Traversal is bounded to 2,000 Elements and depth 512 (MaterialApp's ordinary
internal tree already exceeds depth 128). It uses public release-available APIs,
not debugCreator, runtimeType strings, semantics labels, or widget keys.
Response snapshots are ephemeral and frame-driven only while a tap is pending;
no timer-driven rendering/polling loop. Material's internal border painters are
recognized by the public Material.child boundary; app child painters still
suppress dead events. No-op Material buttons must retain dead eligibility.

Release validation still needs real Android/iOS device runs, profile-mode cost
measurements on large trees, and app-specific custom rendering coverage. Widget
and release compilation checks cannot replace those checks. Custom render
objects/raw pointer handlers are not fully covered by this experimental observer.


## Validation

Flutter 3.19.0: 189 analytics tests passed (144 existing + 45 signal tests).
Flutter 3.44.6: full suite passed before final ownership additions; all 45 signal
tests passed after those changes. Flutter 3.19 release web import/build probe
compiled successfully; this checks package build compatibility, not web capture.
Focused static analysis covers lib and signal tests. Existing example-wide lint
suggestions are outside this change. No production dependency was added.


## Beta release designation

Release the frustration signals feature as **Beta**. Public API Dartdocs and
README notices mirror native/RN: autocapture may contain issues, its API and
captured properties may change before general availability, and customers
building reports on autocaptured events should pin their SDK version. Keep this
notice on options, event metadata, root/navigation widgets, the autocapture
accessor/class and manual signal methods. This designation does not remove the
recorded validation requirements or change package versioning by itself.
