import 'package:flutter/material.dart';
import '../auth/owner_mode_lock.dart';

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
            appBar: AppBar(title: const Text('Owner access required')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Owner mode is locked on this device. Ask the owner to unlock it.',
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
  String? error;

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
        setState(() => error = 'Wrong owner password.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not check the password. Check your connection.',
        );
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Owner mode is locked. Enter the owner password.'),
            TextField(
              key: const ValueKey('owner-unlock-password'),
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Owner password'),
              onSubmitted: (_) => unlock(),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: unlocking ? null : unlock,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(unlocking ? 'Checking…' : 'Unlock owner mode'),
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
