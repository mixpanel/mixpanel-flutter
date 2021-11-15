@JS('mixpanel')
library mpjs;

import 'package:js/js.dart';

@JS('init')
external void init(String token);

@JS('track')
external void track(String name);
