/// Metadata for a manually tracked click, rage click, or dead click.
///
/// Use a static, developer-assigned [elementId], such as `checkout_button`.
/// Never use visible text, accessibility labels, input values, or personal data
/// as identifiers. This class does not sanitize developer-supplied strings.
///
/// Metadata does not establish that a target's UI response can be observed.
/// Automatic dead-click detection must separately verify response coverage and
/// skip unsupported/failed observations; an unchanged or empty Flutter snapshot
/// is not evidence that an embedded native or custom-painted surface was idle.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class ClickEvent {
  const ClickEvent({
    required this.x,
    required this.y,
    required this.elementId,
    this.tagName,
    this.role,
    this.elements,
  });

  /// Horizontal position in the owning Flutter view's logical pixels.
  final double x;

  /// Vertical position in the owning Flutter view's logical pixels.
  final double y;

  /// Static identifier for the target, without user data.
  final String elementId;

  /// Widget type, for example `ElevatedButton`, without instance details.
  final String? tagName;

  /// Semantic role, for example `Button` or `Link`.
  final String? role;

  /// Type-only hierarchy, for example `ElevatedButton > Column`.
  final String? elements;
}
