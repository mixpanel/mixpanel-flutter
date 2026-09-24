# SDK-30 packaging decision

## Current decision (2026-09-24)

Autocapture is built into analytics. Extractability into an optional package is no
longer a requirement. Mixpanel owns a private controller field; the root widget and
navigator observer share library-private access through a narrow Dart `part` file.
The Expando binding registry has been removed. Detector components remain separate
internal libraries for clarity and testability, and the controller keeps an injected
event sink. Public integration and Flutter/Dart minimums remain unchanged.

The original scoping notes below are historical and superseded where they require
future package extraction or prohibit `part` integration. Extraction would now be
a deliberate future redesign, not a supported boundary promised by this implementation.

## Historical scoping notes

2026-09-14: Ship the feature inside `mixpanel_flutter` with Flutter >=3.19.0
and Dart >=3.3.0. Do not create a package or publishing configuration now.
Initial automatic platform scope is Android/iOS. Rage detection follows
Android: reset after a qualifying burst. Related iOS parity work: SDK-166.

## Extraction before launch is feasible

Only the ClickEvent value object and manual emitters have been implemented.
There is no automatic detector dependency to untangle yet. Keep the automatic
feature behind these boundaries during implementation:

- Put Flutter widgets, target resolution, snapshots, and detectors in
  `lib/src/autocapture/` as ordinary libraries, not `part` files coupled to
  analytics library-private state.
- Give the detector core an event-sink callback, injected clock, and explicit
  start/stop/reset operations. Keep MethodChannel, codec, token storage, event
  queueing and native SDK access in an analytics adapter.
- Keep automatic options and root-wrapper ownership out of native channel
  configuration. A thin `Mixpanel.init` convenience adapter can configure the
  feature without making the detector depend on Mixpanel internals.
- Make consent and identity changes an explicit adapter input. Stop observation
  synchronously on opt-out; invalidate pending events on reset/identify/reinit.
  Persisted opt-out must be resolved before collection starts.
- Keep snapshots and user-content digests private to the feature. Event output
  must be an allowlisted value payload; no RenderObject/Element references or
  response digests cross the event sink.
- Keep detector tests independent of the platform channel. Test the analytics
  adapter separately for metadata, lifecycle and delivery behavior.

The existing common EventBridge carries tracked analytics events; it is not a
consent/identity lifecycle stream. It cannot be reused as proof that collection
is permitted. `hasOptedOutTracking()` alone is also insufficient to notify a
separate package synchronously about later opt-out/reset calls. If extracted,
retain a small analytics-side lifecycle hook (or introduce an explicitly
specified shared contract) and test it. Do not implement polling as a substitute.

## Extraction steps if the team chooses it before release

1. Move automatic widgets, options, target resolver, detectors, snapshots and
   their tests into an optional package. Preserve the event schema and behavior.
2. Supply an adapter using analytics' public track API plus the explicitly
   supported lifecycle hook. Dependency direction: optional feature -> analytics;
   analytics must not depend back on the optional package.
3. Keep low-level manual ClickEvent emission in analytics if useful. The current
   value object requires no modern Flutter APIs. Automatic detection need not
   own the existing screen-view Autocapture facade.
4. Remove automatic imports/exports and convenience-init types from analytics;
   update the new feature's installation/import/init examples. An analytics
   re-export of the optional package would make that dependency mandatory and
   defeat the compatibility purpose.
5. If the purpose is preserving older analytics compatibility, undo the minimum
   bump only after removing all newer-API references and validating the intended
   older toolchains. Moving files alone does not lower package constraints.
6. Register the package in `.github/modules.json`, add a release tag trigger,
   configure pub.dev trusted publishing and applicable repository protections,
   and add package CI/dry-run validation. Reuse the current shared release
   workflow; a completely new workflow YAML is not intrinsically required.

Doing this before publishing avoids a migration for external users. It still
requires adapter work, dependency/public-API adjustments, examples and release
setup; it is not a promise that extraction will be only a file move. No detector
algorithm rewrite should be necessary if the boundaries above are maintained.

## Source inspection

- `.github/modules.json` and `.github/workflows/release-pub-dev.yml`: shared
  tag-driven analytics/common/replay publishing with per-package metadata.
- `packages/mixpanel_flutter/lib/mixpanel_flutter.dart`: private static channel,
  public track API, init/consent/reset/identify methods, manual Autocapture facade.
- `packages/mixpanel_flutter/lib/src/autocapture/click_event.dart`: standalone
  immutable event model.
- `packages/mixpanel_flutter_common/lib/src/event_bridge.dart`: asynchronous
  tracked-event stream, not a consent lifecycle contract.

## Confirmed interview decisions

- One root `MixpanelAutocaptureWidget` is acceptable; individual controls need
  no wrapper.
- Metadata uses explicit developer-set Semantics.identifier or structural ID;
  no accessibility labels, visible text, input values or widget keys as metadata.
  Identifiers are machine-readable accessibility/test IDs, not spoken labels.
- Defer the public exclusion wrapper until the team needs it. Keep the internal
  eligibility boundary extensible; do not add a public exclusion API now.
- Non-editable displayed text may be compared locally to detect UI responses.
  Neither that text nor its derived response hash may be sent, logged or
  persisted; editable/secure values remain excluded.
- Android verification: DeadClickDetector attaches OnGlobalLayoutListener and
  OnScrollChangedListener only for pure XML, not OnDrawListener. XML structural
  and mixed-mode content snapshots include TextView text. Compose snapshots
  include text and semantic structure; listener suppression avoids ripple-driven
  cancellation. Flutter must detect label changes without treating every
  redraw as a meaningful response.

### Further confirmed dead-click behavior

- A meaningful UI change anywhere in the owning view cancels the pending check.
- Keep the configurable 500 ms default deadline; later responses do not retract
  emitted events.
- Match Android: any newly accepted tap cancels the previous check before
  testing eligibility. Only an eligible tap starts a replacement check.
- For future Android/iOS parity findings, ask Rahul which behavior is intended,
  then create a Linear ticket assigned to him for the platform to change.

## Authoritative behavior context

See `context/AUTOCAPTURE.md` for the consolidated interview decisions and
unknown-response suppression contract. In particular, unsupported observation
must skip automatic dead detection, with manual APIs available for app-detected
signals. No public exclusion wrapper is in scope for the first release.


## Implemented module boundary

`lib/src/autocapture/` contains options, event model, target resolver, response
snapshots, rage/dead detectors, controller, and root/navigation widgets. Only the
root/navigation adapter imports Mixpanel. The controller accepts an event sink
and consent reader. Extraction can move the remaining modules without moving
analytics transport or adding a second native plugin. Existing public exports
can remain as compatibility shims if extracted before release.
