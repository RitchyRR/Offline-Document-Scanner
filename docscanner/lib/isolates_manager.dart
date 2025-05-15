import 'dart:async';
import 'package:collection/collection.dart' show HeapPriorityQueue;
import 'dart:developer' as dev show log;
import 'dart:isolate';
import 'dart:math' as math;
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

  final int maxIsolates = math.max(1, Platform.numberOfProcessors - 1);
  final int maxImmediateIsolatesSpillover = 2;
  final List<_Worker> _workers = [];
  final HeapPriorityQueue<_QueuedTask<dynamic>> _taskQueue =
      HeapPriorityQueue<_QueuedTask<dynamic>>();

  Future<void> _init() async {
    // -1 because: reserve one for prio immediate
    for (int i = 0; i < maxIsolates - 1; i++) {
      _workers.add(_Worker());
    }
  }

  Future<TaskKiller> runTask<T>(
    void Function(T) entryPoint,
    T message, {
    IsolatePriority prio = IsolatePriority.regular,
    Duration maxRuntime = const Duration(minutes: 5),
  }) async {
    await _initFuture;
    final completer = Completer<TaskKiller>();
    _taskQueue.add(
      _QueuedTask<T>(entryPoint, message, completer, prio, maxRuntime),
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
          _workers.length < maxIsolates + maxImmediateIsolatesSpillover) {
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

  final Duration maxRuntime;
  Timer? _runtimeTimer;

  _QueuedTask(
    this.entryPoint,
    this.message,
    this.completer,
    this.prio,
    this.maxRuntime,
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

          //final bool runImmediate = prio == IsolatePriority.immediate;
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
            worker.isolate = null;
            worker.task = null;
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
            cleanup();
            dev.log("Isolate error: $e");
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
          worker.isBusy = false;
          worker.task = null;
          completer.completeError(e);
          IsolatesManager()._tryStartNext();
        });
  }
}

class _Worker<T> {
  Isolate? isolate;
  _QueuedTask<T>? task;
  bool isBusy = false;
}
