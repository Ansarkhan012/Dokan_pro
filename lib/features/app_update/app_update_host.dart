import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/billing_activity.dart';
import '../../core/l10n/l10n.dart';
import 'update_controller.dart';
import 'update_dialog.dart';

/// Runs update checks around the app without ever blocking it.
///
/// * A few seconds after startup, and when the app returns to the
///   foreground (throttled by the controller, 6 h by default).
/// * Offline, slow or failing checks are silent.
/// * One dialog at a time; an optional release the user postponed is not
///   shown again (a newer one is).
/// * While a sale is being built ([BillingActivity]) the prompt waits.
/// * With no [controller] (updates not configured, or not Android) this is
///   just [child].
class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost({
    super.key,
    required this.controller,
    required this.child,
    this.startupDelay = const Duration(seconds: 5),
    this.busyRetry = const Duration(seconds: 60),
    this.isBillingBusy,
  });

  final UpdateController? controller;
  final Widget child;
  final Duration startupDelay, busyRetry;

  /// Defaults to [BillingActivity.isBusy].
  final bool Function()? isBillingBusy;

  /// The running host when updates are configured. Pushed routes (such as
  /// Settings) are not below `home`, so this is not an ancestor lookup.
  static AppUpdateHostState? get current => AppUpdateHostState._current;

  @override
  State<AppUpdateHost> createState() => AppUpdateHostState();
}

class AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  static AppUpdateHostState? _current;
  Timer? _startup, _retry;
  bool _dialogOpen = false;

  UpdateController? get _controller => widget.controller;
  bool get _billingBusy =>
      (widget.isBillingBusy ?? () => BillingActivity.isBusy)();

  /// Whether updates are available in this build (Settings shows the action).
  bool get enabled => _controller != null;

  @override
  void initState() {
    super.initState();
    if (_controller == null) return;
    _current = this;
    WidgetsBinding.instance.addObserver(this);
    _startup = Timer(widget.startupDelay, _autoCheck);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoCheck();
  }

  Future<void> _autoCheck() async {
    final c = _controller;
    if (c == null || !mounted) return;
    await c.check();
    final offer = c.offer;
    if (offer != null && await c.shouldPrompt(offer)) _prompt();
  }

  void _prompt() {
    final c = _controller;
    if (c == null || !mounted || _dialogOpen) return;
    if (_billingBusy) {
      _retry?.cancel();
      _retry = Timer(widget.busyRetry, _prompt);
      return;
    }
    _show(c);
  }

  Future<void> _show(UpdateController c) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AppUpdateDialog(controller: c),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  /// Settings → Check for updates. Always checks; shows the result.
  Future<void> checkNow() async {
    final c = _controller;
    if (c == null || _dialogOpen) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(context.l10n.updateChecking)),
    );
    await c.check(manual: true);
    messenger?.hideCurrentSnackBar();
    if (mounted) await _show(c);
  }

  @override
  void dispose() {
    if (identical(_current, this)) _current = null;
    _startup?.cancel();
    _retry?.cancel();
    if (_controller != null) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
