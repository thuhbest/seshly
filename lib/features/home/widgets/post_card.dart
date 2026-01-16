import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../view/question_detail_view.dart';
import 'package:seshly/features/tutors/view/find_tutor_view.dart';
import '../../profile/view/profile_view.dart';

class PostCard extends StatefulWidget {
  final String postId;
  final String authorId;
  final String subject;
  final String time;
  final String question;
  final String author;
  final int likes;
  final int comments;
  final String? attachmentUrl;
  final String? link;

  const PostCard({
    super.key,
    required this.postId,
    required this.authorId,
    required this.subject,
    required this.time,
    required this.question,
    required this.author,
    required this.likes,
    required this.comments,
    this.attachmentUrl,
    this.link,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isExpanded = false;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _hasReacted = false;
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);
  final Color backgroundColor = const Color(0xFF0F142B);

  @override
  void initState() {
    super.initState();
    _checkIfUserReacted();
    if (widget.attachmentUrl != null &&
        (widget.attachmentUrl!.toLowerCase().contains('.mp4') ||
            widget.attachmentUrl!.toLowerCase().contains('.mov'))) {
      _isVideo = true;
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.attachmentUrl!),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      )..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  Future<void> _checkIfUserReacted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('helpful_users')
        .doc(user.uid)
        .get();
    if (mounted) setState(() => _hasReacted = doc.exists);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Post?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will remove your question forever. You cannot undo this action.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Post deleted")));
              }
            },
            child: const Text("Delete Forever", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showReportSheet() {
    final List<String> reasons = ["Inappropriate content", "Spam", "Harassment", "Incorrect information", "Other"];
    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Report Post", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ...reasons.map((reason) => ListTile(
              title: Text(reason, style: const TextStyle(color: Colors.white70)),
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                await FirebaseFirestore.instance.collection('reports').add({
                  'postId': widget.postId,
                  'reporterId': user?.uid,
                  'reason': reason,
                  'createdAt': FieldValue.serverTimestamp(),
                  'status': 'pending',
                });
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted. Thank you.")));
                }
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showShareOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.copy_rounded, color: tealAccent),
              title: const Text("Copy Text", style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.question));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Text copied to clipboard")));
              },
            ),
            if (widget.attachmentUrl != null)
              ListTile(
                leading: Icon(Icons.download_rounded, color: tealAccent),
                title: Text(_isVideo ? "Save Video to Gallery" : "Save Image to Gallery", style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  var file = await DefaultCacheManager().getSingleFile(widget.attachmentUrl!);
                  await ImageGallerySaver.saveFile(file.path);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved to gallery!")));
                },
              ),
            ListTile(
              leading: Icon(Icons.ios_share_rounded, color: tealAccent),
              title: const Text("Share to Apps", style: TextStyle(color: Colors.white)),
              onTap: () {
                Share.share("${widget.question}\n\nShared from Seshly");
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleHelpful() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bool wasReacted = _hasReacted;
    setState(() => _hasReacted = !wasReacted);
    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    final reactorRef = postRef.collection('helpful_users').doc(user.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        if (!wasReacted) {
          transaction.set(reactorRef, {'timestamp': FieldValue.serverTimestamp()});
          transaction.update(postRef, {'likes': FieldValue.increment(1)});
        } else {
          transaction.delete(reactorRef);
          transaction.update(postRef, {'likes': FieldValue.increment(-1)});
        }
      });
    } catch (e) {
      if (mounted) setState(() => _hasReacted = wasReacted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2), 
            blurRadius: 15, 
            offset: const Offset(0, 8)
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tealAccent.withValues(alpha: 0.1), 
                    borderRadius: BorderRadius.circular(12)
                  ),
                  child: Text(widget.subject, 
                    style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Row(
                  children: [
                    Text(widget.time, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(width: 5),
                    _OptionsButton(
                      onDelete: _showDeleteConfirmation, 
                      onReport: _showReportSheet, 
                      isAuthor: widget.authorId == currentUser?.uid
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Text(
                    widget.question,
                    maxLines: _isExpanded ? null : 3,
                    overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                  ),
                ),
                const SizedBox(height: 12),
                
                // 🔥 FIXED AUTHOR BUTTON: isolated animation and static "by "
                Row(
                  children: [
                    Text(
                      "by ",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4), 
                        fontSize: 13, 
                        fontStyle: FontStyle.italic
                      ),
                    ),
                    _AuthorButton(
                      name: widget.author,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileView()));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.attachmentUrl != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenMediaViewer(url: widget.attachmentUrl!, isVideo: _isVideo, videoController: _videoController))),
                child: Hero(
                  tag: widget.postId, 
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16), 
                    child: AspectRatio(
                      aspectRatio: 16 / 9, 
                      child: _isVideo ? _buildVideoPlayer() : Image.network(widget.attachmentUrl!, fit: BoxFit.cover)
                    )
                  )
                ),
              ),
            ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ActionIconButton(
                  icon: _hasReacted ? Icons.auto_awesome : Icons.auto_awesome_outlined, 
                  label: "Helpful (${widget.likes})", 
                  color: _hasReacted ? tealAccent : Colors.white54, 
                  onTap: _handleHelpful
                ),
                ActionIconButton(
                  icon: Icons.chat_bubble_rounded, 
                  label: widget.comments.toString(), 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuestionDetailView()))
                ),
                ActionIconButton(
                  icon: Icons.person_search_rounded, 
                  label: "Tutor", 
                  color: tealAccent, 
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FindTutorView()))
                ),
                ActionIconButton(
                  icon: Icons.share_rounded, 
                  label: "", 
                  onTap: _showShareOptions
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
    }
    return VideoPlayer(_videoController!);
  }
}

// 🔥 ELITE AUTHOR BUTTON W/ MOTION
class _AuthorButton extends StatefulWidget {
  final String name;
  final VoidCallback onTap;
  const _AuthorButton({required this.name, required this.onTap});

  @override
  State<_AuthorButton> createState() => _AuthorButtonState();
}

class _AuthorButtonState extends State<_AuthorButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Text(
          widget.name,
          style: const TextStyle(
            color: Colors.white70, // High visibility color as per screenshot
            fontSize: 13,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _OptionsButton extends StatefulWidget {
  final VoidCallback onDelete, onReport;
  final bool isAuthor;
  const _OptionsButton({required this.onDelete, required this.onReport, required this.isAuthor});

  @override
  State<_OptionsButton> createState() => _OptionsButtonState();
}

class _OptionsButtonState extends State<_OptionsButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.8 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: PopupMenuButton(
          icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
          color: const Color(0xFF1E243A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          itemBuilder: (context) => [
            if (widget.isAuthor)
              PopupMenuItem(onTap: widget.onDelete, child: const Row(children: [Icon(Icons.delete_outline, color: Colors.redAccent, size: 18), SizedBox(width: 10), Text("Delete", style: TextStyle(color: Colors.redAccent))])),
            PopupMenuItem(onTap: widget.onReport, child: const Row(children: [Icon(Icons.report_gmailerrorred_rounded, color: Colors.white70, size: 18), SizedBox(width: 10), Text("Report", style: TextStyle(color: Colors.white70))])),
          ],
        ),
      ),
    );
  }
}

class FullScreenMediaViewer extends StatelessWidget {
  final String url;
  final bool isVideo;
  final VideoPlayerController? videoController;

  const FullScreenMediaViewer({super.key, required this.url, required this.isVideo, this.videoController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: Hero(
          tag: url,
          child: isVideo 
            ? AspectRatio(aspectRatio: videoController!.value.aspectRatio, child: VideoPlayer(videoController!))
            : Image.network(url),
        ),
      ),
    );
  }
}

class ActionIconButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.color = Colors.white54,
    required this.onTap,
  });

  @override
  State<ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<ActionIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 25), // Adjusted for proper screenshot match (0.1 * 255)
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: widget.color, size: 18),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(widget.label, style: TextStyle(color: widget.color, fontWeight: FontWeight.bold, fontSize: 13)),
              ]
            ],
          ),
        ),
      ),
    );
  }
}