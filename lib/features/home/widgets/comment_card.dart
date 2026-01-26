import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class CommentCard extends StatelessWidget {
  final String author, time, initials, text;
  final int likes;
  final String? avatarUrl;
  final VoidCallback? onLike;
  final VoidCallback? onReply;

  const CommentCard({
    super.key,
    required this.author,
    required this.time,
    required this.initials,
    required this.text,
    required this.likes,
    this.avatarUrl,
    this.onLike,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);
    final Color metaColor = Colors.white.withValues(alpha: 0.45);
    final Color borderColor = Colors.white.withValues(alpha: 0.08);
    final bool hasAvatar = avatarUrl != null && avatarUrl!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cardColor.withValues(alpha: 0.85),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: hasAvatar
                  ? Image.network(
                      avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _InitialsBadge(initials: initials),
                    )
                  : _InitialsBadge(initials: initials),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cardColor.withValues(alpha: 0.9),
                    const Color(0xFF171C30).withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          author,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(time, style: TextStyle(color: metaColor, fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ActionChip(
                        icon: Icons.favorite_border,
                        label: likes.toString(),
                        color: metaColor,
                        onTap: onLike,
                      ),
                      const SizedBox(width: 10),
                      _ActionChip(
                        icon: Icons.reply_rounded,
                        label: "Reply",
                        color: tealAccent.withValues(alpha: 0.7),
                        onTap: onReply,
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InitialsBadge extends StatelessWidget {
  final String initials;
  const _InitialsBadge({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(color: Color(0xFF00C09E), fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );

    if (onTap == null) return content;
    return PressableScale(
      onTap: onTap,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }
}
