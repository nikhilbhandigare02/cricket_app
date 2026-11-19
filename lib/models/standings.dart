import 'models.dart';
import 'scorecard.dart';

/// One row of the league table.
class Standing {
  final String id;
  final String name;
  int played = 0, won = 0, lost = 0, drawn = 0, points = 0, diff = 0;
  // Net run rate inputs: runs scored/conceded and balls faced/bowled.
  int runsFor = 0, ballsFaced = 0, runsAgainst = 0, ballsBowled = 0;
  Standing(this.id, this.name);

  double get nrr {
    final forRate = ballsFaced == 0 ? 0.0 : runsFor * 6 / ballsFaced;
    final againstRate = ballsBowled == 0 ? 0.0 : runsAgainst * 6 / ballsBowled;
    return forRate - againstRate;
  }
}

/// League table from the round-robin matches (those not part of the knockout
/// bracket). A win is 2 points, a draw 1; ties are split by net run rate, then
/// run difference. [innings] (matchId -> teamId -> innings) supplies the overs.
List<Standing> computeStandings(List<MatchGame> matches,
    {Map<String, Map<String, Innings>> innings = const {}, List<Team> teams = const []}) {
  final rows = <String, Standing>{};
  Standing row(String id, String name) => rows.putIfAbsent(id, () => Standing(id, name));
  // Every team is listed from the start, on 0 points, before it has played.
  for (final t in teams) {
    row(t.id, t.name);
  }
  for (final m in matches) {
    if (m.bracketSlot != null) continue;
    final a = row(m.teamAId, m.teamAName);
    final b = row(m.teamBId, m.teamBName);
    if (!m.completed) continue;
    a.played++;
    b.played++;
    a.diff += m.scoreA - m.scoreB;
    b.diff += m.scoreB - m.scoreA;
    final ia = innings[m.id]?[m.teamAId], ib = innings[m.id]?[m.teamBId];
    if (ia != null && ib != null) {
      // An all-out side is counted as having faced its full quota of overs.
      int faced(Innings i) => i.allOut && m.liveMaxOvers > 0 ? m.liveMaxOvers * 6 : i.balls;
      a.runsFor += ia.runs;
      a.ballsFaced += faced(ia);
      a.runsAgainst += ib.runs;
      a.ballsBowled += faced(ib);
      b.runsFor += ib.runs;
      b.ballsFaced += faced(ib);
      b.runsAgainst += ia.runs;
      b.ballsBowled += faced(ia);
    }
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
      if (x.nrr != y.nrr) return y.nrr.compareTo(x.nrr);
      if (x.diff != y.diff) return y.diff.compareTo(x.diff);
      return x.name.compareTo(y.name);
    });
}

/// Teams that have already secured a playoff place (shown with "Q" in the table).
/// A team is qualified when no more than [spots] - 1 other teams can still finish
/// level with or above it, counting every unplayed league match as a win for them
/// (a tie on points could go against it on net run rate). Once the league is
/// complete, the top [spots] of the table are the qualifiers.
Set<String> qualifiedTeamIds(List<Standing> table, List<MatchGame> matches, {int spots = 4}) {
  final league = matches.where((m) => m.bracketSlot == null).toList();
  if (table.length < spots || league.isEmpty) return {};
  if (league.every((m) => m.completed)) {
    return {for (final s in table.take(spots)) s.id};
  }
  final remaining = <String, int>{};
  for (final m in league) {
    if (m.completed) continue;
    remaining[m.teamAId] = (remaining[m.teamAId] ?? 0) + 1;
    remaining[m.teamBId] = (remaining[m.teamBId] ?? 0) + 1;
  }
  final out = <String>{};
  for (final t in table) {
    final threats = table.where((o) => o.id != t.id && o.points + 2 * (remaining[o.id] ?? 0) >= t.points).length;
    if (threats <= spots - 1) out.add(t.id);
  }
  return out;
}
