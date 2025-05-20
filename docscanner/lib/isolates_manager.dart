import 'dart:async';
import 'package:collection/collection.dart' show HeapPriorityQueue;
import 'dart:developer' as dev show log;
import 'dart:isolate';
import 'dart:io';

class TaskKiller {
  final void Function() _kill;
  final void Function() _delay;
  TaskKiller(this._kill, this._delay);
  void kill() => _kill();
  void delay() => _delay();
}

enum IsolatePriority { late, regular, quick, immediate }

extension on IsolatePriority {
  int get level {
    switch (this) {
      case IsolatePriority.immediate:
        return 4;
      case IsolatePriority.quick:
        return 3;
      case IsolatePriority.regular:
        return 2;
      case IsolatePriority.late:
        return 1;
    }
  }
}

class IsolatesManager {
  static final IsolatesManager _instance = IsolatesManager._internal();
  factory IsolatesManager() => _instance;

  late Future _initFuture;
  IsolatesManager._internal() {
    _initFuture = _init();
  }

  int getIsolatesCount() {
    int busyCount = 0;
    for (var worker in _workers) {
      if (worker.isBusy) busyCount++;
    }
    return busyCount;
  }

  final int maxIsolates = (Platform.numberOfProcessors - 2).clamp(
    3,
    Platform.numberOfProcessors - 2,
  );
  final int baseNOfIsolates = (Platform.numberOfProcessors ~/ 2).clamp(
    2,
    Platform.numberOfProcessors - 2,
  );
  final List<_Worker> _workers = [];
  final HeapPriorityQueue<_QueuedTask<dynamic>> _taskQueue =
      HeapPriorityQueue<_QueuedTask<dynamic>>();

  Future<void> _init() async {
    for (int i = 0; i < baseNOfIsolates; i++) {
      _workers.add(_Worker());
    }
    _startPinger();
  }

  _startPinger() async {
    Timer? pingCheckTimer;
    final pingPort = ReceivePort();
    var lastPing = DateTime.now();

    Isolate pinger = await Isolate.spawn(_isolatePinger, pingPort.sendPort);

    // receive ping
    pingPort.listen((message) {
      lastPing = DateTime.now();
    });
    // check if ping is outdated
    Future.delayed(Duration(seconds: 5), () {
      var lastCheckedTime = DateTime.now();
      pingCheckTimer = Timer.periodic(Duration(seconds: 1), (_) {
        final now = DateTime.now();
        final pingDelay = now.difference(lastPing);
        final freezeDuration = now.difference(lastCheckedTime);
        final toleratedDelay = Duration(seconds: 4);
        if (pingDelay > (toleratedDelay + freezeDuration)) {
          pinger.kill();
          pingCheckTimer?.cancel();
          pingPort.close();
          //todo cleanup all isolates and trigger _onBadExit
          for (var task in _taskQueue.toList()) {
            Future.delayed(Duration(seconds: 1), () {
              task.onBadExit(
                null,
                Exception(
                  "Isolate missed ping. Likely killed by System, restarting all isolates.",
                ),
              );
              _taskQueue.remove(task);
            });
          }
          for (var worker in _workers) {
            Future.delayed(Duration(seconds: 1), () {
              worker.isolate?.kill(priority: Isolate.immediate);
              worker.task?.onBadExit(
                null,
                Exception(
                  "Isolate missed ping. Likely killed by System, restarting all isolates.",
                ),
              );
              worker.reset();
            });
          }
          _startPinger();
        }
        lastCheckedTime = now;
      });
    });
  }

  static _isolatePinger<T>(SendPort sendPing) async {
    Timer.periodic(Duration(seconds: 1), (timer) {
      sendPing.send(true);
    });
  }

  Future<TaskKiller> runTask<T>(
    void Function(T) entryPoint,
    T message, {
    IsolatePriority prio = IsolatePriority.regular,
    Duration maxRuntime = const Duration(minutes: 5),
    void Function(Object error, StackTrace stack)? onErrorFunction,
  }) async {
    await _initFuture;
    final completer = Completer<TaskKiller>();
    _taskQueue.add(
      _QueuedTask<T>(
        entryPoint,
        message,
        completer,
        prio,
        maxRuntime,
        onErrorFunction,
      ),
    );
    _tryStartNext();
    return completer.future;
  }

  void _tryStartNext() {
    bool wasStarted = false; // for prio == IsolatePriority.immediate
    for (final worker in _workers) {
      if (!worker.isBusy && _taskQueue.isNotEmpty) {
        wasStarted = true;
        final task = _taskQueue.removeFirst();
        worker.isBusy = true;
        worker.task = task;

        task.startIsolate(worker);
        break;
      }
    }
    if (!wasStarted && _taskQueue.isNotEmpty) {
      final task = _taskQueue.first;
      if (task.prio == IsolatePriority.immediate &&
          _workers.length < maxIsolates) {
        _taskQueue.removeFirst();
        final immediateWorker = _Worker();
        _workers.add(immediateWorker);
        immediateWorker.isBusy = true;
        immediateWorker.task = task;
        task.startIsolate(immediateWorker);
        return;
      }
    }
  }
}

class _QueuedTask<T> implements Comparable<_QueuedTask> {
  final void Function(T) entryPoint;
  final T message;
  final Completer<TaskKiller> completer;
  IsolatePriority prio;

  final void Function(Object error, StackTrace stack)? onErrorFunction;

  final Duration maxRuntime;
  Timer? _runtimeTimer;

  _QueuedTask(
    this.entryPoint,
    this.message,
    this.completer,
    this.prio,
    this.maxRuntime,
    this.onErrorFunction,
  );

  @override
  int compareTo(_QueuedTask other) {
    // higher priority comes first
    return other.prio.level.compareTo(prio.level);
  }

  void startIsolate(_Worker worker) {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    Isolate.spawn<T>(
          entryPoint,
          message,
          onExit: exitPort.sendPort,
          onError: errorPort.sendPort,
        )
        .then((isolate) {
          worker.isolate = isolate;

          bool cleanedUp = false;
          void cleanup() {
            if (cleanedUp) return;
            cleanedUp = true;
            _runtimeTimer?.cancel();
            receivePort.close();
            errorPort.close();
            exitPort.close();
            worker.isBusy = false;
            worker.isolate?.kill(priority: Isolate.immediate);
            worker.reset();
            if (IsolatesManager()._workers.length >
                IsolatesManager().maxIsolates - 1) {
              IsolatesManager()._workers.remove(worker);
            }
            IsolatesManager()._tryStartNext();
          }

          // maxRuntime -> kill
          _runtimeTimer = Timer(maxRuntime, () {
            dev.log("Killing isolate due to timeout: $maxRuntime");
            cleanup();
          });

          // exit / error
          exitPort.listen((_) => cleanup());
          errorPort.listen((e) {
            onBadExit(cleanup, e);
          });

          final killer = TaskKiller(
            // kill
            () {
              if (worker.task != this) {
                dev.log(
                  "Warning: TaskKiller,kill: Task is already not running.",
                );
                return;
              }
              if (worker.isolate != null) {
                cleanup();
              }
            },
            // delay
            () {
              if (worker.task != this) {
                dev.log(
                  "Warning: TaskKiller, killResumeLate: Task is already not running.",
                );
                return;
              }
              prio = IsolatePriority.late;
            },
          );

          completer.complete(killer);
        })
        .catchError((e) {
          worker.reset();
          completer.completeError(e);
          IsolatesManager()._tryStartNext();
        });
  }

  void onBadExit(void Function()? cleanup, e) {
    if (cleanup != null) cleanup();
    Object error = e;
    StackTrace stack = StackTrace.current;
    dev.log("Error in Isolate: $e");
    if (e is List && e.length == 2) {
      error = e[0];
      if (e[1] is String) {
        stack = StackTrace.fromString(e[1]);
      }
    }
    if (onErrorFunction != null) {
      onErrorFunction!(error, stack);
    }
  }
}

class _Worker<T> {
  Isolate? isolate;
  _QueuedTask<T>? task;
  bool isBusy = false;
  reset() {
    isolate = null;
    task = null;
    isBusy = false;
  }
}
