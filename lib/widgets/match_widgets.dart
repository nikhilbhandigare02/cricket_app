import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import 'animations.dart';
import 'team_avatar.dart';

final _dateFmt = DateFormat('EEE, dd MMM yyyy');
final _timeFmt = DateFormat('hh:mm a');

String fmtDate(DateTime d) => _dateFmt.format(d);
String fmtTime(DateTime d) => _timeFmt.format(d);

/// Centered icon + message for lists with nothing in them yet.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.text, this.icon = Icons.sports_cricket});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

class MatchTile extends StatelessWidget {
  final MatchGame match;

  /// When set, the badge shows Win/Loss/Draw for this team.
  final String? myTeamId;
  final VoidCallback? onTap;

  const MatchTile({super.key, required this.match, this.myTeamId, this.onTap});

  Widget _team(BuildContext context, String id, String name) {
    final scheme = Theme.of(context).colorScheme;
    final isWinner = match.completed && match.winnerId == id;
    return Expanded(
      child: Column(children: [
        TeamAvatar(
          teamId: id,
          name: name,
          radius: 24,
          background: isWinner ? Colors.green : scheme.primaryContainer,
          foreground: isWinner ? Colors.white : scheme.onPrimaryContainer,
          ring: isWinner ? Colors.green : null,
        ),
        const SizedBox(height: 6),
        Text(name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        if (isWinner)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.emoji_events, size: 16, color: Colors.amber),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = match.isLive
        ? 'LIVE'
        : myTeamId != null
            ? match.statusFor(myTeamId!)
            : (match.completed ? 'Completed' : 'Upcoming');
    final color = switch (status) {
      'LIVE' => Colors.red,
      'Win' => Colors.green,
      'Loss' => Colors.red,
      'Draw' => Colors.orange,
      'Completed' => Colors.blueGrey,
      _ => Colors.blue,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(children: [
          Container(
            color: color.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              Icon(Icons.event, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${fmtDate(match.dateTime)}  •  ${fmtTime(match.dateTime)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                child: status == 'LIVE'
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        PulseDot(color: Colors.white, size: 8),
                        SizedBox(width: 3),
                        Text('LIVE',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ])
                    : Text(status,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _team(context, match.teamAId, match.teamAName),
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 6, right: 6),
                child: match.completed || match.isLive
                    ? Text('${match.scoreA} - ${match.scoreB}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24))
                    : Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                        child: const Text('VS',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      ),
              ),
              _team(context, match.teamBId, match.teamBName),
            ]),
          ),
          if (match.venue.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(match.venue, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// A scrollable list of matches with a count header and a date filter: chips
/// for each day that has matches, plus a calendar button for any other date.
class MatchList extends StatefulWidget {
  final List<MatchGame> matches;
  final String emptyText;
  final String? myTeamId;
  final void Function(MatchGame)? onTap;

  /// When set, a header shows the total, e.g. "Upcoming matches: 66".
  final String? countLabel;

  const MatchList({
    super.key,
    required this.matches,
    required this.emptyText,
    this.myTeamId,
    this.onTap,
    this.countLabel,
  });

  @override
  State<MatchList> createState() => _MatchListState();
}

class _MatchListState extends State<MatchList> {
  DateTime? _day; // null = all dates

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickDay(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _day = _dateOnly(d));
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.matches;
    if (all.isEmpty) return EmptyState(text: widget.emptyText, icon: Icons.event_busy);
    final scheme = Theme.of(context).colorScheme;

    // Days that have matches, in list order, with how many matches each has.
    final counts = <DateTime, int>{};
    for (final m in all) {
      counts.update(_dateOnly(m.dateTime), (c) => c + 1, ifAbsent: () => 1);
    }
    final days = counts.keys.toList();
    final shown = _day == null ? all : all.where((m) => _dateOnly(m.dateTime) == _day).toList();
    final dayFmt = DateFormat('EEE, d MMM');

    return Column(children: [
      if (widget.countLabel != null)
        Container(
          width: double.infinity,
          color: scheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.format_list_numbered, size: 18, color: scheme.onPrimaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedValueText(
                  _day == null
                      ? '${widget.countLabel}: ${all.length}'
                      : '${widget.countLabel} on ${dayFmt.format(_day!)}: ${shown.length} (of ${all.length})',
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ]),
        ),
      SizedBox(
        height: 52,
        child: Row(children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All dates'),
                    selected: _day == null,
                    onSelected: (_) => setState(() => _day = null),
                  ),
                ),
                for (final d in days)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${dayFmt.format(d)} (${counts[d]})'),
                      selected: _day == d,
                      onSelected: (_) => setState(() => _day = _day == d ? null : d),
                    ),
                  ),
                // A date picked from the calendar that has no matches.
                if (_day != null && !counts.containsKey(_day))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text(dayFmt.format(_day!)),
                      selected: true,
                      onDeleted: () => setState(() => _day = null),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _pickDay(_day ?? days.first),
          ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? const EmptyState(text: 'No matches on this date', icon: Icons.event_busy)
            : ListView.builder(
                padding: const EdgeInsets.only(top: 2, bottom: 90),
                itemCount: shown.length,
                itemBuilder: (_, i) => FadeSlideIn(
                  key: ValueKey(shown[i].id),
                  index: i,
                  child: MatchTile(
                    match: shown[i],
                    myTeamId: widget.myTeamId,
                    onTap: widget.onTap == null ? null : () => widget.onTap!(shown[i]),
                  ),
                ),
              ),
      ),
    ]);
  }
}

/// Win/Loss summary for a team across completed matches.
class RecordBar extends StatelessWidget {
  final List<MatchGame> matches;
  final String teamId;
  const RecordBar({super.key, required this.matches, required this.teamId});

  @override
  Widget build(BuildContext context) {
    final done = matches.where((m) => m.involves(teamId) && m.completed).toList();
    final w = done.where((m) => m.winnerId == teamId).length;
    final d = done.where((m) => m.winnerId == null).length;
    final l = done.length - w - d;
    Widget stat(String label, int v, Color c) => Column(children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Text('$v', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c)),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ]);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            stat('Played', done.length, Colors.blueGrey),
            stat('Won', w, Colors.green),
            stat('Lost', l, Colors.red),
            stat('Draw', d, Colors.orange),
          ],
        ),
      ),
    );
  }
}
