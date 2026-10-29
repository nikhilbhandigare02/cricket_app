import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/scorecard.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/match_widgets.dart';

/// Read-only match report: result, both teams' batting and bowling, extras.
/// [myTeamId] (an owner's own team) turns the banner into You won / You lost.
class MatchDetailScreen extends StatefulWidget {
  final MatchGame match;
  final String? myTeamId;
  const MatchDetailScreen({super.key, required this.match, this.myTeamId});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  // Everything updates live: the match, and both innings, are watched as streams.
  late MatchGame m = widget.match;
  late final _matchStream = Db.matchStream(widget.match.id);
  late final _inningsA = Db.inningsStream(widget.match.id, widget.match.teamAId);
  late final _inningsB = Db.inningsStream(widget.match.id, widget.match.teamBId);

  String _name(String id) => id == m.teamAId ? m.teamAName : m.teamBName;

  /// "X won by N runs" style line from the saved totals.
  String get _resultText {
    if (m.isLive) return 'Match in progress';
    if (!m.completed) return 'Match not played yet';
    if (m.winnerId == null) return 'Match drawn';
    final diff = (m.scoreA - m.scoreB).abs();
    return '${_name(m.winnerId!)} won by $diff run${diff == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MatchGame?>(
      stream: _matchStream,
      initialData: widget.match,
      builder: (context, matchSnap) {
        if (matchSnap.data != null) m = matchSnap.data!;
        return Scaffold(
          appBar: AppBar(title: Text('${m.teamAName} vs ${m.teamBName}')),
          body: StreamBuilder<Innings>(
            stream: _inningsA,
            builder: (context, a) => StreamBuilder<Innings>(
              stream: _inningsB,
              builder: (context, b) {
                if (a.hasError || b.hasError) {
                  return EmptyState(text: '${a.error ?? b.error}', icon: Icons.error_outline);
                }
                if (!a.hasData || !b.hasData) return const Center(child: CircularProgressIndicator());
                final innings = [a.data!, b.data!];
                final hasCard = innings.any((i) => i.bat.isNotEmpty || i.bowl.isNotEmpty);
                return ListView(
                  padding: const EdgeInsets.only(top: 6, bottom: 24),
                  children: [
                    if (m.isLive) _liveCard(context, innings),
                    _banner(context),
                    if (!hasCard)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: EmptyState(
                            text: 'No scorecard entered for this match', icon: Icons.scoreboard_outlined),
                      )
                    else
                      for (final inn in innings) _inningsCard(context, inn, innings.firstWhere((o) => o != inn)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// "LIVE" panel: running score, the two batters at the crease, the bowler and
  /// the balls of the current over. Updates as the admin scores.
  Widget _liveCard(BuildContext context, List<Innings> innings) {
    final bat = innings.firstWhere((i) => i.teamId == m.liveBatting, orElse: () => innings.first);
    BatRow? row(String id) {
      for (final r in bat.bat) {
        if (r.playerId == id) return r;
      }
      return null;
    }

    BowlRow? bowlRow;
    for (final r in bat.bowl) {
      if (r.playerId == m.liveBowlerId) bowlRow = r;
    }
    final crr = bat.balls == 0 ? 0.0 : bat.runs * 6 / bat.balls;
    final theme = Theme.of(context);
    Widget batter(String name, String id, bool onStrike) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(onStrike ? Icons.sports_cricket : Icons.person_outline, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$name${onStrike ? ' *' : ''}',
                  style: TextStyle(color: Colors.white, fontWeight: onStrike ? FontWeight.bold : FontWeight.normal)),
            ),
            Text('${row(id)?.runs ?? 0}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        );

    return Card(
      color: Colors.red.shade700,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const PulseDot(size: 9),
                const SizedBox(width: 3),
                Text('LIVE',
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_name(bat.teamId),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          AnimatedValueText('${bat.runs}/${bat.wickets}',
              style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          Text(
            'Overs ${ballsToOvers(bat.balls)}${m.liveMaxOvers > 0 ? ' / ${m.liveMaxOvers}' : ''}'
            '  •  Run rate ${crr.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70),
          ),
          const Divider(color: Colors.white24, height: 20),
          batter(m.liveStriker, m.liveStrikerId, true),
          batter(m.liveNonStriker, m.liveNonStrikerId, false),
          if (m.liveBowler.isNotEmpty) ...[
            const Divider(color: Colors.white24, height: 20),
            Row(children: [
              const Icon(Icons.sports_baseball, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(child: Text(m.liveBowler, style: const TextStyle(color: Colors.white))),
              if (bowlRow != null)
                Text(
                  '${ballsToOvers(bowlRow.balls)} ov  ${bowlRow.runs} R  ${bat.wicketsOf(bowlRow.playerId)} W',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
            ]),
          ],
          if (m.liveOver.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final b in m.liveOver)
                CircleAvatar(
                  radius: 14,
                  backgroundColor: b.contains('W') ? Colors.black87 : (b == '4' || b == '6' ? Colors.green : Colors.white),
                  foregroundColor: (b.contains('W') || b == '4' || b == '6') ? Colors.white : Colors.black87,
                  child: Text(b, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _banner(BuildContext context) {
    final my = widget.myTeamId;
    final status = (my != null && m.involves(my)) ? m.statusFor(my) : null;
    final color = switch (status) {
      'Win' => Colors.green,
      'Loss' => Colors.red,
      'Draw' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    final headline = switch (status) {
      'Win' => 'Your team won',
      'Loss' => 'Your team lost',
      'Draw' => 'Match drawn',
      _ => _resultText,
    };
    Widget team(String id, String name, int score) => Expanded(
          child: Column(children: [
            Text(name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(m.completed || m.isLive ? '$score' : '-',
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
            if (m.completed && m.winnerId == id) const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
          ]),
        );
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(headline, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          if (status != null && m.completed)
            Text(_resultText, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            team(m.teamAId, m.teamAName, m.scoreA),
            const Padding(
              padding: EdgeInsets.only(top: 30, left: 6, right: 6),
              child: Text('vs', style: TextStyle(color: Colors.white70)),
            ),
            team(m.teamBId, m.teamBName, m.scoreB),
          ]),
          const SizedBox(height: 10),
          Text('${fmtDate(m.dateTime)}  •  ${fmtTime(m.dateTime)}${m.venue.isEmpty ? '' : '  •  ${m.venue}'}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _inningsCard(BuildContext context, Innings inn, Innings other) {
    if (inn.bat.isEmpty && inn.bowl.isEmpty && other.bowl.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          color: theme.colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Text('${_name(inn.teamId)} batting',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text('${inn.runs}/${inn.wickets}', style: theme.textTheme.titleLarge),
            const SizedBox(width: 6),
            Text('(${ballsToOvers(inn.balls)} ov)'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _header(const ['Batter', 'Runs'], firstFlex: 4),
            if (inn.bat.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No batting entered')),
            for (final b in inn.bat)
              _row(
                [b.name, '${b.runs}'],
                firstFlex: 4,
                sub: b.isOut ? '${b.how}${b.bowlerName.isEmpty ? '' : ' b ${b.bowlerName}'}' : 'not out',
                subColor: b.isOut ? Colors.red.shade700 : Colors.green.shade700,
                boldIndexes: const {1},
              ),
            const SizedBox(height: 6),
            Text(
              'Extras ${inn.extras}  (Wd ${inn.wides}, Nb ${inn.noBalls}, B ${inn.byes}, Lb ${inn.legByes})',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            Text('Bowling - ${_name(inn.teamId == m.teamAId ? m.teamBId : m.teamAId)}',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _header(const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'], firstFlex: 4),
            if (inn.bowl.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No bowling entered')),
            for (final b in inn.bowl)
              _row(
                [
                  b.name,
                  ballsToOvers(b.balls),
                  '${b.maidens}',
                  '${b.runs}',
                  '${inn.wicketsOf(b.playerId)}',
                  b.economy.toStringAsFixed(1),
                ],
                firstFlex: 4,
                boldIndexes: const {4},
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _header(List<String> cols, {required int firstFlex}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          for (var i = 0; i < cols.length; i++)
            Expanded(
              flex: i == 0 ? firstFlex : 1,
              child: Text(cols[i],
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            ),
        ]),
      );

  Widget _row(
    List<String> cols, {
    required int firstFlex,
    String? sub,
    Color? subColor,
    Set<int> boldIndexes = const {},
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < cols.length; i++)
            Expanded(
              flex: i == 0 ? firstFlex : 1,
              child: i == 0
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cols[0], style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: subColor)),
                    ])
                  : Text(cols[i],
                      textAlign: TextAlign.right,
                      style: TextStyle(fontWeight: boldIndexes.contains(i) ? FontWeight.bold : FontWeight.normal)),
            ),
        ]),
      );
}
