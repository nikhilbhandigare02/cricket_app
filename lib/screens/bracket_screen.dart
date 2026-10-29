import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/db.dart';
import '../widgets/form_widgets.dart';
import '../widgets/match_actions.dart';
import '../widgets/match_widgets.dart';

/// Knockout bracket. Admin ([canEdit]) can schedule each pairing's match and
/// open its scorecard; winners move to the next round automatically when a
/// score is saved. Owners get a read-only view.
class BracketView extends StatelessWidget {
  final bool canEdit;
  const BracketView({super.key, required this.canEdit});

  static String roundName(int round, int totalRounds) {
    final fromEnd = totalRounds - 1 - round;
    return switch (fromEnd) {
      0 => 'Final',
      1 => 'Semi-finals',
      2 => 'Quarter-finals',
      _ => 'Round ${round + 1}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BracketSlot>>(
      stream: Db.bracketStream(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final slots = snap.data!;
        if (slots.isEmpty) {
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            EmptyState(
                icon: Icons.account_tree,
                text: canEdit
                    ? 'No bracket yet.\nTap "Create bracket".'
                    : 'The admin has not created a bracket yet.'),
            if (canEdit) const _DeleteTournamentButton(),
          ]);
        }
        final totalRounds = slots.last.round + 1;
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
                if (canEdit) const _DeleteTournamentButton(),
                const _Standings(),
                SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var r = 0; r < totalRounds; r++)
                    SizedBox(
                      width: 230,
                      child: Column(children: [
                        Text(roundName(r, totalRounds),
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final s in slots.where((s) => s.round == r))
                          Padding(
                            // Space later rounds out so they sit between their feeders.
                            padding: EdgeInsets.symmetric(vertical: 6 + 70.0 * ((1 << r) - 1)),
                            child: _SlotCard(slot: s, canEdit: canEdit),
                          ),
                      ]),
                    ),
                ]),
              ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  final BracketSlot slot;
  final bool canEdit;
  const _SlotCard({required this.slot, required this.canEdit});

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
    final bye = slot.winnerId != null &&
        slot.matchId == null &&
        (slot.teamAId == null || slot.teamBId == null);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit && slot.matchId != null ? () => _openScorecard(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _team(slot.teamAId, slot.teamAName ?? (bye ? 'BYE' : null)),
            const Divider(height: 8),
            _team(slot.teamBId, slot.teamBName ?? (bye ? 'BYE' : null)),
            if (slot.scoreText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Score: ${slot.scoreText}', style: Theme.of(context).textTheme.bodySmall),
              )
            else if (slot.matchId != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  canEdit ? 'Match scheduled - tap to score' : 'Match scheduled',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else if (canEdit && slot.ready && slot.winnerId == null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _scheduleDialog(context, slot),
                  child: const Text('Schedule match'),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

Future<void> _scheduleDialog(BuildContext context, BracketSlot slot) async {
  var when = DateTime.now().add(const Duration(days: 1));
  when = DateTime(when.year, when.month, when.day, 9, 0);
  final venue = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('${slot.teamAName} vs ${slot.teamBName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
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
          TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Schedule')),
        ],
      ),
    ),
  );
  if (ok == true) await Db.scheduleBracketMatch(slot, when, venue.text.trim());
}

/// Admin button: wipes the bracket and all matches so a fresh tournament can
/// be created (where every team plays every other team again).
class _DeleteTournamentButton extends StatelessWidget {
  const _DeleteTournamentButton();

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bracket & league?'),
        content: const Text(
          'This deletes the bracket, ALL matches (league and knockout) and their '
          'scorecards and results. Teams, players and owners are kept.\n\n'
          'Then tap "Create bracket" to start a new tournament where every team '
          'plays every other team.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Db.deleteTournament();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bracket and matches deleted. Create a new bracket.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete bracket & league'),
          onPressed: () => _delete(context),
        ),
      ),
    );
  }
}

/// One row of the league table.
class Standing {
  final String id;
  final String name;
  int played = 0, won = 0, lost = 0, drawn = 0, points = 0, diff = 0;
  Standing(this.id, this.name);
}

/// League table from the round-robin matches (those not part of the knockout
/// bracket). A win is 2 points, a draw 1; ties are split by run difference.
List<Standing> computeStandings(List<MatchGame> matches) {
  final rows = <String, Standing>{};
  Standing row(String id, String name) => rows.putIfAbsent(id, () => Standing(id, name));
  for (final m in matches) {
    if (m.bracketSlot != null) continue;
    final a = row(m.teamAId, m.teamAName);
    final b = row(m.teamBId, m.teamBName);
    if (!m.completed) continue;
    a.played++;
    b.played++;
    a.diff += m.scoreA - m.scoreB;
    b.diff += m.scoreB - m.scoreA;
    if (m.winnerId == null) {
      a.drawn++;
      b.drawn++;
      a.points++;
      b.points++;
    } else if (m.winnerId == m.teamAId) {
      a.won++;
      b.lost++;
      a.points += 2;
    } else {
      b.won++;
      a.lost++;
      b.points += 2;
    }
  }
  return rows.values.toList()
    ..sort((x, y) {
      if (x.points != y.points) return y.points.compareTo(x.points);
      if (x.diff != y.diff) return y.diff.compareTo(x.diff);
      return x.name.compareTo(y.name);
    });
}

/// League table shown above the bracket once round-robin matches exist.
class _Standings extends StatelessWidget {
  const _Standings();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        final rows = computeStandings(snap.data ?? const []);
        if (rows.isEmpty) return const SizedBox.shrink();
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
            subtitle: const Text('Every team plays every other team - win 2, draw 1'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Row(children: [
                cell('Team', flex: 4, bold: true, align: TextAlign.left),
                cell('P', bold: true),
                cell('W', bold: true),
                cell('L', bold: true),
                cell('D', bold: true),
                cell('Pts', bold: true),
              ]),
              const Divider(height: 12),
              for (var i = 0; i < rows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    cell('${i + 1}. ${rows[i].name}', flex: 4, align: TextAlign.left),
                    cell('${rows[i].played}'),
                    cell('${rows[i].won}'),
                    cell('${rows[i].lost}'),
                    cell('${rows[i].drawn}'),
                    cell('${rows[i].points}', bold: true),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Admin: pick the teams, whether every team should also play every other team
/// (round-robin league), and how the knockout is seeded. Rebuilds the bracket.
Future<void> createBracketDialog(BuildContext context) async {
  final teams = await Db.teamsStream().first;
  if (!context.mounted) return;
  if (teams.length < 2) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least 2 teams first')));
    return;
  }
  final selected = {for (final t in teams) t.id};
  var seeding = 'random';
  var roundRobin = true;
  var fresh = true;
  var start = DateTime.now().add(const Duration(days: 1));
  start = DateTime(start.year, start.month, start.day, 9, 0);
  final perDay = TextEditingController(text: '2');
  final slot = TextEditingController(text: '120');
  final venue = TextEditingController();
  const seedOptions = {
    'random': 'Random draw',
    'listed': 'Order listed below',
    'table': 'League table',
  };

  final ok = await showFormDialog(
    context,
    title: 'Create tournament',
    icon: Icons.account_tree,
    confirmLabel: 'Create',
    builder: (ctx, setS) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start fresh'),
          subtitle: const Text('Delete the old bracket and ALL existing matches first, '
              'so every pair of teams gets a new match'),
          value: fresh,
          onChanged: (v) => setS(() => fresh = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Every team plays every other team'),
          subtitle: const Text('Creates round-robin league matches for the picked teams'),
          value: roundRobin,
          onChanged: (v) => setS(() => roundRobin = v),
        ),
        if (roundRobin) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('Start: ${fmtDate(start)}  ${fmtTime(start)}'),
            onPressed: () async {
              final d = await showDatePicker(
                  context: ctx, initialDate: start, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (d == null || !ctx.mounted) return;
              final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(start));
              if (t == null) return;
              setS(() => start = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
          ),
          const SizedBox(height: 12),
          formField(perDay, 'Matches per day', Icons.today, type: TextInputType.number),
          formField(slot, 'Minutes between matches', Icons.timer_outlined, type: TextInputType.number),
          formField(venue, 'Venue', Icons.place_outlined),
        ],
        const Text('Knockout seeding'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final e in seedOptions.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: seeding == e.key,
              onSelected: (_) => setS(() => seeding = e.key),
            ),
        ]),
        const Divider(height: 24),
        const Text('Teams'),
        for (final t in teams)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(t.name),
            value: selected.contains(t.id),
            onChanged: (v) => setS(() => v == true ? selected.add(t.id) : selected.remove(t.id)),
          ),
      ],
    ),
  );
  if (ok != true) return;
  final picked = teams.where((t) => selected.contains(t.id)).toList();
  if (picked.length < 2) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick at least 2 teams')));
    }
    return;
  }

  final all = await Db.matchesStream().first;
  if (fresh && all.isNotEmpty) {
    if (!context.mounted) return;
    final sure = await confirmDelete(
      context,
      title: 'Delete ${all.length} existing matches?',
      message: '"Start fresh" deletes the old bracket and all ${all.length} matches, with their scores and '
          'scorecards, before the new tournament is created.',
      confirmLabel: 'Delete and create',
    );
    if (!sure) return;
  }
  // Seeding by table must read the results before a fresh start wipes them.
  final standings = computeStandings(all);
  final league = fresh ? <MatchGame>[] : all.where((m) => m.bracketSlot == null).toList();
  if (fresh) await Db.deleteTournament();
  if (seeding == 'table') {
    final order = {for (final (i, s) in standings.indexed) s.id: i};
    picked.sort((a, b) => (order[a.id] ?? 999).compareTo(order[b.id] ?? 999));
  } else if (seeding == 'random') {
    picked.shuffle();
  }
  await Db.createBracket(picked);
  var created = 0;
  if (roundRobin) {
    created = await Db.generateRoundRobin(
      allTeams: picked,
      existing: league,
      start: start,
      matchesPerDay: (int.tryParse(perDay.text) ?? 2).clamp(1, 50),
      slotMinutes: (int.tryParse(slot.text) ?? 120).clamp(15, 1440),
      venue: venue.text.trim(),
    );
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(roundRobin
            ? 'Bracket created and $created league matches scheduled'
            : 'Bracket created')));
  }
}
