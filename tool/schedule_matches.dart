// Arranges the 66 league matches in tool/apl2026.json (in the order they are listed)
// over the match days. The 4 playoff matches are added by tool/import_data.dart after
// the last league match, so they land on the last day:
//   Nov 8 - 15, Nov 9 - 25, Nov 10 - 20, Nov 11 - 6 league + 4 playoffs = 10
//   (70 matches in total).
// Every day starts at 17:00 (5 PM) with a match every 25 minutes (a match day runs 5 PM to 5 PM the next day,
// so late matches carry the next calendar date).
// Safe to run again: the result is the same.
//
// Run from the project root:
//   dart tool/schedule_matches.dart            rewrites the "matches" list
//   dart tool/schedule_matches.dart --dry-run  only prints the new schedule
//   dart tool/schedule_matches.dart --push     arranges AND writes it to Firebase in one go
//                                              (replaces all matches; asks for the admin
//                                              password, hidden, and a "yes")
import 'dart:convert';
import 'dart:io';

const leagueMatchesPerDay = {
  '2026-11-08': 15,
  '2026-11-09': 25,
  '2026-11-10': 20,
  '2026-11-11': 6,
};
const dayStart = '17:00'; // a match day runs from 5 PM until 5 AM the next morning
const slotMinutes = 25;

String two(int n) => n.toString().padLeft(2, '0');

Future<void> main(List<String> args) async {
  final dry = args.contains('--dry-run');
  final file = File('tool/apl2026.json');
  if (!file.existsSync()) {
    stderr.writeln('Run this from the project root (tool/apl2026.json must exist).');
    exit(1);
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final all = (data['matches'] as List).map((m) => List<dynamic>.of(m as List)).toList();
  final total = leagueMatchesPerDay.values.reduce((a, b) => a + b);
  if (all.length != total) {
    stderr.writeln('File has ${all.length} league matches; need $total.');
    exit(1);
  }

  var next = 0;
  for (final e in leagueMatchesPerDay.entries) {
    var t = DateTime.parse('${e.key} $dayStart:00');
    final first = next;
    for (var i = 0; i < e.value; i++, next++) {
      all[next][0] = '${t.year}-${two(t.month)}-${two(t.day)}';
      all[next][1] = '${two(t.hour)}:${two(t.minute)}';
      t = t.add(const Duration(minutes: slotMinutes));
    }
    stdout.writeln('${e.key}: ${e.value} league matches (${all[first][0]} ${all[first][1]} - ${all[next - 1][0]} ${all[next - 1][1]})');
  }
  stdout.writeln('Total: ${all.length} league matches + 4 playoffs added by the import = ${all.length + 4}');
  if (dry) {
    stdout.writeln('Dry run only - file not changed.');
    return;
  }

  data['matches'] = all;
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  stdout.writeln('Updated tool/apl2026.json.');

  if (args.contains('--push')) {
    stdout.writeln('\nWriting to Firebase (replaces all existing matches)...');
    final p = await Process.start(
        Platform.resolvedExecutable, ['tool/import_data.dart', '--matches-only', '--clean-matches'],
        mode: ProcessStartMode.inheritStdio);
    exit(await p.exitCode);
  }
}
