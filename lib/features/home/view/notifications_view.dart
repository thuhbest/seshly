import 'package:flutter/material.dart';
import '../widgets/notification_tile.dart';

class NotificationsView extends StatelessWidget {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Notifications",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
            Text(
              "Stay updated with your activity",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              "Mark all read",
              style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 20),
          const Text(
            "New",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 15),
          const NotificationTile(
            title: "Low Sesh Minutes",
            subtitle: "You have 45 minutes remaining. Recharge now to keep learning!",
            time: "Just now",
            icon: Icons.error_outline,
            iconColor: Color(0xFFFF5252),
            actionLabel: "Recharge",
            isNew: true,
          ),
          const NotificationTile(
            title: "New answer on your question",
            subtitle: "Thuhbest answered: 'How do I solve quadratic equations using the...'",
            time: "5m ago",
            initials: "TH",
            isNew: true,
          ),
          const NotificationTile(
            title: "New friend request",
            subtitle: "Luko wants to connect with you",
            time: "15m ago",
            initials: "LU",
            actionLabel: "Accept",
            isNew: true,
          ),
          const NotificationTile(
            title: "Someone liked your answer",
            subtitle: "Thimna and 12 others liked your answer about derivatives",
            time: "1h ago",
            icon: Icons.favorite_border,
            isNew: true,
          ),
          const NotificationTile(
            title: "Mentorship session reminder",
            subtitle: "You have a mentorship check-in with Thimna tomorrow at 3:00 PM",
            time: "2h ago",
            initials: "TM",
            actionLabel: "View",
            isNew: true,
          ),
          const SizedBox(height: 25),
          const Text(
            "Earlier",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 15),
          // Placeholder for older notifications
          NotificationTile(
            title: "Welcome to Seshly",
            subtitle: "Start your study journey with AI assistance and community support.",
            time: "2d ago",
            icon: Icons.celebration_outlined,
            iconColor: tealAccent,
            isNew: false,
          ),
        ],
      ),
    );
  }
}