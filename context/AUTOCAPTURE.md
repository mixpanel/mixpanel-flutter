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


## Review hardening — 2026-09-16

Consent refresh epochs are separate from detection generations: navigation must
not strand a suspended controller; newer consent actions/close still win. The
instance controller is accessed only through the non-exported internal adapter. Lifecycle methods intentionally
use the shared active controller because native method channels share one SDK.
Generic consent-failure diagnostics contain no payload/error details.

Target resolution hit-tests first and prunes using actual render ancestry (not
approximate widget rectangles). Only hit targets enter the ownership map.
Response snapshots cache parent paint transforms, excluding the root's physical
pixel transform to preserve logical coordinates. The same frame snapshot serves
an old pending dead candidate and an overlapping new press. No idle observer
post-frame work, and binding identity is checked. Do not throttle away single-frame
responses or shorten structural IDs without addressing collisions.

Traversal limits remain fail-closed with one generic process-wide diagnostic;
raising the budget is not a performance fix. Device/profile-mode measurements
remain a release prerequisite. Radio state comes from effective checked semantics
without reading labels/text, compatible with both legacy controls and RadioGroup.
Tap duration is inclusive at 500 ms to match Android. Stylus remains unsupported.

Validation after review hardening: all 208 analytics tests pass on both Flutter
3.19.0 and installed Flutter 3.44.6 (19 additional regressions). Focused static
analysis and formatting checks are clean. Regressions cover consent/native-call
navigation races for identify/reset/opt-in, newer opt-out/close precedence, shared
handle opt-out, exact 500 ms taps, large unrelated trees, transform coordinates,
snapshot overflow, overlapping transient responses, radio feedback and idle
frame observers. These widget tests do not establish physical-device tap latency.

## Overlay review follow-up — 2026-09-16

Element ancestry and render ancestry diverge for OverlayPortal. Target lookup
keeps its pruned fast path but requires ownership of the deepest render hit. If
missing, a separately bounded unpruned pass retries; unresolved/over-budget hits
are skipped, never attributed to a root listener or other higher wrapper.

Snapshot traversal must not discard Element descendants just because their
host RenderBox is empty/offscreen: a portal can render those descendants in an
overlay elsewhere. Individual meaningful widgets are still checked against the
viewport using actual render transforms. This can visit more mounted elements;
the existing traversal budget and conservative suppression remain in force.
Unsupported surfaces with unknown visibility conservatively suppress dead
detection; proven offscreen surfaces do not. Profile device workloads before Beta.

Radio checked-state lookup stops at the first answer; missing state suppresses
the entire view's dead-click check. Frame callback installation uses weak binding
keys to avoid duplicate installation on A -> B -> A without retaining old
bindings. Transform caching and full structural ID ancestry are preserved.

Validation: 213 tests pass on Flutter 3.19.0 and 3.44.6; focused analysis and
format checks pass. Five additional tests cover portal attribution/unique IDs,
portal response observation, menu attribution, bounded fallback failure, and
binding flip-flop dispatch.


## Surface visibility follow-up — 2026-09-16

Unsupported-surface suppression now checks the surface's actual viewport bounds,
including findRenderObject for stateful/stateless platform-view widgets. Finite,
nonempty bounds entirely outside the viewport do not veto dead clicks. Missing,
empty or invalid geometry remains unknown and suppresses detection. Descendant
traversal continues so a sized offscreen portal host cannot hide visible overlay
content. Matrix caching and the bounded traversal policy are unchanged.

Validation: all 220 tests pass on Flutter 3.19.0 and 3.44.6; focused static
analysis, formatting and diff whitespace checks pass. Seven new regressions cover
offscreen painters, visible/offscreen textures, portal surfaces/responses under
sized offscreen hosts, and visible/offscreen StatefulElement platform surfaces.
The platform-view fixture supplies geometry without native channels; real-device
platform rendering/performance remains a separate release validation task.


## Greptile review follow-up

identify/reset always attempt epoch-guarded consent refresh after the native
operation, including when that operation throws. The original native exception
still reaches the caller; a failed/unknown/denied consent read keeps capture
suspended. Pending pre-operation detections remain discarded. Newer opt-out,
reset or reinitialization cannot be overridden by stale failure recovery.

The public autocaptureController getter has been removed. AutocaptureBinding,
an unexported src adapter with weak instance keys, connects initialization to
root/navigation widgets without exposing the controller on Mixpanel's API.
The existing public mixpanel.autocapture API is unchanged.

Validation: 236 tests pass on Flutter 3.19.0 and 3.44.6, including 16 new
lifecycle-failure tests. Coverage includes original-error preservation, all
consent outcomes, pending detection cancellation, opt-out during native/recovery
work, newer reset and reinitialization. Focused analysis and format checks pass.


## Configuration shape — 2026-09-17

AutocaptureOptions now contains clickOptions: ClickOptions,
rageClickOptions: RageClickOptions, and deadClickOptions: DeadClickOptions.
Each nested options class has enabled (default true). Rage settings are
clickThreshold, timeWindowMs, radius; dead settings are timeWindowMs. Defaults,
normalization bounds, opt-in and independent detection behavior are unchanged.
This intentionally replaces the unreleased flat API before Beta.

Verified native Android/Swift and RN source: all use per-signal options; RN
additionally allows boolean-or-object shorthand and short top-level names.
Flutter follows native member names with Dart const named constructors and
strongly typed option values, not Object/dynamic unions. Public options retain
the Beta notice. The rage detector depends only on RageClickOptions.

Nested-options validation: all 239 tests pass on Flutter 3.19.0 and 3.44.6.
Added default/boundary coverage and end-to-end custom rage/dead configuration
checks with basic click emission disabled. All eight enable combinations retain
coverage through the nested API. Focused analysis and formatting pass.


## Non-architectural review updates (2026-09-23)

Public rage/dead options now expose final `Duration timeWindow` fields instead
of integer `timeWindowMs` getters. Defaults remain 1 second / 500 milliseconds;
comparisons and timers preserve microsecond precision within the existing
1 millisecond–1 minute limits. Threshold/radius have constructor assertions.
Duration assertions run when consumed because Dart cannot evaluate Duration
comparisons in const constructor assertions. Internal normalization preserves
release-mode bounds and the nonfinite-radius fallback. No widget decomposition
is included. Example ordering follows init; feature changelog additions removed.

Dedicated resolver, snapshot and dead-detector tests exercise privacy/ownership,
portal fallback and budgets, transforms, unsupported surfaces, editable exclusion,
Radio state, unknown/changed suppression, candidate replacement and scheduled-frame
cancellation. These fixtures do not initialize Mixpanel or mock analytics channels.

Validation: all 269 analytics tests pass on Flutter 3.19.0 and 3.44.6;
focused analysis of lib and test/autocapture reports no issues on both.


## Explicit state and cancellable operations

Replaced controller consent booleans/counters with CaptureStatus, ConsentRequest
and CaptureSession. Navigation cancels detection sessions without cancelling consent
reads; newer lifecycle operations and close cancel stale consent requests. Closed
status is terminal. Requests are consumed once and cross-controller operations are
rejected. `_PendingTap` groups press state; `_PendingDeadClick` groups the baseline,
event, timer and callbacks. Candidate identity protects deferred-frame completion.
The pending candidate owns weak-target/session validity and delivery callbacks;
view snapshots no longer read the detector's state. Invalidating an old candidate's
target does not automatically invalidate a new press's independent baseline.
The broader recognizer/response-tracker extraction remains separate work.


## Focused component extraction (2026-09-24)

DeadClickDetector.start atomically replaces a fully configured candidate. Its one
required callback is candidate-owned. PointerTapTracker owns passive pointer rules;
UiResponseTracker owns press response comparison and idempotent response subscription
start/stop. ResponseChange distinguishes unchanged, changed and unknown; observations
retain transient responses. Frame snapshots remain shared between press and candidate.
CaptureFrameObserver is a separate module. Shared widget classification and traversal
policy no longer live in TargetResolver. Resolver uses named attribution stages;
a per-capture snapshot builder owns geometry/digest/budget and named coverage/content
methods. Traversal behavior and privacy boundaries are preserved.
DetectionSession replaces the ambiguous CaptureSession name. Consent requests use
identity without a redundant cancelled flag; suspend creates no request, whereas
beginConsentOperation returns a guarded lifecycle request. Rage detector settings
are normalized once. No public API changes or new dependencies.
Validation: all 303 tests pass on Flutter 3.19.0 and 3.44.6 in separate clean package
copies. New focused tests cover pointer boundaries, response outcomes, shared sampling,
subscription cleanup and classification. Existing lifecycle/privacy/portal regressions
remain in the full suite.
