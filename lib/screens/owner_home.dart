import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/db.dart';
import '../widgets/match_widgets.dart';
import '../widgets/live_banner.dart';
import '../widgets/owner_edit.dart';
import '../widgets/team_avatar.dart';
import 'bracket_screen.dart';
import 'match_detail_screen.dart';
import 'player_stats_screen.dart';
import 'team_detail.dart';

/// Read-only view for an owner: own team(s), upcoming matches and results.
class OwnerHome extends StatefulWidget {
  final String ownerId;
  final String ownerName;
  const OwnerHome({super.key, required this.ownerId, required this.ownerName});

  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int _tab = 0;
  bool _allMatches = false; // false = only my team's matches, true = every match
  late String _name = widget.ownerName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: Db.teamsOfOwner(widget.ownerId),
      builder: (context, teamSnap) {
        final teams = teamSnap.data ?? [];
        final ids = teams.map((t) => t.id).toSet();
        return Scaffold(
          appBar: AppBar(
            title: Text('Hi, $_name'),
            actions: [
              IconButton(
                tooltip: 'My details',
                icon: const Icon(Icons.manage_accounts),
                onPressed: () async {
                  final saved = await showOwnerEditDialog(context, widget.ownerId);
                  if (saved != null && mounted) setState(() => _name = saved);
                },
              ),
              IconButton(icon: const Icon(Icons.logout), onPressed: Db.signOut),
            ],
          ),
          body: !teamSnap.hasData
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  // Matches being scored right now (any team); tap to follow live.
                  LiveNowBanner(myTeamIds: ids),
                  Expanded(
                    child: IndexedStack(index: _tab, children: [
                      _myTeams(teams),
                      _matches(teams, ids, completed: false),
                      _matches(teams, ids, completed: true),
                      const BracketView(canEdit: false),
                      PlayerStatsView(myTeamIds: ids),
                    ]),
                  ),
                ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.groups), label: 'My Team'),
              NavigationDestination(icon: Icon(Icons.event), label: 'Matches'),
              NavigationDestination(icon: Icon(Icons.emoji_events), label: 'Results'),
              NavigationDestination(icon: Icon(Icons.account_tree), label: 'Bracket'),
              NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Players'),
            ],
          ),
        );
      },
    );
  }

  Widget _myTeams(List<Team> teams) {
    if (teams.isEmpty) return const EmptyState(text: 'No team assigned yet', icon: Icons.groups);
    return ListView(
      padding: const EdgeInsets.only(top: 6),
      children: teams
          .map((t) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: TeamAvatar(
                    teamId: t.id,
                    name: t.name,
                    radius: 26,
                    heroTag: 'team-logo-${t.id}',
                    background: Theme.of(context).colorScheme.primary,
                    foreground: Colors.white,
                  ),
                  title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text('View players, matches and results'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => TeamDetailScreen(team: t, canEdit: false, canManage: true))),
                ),
              ))
          .toList(),
    );
  }

  Widget _matches(List<Team> teams, Set<String> ids, {required bool completed}) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final list = snap.data!
            .where((m) =>
                m.completed == completed &&
                (_allMatches || ids.contains(m.teamAId) || ids.contains(m.teamBId)))
            .toList();
        final shown = completed ? list.reversed.toList() : list;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('My team'), icon: Icon(Icons.person)),
                ButtonSegment(value: true, label: Text('All matches'), icon: Icon(Icons.groups)),
              ],
              selected: {_allMatches},
              onSelectionChanged: (v) => setState(() => _allMatches = v.first),
            ),
          ),
          Expanded(
            child: MatchList(
              matches: shown,
              // For a single-team owner show Win/Loss for that team (own matches only).
              myTeamId: !_allMatches && teams.length == 1 ? teams.first.id : null,
              onTap: (m) => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchDetailScreen(
                    match: m,
                    myTeamId: ids.contains(m.teamAId)
                        ? m.teamAId
                        : (ids.contains(m.teamBId) ? m.teamBId : null),
                  ),
                ),
              ),
              countLabel: completed
                  ? (_allMatches ? 'All completed matches' : 'Completed matches')
                  : (_allMatches ? 'All upcoming matches' : 'Upcoming matches'),
              emptyText: completed ? 'No completed matches' : 'No upcoming matches',
            ),
          ),
        ]);
      },
    );
  }
}
