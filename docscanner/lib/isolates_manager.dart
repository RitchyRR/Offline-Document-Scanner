import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:developer' as dev show log;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:io';

class TaskKiller {
  final void Function() _kill;
  final void Function() _killResumeLate;
  TaskKiller(this._kill, this._killResumeLate);
  void kill() => _kill();
  void killResumeLate() => _killResumeLate();
}

enum IsolatePriority { regular, quick, immediate }

class IsolatesManager {
  static final IsolatesManager _instance = IsolatesManager._internal();
  factory IsolatesManager() => _instance;

  late Future _initFuture;
  IsolatesManager._internal() {
    _initFuture = _init();
  }

  static final int _maxIsolates = math.max(1, Platform.numberOfProcessors - 1);
  final Queue<_Worker> _workers = Queue<_Worker>();
  final Queue<_QueuedTask<dynamic>> _taskQueue = Queue<_QueuedTask<dynamic>>();

  Future<void> _init() async {
    for (int i = 0; i < _maxIsolates; i++) {
      _workers.addLast(_Worker());
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

    switch (prio) {
      case IsolatePriority.regular:
        _taskQueue.addLast(
          _QueuedTask<T>(entryPoint, message, completer, maxRuntime),
        );
        break;
      case IsolatePriority.quick:
      case IsolatePriority.immediate:
        _taskQueue.addFirst(
          _QueuedTask<T>(entryPoint, message, completer, maxRuntime),
        );
        break;
    }

    _tryStartNext(prio);
    return completer.future;
  }

  void _tryStartNext(IsolatePriority prio) {
    bool wasStarted = false; // for prio == IsolatePriority.immediate
    for (final worker in _workers) {
      if (!worker.isBusy && _taskQueue.isNotEmpty) {
        wasStarted = true;
        final task = _taskQueue.removeFirst();
        // move to back
        _workers.remove(worker);
        _workers.addLast(worker);

        worker.isBusy = true;
        worker.task = task;

        task.startIsolate(worker);

        break;
      }
    }
    if (!wasStarted && prio == IsolatePriority.immediate) {
      // kill newestWorker
      _Worker newestWorker = _workers.last;
      newestWorker.isolate!.kill(priority: Isolate.immediate);
      newestWorker.isBusy = false;
      newestWorker.isolate = null;
      // add newestWorker.task behind immediateTask
      final immediateTask = _taskQueue.removeFirst();
      _taskQueue.addFirst(newestWorker.task!);
      _taskQueue.addFirst(immediateTask);
      // start immediateTask
      _tryStartNext(IsolatePriority.immediate);
    }
  }
}

class _QueuedTask<T> {
  final void Function(T) entryPoint;
  final T message;
  final Completer<TaskKiller> completer;

  final Duration maxRuntime;
  Timer? _runtimeTimer;

  _QueuedTask(this.entryPoint, this.message, this.completer, this.maxRuntime);

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
            worker.isolate = null;
            worker.task = null;
            IsolatesManager()._tryStartNext(IsolatePriority.regular);
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
              } else {
                IsolatesManager()._taskQueue.remove(this);
              }
            },
            // killResumeLate
            () {
              if (worker.task != this) {
                dev.log(
                  "Warning: TaskKiller, killResumeLate: Task is already not running.",
                );
                return;
              }

              if (worker.isolate != null) {
                if (IsolatesManager()._workers.every((w) => w.isBusy)) {
                  worker.isolate!.kill(priority: Isolate.immediate);
                }
                IsolatesManager()._taskQueue.addLast(this);
                cleanup();
              } else {
                IsolatesManager()._taskQueue.remove(this);
                IsolatesManager()._taskQueue.addLast(this);
              }
            },
          );

          completer.complete(killer);
        })
        .catchError((e) {
          worker.isBusy = false;
          worker.task = null;
          completer.completeError(e);
          IsolatesManager()._tryStartNext(IsolatePriority.regular);
        });
  }
}

class _Worker<T> {
  Isolate? isolate;
  _QueuedTask<T>? task;
  bool isBusy = false;
}
