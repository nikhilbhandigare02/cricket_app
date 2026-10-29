import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/models.dart';
import '../models/scorecard.dart';
import 'team_logos.dart';

class Db {
  static final _fs = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static CollectionReference<Map<String, dynamic>> get owners => _fs.collection('owners');
  static CollectionReference<Map<String, dynamic>> get teams => _fs.collection('teams');
  static CollectionReference<Map<String, dynamic>> get matches => _fs.collection('matches');
  static CollectionReference<Map<String, dynamic>> get users => _fs.collection('users');

  // ---------- auth / profile ----------
  static Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

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
    required List<Map<String, dynamic>> players,
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
    if (slot != null) await _applySlotResult(slot, unlink: true);
  }

  static Future<void> updateSchedule(String id, DateTime when, String venue) =>
      matches.doc(id).update({'dateTime': Timestamp.fromDate(when), 'venue': venue});

  static Future<void> saveResult(MatchGame m, int scoreA, int scoreB) async {
    await matches.doc(m.id).update({
      'completed': true,
      'scoreA': scoreA,
      'scoreB': scoreB,
      'winnerId': scoreA == scoreB ? null : (scoreA > scoreB ? m.teamAId : m.teamBId),
    });
    await syncBracket(m.id);
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
  }

  static Future<void> reopenMatch(String id) async {
    await matches.doc(id).update({'completed': false, 'scoreA': 0, 'scoreB': 0, 'winnerId': null});
    await syncBracket(id);
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

  /// Standard seeding order so top seeds only meet late: size 8 => 1,8,4,5,2,7,3,6.
  static List<int> _seedOrder(int size) {
    var order = [1];
    while (order.length < size) {
      final n = order.length * 2;
      order = [for (final s in order) ...[s, n + 1 - s]];
    }
    return order;
  }

  /// Replaces the bracket with a single-elimination one for [seeded] (in seed
  /// order). A team without an opponent gets a bye and advances automatically.
  static Future<void> createBracket(List<Team> seeded) async {
    var size = 2;
    while (size < seeded.length) {
      size *= 2;
    }
    Team? seedTeam(int seed) => seed <= seeded.length ? seeded[seed - 1] : null;
    final order = _seedOrder(size);
    final rounds = <List<Map<String, Team?>>>[
      [
        for (var i = 0; i < size ~/ 2; i++)
          {'teamA': seedTeam(order[i * 2]), 'teamB': seedTeam(order[i * 2 + 1]), 'winner': null}
      ],
    ];
    for (var n = size ~/ 4; n >= 1; n ~/= 2) {
      rounds.add([for (var i = 0; i < n; i++) {'teamA': null, 'teamB': null, 'winner': null}]);
    }
    // Resolve byes in round 0 and push those teams into round 1.
    for (var i = 0; i < rounds[0].length; i++) {
      final s = rounds[0][i];
      final a = s['teamA'];
      final b = s['teamB'];
      if ((a == null) != (b == null) && rounds.length > 1) {
        final w = a ?? b;
        s['winner'] = w;
        rounds[1][i ~/ 2][i.isEven ? 'teamA' : 'teamB'] = w;
      }
    }
    final old = await bracket.get();
    final batch = _fs.batch();
    for (final d in old.docs) {
      batch.delete(d.reference);
    }
    for (var r = 0; r < rounds.length; r++) {
      for (var i = 0; i < rounds[r].length; i++) {
        final s = rounds[r][i];
        batch.set(bracket.doc('r${r}m$i'), {
          'round': r,
          'index': i,
          'teamAId': s['teamA']?.id,
          'teamAName': s['teamA']?.name,
          'teamBId': s['teamB']?.id,
          'teamBName': s['teamB']?.name,
          'winnerId': s['winner']?.id,
          'winnerName': s['winner']?.name,
          'matchId': null,
          'scoreText': null,
        });
      }
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
    batch.update(bracket.doc(s.id), {'matchId': ref.id});
    await batch.commit();
  }

  /// Mirrors a match result into the bracket: a decided, completed match moves
  /// its winner on to the next round; anything else (draw, reopened, upcoming)
  /// takes that winner out again.
  static Future<void> syncBracket(String matchId) async {
    final d = (await matches.doc(matchId).get()).data();
    final slot = d?['bracketSlot'] as String?;
    if (d == null || slot == null) return;
    final winnerId = d['winnerId'] as String?;
    if (d['completed'] == true && winnerId != null) {
      final name = winnerId == d['teamAId'] ? d['teamAName'] : d['teamBName'];
      await _applySlotResult(slot,
          winnerId: winnerId, winnerName: name, scoreText: '${d['scoreA']} - ${d['scoreB']}');
    } else {
      await _applySlotResult(slot);
    }
  }

  static Future<void> _applySlotResult(String slotId,
      {String? winnerId, String? winnerName, String? scoreText, bool unlink = false}) async {
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
    final nextRef = bracket.doc('r${s.round + 1}m${s.index ~/ 2}');
    final nextSnap = await nextRef.get();
    if (nextSnap.exists) {
      final side = s.index.isEven ? 'teamA' : 'teamB';
      batch.update(nextRef, {'${side}Id': winnerId, '${side}Name': winnerName});
      // Keep a not-yet-played next-round match in step with the new team.
      final nextMatchId = BracketSlot.fromDoc(nextSnap).matchId;
      if (nextMatchId != null) {
        final nm = await matches.doc(nextMatchId).get();
        if (nm.exists && nm.data()!['completed'] != true) {
          batch.update(nm.reference, {'${side}Id': winnerId ?? '', '${side}Name': winnerName ?? ''});
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
    return pairs.length;
  }
}
