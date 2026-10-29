import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/db.dart';
import '../widgets/form_widgets.dart';
import '../services/team_logos.dart';
import '../widgets/match_actions.dart';
import '../widgets/animations.dart';
import '../widgets/team_avatar.dart';
import '../widgets/match_widgets.dart';
import 'match_detail_screen.dart';

/// Team members list + the team's matches.
/// [canEdit] is the admin (also gets the match scoring options). [canManage] is
/// an owner on their own team: can rename it, change its logo and edit players.
class TeamDetailScreen extends StatelessWidget {
  final Team team;
  final bool canEdit;
  final bool canManage;
  const TeamDetailScreen({
    super.key,
    required this.team,
    required this.canEdit,
    this.canManage = false,
  });

  bool get _manage => canEdit || canManage;

  Future<void> _rename(BuildContext context, String current) async {
    final name = TextEditingController(text: current);
    final ok = await showFormDialog(
      context,
      title: 'Team name',
      icon: Icons.shield_outlined,
      builder: (_, _) => formField(name, 'Team name', Icons.shield_outlined),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await Db.renameTeam(team.id, name.text.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not rename: $e')));
      }
    }
  }

  Future<void> _editPlayer(BuildContext context, Player p) async {
    final name = TextEditingController(text: p.name);
    final role = TextEditingController(text: p.role);
    final jersey = TextEditingController(text: '${p.jersey}');
    final phone = TextEditingController(text: p.phone);
    final ok = await showFormDialog(
      context,
      title: 'Edit player',
      icon: Icons.edit,
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          formField(name, 'Player name', Icons.person_outline),
          const Text('Role'),
          const SizedBox(height: 6),
          RoleChips(controller: role),
          formField(
            jersey,
            'Jersey no.',
            Icons.tag,
            type: TextInputType.number,
          ),
          formField(
            phone,
            'Phone',
            Icons.phone_outlined,
            type: TextInputType.phone,
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await Db.updatePlayer(
        team.id,
        p.id,
        name: name.text.trim(),
        role: role.text.trim(),
        jersey: int.tryParse(jersey.text) ?? 0,
        phone: phone.text.trim(),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save player: $e')));
      }
    }
  }

  /// Pick a new logo from the gallery, or remove the current one.
  Future<void> _logoSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${team.name} logo',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheet, 'pick'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Remove logo',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          ],
        ),
      ),
    );
    try {
      if (action == 'pick') {
        final logo = await TeamLogos.pick();
        if (logo == null) return;
        await Db.setTeamLogo(team.id, logo);
        messenger.showSnackBar(const SnackBar(content: Text('Logo updated')));
      } else if (action == 'remove') {
        if (!context.mounted ||
            !await confirmDelete(context,
                title: 'Remove the team logo?',
                message: 'The team goes back to showing its first letter.',
                confirmLabel: 'Remove')) {
          return;
        }
        await Db.setTeamLogo(team.id, null);
        messenger.showSnackBar(const SnackBar(content: Text('Logo removed')));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not change logo: $e')),
      );
    }
  }

  Future<void> _confirmDeletePlayer(BuildContext context, Player p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await Db.deletePlayer(team.id, p.id);
  }

  Future<void> _addPlayer(BuildContext context) async {
    final name = TextEditingController();
    final role = TextEditingController();
    final jersey = TextEditingController();
    final phone = TextEditingController();
    final ok = await showFormDialog(
      context,
      title: 'Add player',
      icon: Icons.person_add,
      confirmLabel: 'Add',
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          formField(name, 'Player name', Icons.person_outline),
          const Text('Role'),
          const SizedBox(height: 6),
          RoleChips(controller: role),
          formField(
            jersey,
            'Jersey no.',
            Icons.tag,
            type: TextInputType.number,
          ),
          formField(
            phone,
            'Phone',
            Icons.phone_outlined,
            type: TextInputType.phone,
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await Db.addPlayer(
        team.id,
        name: name.text.trim(),
        role: role.text.trim(),
        jersey: int.tryParse(jersey.text) ?? 0,
        phone: phone.text.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          // Watches the team so a rename shows straight away.
          title: StreamBuilder<Team?>(
            stream: Db.teamStream(team.id),
            initialData: team,
            builder: (context, snap) {
              final name = snap.data?.name ?? team.name;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TeamAvatar(
                    teamId: team.id,
                    name: name,
                    radius: 16,
                    heroTag: 'team-logo-${team.id}',
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
                ],
              );
            },
          ),
          actions: [
            if (_manage) ...[
              IconButton(
                tooltip: 'Rename team',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, team.name),
              ),
              IconButton(
                tooltip: 'Team logo',
                icon: const Icon(Icons.add_photo_alternate_outlined),
                onPressed: () => _logoSheet(context),
              ),
            ],
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Players'),
              Tab(text: 'Matches'),
              Tab(text: 'Results'),
            ],
          ),
        ),
        // Only the admin can add players; owners can edit/remove their own.
        floatingActionButton: canEdit
            ? FloatingActionButton.extended(
                onPressed: () => _addPlayer(context),
                icon: const Icon(Icons.person_add),
                label: const Text('Add player'),
              )
            : null,
        body: TabBarView(
          children: [
            StreamBuilder<List<Player>>(
              stream: Db.playersStream(team.id),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final players = snap.data!;
                if (players.isEmpty) {
                  return const EmptyState(
                    text: 'No players yet',
                    icon: Icons.person_outline,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 90),
                  itemCount: players.length,
                  itemBuilder: (_, i) {
                    final p = players[i];
                    return FadeSlideIn(
                      key: ValueKey(p.id),
                      index: i,
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 22,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primary,
                            foregroundColor: Colors.white,
                            child: Text(
                              '${p.jersey}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              p.role,
                              p.phone,
                            ].where((s) => s.isNotEmpty).join(' • '),
                          ),
                          onTap: _manage ? () => _editPlayer(context, p) : null,
                          trailing: _manage
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          _confirmDeletePlayer(context, p),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            _TeamMatches(team: team, completed: false, canEdit: canEdit),
            _TeamMatches(team: team, completed: true, canEdit: canEdit),
          ],
        ),
      ),
    );
  }
}

class _TeamMatches extends StatelessWidget {
  final Team team;
  final bool completed;
  final bool canEdit;
  const _TeamMatches({
    required this.team,
    required this.completed,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data!;
        final list = all
            .where((m) => m.involves(team.id) && m.completed == completed)
            .toList();
        return Column(
          children: [
            if (completed)
              Padding(
                padding: const EdgeInsets.all(12),
                child: RecordBar(matches: all, teamId: team.id),
              ),
            Expanded(
              child: MatchList(
                matches: completed ? list.reversed.toList() : list,
                myTeamId: team.id,
                // Admin gets the same options as the Matches tab; owners get the report.
                onTap: (m) => canEdit
                    ? showMatchActions(context, m)
                    : Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MatchDetailScreen(match: m, myTeamId: team.id),
                        ),
                      ),
                countLabel: completed
                    ? 'Completed matches'
                    : 'Upcoming matches',
                emptyText: completed
                    ? 'No completed matches'
                    : 'No upcoming matches',
              ),
            ),
          ],
        );
      },
    );
  }
}
