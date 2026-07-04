import 'dart:async';

/// Emits at most one event per [window], always delivering the *latest*
/// pending event at the end of the window. Used to coalesce Matrix sync
/// bursts into a steady, cheap rebuild cadence (instant first event, then
/// rate-limited) — streams in, streams out, no polling anywhere.
Stream<T> throttleLatest<T>(Stream<T> source, Duration window) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;
  T? pending;
  bool hasPending = false;

  void flush() {
    timer = null;
    if (hasPending) {
      final v = pending as T;
      hasPending = false;
      pending = null;
      controller.add(v);
      timer = Timer(window, flush);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      sub = source.listen((event) {
        if (timer == null) {
          controller.add(event);
          timer = Timer(window, flush);
        } else {
          pending = event;
          hasPending = true;
        }
      }, onError: (Object e, StackTrace s) => controller.addError(e, s),
         onDone: () => controller.close());
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return controller.stream;
}

/// Simple trailing-edge debouncer for search fields etc.
class Debouncer {
  final Duration delay;
  Timer? _timer;
  Debouncer(this.delay);

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}
