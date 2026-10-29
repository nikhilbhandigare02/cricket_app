// Cricket scorecard models. One Innings per batting team, stored at
// matches/{matchId}/innings/{battingTeamId}.

const dismissals = ['Not out', 'Bowled', 'Caught', 'LBW', 'Stumped', 'Hit wicket', 'Run out'];

int parseOversToBalls(String s) {
  final t = s.trim();
  if (t.isEmpty) return 0;
  final parts = t.split('.');
  final o = int.tryParse(parts[0]) ?? 0;
  var b = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  if (b > 5) b = 5;
  return o * 6 + b;
}

String ballsToOvers(int balls) => '${balls ~/ 6}.${balls % 6}';

class BatRow {
  String playerId;
  String name;
  int runs;
  int balls;
  int fours;
  int sixes;
  String how;
  String bowlerId;
  String bowlerName;

  BatRow({
    this.playerId = '',
    this.name = '',
    this.runs = 0,
    this.balls = 0,
    this.fours = 0,
    this.sixes = 0,
    this.how = 'Not out',
    this.bowlerId = '',
    this.bowlerName = '',
  });

  bool get isOut => how != 'Not out';

  /// Run outs are not credited to the bowler.
  bool get creditsBowler => isOut && how != 'Run out';

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'name': name,
        'runs': runs,
        'balls': balls,
        'fours': fours,
        'sixes': sixes,
        'how': how,
        'bowlerId': bowlerId,
        'bowlerName': bowlerName,
      };

  factory BatRow.fromMap(Map<String, dynamic> m) => BatRow(
        playerId: m['playerId'] ?? '',
        name: m['name'] ?? '',
        runs: m['runs'] ?? 0,
        balls: m['balls'] ?? 0,
        fours: m['fours'] ?? 0,
        sixes: m['sixes'] ?? 0,
        how: m['how'] ?? 'Not out',
        bowlerId: m['bowlerId'] ?? '',
        bowlerName: m['bowlerName'] ?? '',
      );
}

class BowlRow {
  String playerId;
  String name;
  int balls;
  int maidens;
  int runs;

  BowlRow({this.playerId = '', this.name = '', this.balls = 0, this.maidens = 0, this.runs = 0});

  double get economy => balls == 0 ? 0 : runs * 6 / balls;

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'name': name,
        'balls': balls,
        'maidens': maidens,
        'runs': runs,
      };

  factory BowlRow.fromMap(Map<String, dynamic> m) => BowlRow(
        playerId: m['playerId'] ?? '',
        name: m['name'] ?? '',
        balls: m['balls'] ?? 0,
        maidens: m['maidens'] ?? 0,
        runs: m['runs'] ?? 0,
      );
}

class Innings {
  final String teamId;
  List<BatRow> bat;
  List<BowlRow> bowl;

  // Extras belong to the team's innings, not to any one batter.
  int wides;
  int noBalls;
  int byes;
  int legByes;

  /// Players per side for this match. The innings is over when all but one are out.
  int players;

  Innings({
    required this.teamId,
    List<BatRow>? bat,
    List<BowlRow>? bowl,
    this.wides = 0,
    this.noBalls = 0,
    this.byes = 0,
    this.legByes = 0,
    this.players = 7,
  })  : bat = bat ?? [],
        bowl = bowl ?? [];

  int get extras => wides + noBalls + byes + legByes;

  int get runs => bat.fold(0, (s, b) => s + b.runs) + extras;
  int get wickets => bat.where((b) => b.isOut).length;
  int get maxWickets => players - 1;
  bool get allOut => wickets >= maxWickets;
  int get balls => bowl.fold(0, (s, b) => s + b.balls);

  /// Wickets credited to a bowler, worked out from the batting rows.
  int wicketsOf(String bowlerId) =>
      bowlerId.isEmpty ? 0 : bat.where((b) => b.creditsBowler && b.bowlerId == bowlerId).length;

  String get summary => '$runs/$wickets (${ballsToOvers(balls)} ov)';

  Map<String, dynamic> toMap() => {
        'teamId': teamId,
        'extras': extras,
        'wides': wides,
        'noBalls': noBalls,
        'byes': byes,
        'legByes': legByes,
        'players': players,
        'runs': runs,
        'wickets': wickets,
        'balls': balls,
        'bat': bat.map((b) => b.toMap()).toList(),
        'bowl': bowl.map((b) => b.toMap()).toList(),
      };

  factory Innings.fromMap(String teamId, Map<String, dynamic> m) => Innings(
        teamId: teamId,
        wides: m['wides'] ?? 0,
        noBalls: m['noBalls'] ?? 0,
        // A scorecard saved before the breakdown existed only has a single total.
        byes: m['byes'] ?? (m.containsKey('wides') ? 0 : (m['extras'] ?? 0)),
        legByes: m['legByes'] ?? 0,
        players: m['players'] ?? 7,
        bat: ((m['bat'] ?? []) as List).map((e) => BatRow.fromMap(Map<String, dynamic>.from(e))).toList(),
        bowl: ((m['bowl'] ?? []) as List).map((e) => BowlRow.fromMap(Map<String, dynamic>.from(e))).toList(),
      );
}
