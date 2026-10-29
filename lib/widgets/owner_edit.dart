import 'package:flutter/material.dart';
import '../services/db.dart';
import 'form_widgets.dart';

/// Edit an owner's name and phone (the login email is fixed). Returns the new
/// name when saved, or null if cancelled. Used by owners for themselves and by
/// the admin for any owner.
Future<String?> showOwnerEditDialog(BuildContext context, String ownerId) async {
  final owner = await Db.ownerById(ownerId);
  if (owner == null || !context.mounted) return null;
  final name = TextEditingController(text: owner.name);
  final phone = TextEditingController(text: owner.phone);
  final ok = await showFormDialog(
    context,
    title: 'Owner details',
    icon: Icons.manage_accounts,
    builder: (_, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      formField(name, 'Owner name', Icons.badge_outlined),
      formField(phone, 'Phone', Icons.phone_outlined, type: TextInputType.phone),
      Row(children: [
        const Icon(Icons.email_outlined, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text('Login: ${owner.email}', style: const TextStyle(color: Colors.grey))),
      ]),
      const SizedBox(height: 8),
    ]),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  try {
    await Db.updateOwner(ownerId, name: name.text.trim(), phone: phone.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Owner details saved')));
    }
    return name.text.trim();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    return null;
  }
}
