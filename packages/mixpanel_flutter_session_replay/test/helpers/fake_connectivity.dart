import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Fake Connectivity for testing
///
/// Returns configurable connectivity results without requiring
/// platform channels.
class FakeConnectivity implements Connectivity {
  List<ConnectivityResult> result;

  FakeConnectivity(this.result);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => result;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      Stream.value(result);
}
