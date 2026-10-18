/// When the POS fetches other devices' changes while it runs (B-4).
///
/// The POS used to pull only at start, so a price, product or stock change
/// made on another device stayed invisible until a restart. This decides when
/// to run the existing reference pull, and makes sure pulls never overlap and
/// never run more often than [minInterval]:
///
/// - [onResume]: the app came back to the foreground.
/// - [onTick]: the periodic retry timer fired. Pulls only while the last pull
///   failed, i.e. while waiting for connectivity to return; an idle online
///   tablet makes no extra requests.
/// - [onUploadSucceeded]: an upload just reached the cloud. If pulls were
///   failing, connectivity is back, so pull at once (still single-flight).
///
/// Each returns true only when a pull ran to completion and applied, which is
/// the caller's cue to reload the catalog. Offline, a pull fails fast and
/// nothing changes: the POS keeps selling from its cached catalog.
final class RemoteRefresh {
  RemoteRefresh({
    required this._pull,
    this.minInterval = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<bool> Function() _pull;
  final Duration minInterval;
  final DateTime Function() _clock;

  Future<bool>? _running;
  DateTime? _lastStarted;
  bool _lastFailed = false;

  /// The last pull failed (offline or the cloud unreachable).
  bool get waitingForConnectivity => _lastFailed;

  /// Starts a pull unconditionally unless one is already running (the
  /// startup refresh). Joins a running pull instead of starting another.
  Future<bool> now() => _start();

  Future<bool> onResume() => _throttled();

  Future<bool> onTick() =>
      _lastFailed ? _throttled() : Future<bool>.value(false);

  Future<bool> onUploadSucceeded() =>
      _lastFailed ? _start() : Future<bool>.value(false);

  Future<bool> _throttled() {
    if (_running case final running?) return running;
    final last = _lastStarted;
    if (last != null && _clock().difference(last) < minInterval) {
      return Future<bool>.value(false);
    }
    return _start();
  }

  Future<bool> _start() {
    if (_running case final running?) return running;
    _lastStarted = _clock();
    final running = _run();
    _running = running;
    return running.whenComplete(() => _running = null);
  }

  Future<bool> _run() async {
    bool applied;
    try {
      applied = await _pull();
    } catch (_) {
      applied = false; // A pull problem never reaches the POS screen.
    }
    _lastFailed = !applied;
    return applied;
  }
}
