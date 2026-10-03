import 'dart:async';
import '../database/repositories/sync_queue_repository.dart';
import 'sale_upload_gateway.dart';
import 'sync_worker.dart';

/// Runs queue uploads in the background for one POS runtime.
///
/// Checkout never waits for it: [wake] returns immediately and never throws,
/// and every failure of a run (RPC error, lost lease, network timeout, closed
/// database) only leaves the queued operations pending for a later attempt.
/// Each RPC is cut after [rpcTimeout]; the timeout only affects sync status.
/// Give each runner its own [workerId] (`uniqueSyncWorkerId`), so runners
/// never share a lease (R1.6).
final class SyncWorkerRunner {
  SyncWorkerRunner({
    required this.queue,
    required SaleUploadGateway gateway,
    required this.workerId,
    this.cashierToken,
    this.rpcTimeout = defaultRpcTimeout,
    this._clock,
  }) : _gateway = TimeBoundSaleUploadGateway(gateway, rpcTimeout);

  static const defaultRpcTimeout = Duration(seconds: 15);

  final SyncQueueRepository queue;
  final String workerId;
  final Future<String?> Function()? cashierToken;
  final Duration rpcTimeout;
  final SaleUploadGateway _gateway;
  final DateTime Function()? _clock;
  Future<bool>? _running;
  bool _rerun = false;

  /// Starts a run if none is in progress (otherwise one more pass follows the
  /// current one). Fire-and-forget: synchronous and never throws.
  void wake() {
    try {
      unawaited(run());
    } catch (_) {
      // Waking sync can never affect the caller.
    }
  }

  /// One single-flight run; true when nothing is left pending. Never throws.
  Future<bool> run() {
    if (_running case final running?) {
      _rerun = true;
      return running;
    }
    final running = _loop();
    _running = running;
    return running.whenComplete(() => _running = null);
  }

  /// Completes when no run is in progress.
  Future<void> get idle async {
    for (var running = _running; running != null; running = _running) {
      await running;
    }
  }

  Future<bool> _loop() async {
    bool drained;
    do {
      _rerun = false;
      drained = await _pass();
    } while (_rerun);
    return drained;
  }

  Future<bool> _pass() async {
    try {
      await SyncWorker(
        queue: queue,
        gateway: _gateway,
        workerId: workerId,
        cashierToken: cashierToken,
        clock: _clock,
      ).runOnce();
      return (await queue.pending()).isEmpty;
    } catch (_) {
      // Recorded on the operation where possible; otherwise it stays leased
      // or pending and is retried after its lease or backoff expires.
      return false;
    }
  }
}

/// Bounds every upload RPC; a timeout fails that attempt like any RPC error.
final class TimeBoundSaleUploadGateway implements SaleUploadGateway {
  const TimeBoundSaleUploadGateway(this._inner, this._timeout);
  final SaleUploadGateway _inner;
  final Duration _timeout;

  @override
  Future<Object?> uploadSaleAggregate(
    Map<String, dynamic> payload, {
    String? cashierSessionToken,
  }) => _inner
      .uploadSaleAggregate(payload, cashierSessionToken: cashierSessionToken)
      .timeout(_timeout);
}
