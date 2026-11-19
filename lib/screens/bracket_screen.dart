import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/scorecard.dart';
import '../models/standings.dart';
import '../services/db.dart';
import '../widgets/form_widgets.dart';
import '../widgets/match_actions.dart';
import '../widgets/match_widgets.dart';

/// Knockout bracket, built automatically from the points table. Admin ([canEdit])
/// can edit each slot (teams, date, venue) and
/// open its scorecard; winners move to the next round automatically when a
/// score is saved. Owners get a read-only view.
class BracketView extends StatelessWidget {
  final bool canEdit;
  const BracketView({super.key, required this.canEdit});

  /// Column headings of the IPL playoff layout.
  static String roundName(int round) => switch (round) {
        0 => 'Top 4 of the table',
        1 => 'Qualifier 2',
        2 => 'Final',
        _ => 'Round ${round + 1}',
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BracketSlot>>(
      stream: Db.bracketStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final slots = snap.data!;
        if (slots.isEmpty) {
          return SingleChildScrollView(
            child: Column(children: [
              const _Standings(),
              // Admin opening this screen builds the bracket from the league matches.
              if (canEdit) const _AutoCreate(),
              const EmptyState(
                  icon: Icons.account_tree,
                  text: 'The IPL-style playoffs (Qualifier 1, Eliminator, Qualifier 2, Final) are created from the points table '
                      'once league matches are scheduled.'),
            ]),
          );
        }
        final finalSlot = slots.last;
        return Column(children: [
          if (finalSlot.winnerName != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.emoji_events, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Champion: ${finalSlot.winnerName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (canEdit) const _AutoCreate(),
                if (canEdit) const _ReseedButton(),
                const _Standings(),
                _PlayoffFlow(slots: slots, canEdit: canEdit),
                const _Standings(playoffTeams: true),
                const SizedBox(height: 12),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

/// IPL playoffs laid out top to bottom: Qualifier 1 and the Eliminator side by
/// side, then Qualifier 2, then the Final, with arrows showing who goes where.
class _PlayoffFlow extends StatelessWidget {
  final List<BracketSlot> slots;
  final bool canEdit;
  const _PlayoffFlow({required this.slots, required this.canEdit});

  BracketSlot? _slot(String id) => slots.where((s) => s.id == id).firstOrNull;

  Widget _card(String id) {
    final s = _slot(id);
    return s == null ? const SizedBox.shrink() : _SlotCard(slot: s, canEdit: canEdit);
  }

  Widget _arrow(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          const Icon(Icons.arrow_downward, size: 20, color: Colors.grey),
          Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Text('Playoffs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _card('r0m0')),
          const SizedBox(width: 8),
          Expanded(child: _card('r0m1')),
        ]),
        _arrow(context, 'Loser of Qualifier 1 and winner of Eliminator'),
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: _card('r1m0'))),
        _arrow(context, 'Winners of Qualifier 1 and Qualifier 2'),
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: _card('r2m0'))),
      ]),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final BracketSlot slot;
  final bool canEdit;
  const _SlotCard({required this.slot, required this.canEdit});

  /// Title, what feeds each side, and where the teams go next (IPL playoffs).
  static (String, String, String, String) _info(BracketSlot s) => switch (s.id) {
        'r0m0' => ('Qualifier 1', 'Table #1', 'Table #2',
            'Winner to the Final, loser gets Qualifier 2'),
        'r0m1' => ('Eliminator', 'Table #3', 'Table #4',
            'Loser is out, winner plays Qualifier 2'),
        'r1m0' => ('Qualifier 2', 'Loser of Qualifier 1', 'Winner of Eliminator',
            'Winner goes to the Final'),
        'r2m0' => ('Final', 'Winner of Qualifier 1', 'Winner of Qualifier 2', 'Champions'),
        _ => ('Match ${s.round + 1}.${s.index + 1}', 'TBD', 'TBD', ''),
      };

  Widget _team(String? id, String? name) {
    final isWinner = id != null && id == slot.winnerId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text(
            name ?? 'TBD',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
              color: name == null ? Colors.grey : null,
            ),
          ),
        ),
        if (isWinner) const Icon(Icons.check_circle, color: Colors.green, size: 18),
      ]),
    );
  }

  Future<void> _openScorecard(BuildContext context) async {
    final m = await Db.matchById(slot.matchId!);
    if (m == null || !context.mounted) return;
    await showMatchActions(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final (title, labelA, labelB, hint) = _info(slot);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit && slot.matchId != null ? () => _openScorecard(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
              ),
              if (canEdit && slot.winnerId == null)
                InkWell(
                  onTap: () => _editSlotDialog(context, slot),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit, size: 14),
                      SizedBox(width: 4),
                      Text('Edit', style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
            ]),
            _team(slot.teamAId, slot.teamAName ?? labelA),
            const Divider(height: 8),
            _team(slot.teamBId, slot.teamBName ?? labelB),
            if (slot.scoreText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Score: ${slot.scoreText}', style: Theme.of(context).textTheme.bodySmall),
              )
            else if (slot.matchId != null)
              // Padding(
              //   padding: const EdgeInsets.only(top: 4),
              //   child: Text(
              //     'Match scheduled${canEdit ? ' - tap to score' : ''}',
              //     style: Theme.of(context).textTheme.bodySmall,
              //   ),
              // ),
            if (hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(hint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Admin: change the two teams of a bracket slot and the date/venue of its
/// match. The bracket then stays as edited until "Re-seed from points table".
Future<void> _editSlotDialog(BuildContext context, BracketSlot slot) async {
  final teams = await Db.teamsStream().first;
  final existing = slot.matchId == null ? null : await Db.matchById(slot.matchId!);
  if (!context.mounted) return;
  var when = existing?.dateTime ?? DateTime.now().add(const Duration(days: 1));
  if (existing == null) when = DateTime(when.year, when.month, when.day, 9, 0);
  final venue = TextEditingController(text: existing?.venue ?? '');
  String? a = teams.any((t) => t.id == slot.teamAId) ? slot.teamAId : null;
  String? b = teams.any((t) => t.id == slot.teamBId) ? slot.teamBId : null;
  final ok = await showFormDialog(
    context,
    title: 'Edit match',
    icon: Icons.edit,
    builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, children: [
      for (final side in [0, 1])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            initialValue: side == 0 ? a : b,
            isExpanded: true,
            decoration: InputDecoration(labelText: side == 0 ? 'Team A' : 'Team B'),
            items: [for (final t in teams) DropdownMenuItem(value: t.id, child: Text(t.name))],
            onChanged: (v) => setS(() => side == 0 ? a = v : b = v),
          ),
        ),
      OutlinedButton.icon(
        icon: const Icon(Icons.event),
        label: Text('${fmtDate(when)}  ${fmtTime(when)}'),
        onPressed: () async {
          final d = await showDatePicker(
              context: ctx, initialDate: when, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d == null || !ctx.mounted) return;
          final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
          if (t == null) return;
          setS(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
        },
      ),
      formField(venue, 'Venue', Icons.place_outlined),
    ]),
  );
  if (ok != true) return;
  if (a == null || b == null || a == b) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick two different teams')));
    }
    return;
  }
  await Db.updateBracketSlot(slot,
      a: teams.firstWhere((t) => t.id == a),
      b: teams.firstWhere((t) => t.id == b),
      when: when,
      venue: venue.text.trim());
}

/// Builds the bracket (and seeds/schedules it if the league is done) once shown.
class _AutoCreate extends StatefulWidget {
  const _AutoCreate();

  @override
  State<_AutoCreate> createState() => _AutoCreateState();
}

class _AutoCreateState extends State<_AutoCreate> {
  @override
  void initState() {
    super.initState();
    Db.refreshBracket();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Admin button: throws away manual edits and rebuilds the bracket from the table.
class _ReseedButton extends StatelessWidget {
  const _ReseedButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Re-seed from points table'),
          onPressed: () async {
            await Db.resetBracketToTable();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bracket re-seeded from the points table')));
            }
          },
        ),
      ),
    );
  }
}

/// League table shown above the bracket once round-robin matches exist.
class _Standings extends StatefulWidget {
  /// true: show the four teams that make the playoffs (top 4 of the table) instead of the full table.
  final bool playoffTeams;
  const _Standings({this.playoffTeams = false});

  @override
  State<_Standings> createState() => _StandingsState();
}

class _StandingsState extends State<_Standings> {
  final _innings = <String, Map<String, Innings>>{};
  final _loaded = <String, String>{};
  final _loading = <String>{};

  /// Loads the innings of completed league matches once, for the run rate.
  Future<void> _load(List<MatchGame> matches) async {
    for (final m in matches) {
      if (!m.completed || m.bracketSlot != null) continue;
      // Reload when the score changes (match rescored or reopened).
      final key = '${m.id}:${m.scoreA}:${m.scoreB}';
      if (_loaded[m.id] == key || !_loading.add(key)) continue;
      final a = await Db.loadInnings(m.id, m.teamAId);
      final b = await Db.loadInnings(m.id, m.teamBId);
      _loaded[m.id] = key;
      _innings[m.id] = {m.teamAId: a, m.teamBId: b};
      if (mounted) setState(() {});
    }
  }

  /// The top four of the table, picked automatically: a green Q once a team is
  /// sure of its place, otherwise "Projected" while the league is still running.
  Widget _playoffTeamsCard(BuildContext context, List<Standing> rows, Set<String> qualified, List<MatchGame> matches) {
    final top = rows.take(4).toList();
    final leagueDone = matches.where((m) => m.bracketSlot == null).isNotEmpty &&
        matches.where((m) => m.bracketSlot == null).every((m) => m.completed);
    const roles = ['Qualifier 1', 'Qualifier 1', 'Eliminator', 'Eliminator'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified, color: Colors.green),
            const SizedBox(width: 8),
            Text(leagueDone ? 'Qualified for the playoffs' : 'Playoff teams (from the points table)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          const SizedBox(height: 4),
          Text(leagueDone ? 'Top 4 teams of the final table.' : 'Updates automatically as matches finish.',
              style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 18),
          if (top.isEmpty) const Text('No teams yet'),
          for (var i = 0; i < top.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
              title: Text(top[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${top[i].points} pts  •  NRR ${top[i].nrr >= 0 ? '+' : ''}${top[i].nrr.toStringAsFixed(3)}  •  ${roles[i]}'),
              trailing: qualified.contains(top[i].id)
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(6)),
                      child: const Text('Q', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  : const Text('Projected', style: TextStyle(color: Colors.grey)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: Db.teamsStream(),
      builder: (context, teamSnap) => StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        final matches = snap.data ?? const <MatchGame>[];
        _load(matches);
        // Every team is listed from the start, on 0, even before any match.
        final rows = computeStandings(matches, innings: _innings, teams: teamSnap.data ?? const []);
        if (rows.isEmpty) return const SizedBox.shrink();
        final qualified = qualifiedTeamIds(rows, matches);
        if (widget.playoffTeams) return _playoffTeamsCard(context, rows, qualified, matches);
        Widget cell(String t, {int flex = 1, bool bold = false, TextAlign align = TextAlign.center}) => Expanded(
              flex: flex,
              child: Text(t,
                  textAlign: align,
                  style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            );
        return Card(
          child: ExpansionTile(
            initiallyExpanded: true,
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.leaderboard),
            title: const Text('League table', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Win 2, draw 1  •  Q = qualified for the playoffs'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Row(children: [
                cell('Team', flex: 4, bold: true, align: TextAlign.left),
                cell('P', bold: true),
                cell('W', bold: true),
                cell('L', bold: true),
                cell('D', bold: true),
                cell('NRR', flex: 2, bold: true),
                cell('Pts', bold: true),
              ]),
              const Divider(height: 12),
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      flex: 4,
                      child: Row(children: [
                        Flexible(child: Text('${i + 1}. ${rows[i].name}', overflow: TextOverflow.ellipsis)),
                        if (qualified.contains(rows[i].id))
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.green.shade600, borderRadius: BorderRadius.circular(4)),
                            child: const Text('Q',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ]),
                    ),
                    cell('${rows[i].played}'),
                    cell('${rows[i].won}'),
                    cell('${rows[i].lost}'),
                    cell('${rows[i].drawn}'),
                    cell('${rows[i].nrr >= 0 ? '+' : ''}${rows[i].nrr.toStringAsFixed(3)}', flex: 2),
                    cell('${rows[i].points}', bold: true),
                  ]),
                ),
            ],
          ),
        );
      },
      ),
    );
  }
}
