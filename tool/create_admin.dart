// Creates a new admin login (Firebase Auth user + users/{uid} profile with role 'admin').
//
// Run from the project root:
//   dart tool/create_admin.dart jivanediter@gmail.com "Display Name"
//
// You are asked (hidden) for the NEW admin's password and for an EXISTING admin's
// password (needed because Firestore rules only let an admin write users/{uid}).
// Optional: SEED_ADMIN_EMAIL (existing admin, default admin@gmail.com).
import 'dart:convert';
import 'dart:io';

const auth = 'https://identitytoolkit.googleapis.com/v1/accounts';

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
      throw '${json['error']?['message'] ?? text} (HTTP ${res.statusCode})';
    }
    return json;
  } finally {
    client.close();
  }
}

String ask(String prompt) {
  stdout.write(prompt);
  var hidden = false;
  try {
    stdin.echoMode = false;
    hidden = true;
  } catch (_) {}
  final v = stdin.readLineSync() ?? '';
  if (hidden) {
    stdin.echoMode = true;
    stdout.writeln();
  }
  return v;
}

Future<void> main(List<String> args) async {
  final role = args.contains('--admin') ? 'admin' : 'none';
  args = args.where((a) => !a.startsWith('--')).toList();
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/create_admin.dart <email> [display name] [--admin]');
    exit(1);
  }
  final email = args[0].trim();
  final name = args.length > 1 ? args.sublist(1).join(' ') : email.split('@').first;
  final cfgFile = File('android/app/google-services.json');
  if (!cfgFile.existsSync()) {
    stderr.writeln('Run this from the project root (android/app/google-services.json not found).');
    exit(1);
  }
  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;
  final projectId = cfg['project_info']['project_id'] as String;
  final apiKey = cfg['client'][0]['api_key'][0]['current_key'] as String;
  final adminEmail = Platform.environment['SEED_ADMIN_EMAIL'] ?? 'admin@gmail.com';

  stdout.writeln('Firebase project: $projectId');
  stdout.writeln('Creating ${role == 'admin' ? 'admin' : 'regular (no role)'} user: $email');

  final newPw = ask('New password for $email (hidden, min 6 chars): ');
  if (newPw.length < 6) {
    stderr.writeln('Password too short.');
    exit(1);
  }
  final adminPw = role == 'admin' ? ask('Existing admin password for $adminEmail (hidden): ') : '';

  try {
    // 1. create the Auth user
    String uid;
    try {
      final created = await call('POST', '$auth:signUp?key=$apiKey',
          body: {'email': email, 'password': newPw, 'returnSecureToken': true});
      uid = created['localId'] as String;
      stdout.writeln('Auth user created (uid $uid).');
    } catch (e) {
      if (!e.toString().contains('EMAIL_EXISTS')) rethrow;
      // Already exists: sign in with the password you typed to get its uid.
      final existing = await call('POST', '$auth:signInWithPassword?key=$apiKey',
          body: {'email': email, 'password': newPw, 'returnSecureToken': true});
      uid = existing['localId'] as String;
      stdout.writeln('Auth user already existed (uid $uid); using it.');
    }

    if (role != 'admin') {
      stdout.writeln('No Firestore profile written (regular user). Done.');
      return;
    }

    // 2. sign in as the existing admin and write the profile
    final signIn = await call('POST', '$auth:signInWithPassword?key=$apiKey',
        body: {'email': adminEmail, 'password': adminPw, 'returnSecureToken': true});
    final token = signIn['idToken'] as String;
    await call('PATCH',
        'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/users/$uid',
        token: token,
        body: {
          'fields': {
            'role': {'stringValue': 'admin'},
            'name': {'stringValue': name},
          }
        });
    stdout.writeln('Profile users/$uid written with role "admin". Done.');
  } catch (e) {
    stderr.writeln('Failed: $e');
    exit(1);
  }
}
