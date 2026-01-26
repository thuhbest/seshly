import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import '../view/question_detail_view.dart';
import 'package:seshly/widgets/pressable_scale.dart';
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
  final Map<String, dynamic>? repostOf;
  final String? repostText;

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
    this.repostOf,
    this.repostText,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _isExpanded = false;
  bool _expandedLoaded = false;
  VideoPlayerController? _videoController;
  bool _isVideo = false;
  bool _hasReacted = false;
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);
  final Color backgroundColor = const Color(0xFF0F142B);

  String get _expandedStorageKey => 'post_expand_${widget.postId}';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_expandedLoaded) return;
    final bucket = PageStorage.of(context);
    final stored = bucket.readState(context, identifier: _expandedStorageKey);
    if (stored is bool) {
      _isExpanded = stored;
    }
    _expandedLoaded = true;
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
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Post?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "This will remove your question forever. You cannot undo this action.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
              if (!mounted) return;
              Navigator.of(context, rootNavigator: true).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Post deleted")));
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
      builder: (sheetContext) => Padding(
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
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report submitted. Thank you.")));
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showRepostDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Repost", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Add your thoughts (optional)",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: backgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Text(
                widget.question,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: tealAccent),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _createRepost(controller.text.trim());
            },
            child: const Text("Repost", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    final bucket = PageStorage.of(context);
    bucket.writeState(context, _isExpanded, identifier: _expandedStorageKey);
  }

  Future<void> _createRepost(String comment) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please sign in to repost.")));
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final authorName = (userData['fullName'] ?? userData['displayName'] ?? "Student").toString();
      final String repostText = comment.trim();
      final String storedQuestion = repostText.isEmpty ? widget.question : repostText;

      await FirebaseFirestore.instance.collection('posts').add({
        'subject': widget.subject,
        'question': storedQuestion,
        'repostText': repostText,
        'repostOf': {
          'postId': widget.postId,
          'authorId': widget.authorId,
          'author': widget.author,
          'subject': widget.subject,
          'question': widget.question,
          'attachmentUrl': widget.attachmentUrl,
          'link': widget.link,
        },
        'isRepost': true,
        'author': authorName,
        'authorId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'comments': 0,
        'isUrgent': false,
        'attachmentUrl': null,
        'link': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reposted")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not repost right now.")));
    }
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
    final bool isRepost = widget.repostOf != null;
    final questionText = isRepost ? (widget.repostText ?? '').trim() : widget.question.trim();
    final bool canExpand = questionText.length > 140;
    final Color chipBackground = tealAccent.withValues(alpha: 0.1);
    final Color chipBorder = tealAccent.withValues(alpha: 0.25);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E243A), Color(0xFF171C30)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                    color: chipBackground, 
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: chipBorder),
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
                if (questionText.isNotEmpty) ...[
                  GestureDetector(
                    onTap: canExpand ? _toggleExpanded : null,
                    child: Text(
                      questionText,
                      maxLines: _isExpanded ? null : 3,
                      overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                    ),
                  ),
                  if (canExpand) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _toggleExpanded,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _isExpanded ? 'Show less' : '...more',
                          style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (isRepost) ...[
                  _buildRepostQuote(),
                  const SizedBox(height: 12),
                ],
                
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
                      accentColor: tealAccent,
                      accentFill: chipBackground,
                      accentBorder: chipBorder,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileView(userId: widget.authorId, showBack: true),
                          ),
                        );
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
              child: PressableScale(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullScreenMediaViewer(url: widget.attachmentUrl!, isVideo: _isVideo, videoController: _videoController))),
                borderRadius: BorderRadius.circular(16),
                pressedScale: 0.98,
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
                  backgroundColor: chipBackground,
                  onTap: _handleHelpful
                ),
                ActionIconButton(
                  icon: Icons.chat_bubble_rounded, 
                  label: widget.comments.toString(), 
                  backgroundColor: chipBackground,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuestionDetailView(postId: widget.postId)))
                ),
                ActionIconButton(
                  icon: Icons.person_search_rounded, 
                  label: "Tutor", 
                  color: tealAccent, 
                  backgroundColor: chipBackground,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FindTutorView(
                        initialSubject: widget.subject,
                        questionText: widget.question,
                        postId: widget.postId,
                      ),
                    ),
                  )
                ),
                ActionIconButton(
                  icon: Icons.repeat, 
                  label: "Repost", 
                  backgroundColor: chipBackground,
                  onTap: _showRepostDialog
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

  Widget _buildRepostQuote() {
    final data = widget.repostOf ?? {};
    final String originalAuthor = (data['author'] ?? 'Student').toString();
    final String originalSubject = (data['subject'] ?? 'General').toString();
    final String originalQuestion = (data['question'] ?? '').toString();
    final String? originalAttachment = data['attachmentUrl'] as String?;
    final String? originalLink = data['link'] as String?;
    final bool hasAttachment = originalAttachment != null && originalAttachment.isNotEmpty;
    final bool hasLink = originalLink != null && originalLink.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Repost",
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                originalSubject,
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            originalQuestion.isEmpty ? "Original post" : originalQuestion,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            "by $originalAuthor",
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (hasAttachment || hasLink) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                if (hasAttachment) _repostPill(Icons.attachment_rounded, "Attachment"),
                if (hasLink) _repostPill(Icons.link, "Link"),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _repostPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white54, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

// 🔥 ELITE AUTHOR BUTTON W/ MOTION
class _AuthorButton extends StatefulWidget {
  final String name;
  final VoidCallback onTap;
  final Color accentColor;
  final Color accentFill;
  final Color accentBorder;
  const _AuthorButton({
    required this.name,
    required this.onTap,
    required this.accentColor,
    required this.accentFill,
    required this.accentBorder,
  });

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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: widget.accentFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: widget.accentBorder),
          ),
          child: Text(
            widget.name,
            style: TextStyle(
              color: widget.accentColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
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

class ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color? backgroundColor;
  final VoidCallback onTap;

  const ActionIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.color = Colors.white54,
    this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = backgroundColor ?? color.withValues(alpha: 25);
    return PressableScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.92,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ]
          ],
        ),
      ),
    );
  }
}
