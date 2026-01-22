import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../widgets/stats_grid.dart';
import '../widgets/achievement_card.dart';
import 'package:seshly/features/home/widgets/post_card.dart';
import 'settings_view.dart';

class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);
  final ImagePicker _picker = ImagePicker();
  bool _isUploadingImage = false;

  // 🔥 ACTION: Change Profile Picture
  Future<void> _updateProfilePicture() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (image == null) return;

      setState(() => _isUploadingImage = true);
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final storageRef = FirebaseStorage.instance.ref().child('profile_pics').child('${user.uid}.jpg');

      if (kIsWeb) {
        await storageRef.putData(await image.readAsBytes());
      } else {
        await storageRef.putFile(File(image.path));
      }

      final url = await storageRef.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'profilePic': url});

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated!")));
    } catch (e) {
      debugPrint("Upload error: $e");
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  // 🔥 ACTION: Full Screen Viewer
  void _viewFullProfilePic(String? url, String name) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Center(
        child: Hero(
          tag: 'profile_pic',
          child: url != null 
            ? Image.network(url, fit: BoxFit.contain) 
            : Text(name.isNotEmpty ? name[0] : "S", style: const TextStyle(color: Colors.white, fontSize: 100)),
        ),
      ),
    )));
  }

  // 🔥 ACTION: Bio Editor
  void _showBioEditor(String currentBio) {
    final TextEditingController bioController = TextEditingController(text: currentBio);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Edit Bio", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("${bioController.text.length}/1000", 
                      style: TextStyle(color: bioController.text.length >= 1000 ? Colors.red : Colors.white24, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(15)),
                  child: TextField(
                    controller: bioController,
                    maxLines: 8,
                    maxLength: 1000,
                    style: const TextStyle(color: Colors.white),
                    onChanged: (val) => setModalState(() {}),
                    decoration: const InputDecoration(hintText: "Tell your academic story...", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none, counterText: ""),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final navigator = Navigator.of(context); 
                      await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).update({'bio': bioController.text.trim()});
                      if (mounted) navigator.pop(); 
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: tealAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 15)),
                    child: const Text("Save Bio", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: backgroundColor,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final String name = userData['fullName'] ?? "Seshly User";

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(userData, name),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _buildBioSection(userData['bio'] ?? ""),
                      const SizedBox(height: 30),
                      _buildActivityActionButtons(user!.uid),
                      const SizedBox(height: 20),
                      _buildXpCard(userData),
                      const SizedBox(height: 30),
                      const Text("Student Stats", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      StatsGrid(userId: user.uid),
                      const SizedBox(height: 35),
                      
                      // 🔥 ACHIEVEMENTS SECTION (FIXED: Re-added for visibility)
                      const Text("Achievements", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      _buildAchievementGrid(userData),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic> userData, String name) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 25, right: 25, bottom: 30),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF163E44).withValues(alpha: 0.8), backgroundColor])),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => _viewFullProfilePic(userData['profilePic'], name),
                    child: Hero(tag: 'profile_pic', child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: tealAccent.withValues(alpha: 0.2), width: 4)), child: CircleAvatar(radius: 65, backgroundColor: tealAccent.withValues(alpha: 0.05), backgroundImage: userData['profilePic'] != null ? NetworkImage(userData['profilePic']) : null, child: userData['profilePic'] == null ? Text(name.isNotEmpty ? name[0] : "S", style: TextStyle(color: tealAccent, fontSize: 45, fontWeight: FontWeight.bold)) : null))),
                  ),
                  Positioned(top: 5, right: 5, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: tealAccent, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10)]), child: Text(userData['levelOfStudy'] ?? "N/A", style: const TextStyle(color: Color(0xFF0F142B), fontSize: 10, fontWeight: FontWeight.bold)))),
                  Positioned(bottom: 0, right: 0, child: GestureDetector(onTap: _updateProfilePicture, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: cardColor, shape: BoxShape.circle, border: Border.all(color: backgroundColor, width: 2)), child: Icon(Icons.add_a_photo_rounded, size: 18, color: tealAccent)))),
                  if (_isUploadingImage) const Positioned.fill(child: CircularProgressIndicator(color: Colors.white)),
                ],
              ),
              const _SettingsButton(),
            ],
          ),
          const SizedBox(height: 25),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                Text(FirebaseAuth.instance.currentUser?.email ?? "", style: TextStyle(color: tealAccent.withValues(alpha: 0.7), fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 12),
                Text("Student No: ${userData['studentNumber'] ?? "Not Set"}", style: const TextStyle(color: Colors.white38, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [const Icon(Icons.account_balance_rounded, color: Colors.white24, size: 14), const SizedBox(width: 6), Text(userData['university'] ?? "University Not Set", style: const TextStyle(color: Colors.white54, fontSize: 13))]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSection(String bio) {
    return GestureDetector(
      onTap: () => _showBioEditor(bio),
      child: Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Bio", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)), Icon(Icons.notes_rounded, color: tealAccent, size: 18)]),
        const SizedBox(height: 10),
        Text(bio.isEmpty ? "Share your academic journey with the community..." : bio, maxLines: 50, style: const TextStyle(color: Colors.white38, fontSize: 14, height: 1.6)),
      ])),
    );
  }

  Widget _buildXpCard(Map<String, dynamic> userData) {
    final int xp = (userData['xp'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tealAccent.withValues(alpha: 0.15),
            cardColor.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tealAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, color: tealAccent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Total XP", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  "$xp XP",
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "Earn XP from questions, answers, vault uploads, focus sessions, and achievement bonuses.",
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityActionButtons(String uid) {
    return Row(
      children: [
        Expanded(child: _ActivityButton(label: "Questions Asked", icon: Icons.chat_bubble_outline_rounded, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserPostsView(userId: uid))))),
        const SizedBox(width: 15),
        Expanded(child: _ActivityButton(label: "Answers Given", icon: Icons.auto_awesome_mosaic_rounded, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserAnswersView(userId: uid))))),
      ],
    );
  }

  // 🔥 ACHIEVEMENT GRID Logic restored here
  Widget _buildAchievementGrid(Map<String, dynamic> data) {
    final int bestStreak = (data['streakBest'] as int?) ?? (data['streak'] as int?) ?? 0;
    return GridView.count(
      shrinkWrap: true, 
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, 
      mainAxisSpacing: 15, 
      crossAxisSpacing: 15, 
      childAspectRatio: 0.9,
      children: [
        AchievementCard(icon: Icons.volunteer_activism_outlined, title: "Helpful Student", desc: "${data['totalReplies'] ?? 0} helpful reactions", isUnlocked: (data['totalReplies'] ?? 0) > 0),
        AchievementCard(icon: Icons.cloud_upload_outlined, title: "Vault Contributor", desc: "${data['vaultUploads'] ?? 0} documents shared", isUnlocked: (data['vaultUploads'] ?? 0) > 0),
        AchievementCard(icon: Icons.storefront_outlined, title: "Market Master", desc: "Sold ${data['marketSales'] ?? 0} items", isUnlocked: (data['marketSales'] ?? 0) > 0),
        AchievementCard(icon: Icons.timer_outlined, title: "Focus Titan", desc: "${data['seshFocusHours'] ?? 0} hrs in SeshFocus", isUnlocked: (data['seshFocusHours'] ?? 0) > 0),
        AchievementCard(icon: Icons.local_fire_department_outlined, title: "Streak Legend", desc: "Best streak: $bestStreak days", isUnlocked: bestStreak > 0),
        AchievementCard(icon: Icons.bolt_outlined, title: "Power User", desc: "${data['seshMinutes'] ?? 0} SeshMinutes used", isUnlocked: (data['seshMinutes'] ?? 0) > 0),
      ],
    );
  }
}

// 🔥 SUB-VIEW: User's Questions
class UserPostsView extends StatelessWidget {
  final String userId;
  const UserPostsView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)), title: const Text("My Questions", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('posts').where('authorId', isEqualTo: userId).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error loading posts", style: TextStyle(color: Colors.white)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: tealAccent));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("You haven't posted any questions.", style: TextStyle(color: Colors.white38)));
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final timestamp = data['createdAt'] as Timestamp?;
              final timeStr = timestamp != null ? "${DateTime.now().difference(timestamp.toDate()).inMinutes}m ago" : "Just now";
              return PostCard(postId: docs[index].id, authorId: data['authorId'] ?? "", subject: data['subject'] ?? "General", time: timeStr, question: data['question'] ?? "", author: data['author'] ?? "Seshly User", likes: data['likes'] ?? 0, comments: data['comments'] ?? 0, attachmentUrl: data['attachmentUrl']);
            },
          );
        },
      ),
    );
  }
}

// 🔥 SUB-VIEW: User's Answers
class UserAnswersView extends StatelessWidget {
  final String userId;
  const UserAnswersView({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)), title: const Text("My Contributions", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collectionGroup('comments').where('userId', isEqualTo: userId).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.white54)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: tealAccent));
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.maps_ugc_rounded, color: Colors.white10, size: 80), SizedBox(height: 16), Text("No answers yet.\nHelp a peer to earn XP!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 16))]));
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final timestamp = data['createdAt'] as Timestamp?;
              final dateLabel = timestamp != null ? DateFormat('dd MMM yyyy').format(timestamp.toDate()) : "Recently";
              return Container(
                margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: tealAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Text("ANSWER", style: TextStyle(color: tealAccent, fontSize: 10, fontWeight: FontWeight.bold))), Text(dateLabel, style: const TextStyle(color: Colors.white24, fontSize: 11))]),
                  const SizedBox(height: 12),
                  Text(data['text'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, thickness: 0.5),
                  const SizedBox(height: 8),
                  Row(children: [Icon(Icons.link_rounded, color: tealAccent.withValues(alpha: 0.5), size: 16), const SizedBox(width: 6), const Text("View original post", style: TextStyle(color: Colors.white38, fontSize: 12))]),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// 🔥 WIDGETS: Internal Activity Button
class _ActivityButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ActivityButton({required this.label, required this.icon, required this.onTap});

  @override
  State<_ActivityButton> createState() => _ActivityButtonState();
}

class _ActivityButtonState extends State<_ActivityButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(color: _isPressed ? const Color(0xFF00C09E).withValues(alpha: 0.15) : const Color(0xFF1E243A).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isPressed ? const Color(0xFF00C09E).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05))),
          child: Column(children: [Icon(widget.icon, color: const Color(0xFF00C09E), size: 26), const SizedBox(height: 10), Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))]),
        ),
      ),
    );
  }
}

// 🔥 WIDGETS: Settings Button
class _SettingsButton extends StatefulWidget {
  const _SettingsButton();
  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsView())),
      child: AnimatedScale(
        scale: _isPressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: _isPressed ? const Color(0xFF00C09E).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1))),
          child: const Icon(Icons.settings_suggest_rounded, color: Colors.white70, size: 22),
        ),
      ),
    );
  }
}
