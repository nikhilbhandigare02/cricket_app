import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/scorecard.dart';
import '../services/db.dart';
import '../widgets/form_widgets.dart';

/// Admin scorecard editor. The dropdown at the top picks which team is batting;
/// batters come from that team, bowlers from the other team.
class ScorecardScreen extends StatefulWidget {
  final MatchGame match;
  const ScorecardScreen({super.key, required this.match});

  @override
  State<ScorecardScreen> createState() => _ScorecardScreenState();
}

class _ScorecardScreenState extends State<ScorecardScreen> {
  MatchGame get m => widget.match;

  bool _loading = true;
  bool _saving = false;
  late bool _complete = m.completed;
  late String _battingId = m.teamAId;
  final _innings = <String, Innings>{};
  final _players = <String, List<Player>>{};

  String get _fieldingId => _battingId == m.teamAId ? m.teamBId : m.teamAId;
  Innings get _cur => _innings[_battingId]!;
  String _teamName(String id) => id == m.teamAId ? m.teamAName : m.teamBName;

  /// Pings the player-score screens (a separate route) whenever state changes.
  final _refresh = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _refresh.value++;
  }

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  /// Players per side, shared by both innings.
  int get _n => _innings[m.teamAId]!.players;

  /// Smallest count that still fits the rows and wickets already entered.
  int get _minPlayers {
    var min = 2;
    for (final i in _innings.values) {
      if (i.bat.length > min) min = i.bat.length;
      if (i.wickets + 1 > min) min = i.wickets + 1;
    }
    return min;
  }

  void _setPlayers(int v) {
    final n = v.clamp(_minPlayers, 30);
    for (final i in _innings.values) {
      i.players = n;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final id in [m.teamAId, m.teamBId]) {
      _innings[id] = await Db.loadInnings(m.id, id);
      _players[id] = await Db.playersStream(id).first;
    }
    _setPlayers(_innings[m.teamAId]!.players);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Db.saveScorecard(
        m,
        _innings[m.teamAId]!,
        _innings[m.teamBId]!,
        complete: _complete,
      );
      if (mounted) {
        final tie =
            _complete &&
            m.bracketSlot != null &&
            _innings[m.teamAId]!.runs == _innings[m.teamBId]!.runs;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tie
                  ? 'Scorecard saved. Knockout match is tied - bracket not updated, a winner is needed'
                  : 'Scorecard saved',
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${m.teamAName} vs ${m.teamBName}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body(),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _complete,
                      onChanged: (v) => setState(() => _complete = v ?? false),
                      title: const Text(
                        'Mark match completed (winner from run totals)',
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save scorecard'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _body() {
    final batters = _players[_battingId]!;
    final bowlers = _players[_fieldingId]!;
    return Column(
      children: [
        _teamHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _battingId,
                decoration: const InputDecoration(
                  labelText: 'Batting team (innings)',
                ),
                items: [m.teamAId, m.teamBId]
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(_teamName(id)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _battingId = v ?? _battingId),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Players per side')),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove),
                    onPressed: _n > _minPlayers
                        ? () => setState(() => _setPlayers(_n - 1))
                        : null,
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$_n',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    onPressed: _n < 30
                        ? () => setState(() => _setPlayers(_n + 1))
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _sectionTitle(
                'Batting - ${_teamName(_battingId)} (${_cur.bat.length}/$_n)',
                onAdd: _cur.bat.length < _n
                    ? () {
                        final r = BatRow();
                        setState(() => _cur.bat.add(r));
                        _openBat(r);
                      }
                    : null,
              ),
              if (batters.isEmpty)
                const Text(
                  'This team has no players yet. Add players to the team first.',
                ),
              for (var i = 0; i < _cur.bat.length; i++)
                _batSummary(i, _cur.bat[i]),
              const Divider(height: 32),
              _sectionTitle(
                'Bowling - ${_teamName(_fieldingId)}',
                onAdd: () {
                  final r = BowlRow();
                  setState(() => _cur.bowl.add(r));
                  _openBowl(r);
                },
              ),
              if (bowlers.isEmpty)
                const Text('The bowling team has no players yet.'),
              for (var i = 0; i < _cur.bowl.length; i++)
                _bowlSummary(i, _cur.bowl[i]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  /// Extras for the whole batting team. Shown on every player's screen but it
  /// is one shared set of numbers, not per player.
  Widget _extrasCard() {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Team extras: ${_cur.extras}'),
        subtitle: Text(
          'Wd ${_cur.wides}  Nb ${_cur.noBalls}  B ${_cur.byes}  Lb ${_cur.legByes}  (same for every player)',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          _Stepper(
            label: 'Wides',
            value: _cur.wides,
            onChanged: (v) => setState(() => _cur.wides = v),
          ),
          _Stepper(
            label: 'No-balls',
            value: _cur.noBalls,
            onChanged: (v) => setState(() => _cur.noBalls = v),
          ),
          _Stepper(
            label: 'Byes',
            value: _cur.byes,
            onChanged: (v) => setState(() => _cur.byes = v),
          ),
          _Stepper(
            label: 'Leg byes',
            value: _cur.legByes,
            onChanged: (v) => setState(() => _cur.legByes = v),
          ),
        ],
      ),
    );
  }

  /// Pinned team total (runs/wickets, overs, out count) shown above both the
  /// scorecard and each player's screen.
  Widget _teamHeader() {
    final i = _cur;
    final other = _innings[_fieldingId]!;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _teamName(_battingId),
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${i.runs}/${i.wickets}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            Text(
              'Overs ${ballsToOvers(i.balls)}  •  Out ${i.wickets} of ${i.maxWickets}  •  '
              'Extras ${i.extras}${i.allOut ? '  •  ALL OUT' : ''}',
            ),
            Text(
              '${_teamName(_fieldingId)}  ${other.summary}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  // ---- compact cards in the list; tapping opens that player's own screen ----

  Widget _batSummary(int i, BatRow r) {
    final out = r.isOut;
    final how = out
        ? '${r.how}${r.bowlerName.isNotEmpty ? ' b ${r.bowlerName}' : ''}'
        : 'not out';
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${i + 1}')),
        title: Text(r.name.isEmpty ? 'Select player' : r.name),
        subtitle: Text('${r.runs} runs\n$how'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openBat(r),
      ),
    );
  }

  Widget _bowlSummary(int i, BowlRow r) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${i + 1}')),
        title: Text(r.name.isEmpty ? 'Select player' : r.name),
        subtitle: Text(
          '${ballsToOvers(r.balls)} ov  •  ${r.maidens} M  •  ${r.runs} R  •  '
          '${_cur.wicketsOf(r.playerId)} W',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openBowl(r),
      ),
    );
  }

  Future<void> _openBat(BatRow r) async {
    await _openPlayerScreen(
      title: 'Batter score',
      showExtras: true,
      card: () => _batCard(
        r,
        _players[_battingId]!,
        _players[_fieldingId]!,
        detail: true,
      ),
    );
    // Drop a row that was added but never filled in.
    if (mounted &&
        r.playerId.isEmpty &&
        r.runs == 0 &&
        r.balls == 0 &&
        !r.isOut) {
      setState(() => _cur.bat.remove(r));
    }
  }

  Future<void> _openBowl(BowlRow r) async {
    await _openPlayerScreen(
      title: 'Bowler score',
      card: () => _bowlCard(r, _players[_fieldingId]!, detail: true),
    );
    if (mounted &&
        r.playerId.isEmpty &&
        r.balls == 0 &&
        r.runs == 0 &&
        r.maidens == 0) {
      setState(() => _cur.bowl.remove(r));
    }
  }

  Future<void> _openPlayerScreen({
    required String title,
    required Widget Function() card,
    bool showExtras = false,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ValueListenableBuilder<int>(
            valueListenable: _refresh,
            builder: (_, _, _) => Column(
              children: [
                _teamHeader(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      card(),
                      if (showExtras) ...[
                        const SizedBox(height: 8),
                        _extrasCard(),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t, {required VoidCallback? onAdd}) => Row(
    children: [
      Expanded(child: Text(t, style: Theme.of(context).textTheme.titleMedium)),
      TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    ],
  );

  Widget _playerDropdown(
    String label,
    List<Player> list,
    String selectedId,
    void Function(Player) onPick, {
    Map<String, String> unavailable = const {},
  }) {
    final value = list.any((p) => p.id == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      // Players in [unavailable] are greyed out; the value is the reason shown.
      items: list
          .map(
            (p) => DropdownMenuItem(
              value: p.id,
              enabled: !unavailable.containsKey(p.id),
              child: Text(
                unavailable.containsKey(p.id)
                    ? '${p.name} (${unavailable[p.id]})'
                    : p.name,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id == null) return;
        setState(() => onPick(list.firstWhere((p) => p.id == id)));
      },
    );
  }

  Widget _batCard(
    BatRow r,
    List<Player> batters,
    List<Player> bowlers, {
    bool detail = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _playerDropdown(
                    'Batter',
                    batters,
                    r.playerId,
                    (p) {
                      r.playerId = p.id;
                      r.name = p.name;
                    },
                    unavailable: {
                      // Out players can't be picked again; neither can ones already batting.
                      for (final o in _cur.bat)
                        if (!identical(o, r) && o.playerId.isNotEmpty)
                          o.playerId: o.isOut ? 'out' : 'batting',
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDelete(
                      context,
                      title: 'Remove ${r.name.isEmpty ? 'this batter' : r.name}?',
                      message: 'Their runs and dismissal are removed from the scorecard.',
                      confirmLabel: 'Remove',
                    );
                    if (!ok || !mounted) return;
                    setState(() => _cur.bat.remove(r));
                    if (detail) Navigator.pop(context);
                  },
                ),
              ],
            ),
            _Stepper(
              label: 'Runs',
              value: r.runs,
              onChanged: (v) => setState(() => r.runs = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: r.how,
              decoration: const InputDecoration(labelText: 'How out'),
              // Once everyone but one is out, no further wickets can be added.
              items: dismissals
                  .map(
                    (d) => DropdownMenuItem(
                      value: d,
                      enabled: d == 'Not out' || r.isOut || !_cur.allOut,
                      child: Text(d),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                r.how = v ?? r.how;
                if (!r.creditsBowler) {
                  r.bowlerId = '';
                  r.bowlerName = '';
                }
              }),
            ),
            if (r.creditsBowler)
              _playerDropdown('Bowler', bowlers, r.bowlerId, (p) {
                r.bowlerId = p.id;
                r.bowlerName = p.name;
              }),
          ],
        ),
      ),
    );
  }

  Widget _bowlCard(BowlRow r, List<Player> bowlers, {bool detail = false}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _playerDropdown(
                    'Bowler',
                    bowlers,
                    r.playerId,
                    (p) {
                      r.playerId = p.id;
                      r.name = p.name;
                    },
                    unavailable: {
                      for (final o in _cur.bowl)
                        if (!identical(o, r) && o.playerId.isNotEmpty)
                          o.playerId: 'added',
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDelete(
                      context,
                      title: 'Remove ${r.name.isEmpty ? 'this bowler' : r.name}?',
                      message: 'Their overs, runs and wickets are removed from the scorecard.',
                      confirmLabel: 'Remove',
                    );
                    if (!ok || !mounted) return;
                    setState(() => _cur.bowl.remove(r));
                    if (detail) Navigator.pop(context);
                  },
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: r.balls == 0 ? '' : ballsToOvers(r.balls),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Overs (e.g. 3.4)',
                    ),
                    onChanged: (v) =>
                        setState(() => r.balls = parseOversToBalls(v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numField(
                    'Maidens',
                    r.maidens,
                    (v) => setState(() => r.maidens = v),
                  ),
                ),
              ],
            ),
            _Stepper(
              label: 'Runs given',
              value: r.runs,
              onChanged: (v) => setState(() => r.runs = v),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Wickets ${_cur.wicketsOf(r.playerId)} (auto)  •  Econ ${r.economy.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(String label, int value, void Function(int) onChanged) =>
      TextFormField(
        initialValue: value == 0 ? '' : '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      );
}

/// Number field with - / + buttons; the number can also be typed.
class _Stepper extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final TextEditingController _c = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(_Stepper old) {
    super.didUpdateWidget(old);
    if ((int.tryParse(_c.text) ?? 0) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(int v) => widget.onChanged(v < 0 ? 0 : v);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          icon: const Icon(Icons.remove),
          onPressed: widget.value > 0 ? () => _set(widget.value - 1) : null,
        ),
        Expanded(
          child: TextField(
            controller: _c,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: widget.label),
            onChanged: (v) => _set(int.tryParse(v) ?? 0),
          ),
        ),
        IconButton.filledTonal(
          icon: const Icon(Icons.add),
          onPressed: () => _set(widget.value + 1),
        ),
      ],
    );
  }
}
