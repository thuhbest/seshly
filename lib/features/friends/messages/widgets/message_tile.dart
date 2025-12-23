import 'package:flutter/material.dart';

class MessageTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final int unreadCount;
  final bool isGroup;
  final int groupSize;
  final bool isOnline;

  const MessageTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.time,
    this.unreadCount = 0,
    this.isGroup = false,
    this.groupSize = 0,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          // Avatar Section
          Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: isGroup 
                    ? tealAccent.withValues(alpha: 0.1) 
                    : Colors.white.withValues(alpha: 0.05),
                child: isGroup 
                    ? const Icon(Icons.groups_rounded, color: tealAccent, size: 24)
                    : Text(
                        title.substring(0, 1),
                        style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
              ),
              if (isOnline)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0F142B), width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          // Text Section
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (isGroup) ...[
                      const SizedBox(width: 6),
                      Text(
                        groupSize.toString(),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ]
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unreadCount > 0 ? Colors.white70 : Colors.white38,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Time and Badge Section
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 8),
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: tealAccent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount.toString(),
                    style: const TextStyle(color: Color(0xFF0F142B), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}