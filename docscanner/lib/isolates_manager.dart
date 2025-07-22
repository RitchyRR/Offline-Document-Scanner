import 'dart:async';
import 'package:collection/collection.dart' show HeapPriorityQueue;
import 'dart:developer' as dev show log;
import 'dart:isolate';
import 'dart:io';

import 'package:docscanner/app_globals.dart' show ErrorLogger;

class TaskKiller {
  bool exited = false;
  final Future<void> Function() _kill;
  final void Function(IsolatePriority newPrio) _changePrio;
  final void Function(SendPort controlPort) _setControlPort;
  TaskKiller(this._kill, this._changePrio, this._setControlPort);
  Future<void> kill() => _kill();
  void changePrio(IsolatePriority newPrio) => _changePrio(newPrio);
  void setControlPort(SendPort controlPort) => _setControlPort(controlPort);
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

  final int maxIsolates = (Platform.numberOfProcessors - 1).clamp(
    1,
    Platform.numberOfProcessors - 1,
  );
  final int baseNOfIsolates = ((Platform.numberOfProcessors - 1) * 5 / 7)
      .toInt()
      .clamp(1, Platform.numberOfProcessors - 1);
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
        final toleratedDelay = Duration(seconds: 8);
        if (pingDelay > (toleratedDelay + freezeDuration)) {
          pinger.kill(priority: Isolate.immediate);
          pingCheckTimer?.cancel();
          pingPort.close();
          //todo cleanup all isolates and trigger _onBadExit
          for (var task in _taskQueue.toList()) {
            Future.delayed(Duration(seconds: 1), () {
              task.onBadExit(
                Exception(
                  "Isolate missed ping. Likely killed by System, restarting all isolates.",
                ),
              );
              _taskQueue.remove(task);
            });
          }
          for (var worker in _workers) {
            Future.delayed(Duration(seconds: 1), () {
              //worker.isolate?.kill(priority: Isolate.immediate);
              worker.task?.onBadExit(
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
    void Function(T) functionIn,
    T parametersIn, {
    required ReceivePort portIn,
    IsolatePriority prio = IsolatePriority.regular,
    Duration maxRuntime = const Duration(minutes: 5),
    void Function(Object error, StackTrace stack)? onErrorFunction,
  }) async {
    await _initFuture;
    late _QueuedTask<T> task;

    final killer = TaskKiller(
      // kill
      () async {
        // Task queued -> remove from queue
        if (_taskQueue.remove(task)) {
          task._cleanedUp = true;
        }
        // Task running -> kill / cleanup
        else if (task._worker?.isolate != null) {
          task._cleanup?.call("kill");
          await task.exitCompleter.future;
        }
      },
      // changePrio
      (IsolatePriority newPrio) {
        task.prio = newPrio;
      },
      // setControlPort(SendPort controlPort)
      (SendPort controlPortIn) {
        task.controlPort = controlPortIn;
      },
    );

    task = _QueuedTask<T>(
      functionIn,
      parametersIn,
      prio,
      maxRuntime,
      onErrorFunction,
      killer,
      portIn,
    );

    _taskQueue.add(task);
    _tryStartNext();
    return killer;
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
  IsolatePriority prio;
  bool _cleanedUp = false;
  final void Function(Object error, StackTrace stack)? onErrorFunction;
  final Duration maxRuntime;
  Timer? _runtimeTimer;
  TaskKiller? killer;
  ReceivePort entryPointPort;
  SendPort? controlPort;

  final exitCompleter = Completer();

  _Worker? _worker;
  void Function(String reason)? _cleanup;

  _QueuedTask(
    this.entryPoint,
    this.message,
    this.prio,
    this.maxRuntime,
    this.onErrorFunction,
    this.killer,
    this.entryPointPort,
  );

  // higher prio first
  @override
  int compareTo(_QueuedTask other) => other.prio.level.compareTo(prio.level);

  void startIsolate(_Worker worker) {
    _worker = worker;

    // Exit / Error
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    exitPort.listen((_) {
      exitPort.close();
      errorPort.close();
      _cleanup?.call("exit");
      exitCompleter.complete();
      killer?.exited = true;
    });
    errorPort.listen((e) {
      errorPort.close();
      onBadExit(e);
    });

    Isolate.spawn<T>(
          entryPoint,
          message,
          onExit: exitPort.sendPort,
          onError: errorPort.sendPort,
        )
        .then((isolate) {
          worker.isolate = isolate;

          _cleanup = (String reason) {
            if (_cleanedUp) return;
            _cleanedUp = true;

            entryPointPort.close();
            _runtimeTimer?.cancel();
            if (controlPort != null) {
              controlPort!.send("kill");
            } else {
              if (worker.isolate != null) {
                dev.log(
                  "$reason: Ending isolate without controlPort: ${isolate.debugName}",
                );
                worker.isolate!.kill(priority: Isolate.beforeNextEvent);
              }
            }
            worker.reset();
            if (IsolatesManager()._workers.length >
                IsolatesManager().maxIsolates - 1) {
              IsolatesManager()._workers.remove(worker);
            }
            IsolatesManager()._tryStartNext();
          };

          // maxRuntime -> kill
          _runtimeTimer = Timer(maxRuntime, () {
            dev.log("Killing isolate due to timeout: $maxRuntime");
            _cleanup!("timeout, ${maxRuntime.toString()}");
          });
        })
        .catchError((e) {
          worker.reset();
          onBadExit(e);
          IsolatesManager()._tryStartNext();
        });
  }

  void onBadExit(e) {
    if (_cleanedUp) return;
    _cleanup?.call("error");
    Object error = e;
    StackTrace stack = StackTrace.current;
    dev.log("Error in Isolate: $e");
    if (e is List && e.length == 2) {
      error = e[0];
      if (e[1] is String) {
        stack = StackTrace.fromString(e[1]);
      }
    }
    ErrorLogger.logError("Error in Isolate: $error", stack);
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
