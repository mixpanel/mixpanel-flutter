import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function() registerWebPageLifecycle({
  required void Function() onHidden,
  required void Function() onVisible,
}) {
  final visibilityListener = ((web.Event _) {
    if (web.document.visibilityState == 'hidden') {
      onHidden();
    } else if (web.document.visibilityState == 'visible') {
      onVisible();
    }
  }).toJS;
  final pageHideListener = ((web.Event _) => onHidden()).toJS;
  final pageShowListener = ((web.Event _) => onVisible()).toJS;
  web.document.addEventListener('visibilitychange', visibilityListener);
  web.window.addEventListener('pagehide', pageHideListener);
  web.window.addEventListener('pageshow', pageShowListener);

  return () {
    web.document.removeEventListener('visibilitychange', visibilityListener);
    web.window.removeEventListener('pagehide', pageHideListener);
    web.window.removeEventListener('pageshow', pageShowListener);
  };
}
