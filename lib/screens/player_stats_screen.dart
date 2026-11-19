import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/player_stats.dart';
import '../models/scorecard.dart';
import '../services/db.dart';
import '../widgets/match_widgets.dart';

/// Leaderboards for every player: runs, wickets and all-rounders. Shown to the
/// admin and to owners ([myTeamIds] highlights an owner's own players).
class PlayerStatsView extends StatefulWidget {
  final Set<String> myTeamIds;
  const PlayerStatsView({super.key, this.myTeamIds = const {}});

  @override
  State<PlayerStatsView> createState() => _PlayerStatsViewState();
}

class _PlayerStatsViewState extends State<PlayerStatsView> {
  final _innings = <String, Map<String, Innings>>{};
  final _loaded = <String, String>{};
  final _loading = <String>{};
  bool _onlyMine = false;

  Future<void> _load(List<MatchGame> matches) async {
    for (final m in matches) {
      if (!m.completed) continue;
      final key = '${m.id}:${m.scoreA}:${m.scoreB}';
      if (_loaded[m.id] == key || !_loading.add(key)) continue;
      final a = await Db.loadInnings(m.id, m.teamAId);
      final b = await Db.loadInnings(m.id, m.teamBId);
      _loaded[m.id] = key;
      _innings[m.id] = {m.teamAId: a, m.teamBId: b};
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        _load(snap.data!);
        var all = computePlayerStats(snap.data!, _innings);
        if (_onlyMine) all = all.where((p) => widget.myTeamIds.contains(p.teamId)).toList();

        final batters = all.where((p) => p.batted).toList()
          ..sort((a, b) => b.runs != a.runs ? b.runs.compareTo(a.runs) : b.strikeRate.compareTo(a.strikeRate));
        final bowlers = all.where((p) => p.bowled).toList()
          ..sort((a, b) {
            if (b.wickets != a.wickets) return b.wickets.compareTo(a.wickets);
            return a.economy.compareTo(b.economy);
          });
        final allRounders = all.where((p) => p.isAllRounder).toList()
          ..sort((a, b) {
            if (b.allRounderPoints != a.allRounderPoints) return b.allRounderPoints.compareTo(a.allRounderPoints);
            return b.wickets.compareTo(a.wickets); // tie: more wickets first
          });

        return DefaultTabController(
          length: 3,
          child: Column(children: [
            if (widget.myTeamIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('All players'), icon: Icon(Icons.groups)),
                    ButtonSegment(value: true, label: Text('My team'), icon: Icon(Icons.person)),
                  ],
                  selected: {_onlyMine},
                  onSelectionChanged: (v) => setState(() => _onlyMine = v.first),
                ),
              ),
            const TabBar(tabs: [Tab(text: 'Runs'), Tab(text: 'Wickets'), Tab(text: 'All-rounders')]),
            Expanded(
              child: TabBarView(children: [
                _list(batters, Icons.sports_cricket, 'No runs scored yet', (p) => '${p.runs}', 'runs',
                    (p) => '${p.teamName}  •  ${p.innings} inn  •  HS ${p.highest}  •  Avg ${p.average.toStringAsFixed(1)}  •  '
                        'SR ${p.strikeRate.toStringAsFixed(1)}  •  4s ${p.fours}  6s ${p.sixes}'),
                _list(bowlers, Icons.sports_baseball, 'No wickets yet', (p) => '${p.wickets}', 'wkts',
                    (p) => '${p.teamName}  •  ${ballsToOvers(p.ballsBowled)} ov  •  ${p.runsConceded} R  •  '
                        'Econ ${p.economy.toStringAsFixed(2)}  •  Best ${p.bestWickets}/${p.bestRuns}'
                        '${p.runOuts > 0 ? '  •  RO ${p.runOuts}' : ''}'),
                _list(allRounders, Icons.stars, 'No all-rounders yet (needs runs and wickets)',
                    (p) => '${p.allRounderPoints}', 'pts',
                    (p) => '${p.teamName}  •  ${p.matches} matches\n'
                        'Runs ${p.runs} + Wickets ${p.wickets} x 20 (${p.wickets * 20}) = ${p.allRounderPoints}'),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _list(List<PlayerStat> list, IconData icon, String empty, String Function(PlayerStat) big,
      String unit, String Function(PlayerStat) sub) {
    if (list.isEmpty) return EmptyState(text: empty, icon: icon);
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        final mine = widget.myTeamIds.contains(p.teamId);
        return Card(
          color: mine ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
          child: ListTile(
            dense: true,
            isThreeLine: sub(p).contains('\n'),
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(sub(p)),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(big(p), style: Theme.of(context).textTheme.titleLarge),
              Text(unit, style: const TextStyle(fontSize: 10)),
            ]),
          ),
        );
      },
    );
  }
}
