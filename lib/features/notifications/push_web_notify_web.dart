import 'dart:js_interop';

@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  external factory _Notification(String title, [_NotificationOptions? options]);
  external static String get permission;
}

@JS()
@anonymous
extension type _NotificationOptions._(JSObject _) implements JSObject {
  external factory _NotificationOptions({String? body, String? icon});
}

void showWebNotification({required String title, required String body}) {
  try {
    if (_Notification.permission != 'granted') return;
    _Notification(
      title,
      _NotificationOptions(
        body: body,
        icon: '/kampusteyim_icon.png',
      ),
    );
  } catch (_) {}
}
