import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';
import '../models/scorecard.dart';
import '../models/standings.dart';
import 'team_logos.dart';

class Db {
  static final _fs = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;


  static CollectionReference<Map<String, dynamic>> get owners => _fs.collection('owners');
  static CollectionReference<Map<String, dynamic>> get teams => _fs.collection('teams');
  static CollectionReference<Map<String, dynamic>> get matches => _fs.collection('matches');
  static CollectionReference<Map<String, dynamic>> get users => _fs.collection('users');

  // ---------- auth / profile ----------
  static Future<void> signIn(String email, String password) => _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  static Future<void> signOut() async {
    TeamLogos.reset();
    await _auth.signOut();
  }

  /// users/{uid} => { role: 'admin' | 'owner', ownerId?: String }
  static Future<Map<String, dynamic>?> profile(String uid) async {
    final d = await users.doc(uid).get();
    return d.data();
  }

  // ---------- owners ----------
  static Stream<List<Owner>> ownersStream() =>
      owners.orderBy('name').snapshots().map((s) => s.docs.map(Owner.fromDoc).toList());

  /// Creates a login for the owner without signing the admin out, by using a
  /// temporary secondary Firebase app instance. Also creates the owner's single
  /// team (document id == owner id) and its players in the same batch.
  static Future<void> addOwner({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String teamName,
    required List players,
    String? logo, // base64 JPEG from TeamLogos.pick()
  }) async {
    final secondary = await Firebase.initializeApp(
      name: 'owner-create-${DateTime.now().millisecondsSinceEpoch}',
      options: Firebase.app().options,
    );
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
      final cred = await secondaryAuth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final uid = cred.user!.uid;
      final ownerRef = owners.doc();
      final batch = _fs.batch();
      batch.set(ownerRef, {'name': name, 'email': email.trim(), 'phone': phone, 'uid': uid});
      batch.set(users.doc(uid), {'role': 'owner', 'ownerId': ownerRef.id, 'name': name});
      final teamRef = teams.doc(ownerRef.id);
      batch.set(teamRef, {
        'name': teamName,
        'ownerId': ownerRef.id,
        'ownerName': name,
        'logo': ?logo,
      });
      for (final p in players) {
        batch.set(teamRef.collection('players').doc(), p);
      }
      await batch.commit();
      await secondaryAuth.signOut();
    } finally {
      await secondary.delete();
    }
  }

  // ---------- teams ----------
  static Stream<List<Team>> teamsStream() =>
      teams.orderBy('name').snapshots().map((s) => s.docs.map(Team.fromDoc).toList());

  static Stream<List<Team>> teamsOfOwner(String ownerId) => teams
      .where('ownerId', isEqualTo: ownerId)
      .snapshots()
      .map((s) => s.docs.map(Team.fromDoc).toList());

  /// One team per owner: the team id is the owner id, so a second team cannot exist.
  static Future<void> addTeam({required Owner owner, required String name}) =>
      teams.doc(owner.id).set({'name': name, 'ownerId': owner.id, 'ownerName': owner.name});

  static Stream<Team?> teamStream(String id) =>
      teams.doc(id).snapshots().map((d) => d.exists ? Team.fromDoc(d) : null);

  static Future<void> renameTeam(String teamId, String name) => teams.doc(teamId).update({'name': name});

  static Future<Owner?> ownerById(String id) async {
    final d = await owners.doc(id).get();
    return d.exists ? Owner.fromDoc(d) : null;
  }

  /// Edits an owner's name and phone, and keeps the copies of the name in step
  /// (their users/{uid} profile and the ownerName on their team(s)).
  static Future<void> updateOwner(String ownerId, {required String name, required String phone}) async {
    final owner = await ownerById(ownerId);
    if (owner == null) return;
    final batch = _fs.batch();
    batch.update(owners.doc(ownerId), {'name': name, 'phone': phone});
    if (owner.uid.isNotEmpty) batch.update(users.doc(owner.uid), {'name': name});
    for (final t in (await teams.where('ownerId', isEqualTo: ownerId).get()).docs) {
      batch.update(t.reference, {'ownerName': name});
    }
    await batch.commit();
  }

  /// Sets (base64 JPEG) or removes (null) a team's logo.
  static Future<void> setTeamLogo(String teamId, String? logo) =>
      teams.doc(teamId).update({'logo': logo ?? FieldValue.delete()});

  static Future<void> deleteTeam(Team t) async {
    final players = await teams.doc(t.id).collection('players').get();
    final batch = _fs.batch();
    for (final p in players.docs) {
      batch.delete(p.reference);
    }
    batch.delete(teams.doc(t.id));
    await batch.commit();
  }

  // ---------- players ----------
  static CollectionReference<Map<String, dynamic>> _players(String teamId) =>
      teams.doc(teamId).collection('players');

  static Stream<List<Player>> playersStream(String teamId) =>
      _players(teamId).orderBy('jersey').snapshots().map((s) => s.docs.map(Player.fromDoc).toList());

  static Future<void> addPlayer(String teamId,
          {required String name, required String role, required int jersey, required String phone}) =>
      _players(teamId).add({'name': name, 'role': role, 'jersey': jersey, 'phone': phone});

  static Future<void> updatePlayer(String teamId, String playerId,
          {required String name, required String role, required int jersey, required String phone}) =>
      _players(teamId).doc(playerId).update({'name': name, 'role': role, 'jersey': jersey, 'phone': phone});

  static Future<void> deletePlayer(String teamId, String playerId) =>
      _players(teamId).doc(playerId).delete();

  // ---------- matches ----------
  static Stream<List<MatchGame>> matchesStream() => matches
      .orderBy('dateTime')
      .snapshots()
      .map((s) => s.docs.map(MatchGame.fromDoc).toList());

  static Map<String, dynamic> _matchData(Team a, Team b, DateTime when, String venue,
          {String? bracketSlot}) =>
      {
        'bracketSlot': bracketSlot,
        'teamAId': a.id,
        'teamAName': a.name,
        'teamBId': b.id,
        'teamBName': b.name,
        'dateTime': Timestamp.fromDate(when),
        'venue': venue,
        'completed': false,
        'scoreA': 0,
        'scoreB': 0,
        'winnerId': null,
      };

  static Future<void> addMatch(Team a, Team b, DateTime when, String venue) =>
      matches.add(_matchData(a, b, when, venue));

  static Future<void> deleteMatch(String id) async {
    final slot = (await matches.doc(id).get()).data()?['bracketSlot'] as String?;
    await matches.doc(id).delete();
    if (slot != null) {
      await _applySlotResult(slot, unlink: true);
    } else {
      await refreshBracket();
    }
  }

  static Future<void> updateSchedule(String id, DateTime when, String venue) async {
    final ref = matches.doc(id);
    await ref.update({'dateTime': Timestamp.fromDate(when), 'venue': venue});
    // A knockout match also shows its date on the bracket slot.
    final slot = (await ref.get()).data()?['bracketSlot'] as String?;
    if (slot != null) await bracket.doc(slot).update({'matchTime': Timestamp.fromDate(when)});
  }

  static Future<void> saveResult(MatchGame m, int scoreA, int scoreB) async {
    await matches.doc(m.id).update({
      'completed': true,
      'scoreA': scoreA,
      'scoreB': scoreB,
      'winnerId': scoreA == scoreB ? null : (scoreA > scoreB ? m.teamAId : m.teamBId),
    });
    await syncBracket(m.id);
    await refreshBracket();
  }

  // ---------- scorecard ----------
  static Stream<MatchGame?> matchStream(String id) =>
      matches.doc(id).snapshots().map((d) => d.exists ? MatchGame.fromDoc(d) : null);

  static Stream<Innings> inningsStream(String matchId, String teamId) =>
      matches.doc(matchId).collection('innings').doc(teamId).snapshots().map((d) {
        final data = d.data();
        return data == null ? Innings(teamId: teamId) : Innings.fromMap(teamId, data);
      });

  /// Pushes the current state of live scoring so owners see it as it happens:
  /// both innings, the running score on the match, and who is at the crease.
  static Future<void> publishLive(
    MatchGame m,
    Innings a,
    Innings b, {
    required String battingId,
    required String strikerId,
    required String striker,
    required String nonStrikerId,
    required String nonStriker,
    required String bowlerId,
    required String bowler,
    required List<String> over,
    required int maxOvers,
  }) {
    final batch = _fs.batch();
    final inn = matches.doc(m.id).collection('innings');
    batch.set(inn.doc(a.teamId), a.toMap());
    batch.set(inn.doc(b.teamId), b.toMap());
    batch.update(matches.doc(m.id), {
      'scoreA': a.runs,
      'scoreB': b.runs,
      'live': true,
      'liveBatting': battingId,
      'liveStrikerId': strikerId,
      'liveStriker': striker,
      'liveNonStrikerId': nonStrikerId,
      'liveNonStriker': nonStriker,
      'liveBowlerId': bowlerId,
      'liveBowler': bowler,
      'liveOver': over,
      'liveMaxOvers': maxOvers,
      'liveUpdated': FieldValue.serverTimestamp(),
    });
    return batch.commit();
  }

  static Future<void> endLive(String matchId) =>
      matches.doc(matchId).update({'live': false});

  static Future<Innings> loadInnings(String matchId, String teamId) async {
    final d = await matches.doc(matchId).collection('innings').doc(teamId).get();
    final data = d.data();
    return data == null ? Innings(teamId: teamId) : Innings.fromMap(teamId, data);
  }

  /// Saves both innings and syncs the match totals. When [complete] is true the
  /// match is marked completed with the winner worked out from the run totals.
  static Future<void> saveScorecard(MatchGame m, Innings a, Innings b,
      {required bool complete}) async {
    final batch = _fs.batch();
    final inn = matches.doc(m.id).collection('innings');
    batch.set(inn.doc(a.teamId), a.toMap());
    batch.set(inn.doc(b.teamId), b.toMap());
    batch.update(matches.doc(m.id), {
      'scoreA': a.runs,
      'scoreB': b.runs,
      'live': false, // saving the scorecard ends the live view
      if (complete) 'completed': true,
      if (complete) 'winnerId': a.runs == b.runs ? null : (a.runs > b.runs ? m.teamAId : m.teamBId),
    });
    await batch.commit();
    await syncBracket(m.id);
    await refreshBracket();
  }

  static Future<void> reopenMatch(String id) async {
    await matches.doc(id).update({'completed': false, 'scoreA': 0, 'scoreB': 0, 'winnerId': null});
    await syncBracket(id);
    await refreshBracket();
  }

  // ---------- tournament bracket ----------
  static CollectionReference<Map<String, dynamic>> get bracket => _fs.collection('bracket');

  static Stream<List<BracketSlot>> bracketStream() => bracket.snapshots().map((s) {
        final list = s.docs.map(BracketSlot.fromDoc).toList();
        list.sort((a, b) => a.round != b.round ? a.round.compareTo(b.round) : a.index.compareTo(b.index));
        return list;
      });

  static Future<MatchGame?> matchById(String id) async {
    final d = await matches.doc(id).get();
    return d.exists ? MatchGame.fromDoc(d) : null;
  }

  /// IPL playoff format, four slots (ids `r{round}m{index}`):
  ///   r0m0 Qualifier 1  : table #1 v #2 - winner to the Final, loser to Qualifier 2
  ///   r0m1 Eliminator   : table #3 v #4 - winner to Qualifier 2, loser is out
  ///   r1m0 Qualifier 2  : loser of Q1 v winner of the Eliminator - winner to the Final
  ///   r2m0 Final        : winner of Q1 v winner of Q2
  static const _iplFormat = 'ipl';

  /// Where the result of [slot] sends its teams: (target slot id, side, winner?).
  static List<(String, String, bool)> _iplRoutes(String slot) => switch (slot) {
        'r0m0' => [('r2m0', 'teamA', true), ('r1m0', 'teamA', false)],
        'r0m1' => [('r1m0', 'teamB', true)],
        'r1m0' => [('r2m0', 'teamB', true)],
        _ => const [],
      };

  /// Creates the empty playoff bracket whose first two matches take the top four
  /// of the league table. [refreshBracket] fills in the teams and schedules the
  /// matches once the league is complete.
  static Future<void> _writeTableBracket() async {
    final batch = _fs.batch();
    for (final d in (await bracket.get()).docs) {
      batch.delete(d.reference);
    }
    const layout = [
      (0, 0, 1, 2),
      (0, 1, 3, 4),
      (1, 0, null, null),
      (2, 0, null, null),
    ];
    for (final (r, i, seedA, seedB) in layout) {
      batch.set(bracket.doc('r${r}m$i'), {
        'round': r,
        'index': i,
        'teamAId': null,
        'teamAName': null,
        'teamBId': null,
        'teamBName': null,
        'winnerId': null,
        'winnerName': null,
        'matchId': null,
        'matchTime': null,
        'scoreText': null,
        'tableSeeded': true,
        'format': _iplFormat,
        'teamCount': 4,
        'seedA': ?seedA,
        'seedB': ?seedB,
      });
    }
    await batch.commit();
  }

  /// Keeps a table-seeded bracket in step with the league. When there is no
  /// bracket yet and there are league matches (between at least four teams), the
  /// IPL playoff bracket is created. Once the league is complete, the top four of
  /// the points table (points, then net run rate) fill Qualifier 1 and the
  /// Eliminator; then every slot with both teams known gets its match scheduled
  /// automatically. If the league changes again before any playoff match is
  /// played, the bracket is cleared and re-seeded, unless the admin edited it by
  /// hand ([updateBracketSlot]). A bracket in the old quarter/semi format is
  /// replaced by the playoff one while none of its matches is completed.
  static Future<void> refreshBracket() async {
    final all = (await matches.get()).docs.map(MatchGame.fromDoc).toList();
    final league = all.where((m) => m.bracketSlot == null).toList();
    final knockout = all.where((m) => m.bracketSlot != null).toList();
    final leagueDone = league.isNotEmpty && league.every((m) => m.completed);

    var slotDocs = (await bracket.get()).docs;
    final oldFormat = slotDocs.isNotEmpty &&
        slotDocs.any((d) => d.data()['format'] != _iplFormat) &&
        !knockout.any((m) => m.completed);
    if (slotDocs.isEmpty || oldFormat) {
      // The bracket appears as soon as there are league matches; its teams fill
      // in from the points table when the league is complete.
      if (league.isEmpty) return;
      final teamIds = {for (final m in league) ...[m.teamAId, m.teamBId]};
      if (teamIds.length < 4) return;
      if (oldFormat) {
        final refs = <DocumentReference>[];
        for (final m in knockout) {
          for (final i in (await matches.doc(m.id).collection('innings').get()).docs) {
            refs.add(i.reference);
          }
          refs.add(matches.doc(m.id));
        }
        await _deleteAll(refs);
        knockout.clear();
      }
      await _writeTableBracket();
      slotDocs = (await bracket.get()).docs;
    }
    slotDocs = slotDocs.where((d) => d.data()['tableSeeded'] == true).toList();
    if (slotDocs.isEmpty) return;

    final edited = slotDocs.any((d) => d.data()['manual'] == true);
    if (!edited && !knockout.any((m) => m.completed)) {
      const teamCount = 4;
      // Seed position (1-based) -> team, only once the table is final.
      final seeds = <int, Team>{};
      if (leagueDone) {
        final innings = <String, Map<String, Innings>>{
          for (final m in league)
            m.id: {
              m.teamAId: await loadInnings(m.id, m.teamAId),
              m.teamBId: await loadInnings(m.id, m.teamBId),
            },
        };
        final table = computeStandings(league, innings: innings);
        for (var i = 0; i < table.length && i < teamCount; i++) {
          seeds[i + 1] = Team(id: table[i].id, name: table[i].name, ownerId: '', ownerName: '');
        }
      }
      await _reseed(slotDocs, seeds, knockout);
    }
    await _scheduleReadySlots();
  }

  /// Bracket wording shown on a playoff match until its team is known.
  static String _placeholder(String slot, String side) {
    const names = {
      'r0m0': ('Table #1', 'Table #2'),
      'r0m1': ('Table #3', 'Table #4'),
      'r1m0': ('Loser of Qualifier 1', 'Winner of Eliminator'),
      'r2m0': ('Winner of Qualifier 1', 'Winner of Qualifier 2'),
    };
    final n = names[slot];
    return n == null ? '' : (side == 'teamA' ? n.$1 : n.$2);
  }

  static Future<void> _reseed(List<QueryDocumentSnapshot<Map<String, dynamic>>> slotDocs,
      Map<int, Team> seeds, List<MatchGame> knockout) async {
    final round0 = slotDocs.where((d) => d.data()['round'] == 0).toList();
    final unchanged = round0.every((d) {
      final m = d.data();
      return m['teamAId'] == seeds[m['seedA']]?.id && m['teamBId'] == seeds[m['seedB']]?.id;
    });
    if (unchanged) return;

    final batch = _fs.batch();
    // Wipe every slot. Scheduled playoff matches (none is played yet) stay, so
    // their dates stay too: they are only reset and get the new teams below.
    for (final d in slotDocs) {
      batch.update(d.reference, {
        'teamAId': null,
        'teamAName': null,
        'teamBId': null,
        'teamBName': null,
        'winnerId': null,
        'winnerName': null,
        'scoreText': null,
      });
    }
    final seeded = {for (final d in round0) d.id: d.data()};
    for (final d in round0) {
      final m = d.data();
      final a = seeds[m['seedA']], b = seeds[m['seedB']];
      batch.update(d.reference, {
        'teamAId': a?.id,
        'teamAName': a?.name,
        'teamBId': b?.id,
        'teamBName': b?.name,
      });
    }
    for (final m in knockout) {
      for (final i in (await matches.doc(m.id).collection('innings').get()).docs) {
        batch.delete(i.reference);
      }
      final slot = m.bracketSlot!;
      final seed = seeded[slot];
      final a = seed == null ? null : seeds[seed['seedA']];
      final b = seed == null ? null : seeds[seed['seedB']];
      batch.update(matches.doc(m.id), {
        'teamAId': a?.id ?? '',
        'teamAName': a?.name ?? _placeholder(slot, 'teamA'),
        'teamBId': b?.id ?? '',
        'teamBName': b?.name ?? _placeholder(slot, 'teamB'),
        'completed': false,
        'scoreA': 0,
        'scoreB': 0,
        'winnerId': null,
        'live': false,
      });
    }
    await batch.commit();
  }

  /// Admin edit of one bracket slot: change its two teams and the date/venue of
  /// its match (created if it has none). Marks the bracket as hand-edited so it
  /// is no longer re-seeded from the table until [resetBracketToTable].
  static Future<void> updateBracketSlot(
    BracketSlot s, {
    required Team a,
    required Team b,
    required DateTime when,
    required String venue,
  }) async {
    final batch = _fs.batch();
    final slotUpdate = {
      'teamAId': a.id,
      'teamAName': a.name,
      'teamBId': b.id,
      'teamBName': b.name,
      'manual': true,
    };
    if (s.matchId != null) {
      batch.update(matches.doc(s.matchId), {
        'teamAId': a.id,
        'teamAName': a.name,
        'teamBId': b.id,
        'teamBName': b.name,
        'dateTime': Timestamp.fromDate(when),
        'venue': venue,
      });
      batch.update(bracket.doc(s.id), {...slotUpdate, 'matchTime': Timestamp.fromDate(when)});
    } else {
      final ref = matches.doc();
      batch.set(ref, _matchData(a, b, when, venue, bracketSlot: s.id));
      batch.update(bracket.doc(s.id), {...slotUpdate, 'matchId': ref.id, 'matchTime': Timestamp.fromDate(when)});
    }
    await batch.commit();
  }

  /// Drops the admin's manual edits and re-seeds the bracket from the table.
  static Future<void> resetBracketToTable() async {
    final batch = _fs.batch();
    for (final d in (await bracket.get()).docs) {
      batch.update(d.reference, {'manual': FieldValue.delete()});
    }
    await batch.commit();
    await refreshBracket();
  }

  /// Creates the match for every table-seeded slot that has both teams but no
  /// match yet: in 25 minute slots right after the latest scheduled match.
  static Future<void> _scheduleReadySlots() async {
    final slots = (await bracket.get()).docs.where((d) => d.data()['tableSeeded'] == true).map(BracketSlot.fromDoc).toList()
      ..sort((a, b) => a.round != b.round ? a.round.compareTo(b.round) : a.index.compareTo(b.index));
    final todo = slots.where((s) => s.ready && s.winnerId == null && s.matchId == null).toList();
    if (todo.isEmpty) return;
    final all = (await matches.get()).docs.map(MatchGame.fromDoc).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    // Same rhythm as the league: one match every 25 minutes,
    // straight after the last scheduled match.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    var base = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 0);
    if (all.isNotEmpty) base = all.last.dateTime.add(const Duration(minutes: 25));
    final venue = all.isEmpty ? '' : all.last.venue;
    final batch = _fs.batch();
    for (var k = 0; k < todo.length; k++) {
      final s = todo[k];
      final a = Team(id: s.teamAId!, name: s.teamAName ?? '', ownerId: '', ownerName: '');
      final b = Team(id: s.teamBId!, name: s.teamBName ?? '', ownerId: '', ownerName: '');
      final when = base.add(Duration(minutes: k * 25));
      final ref = matches.doc();
      batch.set(ref, _matchData(a, b, when, venue, bracketSlot: s.id));
      batch.update(bracket.doc(s.id), {'matchId': ref.id, 'matchTime': Timestamp.fromDate(when)});
    }
    await batch.commit();
  }

  /// Removes the whole tournament: the bracket, every match (league and
  /// knockout) and the scorecards stored under them. Teams and players stay.
  static Future<void> deleteTournament() async {
    final refs = <DocumentReference>[
      for (final d in (await bracket.get()).docs) d.reference,
    ];
    for (final m in (await matches.get()).docs) {
      for (final i in (await m.reference.collection('innings').get()).docs) {
        refs.add(i.reference);
      }
      refs.add(m.reference);
    }
    await _deleteAll(refs);
  }

  static Future<void> _deleteAll(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _fs.batch();
      for (final r in refs.sublist(i, i + 400 > refs.length ? refs.length : i + 400)) {
        batch.delete(r);
      }
      await batch.commit();
    }
  }

  /// Creates a real match for a bracket slot whose two teams are known.
  static Future<void> scheduleBracketMatch(BracketSlot s, DateTime when, String venue) async {
    final a = Team(id: s.teamAId!, name: s.teamAName ?? '', ownerId: '', ownerName: '');
    final b = Team(id: s.teamBId!, name: s.teamBName ?? '', ownerId: '', ownerName: '');
    final ref = matches.doc();
    final batch = _fs.batch();
    batch.set(ref, _matchData(a, b, when, venue, bracketSlot: s.id));
    batch.update(bracket.doc(s.id), {'matchId': ref.id, 'matchTime': Timestamp.fromDate(when)});
    await batch.commit();
  }

  /// Mirrors a match result into the bracket: a decided, completed match moves
  /// its winner (and in Qualifier 1 its loser) on; anything else (draw,
  /// reopened, upcoming) takes them out again.
  static Future<void> syncBracket(String matchId) async {
    final d = (await matches.doc(matchId).get()).data();
    final slot = d?['bracketSlot'] as String?;
    if (d == null || slot == null) return;
    final winnerId = d['winnerId'] as String?;
    if (d['completed'] == true && winnerId != null) {
      final aWon = winnerId == d['teamAId'];
      await _applySlotResult(slot,
          winnerId: winnerId,
          winnerName: aWon ? d['teamAName'] : d['teamBName'],
          loserId: aWon ? d['teamBId'] : d['teamAId'],
          loserName: aWon ? d['teamBName'] : d['teamAName'],
          scoreText: '${d['scoreA']} - ${d['scoreB']}');
    } else {
      await _applySlotResult(slot);
    }
  }

  static Future<void> _applySlotResult(String slotId,
      {String? winnerId,
      String? winnerName,
      String? loserId,
      String? loserName,
      String? scoreText,
      bool unlink = false}) async {
    final ref = bracket.doc(slotId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final s = BracketSlot.fromDoc(snap);
    final batch = _fs.batch();
    batch.update(ref, {
      'winnerId': winnerId,
      'winnerName': winnerName,
      'scoreText': scoreText,
      if (unlink) 'matchId': null,
    });
    final isIpl = snap.data()?['format'] == _iplFormat;
    final routes = isIpl
        ? _iplRoutes(slotId)
        : [('r${s.round + 1}m${s.index ~/ 2}', s.index.isEven ? 'teamA' : 'teamB', true)];
    for (final (targetId, side, winnerGoes) in routes) {
      final nextRef = bracket.doc(targetId);
      final nextSnap = await nextRef.get();
      if (!nextSnap.exists) continue;
      final id = winnerGoes ? winnerId : loserId;
      final name = winnerGoes ? winnerName : loserName;
      batch.update(nextRef, {'${side}Id': id, '${side}Name': name});
      // Keep a not-yet-played next-round match in step with the new team.
      final nextMatchId = BracketSlot.fromDoc(nextSnap).matchId;
      if (nextMatchId != null) {
        final nm = await matches.doc(nextMatchId).get();
        if (nm.exists && nm.data()!['completed'] != true) {
          batch.update(nm.reference, {'${side}Id': id ?? '', '${side}Name': name ?? _placeholder(targetId, side)});
        }
      }
    }
    await batch.commit();
  }

  /// Round-robin: every team plays every other team once. Pairs that already
  /// have a match are skipped. [matchesPerDay] matches per day, spaced
  /// [slotMinutes] apart, one day after another starting from [start].
  static Future<int> generateRoundRobin({
    required List<Team> allTeams,
    required List<MatchGame> existing,
    required DateTime start,
    required int matchesPerDay,
    required int slotMinutes,
    required String venue,
  }) async {
    bool exists(Team a, Team b) => existing.any((m) =>
        (m.teamAId == a.id && m.teamBId == b.id) || (m.teamAId == b.id && m.teamBId == a.id));

    final pairs = <List<Team>>[];
    for (var i = 0; i < allTeams.length; i++) {
      for (var j = i + 1; j < allTeams.length; j++) {
        if (!exists(allTeams[i], allTeams[j])) pairs.add([allTeams[i], allTeams[j]]);
      }
    }
    var batch = _fs.batch();
    for (var k = 0; k < pairs.length; k++) {
      final day = k ~/ matchesPerDay;
      final slot = k % matchesPerDay;
      final when = start.add(Duration(days: day, minutes: slot * slotMinutes));
      batch.set(matches.doc(), _matchData(pairs[k][0], pairs[k][1], when, venue));
      if ((k + 1) % 400 == 0) {
        await batch.commit();
        batch = _fs.batch();
      }
    }
    await batch.commit();
    await refreshBracket();
    return pairs.length;
  }
}
