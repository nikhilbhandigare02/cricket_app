import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/scorecard.dart';
import '../services/db.dart';
import '../widgets/form_widgets.dart';

/// State needed to take back the last ball.
class _Snap {
  final Map<String, dynamic> innings;
  final String striker, nonStriker, bowler, lastBowler;
  final List<String> over;
  final bool noBall;
  _Snap(this.innings, this.striker, this.nonStriker, this.bowler, this.lastBowler, this.over, this.noBall);
}

/// Ball-by-ball scoring. Two batters are at the crease (striker and
/// non-striker): odd runs swap them, even runs and boundaries keep them, the
/// ends of overs swap them, and a new batter always walks in when one is out.
/// Everything is written into the normal scorecard.
class LiveScoringScreen extends StatefulWidget {
  final MatchGame match;
  const LiveScoringScreen({super.key, required this.match});

  @override
  State<LiveScoringScreen> createState() => _LiveScoringScreenState();
}

class _LiveScoringScreenState extends State<LiveScoringScreen> {
  MatchGame get m => widget.match;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  late bool _complete = m.completed;
  late String _battingId = m.teamAId;
  int _maxOvers = 6;
  final _innings = <String, Innings>{};
  final _roster = <String, List<Player>>{};

  // At the crease right now.
  String _striker = '';
  String _nonStriker = '';
  String _bowler = '';
  String _lastBowler = '';
  List<String> _over = [];
  bool _noBall = false;
  final _undo = <_Snap>[];

  Innings get _cur => _innings[_battingId]!;
  String get _fieldingId => _battingId == m.teamAId ? m.teamBId : m.teamAId;
  String _teamName(String id) => id == m.teamAId ? m.teamAName : m.teamBName;

  BatRow? _batRow(String id) {
    for (final b in _cur.bat) {
      if (b.playerId == id) return b;
    }
    return null;
  }

  BowlRow? _bowlRow(String id) {
    for (final b in _cur.bowl) {
      if (b.playerId == id) return b;
    }
    return null;
  }

  Player _player(String teamId, String id) => _roster[teamId]!.firstWhere((p) => p.id == id);

  bool get _inningsOver => _cur.allOut || _cur.balls >= _maxOvers * 6;
  bool get _canScore =>
      !_inningsOver && _batRow(_striker) != null && _batRow(_nonStriker) != null && _bowlRow(_bowler) != null;

  // Every change is pushed to Firebase (after a short pause, so a quick run of
  // taps becomes one write) and owners watch it live.
  bool _started = false;
  Timer? _publishTimer;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (_started) _schedulePublish();
  }

  void _schedulePublish() {
    _publishTimer?.cancel();
    _publishTimer = Timer(const Duration(milliseconds: 400), _publish);
  }

  Future<void> _publish() async {
    if (!_started) return;
    try {
      await Db.publishLive(
        m,
        _innings[m.teamAId]!,
        _innings[m.teamBId]!,
        battingId: _battingId,
        strikerId: _striker,
        striker: _batRow(_striker)?.name ?? '',
        nonStrikerId: _nonStriker,
        nonStriker: _batRow(_nonStriker)?.name ?? '',
        bowlerId: _bowler,
        bowler: _bowlRow(_bowler)?.name ?? '',
        over: _over,
        maxOvers: _maxOvers,
      );
    } catch (_) {
      // Offline or rules problem: the next change tries again.
    }
  }

  @override
  void dispose() {
    _publishTimer?.cancel();
    if (_started) {
      _started = false;
      Db.endLive(m.id).catchError((_) {}); // stop showing the match as LIVE
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final id in [m.teamAId, m.teamBId]) {
      _innings[id] = await Db.loadInnings(m.id, id);
      _roster[id] = await Db.playersStream(id).first;
    }
    final n = _innings[m.teamAId]!.players;
    for (final i in _innings.values) {
      i.players = n;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!await _setup(_battingId) && mounted) Navigator.pop(context);
  }

  // ------------------------------------------------------------ dialogs

  Widget _picker(String label, List<Player> list, String value, Set<String> blocked, void Function(String) onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label|${list.isEmpty ? '' : list.first.id}|$value'),
        initialValue: list.any((p) => p.id == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final p in list)
            DropdownMenuItem(value: p.id, enabled: !blocked.contains(p.id), child: Text(p.name)),
        ],
        onChanged: (v) {
          if (v != null) onPick(v);
        },
      ),
    );
  }

  /// Choose the batting team, then the openers (from that team) and the opening
  /// bowler (from the other team). False if cancelled.
  Future<bool> _setup(String battingId) async {
    var team = battingId;
    var s = '';
    var n = '';
    var bw = '';
    final overs = TextEditingController(text: '$_maxOvers');

    // Pre-select whoever is already at the crease for that team's innings.
    void defaults() {
      final inn = _innings[team]!;
      final live = [for (final b in inn.bat) if (!b.isOut) b.playerId];
      s = live.isNotEmpty ? live[0] : '';
      n = live.length > 1 ? live[1] : '';
      bw = inn.bowl.isNotEmpty ? inn.bowl.last.playerId : '';
    }

    defaults();

    while (true) {
      final ok = await showFormDialog(
        context,
        title: 'Start innings',
        icon: Icons.sports_cricket,
        confirmLabel: 'Start',
        builder: (ctx, setS) {
          final fielding = team == m.teamAId ? m.teamBId : m.teamAId;
          final out = {for (final b in _innings[team]!.bat) if (b.isOut) b.playerId};
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: team,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Batting team'),
                items: [m.teamAId, m.teamBId]
                    .map((id) => DropdownMenuItem(value: id, child: Text(_teamName(id))))
                    .toList(),
                onChanged: (v) {
                  if (v == null || v == team) return;
                  setS(() {
                    team = v;
                    defaults(); // the player lists below belong to the new team
                  });
                },
              ),
            ),
            _picker('Striker', _roster[team]!, s, {...out, n}, (v) => setS(() => s = v)),
            _picker('Non-striker', _roster[team]!, n, {...out, s}, (v) => setS(() => n = v)),
            _picker('Opening bowler (${_teamName(fielding)})', _roster[fielding]!, bw, const {},
                (v) => setS(() => bw = v)),
            formField(overs, 'Overs per innings', Icons.timer_outlined, type: TextInputType.number),
          ]);
        },
      );
      if (ok != true) return false;
      if (s.isNotEmpty && n.isNotEmpty && bw.isNotEmpty && s != n) break;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pick two different batters and a bowler')));
      }
    }

    final fielding = team == m.teamAId ? m.teamBId : m.teamAId;
    setState(() {
      _started = true; // from here on every change is published
      _battingId = team;
      _maxOvers = (int.tryParse(overs.text) ?? 6).clamp(1, 50);
      _striker = s;
      _nonStriker = n;
      _bowler = bw;
      _lastBowler = '';
      _over = [];
      _noBall = false;
      _undo.clear();
      for (final id in [s, n]) {
        if (_batRow(id) == null) {
          final p = _player(team, id);
          _cur.bat.add(BatRow(playerId: p.id, name: p.name));
        }
      }
      if (_bowlRow(bw) == null) {
        final p = _player(fielding, bw);
        _cur.bowl.add(BowlRow(playerId: p.id, name: p.name));
      }
    });
    return true;
  }

  /// Next bowler (the over just finished cannot be bowled again straight away).
  Future<void> _pickBowler({bool forced = true}) async {
    var pick = '';
    final list = _roster[_fieldingId]!;
    final blocked = forced && _lastBowler.isNotEmpty ? {_lastBowler} : <String>{};
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: !forced,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(forced ? 'Over complete - next bowler' : 'Change bowler'),
          content: _picker('Bowler', list, pick, blocked, (v) => setS(() => pick = v)),
          actions: [
            if (!forced) TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: pick.isEmpty ? null : () => Navigator.pop(ctx, true), child: const Text('Start over')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      if (_bowlRow(pick) == null) {
        final p = _player(_fieldingId, pick);
        _cur.bowl.add(BowlRow(playerId: p.id, name: p.name));
      }
      _bowler = pick;
    });
  }

  /// The batter who walks in after a wicket; null when nobody is left.
  Future<String?> _pickBatter() async {
    final used = {for (final b in _cur.bat) b.playerId};
    final available = [for (final p in _roster[_battingId]!) if (!used.contains(p.id)) p];
    if (available.isEmpty || _cur.bat.length >= _cur.players) return null;
    var pick = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Wicket - next batter'),
          content: _picker('New batter', available, pick, const {}, (v) => setS(() => pick = v)),
          actions: [
            FilledButton(onPressed: pick.isEmpty ? null : () => Navigator.pop(ctx), child: const Text('Send in')),
          ],
        ),
      ),
    );
    return pick;
  }

  // ------------------------------------------------------------ scoring

  void _push() {
    _undo.add(_Snap(_cur.toMap(), _striker, _nonStriker, _bowler, _lastBowler, [..._over], _noBall));
    if (_undo.length > 80) _undo.removeAt(0);
    _dirty = true;
  }

  void _takeBack() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    setState(() {
      _innings[_battingId] = Innings.fromMap(_battingId, s.innings);
      _striker = s.striker;
      _nonStriker = s.nonStriker;
      _bowler = s.bowler;
      _lastBowler = s.lastBowler;
      _over = s.over;
      _noBall = s.noBall;
    });
  }

  void _swap() {
    final t = _striker;
    _striker = _nonStriker;
    _nonStriker = t;
  }

  /// After a delivery: a completed over swaps the batters and asks for a bowler.
  Future<void> _afterBall(bool legal) async {
    if (legal && _cur.balls > 0 && _cur.balls % 6 == 0) {
      setState(() {
        _swap();
        _lastBowler = _bowler;
        _bowler = '';
        _over = [];
      });
      if (!_inningsOver && mounted) await _pickBowler();
    } else {
      setState(() {});
    }
  }

  Future<void> _runs(int runs) async {
    if (!_canScore) return;
    _push();
    final s = _batRow(_striker)!;
    final b = _bowlRow(_bowler)!;
    final legal = !_noBall;
    setState(() {
      s.runs += runs;
      b.runs += runs;
      if (legal) {
        b.balls++;
        _over.add('$runs');
      } else {
        _over[_over.length - 1] = runs > 0 ? 'Nb+$runs' : 'Nb'; // the no-ball's own runs
        _noBall = false;
      }
      if (runs.isOdd) _swap();
    });
    await _afterBall(legal);
  }

  void _wide() {
    if (!_canScore) return;
    _push();
    setState(() {
      _cur.wides++;
      _bowlRow(_bowler)!.runs++;
      _over.add('Wd');
    });
  }

  void _noBallTap() {
    if (!_canScore || _noBall) return;
    _push();
    setState(() {
      _cur.noBalls++;
      _bowlRow(_bowler)!.runs++;
      _over.add('Nb');
      _noBall = true; // the next run button scores off this no-ball
    });
  }

  /// One bye or leg bye: a legal ball, one run, batters cross.
  Future<void> _byeTap(bool legBye) async {
    if (!_canScore || _noBall) return;
    _push();
    setState(() {
      legBye ? _cur.legByes++ : _cur.byes++;
      _bowlRow(_bowler)!.balls++;
      _over.add(legBye ? 'Lb1' : 'B1');
      _swap();
    });
    await _afterBall(true);
  }

  Future<void> _wicket() async {
    if (!_canScore) return;
    final types = _noBall
        ? ['Run out']
        : ['Bowled', 'Caught', 'LBW', 'Stumped', 'Hit wicket', 'Run out'];
    var how = types.first;
    var strikerOut = true;
    var completed = 0;
    final sName = _batRow(_striker)!.name;
    final nName = _batRow(_nonStriker)!.name;

    final ok = await showFormDialog(
      context,
      title: 'Wicket',
      icon: Icons.sports_cricket,
      confirmLabel: 'Out',
      builder: (ctx, setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_noBall) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('No-ball: only a run out counts.')),
        Wrap(spacing: 8, children: [
          for (final t in types)
            ChoiceChip(label: Text(t), selected: how == t, onSelected: (_) => setS(() => how = t)),
        ]),
        if (how == 'Run out') ...[
          const SizedBox(height: 14),
          const Text('Who is out?'),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: Text(sName), selected: strikerOut, onSelected: (_) => setS(() => strikerOut = true)),
            ChoiceChip(label: Text(nName), selected: !strikerOut, onSelected: (_) => setS(() => strikerOut = false)),
          ]),
          const SizedBox(height: 14),
          const Text('Runs completed first'),
          Wrap(spacing: 8, children: [
            for (final r in [0, 1, 2])
              ChoiceChip(label: Text('$r'), selected: completed == r, onSelected: (_) => setS(() => completed = r)),
          ]),
        ],
      ]),
    );
    if (ok != true) return;

    _push();
    final s = _batRow(_striker)!;
    final b = _bowlRow(_bowler)!;
    final legal = !_noBall;
    final outId = (how == 'Run out' && !strikerOut) ? _nonStriker : _striker;
    final outRow = _batRow(outId)!;
    setState(() {
      outRow.how = how;
      if (how != 'Run out') {
        outRow.bowlerId = b.playerId;
        outRow.bowlerName = b.name;
      } else {
        s.runs += completed;
        b.runs += completed;
      }
      if (legal) {
        b.balls++;
        _over.add(completed > 0 ? 'W+$completed' : 'W');
      } else {
        _over[_over.length - 1] = 'Nb+W';
        _noBall = false;
      }
    });

    // A new batter always comes straight in, at the end of the one who was out.
    if (!_cur.allOut) {
      final next = await _pickBatter();
      if (next != null && next.isNotEmpty) {
        final p = _player(_battingId, next);
        setState(() {
          _cur.bat.add(BatRow(playerId: p.id, name: p.name));
          if (outId == _striker) {
            _striker = p.id;
          } else {
            _nonStriker = p.id;
          }
        });
      }
    }
    await _afterBall(legal);
  }

  // ------------------------------------------------------------ save

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Db.saveScorecard(m, _innings[m.teamAId]!, _innings[m.teamBId]!, complete: _complete);
      if (!mounted) return;
      _dirty = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scorecard saved')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave live scoring?'),
        content: const Text(
            'Every ball is already saved and shown to owners. Leaving stops the LIVE view. '
            'Tap "Save scorecard" instead if the match is finished.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
        ],
      ),
    );
    return leave == true;
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (!leave || !context.mounted) return;
        setState(() => _dirty = false);
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live scoring'),
          actions: [
            IconButton(
              tooltip: 'Undo last ball',
              icon: const Icon(Icons.undo),
              onPressed: _undo.isEmpty ? null : _takeBack,
            ),
          ],
        ),
        body: _loading ? const Center(child: CircularProgressIndicator()) : _body(),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _complete,
                      onChanged: (v) => setState(() => _complete = v ?? false),
                      title: const Text('Mark match completed (winner from run totals)'),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save scorecard'),
                      ),
                    ),
                  ]),
                ),
              ),
      ),
    );
  }

  Widget _body() {
    final i = _cur;
    final crr = i.balls == 0 ? 0.0 : i.runs * 6 / i.balls;
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Material(
        color: scheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_teamName(_battingId),
                    overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              ),
              Text('${i.runs}/${i.wickets}', style: Theme.of(context).textTheme.headlineSmall),
            ]),
            Text('Overs ${ballsToOvers(i.balls)} / $_maxOvers  •  Run rate ${crr.toStringAsFixed(2)}  •  '
                'Out ${i.wickets} of ${i.maxWickets}'),
            const Row(children: [
              Icon(Icons.circle, size: 10, color: Colors.red),
              SizedBox(width: 6),
              Text('LIVE - owners can follow this', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            if (_inningsOver)
              Text(i.allOut ? 'ALL OUT - innings complete' : 'Overs finished - innings complete',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
          ]),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          DropdownButtonFormField<String>(
            initialValue: _battingId,
            decoration: const InputDecoration(labelText: 'Batting team (innings)'),
            items: [m.teamAId, m.teamBId]
                .map((id) => DropdownMenuItem(value: id, child: Text(_teamName(id))))
                .toList(),
            onChanged: (v) async {
              if (v == null || v == _battingId) return;
              await _setup(v); // cancelled -> stays on the current innings
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          _creaseCard(),
          _bowlerCard(),
          if (_over.isNotEmpty || _noBall) _overCard(),
          const SizedBox(height: 8),
          _pad(),
        ]),
      ),
    ]);
  }

  Widget _creaseCard() {
    Widget row(String id, bool onStrike) {
      final r = _batRow(id);
      return ListTile(
        dense: true,
        leading: Icon(onStrike ? Icons.sports_cricket : Icons.person_outline,
            color: onStrike ? Theme.of(context).colorScheme.primary : null),
        title: Text('${r?.name ?? '-'}${onStrike ? ' *' : ''}',
            style: TextStyle(fontWeight: onStrike ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(onStrike ? 'On strike' : 'Non-striker'),
        trailing: Text('${r?.runs ?? 0}', style: Theme.of(context).textTheme.titleLarge),
      );
    }

    return Card(
      child: Column(children: [
        row(_striker, true),
        row(_nonStriker, false),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Swap strike'),
            onPressed: _canScore
                ? () {
                    _push();
                    setState(_swap);
                  }
                : null,
          ),
        ),
      ]),
    );
  }

  Widget _bowlerCard() {
    final r = _bowlRow(_bowler);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.sports_baseball),
        title: Text(r?.name ?? 'Choose bowler'),
        subtitle: r == null
            ? null
            : Text('${ballsToOvers(r.balls)} ov  •  ${r.maidens} M  •  ${r.runs} R  •  '
                '${_cur.wicketsOf(r.playerId)} W'),
        trailing: TextButton(onPressed: () => _pickBowler(forced: _bowler.isEmpty), child: const Text('Change')),
      ),
    );
  }

  Widget _overCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('This over', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_noBall) ...[
              const SizedBox(width: 10),
              const Chip(label: Text('No-ball: next run counts off it'), visualDensity: VisualDensity.compact),
            ],
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final b in _over)
              CircleAvatar(
                radius: 15,
                backgroundColor: b.contains('W') ? Colors.red : (b == '4' || b == '6' ? Colors.green : Colors.grey.shade300),
                foregroundColor: (b.contains('W') || b == '4' || b == '6') ? Colors.white : Colors.black87,
                child: Text(b, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _pad() {
    final on = _canScore;
    Widget run(int n) => FilledButton.tonal(
          style: (n == 4 || n == 6)
              ? FilledButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)
              : null,
          onPressed: on ? () => _runs(n) : null,
          child: Text('$n', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        );
    Widget small(String t, VoidCallback f) => OutlinedButton(onPressed: on ? f : null, child: Text(t));

    return Column(children: [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
        children: [for (final n in [0, 1, 2, 3, 4, 6]) run(n)],
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: small('Wide', _wide)),
        const SizedBox(width: 8),
        Expanded(child: small('No-ball', _noBallTap)),
        const SizedBox(width: 8),
        Expanded(child: small('Bye', () => _byeTap(false))),
        const SizedBox(width: 8),
        Expanded(child: small('Leg bye', () => _byeTap(true))),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: on ? _wicket : null,
          icon: const Icon(Icons.sports_cricket),
          label: const Text('WICKET'),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        '1 or 3 runs swap the batters; 0, 2, 4 and 6 keep them. The batters also swap at the end of every over.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ]);
  }
}
