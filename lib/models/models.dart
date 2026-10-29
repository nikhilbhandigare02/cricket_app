import 'package:cloud_firestore/cloud_firestore.dart';

class Owner {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String uid;

  Owner({required this.id, required this.name, required this.email, required this.phone, required this.uid});

  factory Owner.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Owner(
      id: d.id,
      name: m['name'] ?? '',
      email: m['email'] ?? '',
      phone: m['phone'] ?? '',
      uid: m['uid'] ?? '',
    );
  }
}

class Team {
  final String id;
  final String name;
  final String ownerId;
  final String ownerName;

  Team({required this.id, required this.name, required this.ownerId, required this.ownerName});

  factory Team.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Team(
      id: d.id,
      name: m['name'] ?? '',
      ownerId: m['ownerId'] ?? '',
      ownerName: m['ownerName'] ?? '',
    );
  }
}

class Player {
  final String id;
  final String name;
  final String role;
  final int jersey;
  final String phone;

  Player({required this.id, required this.name, required this.role, required this.jersey, required this.phone});

  factory Player.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Player(
      id: d.id,
      name: m['name'] ?? '',
      role: m['role'] ?? '',
      jersey: (m['jersey'] ?? 0) as int,
      phone: m['phone'] ?? '',
    );
  }
}

class MatchGame {
  final String id;
  final String teamAId;
  final String teamAName;
  final String teamBId;
  final String teamBName;
  final DateTime dateTime;
  final String venue;
  final bool completed;
  final int scoreA;
  final int scoreB;
  final String? winnerId; // null => draw / not played
  final String? bracketSlot; // set when this match belongs to the tournament bracket

  // Live scoring, written by the admin's live scoring screen after every ball.
  final bool live;
  final String? liveBatting; // id of the team batting right now
  final String liveStrikerId, liveStriker;
  final String liveNonStrikerId, liveNonStriker;
  final String liveBowlerId, liveBowler;
  final List<String> liveOver; // balls of the current over, e.g. ['1', 'Wd', '4', 'W']
  final int liveMaxOvers;
  final DateTime? liveUpdated;

  /// Live now: flagged live, not finished, and updated recently (so a scorer who
  /// closed the app mid-match does not leave a match "live" forever).
  bool get isLive =>
      live &&
      !completed &&
      liveUpdated != null &&
      DateTime.now().difference(liveUpdated!).inMinutes < 120;

  MatchGame({
    this.bracketSlot,
    this.live = false,
    this.liveBatting,
    this.liveStrikerId = '',
    this.liveStriker = '',
    this.liveNonStrikerId = '',
    this.liveNonStriker = '',
    this.liveBowlerId = '',
    this.liveBowler = '',
    this.liveOver = const [],
    this.liveMaxOvers = 0,
    this.liveUpdated,
    required this.id,
    required this.teamAId,
    required this.teamAName,
    required this.teamBId,
    required this.teamBName,
    required this.dateTime,
    required this.venue,
    required this.completed,
    required this.scoreA,
    required this.scoreB,
    required this.winnerId,
  });

  factory MatchGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return MatchGame(
      id: d.id,
      teamAId: m['teamAId'] ?? '',
      teamAName: m['teamAName'] ?? '',
      teamBId: m['teamBId'] ?? '',
      teamBName: m['teamBName'] ?? '',
      dateTime: (m['dateTime'] as Timestamp).toDate(),
      venue: m['venue'] ?? '',
      completed: m['completed'] ?? false,
      scoreA: m['scoreA'] ?? 0,
      scoreB: m['scoreB'] ?? 0,
      winnerId: m['winnerId'],
      bracketSlot: m['bracketSlot'],
      live: m['live'] ?? false,
      liveBatting: m['liveBatting'],
      liveStrikerId: m['liveStrikerId'] ?? '',
      liveStriker: m['liveStriker'] ?? '',
      liveNonStrikerId: m['liveNonStrikerId'] ?? '',
      liveNonStriker: m['liveNonStriker'] ?? '',
      liveBowlerId: m['liveBowlerId'] ?? '',
      liveBowler: m['liveBowler'] ?? '',
      liveOver: [for (final b in (m['liveOver'] ?? const [])) '$b'],
      liveMaxOvers: m['liveMaxOvers'] ?? 0,
      liveUpdated: (m['liveUpdated'] as Timestamp?)?.toDate(),
    );
  }

  bool involves(String teamId) => teamAId == teamId || teamBId == teamId;

  /// Win / Loss / Draw / Upcoming from the point of view of [teamId].
  String statusFor(String teamId) {
    if (!completed) return 'Upcoming';
    if (winnerId == null) return 'Draw';
    return winnerId == teamId ? 'Win' : 'Loss';
  }
}

/// One match position in the knockout bracket (bracket/r{round}m{index}).
/// The winner of slot (r, i) moves into slot (r+1, i ~/ 2): side A if i is
/// even, side B if odd.
class BracketSlot {
  final String id;
  final int round;
  final int index;
  final String? teamAId;
  final String? teamAName;
  final String? teamBId;
  final String? teamBName;
  final String? winnerId;
  final String? winnerName;
  final String? matchId;
  final String? scoreText;

  BracketSlot({
    required this.id,
    required this.round,
    required this.index,
    this.teamAId,
    this.teamAName,
    this.teamBId,
    this.teamBName,
    this.winnerId,
    this.winnerName,
    this.matchId,
    this.scoreText,
  });

  bool get ready => teamAId != null && teamBId != null;

  factory BracketSlot.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return BracketSlot(
      id: d.id,
      round: m['round'] ?? 0,
      index: m['index'] ?? 0,
      teamAId: m['teamAId'],
      teamAName: m['teamAName'],
      teamBId: m['teamBId'],
      teamBName: m['teamBName'],
      winnerId: m['winnerId'],
      winnerName: m['winnerName'],
      matchId: m['matchId'],
      scoreText: m['scoreText'],
    );
  }
}
