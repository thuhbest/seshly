import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class NotificationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final IconData? icon;
  final Color? iconColor;
  final String? initials;
  final String? actionLabel;
  final bool isNew;

  const NotificationTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
    this.icon,
    this.iconColor,
    this.initials,
    this.actionLabel,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardBg = Color(0xFF1E243A);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tealAccent.withValues(alpha: isNew ? 0.2 : 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon / Profile Picture
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (iconColor ?? tealAccent).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: initials != null
                  ? Text(
                      initials!,
                      style: TextStyle(
                        color: iconColor ?? tealAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    )
                  : Icon(icon ?? Icons.notifications_none, color: iconColor ?? tealAccent, size: 24),
            ),
          ),
          const SizedBox(width: 15),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    if (isNew)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: tealAccent, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      time,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                    if (actionLabel != null)
                      PressableScale(
                        onTap: () {},
                        borderRadius: BorderRadius.circular(6),
                        pressedScale: 0.95,
                        child: Text(
                          actionLabel!,
                          style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
