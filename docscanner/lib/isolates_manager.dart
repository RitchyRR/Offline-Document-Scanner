import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:developer' as dev show log;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:io';

class TaskKiller {
  final void Function() _cancel;
  TaskKiller(this._cancel);
  void kill() => _cancel();
}

class IsolatesManager {
  static final IsolatesManager _instance = IsolatesManager._internal();
  factory IsolatesManager() => _instance;

  late Future _initFuture;
  IsolatesManager._internal() {
    _initFuture = _init();
  }

  static final int _maxIsolates = math
      .max(1, Platform.numberOfProcessors - 1)
      .clamp(1, 7);
  final List<_Worker> _workers = [];
  final Queue<_QueuedTask<dynamic>> _taskQueue = Queue<_QueuedTask<dynamic>>();

  Future<void> _init() async {
    for (int i = 0; i < _maxIsolates; i++) {
      _workers.add(_Worker());
    }
  }

  Future<TaskKiller> runTask<T>(void Function(T) entryPoint, T message) async {
    await _initFuture;
    final completer = Completer<TaskKiller>();

    _taskQueue.add(_QueuedTask<T>(entryPoint, message, completer));
    _tryStartNext<T>();
    return completer.future;
  }

  void _tryStartNext<T>() {
    for (final worker in _workers) {
      if (!worker.isBusy && _taskQueue.isNotEmpty) {
        final _QueuedTask<T> task = _taskQueue.removeFirst() as _QueuedTask<T>;
        worker.isBusy = true;

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
                _tryStartNext<T>();
              }

              exitPort.listen((_) => cleanup());
              errorPort.listen((e) {
                cleanup();
                dev.log("Isolate error: $e");
              });

              final killer = TaskKiller(() {
                if (worker.isolate != null) {
                  worker.isolate!.kill(priority: Isolate.immediate);
                  cleanup();
                } else {
                  _taskQueue.remove(task);
                }
              });

              task.completer.complete(killer);
            })
            .catchError((e) {
              worker.isBusy = false;
              task.completer.completeError(e);
              _tryStartNext<T>();
            });

        break;
      }
    }
  }
}

class _QueuedTask<T> {
  final void Function(T) entryPoint;
  final T message;
  final Completer<TaskKiller> completer;

  _QueuedTask(this.entryPoint, this.message, this.completer);
}

class _Worker {
  Isolate? isolate;
  bool isBusy = false;
}
