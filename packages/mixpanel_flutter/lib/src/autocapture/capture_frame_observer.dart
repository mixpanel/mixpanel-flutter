import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';

/// One dispatcher for the binding lifetime, with removable widget listeners.
/// It never retains disposed widget callbacks and never schedules new frames.
class CaptureFrameObserver {
  static final Map<void Function(), bool Function()> _listeners = {};
  static SchedulerBinding? _binding;
  // Weak keys avoid retaining replaced test bindings. A -> B -> A must not
  // install a second persistent callback on A.
  static final Expando<bool> _installed =
      Expando<bool>('capture frame observer');
  static void add(void Function() callback, bool Function() isObserving) {
    _listeners[callback] = isObserving;
    installForBinding(SchedulerBinding.instance);
  }

  @visibleForTesting
  static void installForBinding(SchedulerBinding binding) {
    _binding = binding;
    if (_installed[binding] == true) return;
    _installed[binding] = true;
    binding.addPersistentFrameCallback((_) {
      if (!identical(_binding, binding) ||
          !_listeners.values.any((isObserving) => isObserving())) {
        return;
      }
      binding.addPostFrameCallback((_) {
        if (!identical(_binding, binding)) return;
        // A copy permits listeners to detach during delivery. No copy or
        // post-frame callback is allocated when every listener is idle.
        for (final listener in List<void Function()>.of(_listeners.keys)) {
          if (_listeners[listener]?.call() ?? false) listener();
        }
      });
    });
  }

  static void remove(void Function() callback) => _listeners.remove(callback);
}
