import 'package:flutter/material.dart';

/// Shared tablet presentation pieces so owner screens and dialogs speak the
/// same visual language as New Sale and Create Product: outlined fields,
/// section labels, status pills and an adaptive form dialog.

const posAccent = Color(0xff176b52);
const posBorder = Color(0xffdce2e6);
const posMuted = Color(0xff6c7680);
const posPageBackground = Color(0xfff4f6f7);

/// Outlined, filled inputs instead of underline-only fields. Apply with a
/// [Theme] around a form, not globally.
ThemeData posFormTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  return theme.copyWith(
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
  );
}

class FormSectionLabel extends StatelessWidget {
  const FormSectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

enum StatusTone { success, info, warning, danger, neutral }

/// A compact coloured label for states such as Synced, Low or Voided.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.tone, this.icon});
  final String label;
  final StatusTone tone;
  final IconData? icon;

  static Color colorFor(StatusTone tone) => switch (tone) {
    StatusTone.success => posAccent,
    StatusTone.info => const Color(0xff475467),
    StatusTone.warning => const Color(0xffb54708),
    StatusTone.danger => const Color(0xffb42318),
    StatusTone.neutral => posMuted,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible lets a long label (or a large system font) ellipsize
          // instead of overflowing the pill's row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White bordered card used for list rows and sections on tablet screens.
class PosCard extends StatelessWidget {
  const PosCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: posBorder),
      borderRadius: BorderRadius.circular(10),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Adaptive form dialog: pinned header and footer with a scrolling body, or
/// one scrolling column when the keyboard leaves very little height. The
/// footer stacks its message above the actions on narrow widths.
class PosFormDialog extends StatelessWidget {
  const PosFormDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
    this.message,
    this.maxWidth = 920,
    this.locked = false,
  });

  final String title;
  final String? subtitle;

  /// Builds the body; `wide` is true when there is room for two columns.
  final Widget Function(BuildContext context, bool wide) body;
  final List<Widget> actions;

  /// Shown at the start of the footer (hint or error).
  final Widget? message;
  final double maxWidth;

  /// While locked the body ignores input and system back is blocked.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !locked,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Theme(
            data: posFormTheme(theme),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final header = Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
                final content = Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: AbsorbPointer(
                    absorbing: locked,
                    child: body(context, constraints.maxWidth >= 640),
                  ),
                );
                final footer = _footer();
                // When the keyboard leaves very little room, scroll everything
                // together instead of pinning header and footer.
                if (constraints.maxHeight < 360) {
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, content, footer],
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const Divider(height: 1),
                    Flexible(child: SingleChildScrollView(child: content)),
                    const Divider(height: 1),
                    footer,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final bar = OverflowBar(
      spacing: 8,
      overflowSpacing: 8,
      overflowAlignment: OverflowBarAlignment.end,
      children: actions,
    );
    final hint = message ?? const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 480
            ? Row(
                children: [
                  Expanded(child: hint),
                  const SizedBox(width: 12),
                  bar,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: bar),
                ],
              ),
      ),
    );
  }
}

/// Two equally wide form fields side by side.
class FieldPair extends StatelessWidget {
  const FieldPair(this.first, this.second, {super.key});
  final Widget first, second;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: first),
      const SizedBox(width: 12),
      Expanded(child: second),
    ],
  );
}

/// Footer hint text (`* Required`) or an error in the error colour.
Widget formFooterMessage(BuildContext context, String? error) {
  final theme = Theme.of(context);
  return error == null
      ? Text(
          '* Required',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        )
      : Text(error, style: TextStyle(color: theme.colorScheme.error));
}
