import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/live_scoring_screen.dart';
import '../screens/match_detail_screen.dart';
import '../screens/scorecard_screen.dart';
import '../services/db.dart';
import 'form_widgets.dart';
import 'match_widgets.dart';

/// The admin's options for a match: live scoring, scorecard, score, reschedule,
/// delete. Used everywhere a match can be tapped so it always behaves the same.
Future<void> showMatchActions(BuildContext context, MatchGame m) async {
  await showModalBottomSheet(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('${m.teamAName} vs ${m.teamBName}', style: const TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.play_circle_fill),
          title: const Text('Live scoring (ball by ball)'),
          subtitle: const Text('Batters swap strike automatically'),
          onTap: () {
            Navigator.pop(sheet);
            Navigator.push(context, MaterialPageRoute(builder: (_) => LiveScoringScreen(match: m)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.sports_cricket),
          title: const Text('Scorecard (players, overs, wickets)'),
          onTap: () {
            Navigator.pop(sheet);
            Navigator.push(context, MaterialPageRoute(builder: (_) => ScorecardScreen(match: m)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('Match report'),
          onTap: () {
            Navigator.pop(sheet);
            Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(match: m)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.scoreboard),
          title: Text(m.completed ? 'Edit score' : 'Enter score / finish match'),
          onTap: () {
            Navigator.pop(sheet);
            _scoreDialog(context, m);
          },
        ),
        if (m.completed)
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text('Reopen (mark as upcoming)'),
            onTap: () async {
              Navigator.pop(sheet);
              final ok = await confirmDelete(
                context,
                title: 'Reopen this match?',
                message: 'The score and result of ${m.teamAName} vs ${m.teamBName} are reset to 0-0 and '
                    'the match goes back to Upcoming.',
                confirmLabel: 'Reopen',
              );
              if (ok) await Db.reopenMatch(m.id);
            },
          ),
        ListTile(
          leading: const Icon(Icons.edit_calendar),
          title: const Text('Change date / time / venue'),
          onTap: () {
            Navigator.pop(sheet);
            _rescheduleDialog(context, m);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Delete match', style: TextStyle(color: Colors.red)),
          onTap: () async {
            Navigator.pop(sheet);
            final ok = await confirmDelete(
              context,
              title: 'Delete this match?',
              message: '${m.teamAName} vs ${m.teamBName} will be deleted with its score and scorecard. '
                  'This cannot be undone.',
            );
            if (ok) await Db.deleteMatch(m.id);
          },
        ),
      ]),
    ),
  );
}

Future<void> _scoreDialog(BuildContext context, MatchGame m) async {
  final a = TextEditingController(text: m.completed ? '${m.scoreA}' : '');
  final b = TextEditingController(text: m.completed ? '${m.scoreB}' : '');
  final ok = await showFormDialog(
    context,
    title: 'Match score',
    icon: Icons.scoreboard,
    builder: (_, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: TextField(
          controller: a,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(labelText: m.teamAName),
        ),
      ),
      const Padding(padding: EdgeInsets.only(top: 14, left: 10, right: 10), child: Text('-', style: TextStyle(fontSize: 24))),
      Expanded(
        child: TextField(
          controller: b,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          decoration: InputDecoration(labelText: m.teamBName),
        ),
      ),
    ]),
  );
  if (ok != true) return;
  final sa = int.tryParse(a.text);
  final sb = int.tryParse(b.text);
  if (sa == null || sb == null) return;
  await Db.saveResult(m, sa, sb);
  if (sa == sb && m.bracketSlot != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Knockout match needs a winner - the bracket was not updated')));
  }
}

Future<DateTime?> pickDateTime(BuildContext context, DateTime initial) async {
  final d = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime(2100));
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

Future<void> _rescheduleDialog(BuildContext context, MatchGame m) async {
  var when = m.dateTime;
  final venue = TextEditingController(text: m.venue);
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Reschedule'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('${fmtDate(when)}  ${fmtTime(when)}'),
            onPressed: () async {
              final r = await pickDateTime(ctx, when);
              if (r != null) setS(() => when = r);
            },
          ),
          TextField(controller: venue, decoration: const InputDecoration(labelText: 'Venue')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok == true) await Db.updateSchedule(m.id, when, venue.text.trim());
}

