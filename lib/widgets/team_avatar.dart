import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/team_logos.dart';

/// Round team logo; falls back to the team's first letter when it has none.
class TeamAvatar extends StatelessWidget {
  final String teamId;
  final String name;
  final double radius;

  /// Fallback colours (used when there is no logo).
  final Color? background;
  final Color? foreground;

  /// Draws a coloured ring around the logo (e.g. green for the winner).
  final Color? ring;

  /// Gives the logo a shared-element transition between two screens.
  final String? heroTag;

  const TeamAvatar({
    super.key,
    required this.teamId,
    required this.name,
    this.radius = 22,
    this.background,
    this.foreground,
    this.ring,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    TeamLogos.ensure();
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Map<String, Uint8List>>(
      valueListenable: TeamLogos.logos,
      builder: (_, logos, _) {
        final bytes = logos[teamId];
        final avatar = CircleAvatar(
          radius: radius,
          backgroundColor: bytes != null ? Colors.white : (background ?? scheme.primaryContainer),
          foregroundColor: foreground ?? scheme.onPrimaryContainer,
          backgroundImage: bytes != null ? MemoryImage(bytes) : null,
          child: bytes != null
              ? null
              : Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: radius * 0.8)),
        );
        final shown = ring == null
            ? avatar
            : Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring!, width: 2.5)),
                child: avatar,
              );
        return heroTag == null ? shown : Hero(tag: heroTag!, child: shown);
      },
    );
  }
}
