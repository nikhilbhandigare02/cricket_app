import 'package:flutter_test/flutter_test.dart';
import 'package:village_league/models/scorecard.dart';

void main() {
  test('two run outs count as two wickets, no bowler credit', () {
    final i = Innings(teamId: 't', bat: [
      BatRow(playerId: 'a', name: 'A', runs: 10, how: 'Run out'),
      BatRow(playerId: 'b', name: 'B', runs: 5, how: 'Run out'),
      BatRow(playerId: 'c', name: 'C', runs: 7, how: 'Bowled', bowlerId: 'x'),
    ]);
    expect(i.wickets, 3);
    expect(i.runs, 22);
    expect(i.wicketsOf('x'), 1);
  });
}
