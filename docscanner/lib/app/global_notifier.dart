import 'dart:async';

import 'app_globals.dart' show NotifierEvent;

final GlobalNotifier globalNotifier = GlobalNotifier();

class GlobalNotifier {
  final _controller = StreamController<NotifierEvent>.broadcast();

  Stream<NotifierEvent> get stream => _controller.stream;

  void triggerEvent(NotifierEvent event) {
    _controller.add(event);
  }

  void dispose() {
    _controller.close();
  }
}
