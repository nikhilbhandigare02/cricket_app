// Adds TEST data: 8 teams (7 players each), a full round-robin of 28 matches where
// every team has exactly 1 upcoming match (4 upcoming) and the other 24 are completed,
// plus the empty IPL playoff bracket. All ids start with "test-" so nothing real is touched.
//   SEED_EMAIL=... SEED_PASSWORD=... dart tool/seed_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

Future<Map<String, dynamic>> call(String method, String url, {Map<String, dynamic>? body, String? token}) async {
  final c = HttpClient();
  try {
    final req = await c.openUrl(method, Uri.parse(url));
    req.headers.contentType = ContentType.json;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final j = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (res.statusCode >= 300) throw '${j['error']?['message'] ?? text} (HTTP ${res.statusCode})';
    return j;
  } finally {
    c.close();
  }
}

Map<String, dynamic> val(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is String) return {'stringValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  throw ArgumentError('$v');
}

Future<void> main() async {
  final cfg = jsonDecode(File('android/app/google-services.json').readAsStringSync());
  final projectId = cfg['project_info']['project_id'] as String;
  final apiKey = cfg['client'][0]['api_key'][0]['current_key'] as String;
  final base = 'projects/$projectId/databases/(default)/documents';
  final r = await call('POST', 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      body: {'email': Platform.environment['SEED_EMAIL'], 'password': Platform.environment['SEED_PASSWORD'], 'returnSecureToken': true});
  final token = r['idToken'] as String;
  stdout.writeln('Signed in. Project $projectId');

  final writes = <Map<String, dynamic>>[];
  void set(String path, Map<String, Object?> d) =>
      writes.add({'update': {'name': '$base/$path', 'fields': d.map((k, v) => MapEntry(k, val(v)))}});

  const names = ['Test Tigers', 'Test Lions', 'Test Eagles', 'Test Panthers', 'Test Sharks', 'Test Wolves', 'Test Hawks', 'Test Bulls'];
  const roles = ['Batsman', 'Batsman', 'All-rounder', 'All-rounder', 'Bowler', 'Bowler', 'Wicket-keeper'];
  final ids = [for (var i = 1; i <= 8; i++) 'test-team-$i'];
  const auth = 'https://identitytoolkit.googleapis.com/v1/accounts';
  final ownerPw = Platform.environment['SEED_OWNER_PASSWORD'] ?? 'Owner@123';
  for (var i = 0; i < 8; i++) {
    final email = 'owner${i + 1}@gmail.com';
    String uid;
    try {
      uid = (await call('POST', '$auth:signUp?key=$apiKey', body: {'email': email, 'password': ownerPw, 'returnSecureToken': true}))['localId'];
      stdout.writeln('Created login $email');
    } catch (e) {
      if (!e.toString().contains('EMAIL_EXISTS')) rethrow;
      uid = (await call('POST', '$auth:signInWithPassword?key=$apiKey', body: {'email': email, 'password': ownerPw, 'returnSecureToken': true}))['localId'];
      stdout.writeln('Login $email exists - reusing');
    }
    set('users/$uid', {'role': 'owner', 'ownerId': ids[i], 'name': 'Test Owner ${i + 1}'});
    set('owners/${ids[i]}', {'name': 'Test Owner ${i + 1}', 'email': email, 'phone': '', 'uid': uid});
    set('teams/${ids[i]}', {'name': names[i], 'ownerId': ids[i], 'ownerName': 'Test Owner ${i + 1}'});
    for (var p = 0; p < 7; p++) {
      set('teams/${ids[i]}/players/p${p + 1}', {'name': 'T${i + 1} Player ${p + 1}', 'role': roles[p], 'jersey': p + 1, 'phone': ''});
    }
  }

  const venue = 'Test Ground';
  final rnd = Random(7);
  final upcoming = {'0-1', '2-3', '4-5', '6-7'};
  var n = 0;
  final start = DateTime(2026, 11, 12, 17, 0);
  var upN = 0;
  for (var a = 0; a < 8; a++) {
    for (var b = a + 1; b < 8; b++) {
      n++;
      final up = upcoming.contains('$a-$b');
      final when = up ? DateTime(2026, 11, 20 + upN++, 17, 0) : start.add(Duration(minutes: 25 * (n - 1)));
      final m = <String, Object?>{
        'bracketSlot': null,
        'teamAId': ids[a], 'teamAName': names[a],
        'teamBId': ids[b], 'teamBName': names[b],
        'dateTime': when, 'venue': venue,
        'completed': !up, 'scoreA': 0, 'scoreB': 0, 'winnerId': null,
      };
      if (!up) {
        final sa = 40 + rnd.nextInt(50);
        var sb = 40 + rnd.nextInt(50);
        if (sb == sa) sb++;
        m['scoreA'] = sa;
        m['scoreB'] = sb;
        m['winnerId'] = sa > sb ? ids[a] : ids[b];
      }
      set('matches/test-match-${n.toString().padLeft(2, '0')}', m);
    }
  }

  // Empty IPL playoff bracket (teams are filled in by the app when the league ends).
  const playoffs = [
    ('r0m0', 0, 0, 1, 2, 'Table #1', 'Table #2'),
    ('r0m1', 0, 1, 3, 4, 'Table #3', 'Table #4'),
    ('r1m0', 1, 0, null, null, 'Loser of Qualifier 1', 'Winner of Eliminator'),
    ('r2m0', 2, 0, null, null, 'Winner of Qualifier 1', 'Winner of Qualifier 2'),
  ];
  final last = DateTime(2026, 11, 23, 17, 0);
  for (var k = 0; k < 4; k++) {
    final (slot, round, index, seedA, seedB, nameA, nameB) = playoffs[k];
    final when = last.add(Duration(minutes: 25 * (k + 1)));
    final mid = 'test-match-${(29 + k)}';
    set('matches/$mid', {
      'bracketSlot': slot, 'teamAId': '', 'teamAName': nameA, 'teamBId': '', 'teamBName': nameB,
      'dateTime': when, 'venue': venue, 'completed': false, 'scoreA': 0, 'scoreB': 0, 'winnerId': null,
    });
    set('bracket/$slot', {
      'round': round, 'index': index, 'teamAId': null, 'teamAName': null, 'teamBId': null, 'teamBName': null,
      'winnerId': null, 'winnerName': null, 'matchId': mid, 'matchTime': when, 'scoreText': null,
      'tableSeeded': true, 'format': 'ipl', 'teamCount': 4, 'seedA': seedA, 'seedB': seedB,
    });
  }

  for (var i = 0; i < writes.length; i += 15) {
    await call('POST', 'https://firestore.googleapis.com/v1/$base:commit',
        body: {'writes': writes.sublist(i, min(i + 15, writes.length))}, token: token);
  }
  stdout.writeln('Wrote ${writes.length} documents: 8 teams, 28 league matches (24 completed, 4 upcoming), 4 playoff slots.');
}
