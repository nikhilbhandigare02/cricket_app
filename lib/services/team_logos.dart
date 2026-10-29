import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'db.dart';

/// Team logos, kept as a small base64 JPEG in the team's Firestore document
/// (field `logo`). One listener feeds [logos] so every screen can show a team's
/// logo by id without each loading it separately.
class TeamLogos {
  static final logos = ValueNotifier<Map<String, Uint8List>>({});
  static final _raw = <String, String>{};
  static StreamSubscription<dynamic>? _sub;

  /// Starts listening (once). Safe to call from any widget's build.
  static void ensure() {
    if (_sub != null) return;
    _sub = Db.teams.snapshots().listen(
      (snap) {
        final next = <String, Uint8List>{};
        for (final d in snap.docs) {
          final s = d.data()['logo'];
          if (s is! String || s.isEmpty) continue;
          final cached = logos.value[d.id];
          if (cached != null && _raw[d.id] == s) {
            next[d.id] = cached; // unchanged: reuse the same bytes so images stay cached
            continue;
          }
          try {
            next[d.id] = base64Decode(s);
            _raw[d.id] = s;
          } catch (_) {}
        }
        logos.value = next;
      },
      onError: (_) {
        _sub?.cancel(); // e.g. signed out; try again on next use
        _sub = null;
      },
    );
  }

  /// Call when signing out.
  static void reset() {
    _sub?.cancel();
    _sub = null;
    _raw.clear();
    logos.value = {};
  }

  /// Opens the gallery and returns the chosen picture shrunk to 256 px as a
  /// base64 JPEG (about 20-40 KB), or null if nothing was picked.
  static Future<String?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 80,
    );
    if (file == null) return null;
    return base64Encode(await file.readAsBytes());
  }
}
