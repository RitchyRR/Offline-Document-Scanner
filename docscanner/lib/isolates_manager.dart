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
  //.clamp(1, 15);
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
  }) async {
    await _initFuture;
    final completer = Completer<TaskKiller>();

    switch (prio) {
      case IsolatePriority.regular:
        _taskQueue.addLast(_QueuedTask<T>(entryPoint, message, completer));
        break;
      case IsolatePriority.quick:
      case IsolatePriority.immediate:
        _taskQueue.addFirst(_QueuedTask<T>(entryPoint, message, completer));
        break;
    }

    _tryStartNext<T>(prio);
    return completer.future;
  }

  void _tryStartNext<T>(IsolatePriority prio) {
    bool wasStarted = false;
    for (final worker in _workers) {
      if (!worker.isBusy && _taskQueue.isNotEmpty) {
        wasStarted = true;
        final _QueuedTask<T> task = _taskQueue.removeFirst() as _QueuedTask<T>;
        // move to back
        _workers.remove(worker);
        _workers.addLast(worker);
        worker.isBusy = true;
        worker.task = task;

        final receivePort = ReceivePort();
        final errorPort = ReceivePort();
        final exitPort = ReceivePort();

        Isolate.spawn<T>(
              task.entryPoint,
              task.message,
              onExit: exitPort.sendPort,
              onError: errorPort.sendPort,
            )
            .then((isolate) {
              worker.isolate = isolate;

              void cleanup() {
                receivePort.close();
                errorPort.close();
                exitPort.close();
                worker.isBusy = false;
                worker.isolate = null;
                _tryStartNext<T>(IsolatePriority.regular);
              }

              exitPort.listen((_) => cleanup());
              errorPort.listen((e) {
                cleanup();
                dev.log("Isolate error: $e");
              });

              final killer = TaskKiller(
                // kill
                () {
                  if (worker.isolate != null) {
                    worker.isolate!.kill(priority: Isolate.immediate);
                    cleanup();
                  } else {
                    _taskQueue.remove(task);
                  }
                },
                // killResumeLate
                () {
                  if (worker.isolate != null) {
                    bool allBusy = true;
                    for (final worker in _workers) {
                      if (!worker.isBusy) allBusy = false;
                    }
                    if (allBusy) {
                      worker.isolate!.kill(priority: Isolate.immediate);
                    }
                    _taskQueue.addLast(task);
                  } else {
                    _taskQueue.remove(task);
                    _taskQueue.addLast(task);
                  }
                },
              );

              task.completer.complete(killer);
            })
            .catchError((e) {
              worker.isBusy = false;
              task.completer.completeError(e);
              _tryStartNext<T>(IsolatePriority.regular);
            });

        break;
      }
    }
    if (!wasStarted && prio == IsolatePriority.immediate) {
      // kill newestWorker
      _Worker newestWorker = _workers.last;
      newestWorker.isolate!.kill();
      // add newestWorker.task behind immediateTask
      final _QueuedTask<T> immediateTask =
          _taskQueue.removeFirst() as _QueuedTask<T>;
      _taskQueue.addFirst(newestWorker.task!);
      _taskQueue.addFirst(immediateTask);
      // start immediateTask
      _tryStartNext<T>(IsolatePriority.immediate);
    }
  }
}

class _QueuedTask<T> {
  final void Function(T) entryPoint;
  final T message;
  final Completer<TaskKiller> completer;

  _QueuedTask(this.entryPoint, this.message, this.completer);
}

class _Worker<T> {
  Isolate? isolate;
  _QueuedTask<T>? task;
  bool isBusy = false;
}
