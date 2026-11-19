import 'models.dart';
import 'scorecard.dart';

/// Season totals for one player, added up from every completed match's scorecard.
class PlayerStat {
  final String id; // player id (unique per team)
  final String teamId;
  String name;
  String teamName;
  int matches = 0;
  // batting
  int innings = 0, runs = 0, balls = 0, fours = 0, sixes = 0, highest = 0, notOuts = 0;
  // bowling
  int wickets = 0, ballsBowled = 0, runsConceded = 0, maidens = 0, bestWickets = 0, bestRuns = 0;
  // fielding
  int runOuts = 0;
  final _played = <String>{};

  PlayerStat(this.id, this.teamId, this.name, this.teamName);

  int get dismissals => innings - notOuts;
  double get average => dismissals == 0 ? runs.toDouble() : runs / dismissals;
  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
  double get economy => ballsBowled == 0 ? 0 : runsConceded * 6 / ballsBowled;

  bool get batted => innings > 0;
  bool get bowled => ballsBowled > 0 || wickets > 0;

  /// All-rounder rating: a wicket is worth about 20 runs.
  int get allRounderPoints => runs + wickets * 20;
  bool get isAllRounder => runs > 0 && wickets > 0;
}

/// Adds up every completed match. [innings] is matchId -> battingTeamId -> Innings.
List<PlayerStat> computePlayerStats(List<MatchGame> matches, Map<String, Map<String, Innings>> innings) {
  final stats = <String, PlayerStat>{};
  PlayerStat of(String matchId, String teamId, String teamName, String playerId, String name) {
    final s = stats.putIfAbsent('$teamId|$playerId', () => PlayerStat(playerId, teamId, name, teamName));
    if (s._played.add(matchId)) s.matches++;
    return s;
  }

  for (final m in matches) {
    if (!m.completed) continue;
    final inn = innings[m.id];
    if (inn == null) continue;
    for (final batTeam in [m.teamAId, m.teamBId]) {
      final i = inn[batTeam];
      if (i == null) continue;
      final batName = batTeam == m.teamAId ? m.teamAName : m.teamBName;
      final fieldId = batTeam == m.teamAId ? m.teamBId : m.teamAId;
      final fieldName = batTeam == m.teamAId ? m.teamBName : m.teamAName;
      for (final b in i.bat) {
        if (b.playerId.isEmpty) continue;
        final s = of(m.id, batTeam, batName, b.playerId, b.name);
        s.innings++;
        s.runs += b.runs;
        s.balls += b.balls;
        s.fours += b.fours;
        s.sixes += b.sixes;
        if (b.runs > s.highest) s.highest = b.runs;
        if (!b.isOut) s.notOuts++;
        if (b.how == 'Run out' && b.fielderId.isNotEmpty) {
          of(m.id, fieldId, fieldName, b.fielderId, b.fielderName).runOuts++;
        }
      }
      for (final w in i.bowl) {
        if (w.playerId.isEmpty) continue;
        final s = of(m.id, fieldId, fieldName, w.playerId, w.name);
        final wk = i.wicketsOf(w.playerId);
        s.wickets += wk;
        s.ballsBowled += w.balls;
        s.runsConceded += w.runs;
        s.maidens += w.maidens;
        if (wk > s.bestWickets || (wk == s.bestWickets && wk > 0 && w.runs < s.bestRuns)) {
          s.bestWickets = wk;
          s.bestRuns = w.runs;
        }
      }
    }
  }
  return stats.values.toList();
}
