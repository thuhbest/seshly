import 'package:flutter/material.dart';
import 'package:seshly/theme/seshly_theme.dart';

class GoldTickBadge extends StatelessWidget {
  const GoldTickBadge({super.key, this.size = 16, this.showLabel = false});

  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: showLabel ? 8 : 4,
        vertical: showLabel ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: SeshlyPalette.gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: SeshlyPalette.gold.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, color: SeshlyPalette.gold, size: size),
          if (showLabel) ...[
            const SizedBox(width: 6),
            const Text(
              'Gold Tick',
              style: TextStyle(
                color: SeshlyPalette.gold,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
