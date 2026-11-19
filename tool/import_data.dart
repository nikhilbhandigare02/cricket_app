// Imports owners, teams, players and matches from tool/apl2026.json into your
// Firebase project. Nothing is hardcoded in the app: this script reads the JSON
// file and writes to Firestore as your admin (so your Firestore rules still apply).
//
// Run from the project root:
//   dart tool/import_data.dart            asks for your admin password (hidden)
//   dart tool/import_data.dart --clean    first deletes the existing owners, teams,
//                                         players, matches, scorecards and bracket
//   dart tool/import_data.dart --matches-only  only (re)writes the matches, using the teams
//                                         already in Firebase (matched by team name);
//                                         owners, logins, teams and players are untouched
//   dart tool/import_data.dart --matches-only --clean-matches  also deletes the existing
//                                         matches, scorecards and bracket first
//   dart tool/import_data.dart --dry-run  only checks the file, no network
//
// Optional environment variables: SEED_ADMIN_EMAIL (default admin@gmail.com),
// SEED_ADMIN_PASSWORD (otherwise you are asked), SEED_OWNER_PASSWORD (default
// Owner@123, used for every new owner login), SEED_YES=1 (skip the confirmation).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final env = Platform.environment;
final adminEmail = env['SEED_ADMIN_EMAIL'] ?? 'admin@gmail.com';
final ownerPassword = env['SEED_OWNER_PASSWORD'] ?? 'Owner@123';

class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);
  @override
  String toString() => '$message (HTTP $status)';
}

Future<Map<String, dynamic>> call(String method, String url, {Map<String, dynamic>? body, String? token}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    req.headers.contentType = ContentType.json;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    if (res.statusCode >= 300) {
      throw ApiError(res.statusCode, (json['error']?['message'] ?? text).toString());
    }
    return json;
  } finally {
    client.close();
  }
}

// ---- Firestore value encoding

Map<String, dynamic> val(Object? v) {
  if (v == null) return {'nullValue': null};
  if (v is bool) return {'booleanValue': v};
  if (v is int) return {'integerValue': '$v'};
  if (v is String) return {'stringValue': v};
  if (v is DateTime) return {'timestampValue': v.toUtc().toIso8601String()};
  throw ArgumentError('Unsupported value $v');
}

class Writer {
  final String base;
  final writes = <Map<String, dynamic>>[];
  Writer(this.base);

  void set(String path, Map<String, Object?> data) => writes.add({
        'update': {'name': '$base/$path', 'fields': data.map((k, v) => MapEntry(k, val(v)))},
      });

  void delete(String fullName) => writes.add({'delete': fullName});
}

Future<void> commitAll(String base, String token, List<Map<String, dynamic>> writes, String label) async {
  const chunk = 15; // keeps each request well inside Firestore's rules-lookup limit
  for (var i = 0; i < writes.length; i += chunk) {
    await call('POST', 'https://firestore.googleapis.com/v1/$base:commit',
        body: {'writes': writes.sublist(i, min(i + chunk, writes.length))}, token: token);
    stdout.write('\r$label ${min(i + chunk, writes.length)} / ${writes.length}   ');
  }
  if (writes.isNotEmpty) stdout.writeln();
}

/// Every document in a collection (all pages), as {name, fields}.
Future<List<Map<String, dynamic>>> listDocs(String base, String token, String path) async {
  final out = <Map<String, dynamic>>[];
  String? page;
  do {
    final url = 'https://firestore.googleapis.com/v1/$base/$path?pageSize=300${page == null ? '' : '&pageToken=$page'}';
    final r = await call('GET', url, token: token);
    out.addAll(((r['documents'] ?? []) as List).cast<Map<String, dynamic>>());
    page = r['nextPageToken'] as String?;
  } while (page != null);
  return out;
}

String readPassword() {
  final fromEnv = env['SEED_ADMIN_PASSWORD'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  stdout.write('Password for $adminEmail (hidden): ');
  var hidden = false;
  try {
    stdin.echoMode = false;
    hidden = true;
  } catch (_) {}
  final pw = stdin.readLineSync() ?? '';
  if (hidden) {
    stdin.echoMode = true;
    stdout.writeln();
  }
  return pw;
}

Never fail(String msg) {
  stderr.writeln(msg);
  exit(1);
}

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry-run');
  final clean = args.contains('--clean');
  final matchesOnly = args.contains('--matches-only');
  final cleanMatches = args.contains('--clean-matches');

  // ---- load and check the data file
  final dataFile = File('tool/apl2026.json');
  final cfgFile = File('android/app/google-services.json');
  if (!dataFile.existsSync() || !cfgFile.existsSync()) {
    fail('Run this from the project root (tool/apl2026.json and android/app/google-services.json must exist).');
  }
  final data = jsonDecode(dataFile.readAsStringSync()) as Map<String, dynamic>;
  final venue = (data['venue'] ?? '') as String;
  final teams = (data['teams'] as List).cast<Map<String, dynamic>>();
  final matches = (data['matches'] as List).cast<List<dynamic>>();
  final keys = {for (final t in teams) t['key'] as String};
  if (keys.length != teams.length) fail('Duplicate team keys in tool/apl2026.json');
  // Team logos: "logo" is a picture file path in the JSON; sent as base64 in the team document.
  final logos = <String, String>{};
  for (final t in teams) {
    final path = t['logo'] as String?;
    if (matchesOnly || path == null || path.isEmpty) continue;
    final f = File(path);
    if (!f.existsSync()) fail('Logo file not found for ${t['name']}: $path');
    if (f.lengthSync() > 300 * 1024) fail('Logo for ${t['name']} is over 300 KB: $path');
    logos[t['key'] as String] = base64Encode(f.readAsBytesSync());
  }
  stdout.writeln('${logos.length} team logos found.');
  final pairs = <String>{};
  for (final m in matches) {
    final a = m[2] as String, b = m[3] as String;
    if (!keys.contains(a) || !keys.contains(b) || a == b) fail('Bad match entry: $m');
    if (!pairs.add(([a, b]..sort()).join('-'))) stdout.writeln('Note: $a vs $b appears more than once.');
    DateTime.parse('${m[0]} ${m[1]}:00'); // throws on a bad date/time
  }
  final expected = teams.length * (teams.length - 1) ~/ 2;
  stdout.writeln('${teams.length} teams, ${matches.length} matches, ${pairs.length} different pairings '
      '(a full round-robin would have $expected).');
  if (pairs.length < expected) {
    stdout.writeln('Warning: ${expected - pairs.length} pairing(s) are missing, so not every team plays every other team.');
  }
  if (dry) {
    stdout.writeln('Dry run only - nothing was sent.');
    return;
  }

  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId = cfg['project_info']['project_id'] as String;
  final apiKey = cfg['client'][0]['api_key'][0]['current_key'] as String;
  final base = 'projects/$projectId/databases/(default)/documents';

  stdout.writeln('\nFirebase project: $projectId');
  if (clean) stdout.writeln('--clean: ALL existing owners, teams, players, matches, scorecards and the bracket will be deleted first.');
  if (matchesOnly) {
    stdout.writeln('--matches-only: writes ${matches.length} matches for the teams already in Firebase.');
    if (cleanMatches) stdout.writeln('--clean-matches: ALL existing matches, scorecards and the bracket will be deleted first.');
  } else {
    stdout.writeln('Owner logins are created with password "$ownerPassword" (existing ones are reused).');
  }
  if (env['SEED_YES'] != '1') {
    stdout.write('Type "yes" to continue: ');
    if ((stdin.readLineSync() ?? '').trim().toLowerCase() != 'yes') {
      stdout.writeln('Cancelled.');
      return;
    }
  }

  // ---- sign in as admin
  const auth = 'https://identitytoolkit.googleapis.com/v1/accounts';
  final adminPw = readPassword();
  String token;
  try {
    final r = await call('POST', '$auth:signInWithPassword?key=$apiKey',
        body: {'email': adminEmail, 'password': adminPw, 'returnSecureToken': true});
    token = r['idToken'] as String;
  } on ApiError catch (e) {
    fail('Admin sign-in failed: $e');
  }
  stdout.writeln('Signed in as $adminEmail.');

  try {
    // ---- optional clean-up
    if (clean) {
      final del = Writer(base);
      for (final t in await listDocs(base, token, 'teams')) {
        final id = (t['name'] as String).split('/').last;
        for (final p in await listDocs(base, token, 'teams/$id/players')) {
          del.delete(p['name'] as String);
        }
        del.delete(t['name'] as String);
      }
      for (final m in await listDocs(base, token, 'matches')) {
        final id = (m['name'] as String).split('/').last;
        for (final i in await listDocs(base, token, 'matches/$id/innings')) {
          del.delete(i['name'] as String);
        }
        del.delete(m['name'] as String);
      }
      for (final c in ['owners', 'bracket']) {
        for (final d in await listDocs(base, token, c)) {
          del.delete(d['name'] as String);
        }
      }
      for (final u in await listDocs(base, token, 'users')) {
        if (u['fields']?['role']?['stringValue'] == 'owner') del.delete(u['name'] as String);
      }
      await commitAll(base, token, del.writes, 'Deleted');
    }

    // ---- matches only: replace old matches, then look the teams up by name
    final existingTeamIds = <String, String>{};
    if (matchesOnly) {
      if (cleanMatches) {
        final del = Writer(base);
        for (final m in await listDocs(base, token, 'matches')) {
          final id = (m['name'] as String).split('/').last;
          for (final i in await listDocs(base, token, 'matches/$id/innings')) {
            del.delete(i['name'] as String);
          }
          del.delete(m['name'] as String);
        }
        for (final d in await listDocs(base, token, 'bracket')) {
          del.delete(d['name'] as String);
        }
        await commitAll(base, token, del.writes, 'Deleted');
      }
      for (final t in await listDocs(base, token, 'teams')) {
        final name = (t['fields']?['name']?['stringValue'] ?? '') as String;
        existingTeamIds[name.trim().toLowerCase()] = (t['name'] as String).split('/').last;
      }
      final missing = [
        for (final t in teams)
          if (!existingTeamIds.containsKey((t['name'] as String).trim().toLowerCase())) t['name'],
      ];
      if (missing.isNotEmpty) {
        fail('These teams are not in Firebase yet (add them, or run without --matches-only): $missing');
      }
    }

    // ---- owner logins (create, or reuse if they already exist)
    final uids = <String, String>{};
    for (final t in matchesOnly ? const <Map<String, dynamic>>[] : teams) {
      final email = t['email'] as String;
      try {
        final r = await call('POST', '$auth:signUp?key=$apiKey',
            body: {'email': email, 'password': ownerPassword, 'returnSecureToken': true});
        uids[t['key'] as String] = r['localId'] as String;
        stdout.writeln('Created login $email');
      } on ApiError catch (e) {
        if (!e.message.contains('EMAIL_EXISTS')) fail('Could not create $email: $e');
        try {
          final r = await call('POST', '$auth:signInWithPassword?key=$apiKey',
              body: {'email': email, 'password': ownerPassword, 'returnSecureToken': true});
          uids[t['key'] as String] = r['localId'] as String;
          stdout.writeln('Login $email already exists - reusing');
        } on ApiError catch (e2) {
          fail('$email exists with a different password ($e2). Delete it in Firebase Authentication and run again.');
        }
      }
    }

    // ---- documents (ids are fixed, so running again overwrites rather than duplicates)
    final w = Writer(base);
    final teamId = <String, String>{};
    final teamName = <String, String>{};
    for (final t in teams) {
      final key = t['key'] as String;
      final ownerId = 'apl-owner-$key'; // team id == owner id (one team per owner)
      teamId[key] = ownerId;
      teamName[key] = t['name'] as String;
      if (matchesOnly) {
        // Keep the teams as they are in Firebase; only point the matches at them.
        teamId[key] = existingTeamIds[(t['name'] as String).trim().toLowerCase()]!;
        continue;
      }
      w.set('owners/$ownerId', {
        'name': t['ownerName'],
        'email': t['email'],
        'phone': t['phone'] ?? '',
        'uid': uids[key],
      });
      w.set('users/${uids[key]}', {'role': 'owner', 'ownerId': ownerId, 'name': t['ownerName']});
      w.set('teams/$ownerId', {
        'name': t['name'],
        'ownerId': ownerId,
        'ownerName': t['ownerName'],
        'logo': ?logos[key],
      });
      final players = ((t['players'] ?? []) as List).cast<Map<String, dynamic>>();
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        w.set('teams/$ownerId/players/p${i + 1}', {
          'name': p['name'],
          'role': p['role'] ?? '',
          'jersey': p['jersey'] ?? i + 1,
          'phone': p['phone'] ?? '',
        });
      }
    }
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final a = m[2] as String, b = m[3] as String;
      w.set('matches/apl-match-${(i + 1).toString().padLeft(2, '0')}', {
        'bracketSlot': null,
        'teamAId': teamId[a],
        'teamAName': teamName[a],
        'teamBId': teamId[b],
        'teamBName': teamName[b],
        'dateTime': DateTime.parse('${m[0]} ${m[1]}:00'),
        'venue': venue,
        'completed': false,
        'scoreA': 0,
        'scoreB': 0,
        'winnerId': null,
      });
    }
    // Playoffs: four matches (IPL format) right after the last league match, one
    // every 25 minutes, with no teams yet. The app fills the teams in from the
    // points table when the league ends. Same slot ids as the app's own bracket.
    var last = DateTime.parse('${matches.first[0]} ${matches.first[1]}:00');
    for (final m in matches) {
      final t = DateTime.parse('${m[0]} ${m[1]}:00');
      if (t.isAfter(last)) last = t;
    }
    const playoffs = [
      ('r0m0', 0, 0, 1, 2, 'Table #1', 'Table #2'),
      ('r0m1', 0, 1, 3, 4, 'Table #3', 'Table #4'),
      ('r1m0', 1, 0, null, null, 'Loser of Qualifier 1', 'Winner of Eliminator'),
      ('r2m0', 2, 0, null, null, 'Winner of Qualifier 1', 'Winner of Qualifier 2'),
    ];
    for (var k = 0; k < playoffs.length; k++) {
      final (slot, round, index, seedA, seedB, nameA, nameB) = playoffs[k];
      final when = last.add(Duration(minutes: 25 * (k + 1)));
      final matchId = 'apl-match-${(matches.length + k + 1).toString().padLeft(2, '0')}';
      w.set('matches/$matchId', {
        'bracketSlot': slot,
        'teamAId': '',
        'teamAName': nameA,
        'teamBId': '',
        'teamBName': nameB,
        'dateTime': when,
        'venue': venue,
        'completed': false,
        'scoreA': 0,
        'scoreB': 0,
        'winnerId': null,
      });
      w.set('bracket/$slot', {
        'round': round,
        'index': index,
        'teamAId': null,
        'teamAName': null,
        'teamBId': null,
        'teamBName': null,
        'winnerId': null,
        'winnerName': null,
        'matchId': matchId,
        'matchTime': when,
        'scoreText': null,
        'tableSeeded': true,
        'format': 'ipl',
        'teamCount': 4,
        'seedA': seedA,
        'seedB': seedB,
      });
    }
    await commitAll(base, token, w.writes, 'Written');
  } on ApiError catch (e) {
    stderr.writeln('\nFirestore request failed: $e');
    stderr.writeln('If this says permission denied: publish firestore.rules, and check that users/{your admin uid} has role = admin.');
    exit(1);
  }

  if (matchesOnly) {
    stdout.writeln('\nDone: ${matches.length} matches written.');
    return;
  }
  stdout.writeln('\nDone: ${teams.length} owners and teams, ${matches.length} matches.');
  stdout.writeln('Admin login:  $adminEmail (your password)');
  stdout.writeln('Owner logins: ${teams.first['email']} ... ${teams.last['email']}  password "$ownerPassword"');
}
