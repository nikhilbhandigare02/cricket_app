import 'package:flutter/material.dart';
import '../models/models.dart';
import '../screens/match_detail_screen.dart';
import '../services/db.dart';
import 'animations.dart';

/// Strip of matches being scored right now. Shows nothing when none are live;
/// tap a card to follow the match ball by ball. [myTeamIds] puts the owner's own
/// matches first.
class LiveNowBanner extends StatelessWidget {
  final Set<String> myTeamIds;
  const LiveNowBanner({super.key, this.myTeamIds = const {}});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MatchGame>>(
      stream: Db.matchesStream(),
      builder: (context, snap) {
        final live = [for (final m in snap.data ?? const <MatchGame>[]) if (m.isLive) m]
          ..sort((a, b) {
            final am = a.teamAId.isNotEmpty && (myTeamIds.contains(a.teamAId) || myTeamIds.contains(a.teamBId));
            final bm = b.teamAId.isNotEmpty && (myTeamIds.contains(b.teamAId) || myTeamIds.contains(b.teamBId));
            return am == bm ? 0 : (am ? -1 : 1);
          });
        if (live.isEmpty) return const SizedBox.shrink();
        return Container(
          color: Colors.red.shade50,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: live.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _LiveCard(match: live[i], mine: myTeamIds),
            ),
          ),
        );
      },
    );
  }
}

class _LiveCard extends StatelessWidget {
  final MatchGame match;
  final Set<String> mine;
  const _LiveCard({required this.match, required this.mine});

  @override
  Widget build(BuildContext context) {
    final m = match;
    final myTeam = mine.contains(m.teamAId) ? m.teamAId : (mine.contains(m.teamBId) ? m.teamBId : null);
    final batting = m.liveBatting == m.teamAId ? m.teamAName : (m.liveBatting == m.teamBId ? m.teamBName : '');
    return SizedBox(
      width: 260,
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.red.shade700,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MatchDetailScreen(match: m, myTeamId: myTeam)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const PulseDot(size: 8),
                    const SizedBox(width: 2),
                    Text('LIVE',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
                if (myTeam != null) ...[
                  const SizedBox(width: 6),
                  const Text('Your team', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ]),
              const SizedBox(height: 6),
              Text('${m.teamAName}  ${m.scoreA}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('${m.teamBName}  ${m.scoreB}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              if (batting.isNotEmpty)
                Text('$batting batting', style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}
