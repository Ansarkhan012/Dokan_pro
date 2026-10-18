import 'package:flutter/material.dart';
import '../auth/owner_mode_lock.dart';
import '../core/l10n/l10n.dart';

final class OwnerAction {
  const OwnerAction({
    required this.label,
    required this.icon,
    required this.builder,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  final bool primary;
}

/// The only way owner screens are opened: the route itself re-checks the lock,
/// so a push that bypasses the hub buttons is still rejected.
Route<void> ownerOnlyRoute(OwnerModeLock lock, WidgetBuilder builder) =>
    MaterialPageRoute<void>(
      builder: (context) => OwnerOnlyGuard(lock: lock, builder: builder),
    );

/// Builds [builder] only while owner mode is unlocked. If owner mode locks
/// while the screen is open, the screen is torn down.
class OwnerOnlyGuard extends StatelessWidget {
  const OwnerOnlyGuard({super.key, required this.lock, required this.builder});
  final OwnerModeLock lock;
  final WidgetBuilder builder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lock,
    builder: (context, _) => lock.ownerAccessAllowed
        ? builder(context)
        : Scaffold(
            appBar: AppBar(title: Text(context.l10n.ownerAccessRequired)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10n.ownerLockedAskOwner,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
  );
}

/// Owner entries on the device hub: the actions while owner mode is unlocked,
/// otherwise a password prompt to unlock it.
class OwnerModeSection extends StatefulWidget {
  const OwnerModeSection({
    super.key,
    required this.lock,
    required this.reauthenticator,
    required this.actions,
  });
  final OwnerModeLock lock;
  final OwnerReauthenticator reauthenticator;
  final List<OwnerAction> actions;
  @override
  State<OwnerModeSection> createState() => _OwnerModeSectionState();
}

class _OwnerModeSectionState extends State<OwnerModeSection> {
  final password = TextEditingController();
  bool unlocking = false;

  /// Resolved when shown, so a language switch also translates the error.
  String Function(AppLocalizations)? error;

  Future<void> unlock() async {
    if (unlocking) return;
    setState(() {
      unlocking = true;
      error = null;
    });
    try {
      if (await widget.reauthenticator.verifyPassword(password.text)) {
        await widget.lock.release();
        password.clear();
      } else if (mounted) {
        setState(() => error = (l10n) => l10n.ownerErrWrongPassword);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = (l10n) => l10n.ownerErrCheckPassword);
      }
    } finally {
      if (mounted) setState(() => unlocking = false);
    }
  }

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lock,
    builder: (context, _) {
      if (!widget.lock.isLoaded) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!widget.lock.ownerAccessAllowed) {
        final l10n = context.l10n;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.ownerLockedEnterPassword),
            TextField(
              key: const ValueKey('owner-unlock-password'),
              controller: password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: l10n.ownerPassword),
              onSubmitted: (_) => unlock(),
            ),
            if (error case final error?)
              Text(
                error(l10n),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: unlocking ? null : unlock,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(unlocking ? l10n.ownerChecking : l10n.ownerUnlock),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in widget.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _button(
                action,
                () => Navigator.of(
                  context,
                ).push(ownerOnlyRoute(widget.lock, action.builder)),
              ),
            ),
        ],
      );
    },
  );

  Widget _button(OwnerAction action, VoidCallback onPressed) => action.primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(action.icon),
          label: Text(action.label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(action.icon),
          label: Text(action.label),
        );
}
