import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/form_widgets.dart';
import '../widgets/match_actions.dart';
import '../widgets/match_widgets.dart';
import '../widgets/owner_edit.dart';
import '../widgets/team_avatar.dart';
import 'add_owner_screen.dart';
import 'bracket_screen.dart';
import 'team_detail.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _tab = 0;

  static const _titles = [
    'Owners & Teams',
    'Upcoming Matches',
    'Completed Matches',
    'Tournament Bracket',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: Db.signOut),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _OwnersTab(),
          _MatchesTab(completed: false),
          _MatchesTab(completed: true),
          BracketView(canEdit: true),
        ],
      ),
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
          onPressed: () => _addOwnerDialog(context),
          icon: const Icon(Icons.person_add),
          label: const Text('Add owner'),
        ),
        1 => FloatingActionButton.extended(
          onPressed: () => _scheduleSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('Schedule'),
        ),
        3 => FloatingActionButton.extended(
          onPressed: () => createBracketDialog(context),
          icon: const Icon(Icons.account_tree),
          label: const Text('Create bracket'),
        ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.groups), label: 'Owners'),
          NavigationDestination(icon: Icon(Icons.event), label: 'Matches'),
          NavigationDestination(
            icon: Icon(Icons.emoji_events),
            label: 'Results',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree),
            label: 'Bracket',
          ),
        ],
      ),
    );
  }
}

// ======================= OWNERS =======================

class _OwnersTab extends StatelessWidget {
  const _OwnersTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Owner>>(
      stream: Db.ownersStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final owners = snap.data!;
        if (owners.isEmpty) {
          return const EmptyState(
            text: 'No owners yet.\nTap "Add owner" to create one.',
            icon: Icons.groups,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(top: 6, bottom: 90),
          itemCount: owners.length,
          itemBuilder: (_, i) {
            final o = owners[i];
            return FadeSlideIn(
              key: ValueKey(o.id),
              index: i,
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: Text(
                      o.name.isEmpty ? '?' : o.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  title: Text(
                    o.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${o.email}\n${o.phone}'),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OwnerDetailScreen(owner: o),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _addOwnerDialog(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const AddOwnerScreen(),
    ),
  );
}

class OwnerDetailScreen extends StatelessWidget {
  final Owner owner;
  const OwnerDetailScreen({super.key, required this.owner});

  Future<void> _addTeam(BuildContext context) async {
    final name = TextEditingController();
    final ok = await showFormDialog(
      context,
      title: 'Add team',
      icon: Icons.group_add,
      confirmLabel: 'Add',
      builder: (_, _) => formField(name, 'Team name', Icons.shield_outlined),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await Db.addTeam(owner: owner, name: name.text.trim());
    }
  }

  /// Builds [child] from the owner's current details, so edits show straight away.
  Widget _liveOwner(Widget Function(Owner) child) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Db.owners.doc(owner.id).snapshots(),
        builder: (context, snap) => child(
          snap.hasData && snap.data!.exists ? Owner.fromDoc(snap.data!) : owner,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: Db.teamsOfOwner(owner.id),
      builder: (context, snap) {
        final teams = snap.data;
        return Scaffold(
          appBar: AppBar(title: _liveOwner((o) => Text(o.name))),
          // One team per owner: only offer "Add team" while the owner has none.
          floatingActionButton: teams != null && teams.isEmpty
              ? FloatingActionButton.extended(
                  onPressed: () => _addTeam(context),
                  icon: const Icon(Icons.group_add),
                  label: const Text('Add team'),
                )
              : null,
          body: Column(
            children: [
              _liveOwner(
                (o) => ListTile(
                  leading: const Icon(Icons.email),
                  title: Text(o.email),
                  subtitle: Text(o.phone),
                  trailing: IconButton(
                    tooltip: 'Edit owner details',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showOwnerEditDialog(context, owner.id),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: teams == null
                    ? const Center(child: CircularProgressIndicator())
                    : teams.isEmpty
                    ? const EmptyState(text: 'No team yet', icon: Icons.groups)
                    : ListView(
                        padding: const EdgeInsets.only(top: 6),
                        children: teams
                            .map(
                              (t) => Card(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: TeamAvatar(
                                    teamId: t.id,
                                    name: t.name,
                                    radius: 24,
                                    heroTag: 'team-logo-${t.id}',
                                  ),
                                  title: Text(
                                    t.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'Tap to view / add players',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () =>
                                        _confirmDeleteTeam(context, t),
                                  ),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TeamDetailScreen(
                                        team: t,
                                        canEdit: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteTeam(BuildContext context, Team t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${t.name}?'),
        content: const Text(
          'Its players will be removed. Existing matches are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await Db.deleteTeam(t);
  }
}

// ======================= MATCHES =======================

class _MatchesTab extends StatelessWidget {
  final bool completed;
  const _MatchesTab({required this.completed});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!.where((m) => m.completed == completed).toList();
        return MatchList(
          matches: completed ? list.reversed.toList() : list,
          countLabel: completed ? 'Completed matches' : 'Upcoming matches',
          emptyText: completed
              ? 'No completed matches'
              : 'No upcoming matches. Tap "Schedule".',
          onTap: (m) => showMatchActions(context, m),
        );
      },
    );
  }
}

/// Choose between a single match or auto round-robin.
Future<void> _scheduleSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sports),
            title: const Text('Schedule a single match'),
            onTap: () {
              Navigator.pop(sheet);
              _singleMatchDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome),
            title: const Text('Auto-generate lots (each team vs each team)'),
            subtitle: const Text(
              'Round-robin; skips pairs that already have a match',
            ),
            onTap: () {
              Navigator.pop(sheet);
              _roundRobinDialog(context);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _singleMatchDialog(BuildContext context) async {
  final teams = await Db.teamsStream().first;
  if (!context.mounted) return;
  if (teams.length < 2) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Add at least 2 teams first')));
    return;
  }
  Team? a;
  Team? b;
  var when = DateTime.now().add(const Duration(days: 1));
  final venue = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('New match'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Team>(
                decoration: const InputDecoration(labelText: 'Team A'),
                items: teams
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (v) => setS(() => a = v),
              ),
              DropdownButtonFormField<Team>(
                decoration: const InputDecoration(labelText: 'Team B'),
                items: teams
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (v) => setS(() => b = v),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${fmtDate(when)}  ${fmtTime(when)}'),
                onPressed: () async {
                  final r = await pickDateTime(ctx, when);
                  if (r != null) setS(() => when = r);
                },
              ),
              TextField(
                controller: venue,
                decoration: const InputDecoration(labelText: 'Venue'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  if (a == null || b == null || a!.id == b!.id) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick two different teams')));
    }
    return;
  }
  await Db.addMatch(a!, b!, when, venue.text.trim());
}

Future<void> _roundRobinDialog(BuildContext context) async {
  final teams = await Db.teamsStream().first;
  final existing = await Db.matchesStream().first;
  if (!context.mounted) return;
  if (teams.length < 2) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Add at least 2 teams first')));
    return;
  }
  var start = DateTime.now().add(const Duration(days: 1));
  start = DateTime(start.year, start.month, start.day, 9, 0);
  final perDay = TextEditingController(text: '2');
  final slot = TextEditingController(text: '120');
  final venue = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Generate lots'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${teams.length} teams, each plays every other team once.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('Start: ${fmtDate(start)}  ${fmtTime(start)}'),
                onPressed: () async {
                  final r = await pickDateTime(ctx, start);
                  if (r != null) setS(() => start = r);
                },
              ),
              TextField(
                controller: perDay,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Matches per day'),
              ),
              TextField(
                controller: slot,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes between matches in a day',
                ),
              ),
              TextField(
                controller: venue,
                decoration: const InputDecoration(labelText: 'Venue'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final n = await Db.generateRoundRobin(
    allTeams: teams,
    existing: existing,
    start: start,
    matchesPerDay: (int.tryParse(perDay.text) ?? 1).clamp(1, 50),
    slotMinutes: (int.tryParse(slot.text) ?? 120).clamp(15, 1440),
    venue: venue.text.trim(),
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$n matches created')));
  }
}
