import 'web_page_lifecycle_stub.dart'
    if (dart.library.js_interop) 'web_page_lifecycle_web.dart'
    as impl;

void Function()? registerWebPageLifecycle({
  required void Function() onHidden,
  required void Function() onVisible,
}) => impl.registerWebPageLifecycle(onHidden: onHidden, onVisible: onVisible);
