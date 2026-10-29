import 'package:flutter/material.dart';

/// Asks "are you sure?" before anything is deleted or reset. True only if the
/// user confirms; tapping outside or Cancel keeps everything as it was.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 38),
      title: Text(title, textAlign: TextAlign.center),
      content: message == null ? null : Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Text field with a leading icon, used by every "add" form.
Widget formField(
  TextEditingController c,
  String label,
  IconData icon, {
  TextInputType? type,
  bool obscure = false,
  Widget? suffix,
  String? Function(String?)? validator,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: suffix,
        ),
      ),
    );

/// Icon + title row that introduces a group of fields.
class FormSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;
  const FormSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(icon, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            ?trailing,
          ]),
          const SizedBox(height: 14),
          ...children,
        ]),
      ),
    );
  }
}

const playerRoles = ['Batsman', 'Bowler', 'All-rounder', 'Wicket-keeper'];

/// Tap-to-pick player role; writes the choice into [controller].
class RoleChips extends StatefulWidget {
  final TextEditingController controller;
  const RoleChips({super.key, required this.controller});

  @override
  State<RoleChips> createState() => _RoleChipsState();
}

class _RoleChipsState extends State<RoleChips> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final r in playerRoles)
            ChoiceChip(
              label: Text(r),
              selected: widget.controller.text == r,
              onSelected: (on) => setState(() => widget.controller.text = on ? r : ''),
            ),
        ],
      ),
    );
  }
}

/// Dialog with a coloured icon header, a scrollable body and Cancel / confirm
/// buttons. Resolves to true when confirmed.
Future<bool?> showFormDialog(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Widget Function(BuildContext, StateSetter) builder,
  String confirmLabel = 'Save',
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          title: Container(
            color: scheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold, color: scheme.onPrimaryContainer)),
              ),
            ]),
          ),
          content: SingleChildScrollView(child: builder(ctx, setS)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
          ],
        );
      },
    ),
  );
}
