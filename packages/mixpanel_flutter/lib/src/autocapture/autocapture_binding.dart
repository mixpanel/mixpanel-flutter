import 'autocapture_controller.dart';

/// Package-internal bridge between analytics instances and capture widgets.
/// Not exported by the SDK. Weak keys avoid retaining discarded instances.
class AutocaptureBinding {
  static final Expando<AutocaptureController> _controllers =
      Expando<AutocaptureController>('Mixpanel autocapture');

  static void attach(Object instance, AutocaptureController controller) {
    _controllers[instance] = controller;
  }

  static AutocaptureController? getController(Object? instance) =>
      instance == null ? null : _controllers[instance];
}
