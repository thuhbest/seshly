import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:seshly/features/sesh/view/sesh_ai_chat_view.dart';

class SeshAiThreadsView extends StatelessWidget {
  const SeshAiThreadsView({super.key});

  static const _presets = <_RolePreset>[
    _RolePreset(
      title: 'Student Flight Deck',
      subtitle: 'Plan your week, drill weak topics, keep momentum.',
      icon: Icons.school_outlined,
      starterPrompt:
          'Build a 7-day learning sprint for me. Start by asking what my exams, modules, and weak topics are.',
    ),
    _RolePreset(
      title: 'Tutor Ops',
      subtitle: 'Session plans, diagnostics, and instant lesson scaffolds.',
      icon: Icons.record_voice_over_outlined,
      starterPrompt:
          'Act as my tutor copilot. Create a 60-minute lesson blueprint with checkpoints and confidence metrics.',
    ),
    _RolePreset(
      title: 'Mentor Intelligence',
      subtitle: 'Track mentee growth, accountability, and habits.',
      icon: Icons.psychology_alt_outlined,
      starterPrompt:
          'Create a mentorship operating system with weekly reviews, goals, and intervention triggers.',
    ),
    _RolePreset(
      title: 'University Command',
      subtitle: 'Program-level support and student success insights.',
      icon: Icons.account_balance_outlined,
      starterPrompt:
          'Design a university-level student success playbook using AI tutoring, analytics, and intervention loops.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0B1024);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Text('Please sign in to see your chats.', style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final threads = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_threads')
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text('Sesh AI Mission Control', style: GoogleFonts.playfairDisplay(color: Colors.white)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1024), Color(0xFF0F2236), Color(0xFF0A1E2F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildPresetScroller(context),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: threads,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
                  }
                  if (snap.hasError) {
                    return const Center(child: Text('Failed to load chats.', style: TextStyle(color: Colors.white54)));
                  }
                  final docs = (snap.data?.docs ?? []).toList();
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'No chats yet. Launch one of the role-based copilots above.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(color: Colors.white38),
                        ),
                      ),
                    );
                  }
                  docs.sort((a, b) {
                    final aPinned = (a.data()['pinned'] ?? false) == true;
                    final bPinned = (b.data()['pinned'] ?? false) == true;
                    if (aPinned != bPinned) return bPinned ? 1 : -1;
                    final aUpdated = (a.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                    final bUpdated = (b.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                    return bUpdated.compareTo(aUpdated);
                  });
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final title = (data['title'] ?? 'Sesh AI').toString();
                      final lastMessage = (data['lastMessage'] ?? '').toString();
                      final threadId = docs[index].id;
                      final pinned = (data['pinned'] ?? false) == true;
                      return ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        tileColor: const Color(0xFF141B2F).withValues(alpha: 0.9),
                        title: Text(title, style: GoogleFonts.playfairDisplay(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          lastMessage.isEmpty ? 'Tap to continue this mission' : lastMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: pinned
                            ? const Icon(Icons.push_pin, color: Color(0xFF7CF1D6), size: 18)
                            : const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SeshAiChatView(
                                title: title,
                                threadId: threadId,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetScroller(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final preset = _presets[index];
          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SeshAiChatView(
                    title: preset.title,
                    subject: preset.title,
                    initialMessage: preset.starterPrompt,
                    autoSend: true,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 250,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141B2F).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00C09E).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(preset.icon, color: const Color(0xFF00C09E), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          preset.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.playfairDisplay(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    preset.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontSize: 12, height: 1.35),
                  ),
                  const Spacer(),
                  Text(
                    'Launch',
                    style: GoogleFonts.spaceGrotesk(
                      color: const Color(0xFF7CF1D6),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RolePreset {
  const _RolePreset({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.starterPrompt,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String starterPrompt;
}
