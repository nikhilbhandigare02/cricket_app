import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/db.dart';
import '../services/team_logos.dart';
import '../widgets/form_widgets.dart';

class _PlayerForm {
  final name = TextEditingController();
  final role = TextEditingController();
  final jersey = TextEditingController();
  final phone = TextEditingController();

  _PlayerForm(int number) {
    jersey.text = '$number';
  }

  void dispose() {
    name.dispose();
    role.dispose();
    jersey.dispose();
    phone.dispose();
  }
}

/// Full-screen form: owner, login, team and players in one go.
class AddOwnerScreen extends StatefulWidget {
  const AddOwnerScreen({super.key});

  @override
  State<AddOwnerScreen> createState() => _AddOwnerScreenState();
}

class _AddOwnerScreenState extends State<AddOwnerScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _team = TextEditingController();
  final _players = <_PlayerForm>[_PlayerForm(1)];
  bool _hide = true;
  bool _saving = false;
  String? _logo; // base64 JPEG chosen for the team

  Future<void> _pickLogo() async {
    try {
      final logo = await TeamLogos.pick();
      if (logo != null) setState(() => _logo = logo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _pass, _team]) {
      c.dispose();
    }
    for (final p in _players) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final players = [
      for (final p in _players)
        if (p.name.text.trim().isNotEmpty)
          {
            'name': p.name.text.trim(),
            'role': p.role.text.trim(),
            'jersey': int.tryParse(p.jersey.text) ?? 0,
            'phone': p.phone.text.trim(),
          },
    ];
    setState(() => _saving = true);
    try {
      await Db.addOwner(
        name: _name.text.trim(),
        email: _email.text,
        phone: _phone.text.trim(),
        password: _pass.text,
        teamName: _team.text.trim(),
        logo: _logo,
        players: players,
      );
      messenger.showSnackBar(SnackBar(content: Text('${_name.text.trim()} and ${_team.text.trim()} added')));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  String? _required(String? v, String what) => (v == null || v.trim().isEmpty) ? 'Enter $what' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add owner & team')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            FormSection(icon: Icons.person, title: 'Owner', children: [
              formField(_name, 'Owner name', Icons.badge_outlined, validator: (v) => _required(v, 'owner name')),
              formField(_phone, 'Phone', Icons.phone_outlined, type: TextInputType.phone),
            ]),
            FormSection(icon: Icons.lock, title: 'Owner login', children: [
              formField(
                _email,
                'Login email',
                Icons.email_outlined,
                type: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              formField(
                _pass,
                'Password (min 6)',
                Icons.lock_outline,
                obscure: _hide,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
                validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
              ),
            ]),
            FormSection(icon: Icons.groups, title: 'Team', children: [
              formField(_team, 'Team name (one team per owner)', Icons.shield_outlined,
                  validator: (v) => _required(v, 'a team name')),
              Row(children: [
                _logo == null
                    ? const CircleAvatar(radius: 30, child: Icon(Icons.image_outlined))
                    : CircleAvatar(radius: 30, backgroundColor: Colors.white, backgroundImage: MemoryImage(base64Decode(_logo!))),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(_logo == null ? 'Add team logo' : 'Change logo'),
                      onPressed: _pickLogo,
                    ),
                    if (_logo != null)
                      TextButton(onPressed: () => setState(() => _logo = null), child: const Text('Remove')),
                  ]),
                ),
              ]),
            ]),
            for (var i = 0; i < _players.length; i++)
              FormSection(
                key: ObjectKey(_players[i]),
                icon: Icons.sports_cricket,
                title: 'Player ${i + 1}',
                trailing: _players.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          final p = _players[i];
                          // An empty row can go straight away; one with details asks first.
                          final hasData = p.name.text.trim().isNotEmpty || p.phone.text.trim().isNotEmpty;
                          if (hasData &&
                              !await confirmDelete(context,
                                  title: 'Remove player ${i + 1}?',
                                  message: 'The details you typed for this player are discarded.',
                                  confirmLabel: 'Remove')) {
                            return;
                          }
                          if (mounted) setState(() => _players.remove(p));
                          p.dispose();
                        },
                      )
                    : null,
                children: [
                  formField(_players[i].name, 'Player name', Icons.person_outline),
                  const Text('Role'),
                  const SizedBox(height: 6),
                  RoleChips(controller: _players[i].role),
                  Row(children: [
                    Expanded(
                      child: formField(_players[i].jersey, 'Jersey no.', Icons.tag, type: TextInputType.number),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: formField(_players[i].phone, 'Phone', Icons.phone_outlined,
                          type: TextInputType.phone),
                    ),
                  ]),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add another player'),
                onPressed: () => setState(() => _players.add(_PlayerForm(_players.length + 1))),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_saving ? 'Creating...' : 'Create owner & team'),
          ),
        ),
      ),
    );
  }
}
