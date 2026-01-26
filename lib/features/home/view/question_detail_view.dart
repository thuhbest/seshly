import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/comment_card.dart';
import '../widgets/ai_tutor_help_view.dart';
import 'package:seshly/widgets/responsive.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class QuestionDetailView extends StatefulWidget {
  final String? postId;
  const QuestionDetailView({super.key, this.postId});

  @override
  State<QuestionDetailView> createState() => _QuestionDetailViewState();
}

class _ScrollBehavior extends ScrollBehavior {
  Widget buildViewportChrome(BuildContext context, Widget child, AxisDirection axisDirection) => child;
}

class _QuestionDetailViewState extends State<QuestionDetailView> {
  bool isAiView = false;
  bool _isSubmittingComment = false;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    final String? postId = widget.postId;

    if (postId == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: _buildAppBar(),
        body: ResponsiveCenter(
          padding: EdgeInsets.zero,
          child: _buildStatusMessage("Question not found."),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildAppBar(),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('posts').doc(postId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
            }
            if (snapshot.hasError) {
              return _buildStatusMessage("Error loading question.");
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return _buildStatusMessage("Question not found.");
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final String authorName = (data['author'] ?? data['authorName'] ?? "Student").toString();
            final String subject = (data['subject'] ?? "General").toString();
            final String question = (data['question'] ?? "").toString();
            final String details = (data['details'] ?? data['body'] ?? "").toString();
            final int likes = (data['likes'] as num?)?.toInt() ?? 0;
            final int commentCount = (data['comments'] as num?)?.toInt() ?? 0;
            final Timestamp? createdAt = data['createdAt'] as Timestamp?;
            final String timeLabel = _timeAgo(createdAt);
            final String? attachmentUrl = data['attachmentUrl'] as String?;
            final String? safeAttachmentUrl = attachmentUrl?.trim();
            final String? link = data['link'] as String?;
            final String initials = _initialsFromName(authorName) ?? "S";
            final bool isVideo = _isVideoAttachment(safeAttachmentUrl);

            return Column(
              children: [
                Expanded(
                  child: ScrollConfiguration(
                    behavior: _ScrollBehavior(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _avatar(initials),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    authorName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    timeLabel,
                                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              _tag(subject),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            question.isNotEmpty ? question : "Question details unavailable.",
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (details.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              details,
                              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                            ),
                          ],
                          if (safeAttachmentUrl != null && safeAttachmentUrl.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            PressableScale(
                              onTap: () => _openUrl(safeAttachmentUrl),
                              borderRadius: BorderRadius.circular(16),
                              pressedScale: 0.98,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: isVideo
                                    ? _buildVideoAttachment()
                                    : Image.network(
                                        safeAttachmentUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => _buildAttachmentFallback(),
                                      ),
                              ),
                            ),
                          ],
                          if (link != null && link.trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            PressableScale(
                              onTap: () => _openUrl(link),
                              borderRadius: BorderRadius.circular(12),
                              pressedScale: 0.98,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 13),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 25)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.link, color: Color(0xFF00C09E), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        link,
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              const Icon(Icons.favorite_border, color: Colors.white38, size: 18),
                              const SizedBox(width: 6),
                              Text(likes.toString(), style: const TextStyle(color: Colors.white38)),
                              const SizedBox(width: 20),
                              const Icon(Icons.chat_bubble_outline, color: Colors.white38, size: 18),
                              const SizedBox(width: 6),
                              Text(commentCount.toString(), style: const TextStyle(color: Colors.white38)),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 40),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cardColor.withValues(alpha: 128),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _tabButton("Answers ($commentCount)", !isAiView, () => setState(() => isAiView = false)),
                                _tabButton("Ask Sesh", isAiView, () => setState(() => isAiView = true), icon: Icons.auto_awesome),
                              ],
                            ),
                          ),
                          const SizedBox(height: 25),
                          isAiView ? const AiTutorHelpView() : _buildCommentsList(postId),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!isAiView) _buildCommentInput(postId),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text("Question", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      actions: [
        _headerCircleButton(Icons.share_outlined),
        _headerCircleButton(Icons.more_horiz),
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildStatusMessage(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: Colors.white54)),
    );
  }

  Widget _buildCommentsList(String postId) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
        }
        if (snapshot.hasError) {
          return _buildStatusMessage("Error loading answers.");
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildStatusMessage("No answers yet. Be the first to help!");
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String authorName = (data['authorName'] ?? data['author'] ?? "Student").toString();
            final String initials = _initialsFromName(authorName) ?? "S";
            final String text = (data['text'] ?? "").toString();
            final int likes = (data['likes'] as num?)?.toInt() ?? 0;
            final Timestamp? createdAt = data['createdAt'] as Timestamp?;
            final String? authorId = data['userId']?.toString();
            final String? authorPhoto = data['authorPhoto']?.toString();

            if (authorPhoto != null && authorPhoto.trim().isNotEmpty) {
              return CommentCard(
                author: authorName,
                time: _timeAgo(createdAt),
                initials: initials,
                text: text,
                likes: likes,
                avatarUrl: authorPhoto,
              );
            }

            if (authorId == null || authorId.isEmpty) {
              return CommentCard(
                author: authorName,
                time: _timeAgo(createdAt),
                initials: initials,
                text: text,
                likes: likes,
              );
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(authorId).snapshots(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final String? avatarUrl = userData['profilePic'] as String?;
                return CommentCard(
                  author: authorName,
                  time: _timeAgo(createdAt),
                  initials: initials,
                  text: text,
                  likes: likes,
                  avatarUrl: avatarUrl,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCommentInput(String postId) {
    final user = FirebaseAuth.instance.currentUser;
    final bool hasText = _commentController.text.trim().isNotEmpty;
    final bool canSend = hasText && !_isSubmittingComment;
    final bool isSignedIn = user != null;
    final bool isReady = canSend && isSignedIn;
    final Color inputBorder = Colors.white.withValues(alpha: 0.08);
    final Color inputFocusedBorder = const Color(0xFF00C09E).withValues(alpha: 0.6);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2F),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          if (user != null)
            StreamBuilder<DocumentSnapshot>(
              stream: _db.collection('users').doc(user.uid).snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                final String displayName = (data['fullName'] ?? data['displayName'] ?? "You").toString();
                final String initials = _initialsFromName(displayName) ?? "Y";
                final String? avatarUrl = data['profilePic'] as String?;
                final String? trimmedAvatar = avatarUrl?.trim();
                return Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E243A),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: ClipOval(
                    child: trimmedAvatar != null && trimmedAvatar.isNotEmpty
                        ? Image.network(
                            trimmedAvatar,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                initials,
                                style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              initials,
                              style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                );
              },
            ),
          if (user != null) const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _commentController,
              focusNode: _commentFocusNode,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: user == null ? "Sign in to answer..." : "Write an answer...",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1C2238),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: inputFocusedBorder),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (!canSend) return;
                if (!isSignedIn) {
                  _showSnack("Please sign in to comment.");
                  return;
                }
                _submitComment(postId);
              },
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isReady ? const Color(0xFF00C09E) : Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: _isSubmittingComment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F142B)),
                        ),
                      )
                    : Icon(Icons.send, color: isReady ? const Color(0xFF0F142B) : Colors.white54, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment(String postId) async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSubmittingComment) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("Please sign in to comment.");
      return;
    }

    setState(() => _isSubmittingComment = true);
    try {
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final authorName = (userData['fullName'] ?? userData['displayName'] ?? "Student").toString();
      final String? rawPhoto = (userData['profilePic'] ?? user.photoURL) as String?;
      final String? authorPhoto = rawPhoto?.trim().isNotEmpty == true ? rawPhoto!.trim() : null;

      final postRef = _db.collection('posts').doc(postId);
      final commentRef = postRef.collection('comments').doc();

      final commentData = <String, dynamic>{
        'text': text,
        'userId': user.uid,
        'authorName': authorName,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
      };
      if (authorPhoto != null) {
        commentData['authorPhoto'] = authorPhoto;
      }

      await _db.runTransaction((transaction) async {
        transaction.set(commentRef, commentData);
        transaction.update(postRef, {'comments': FieldValue.increment(1)});
      });

      _commentController.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    } catch (_) {
      _showSnack("Could not post your answer.");
    } finally {
      if (mounted) {
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showSnack("Could not open link.");
    }
  }

  bool _isVideoAttachment(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('.mp4') || lower.contains('.mov') || lower.contains('.webm');
  }

  Widget _buildVideoAttachment() {
    return Container(
      height: 180,
      color: Colors.black.withValues(alpha: 128),
      child: const Center(
        child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 56),
      ),
    );
  }

  Widget _buildAttachmentFallback() {
    return Container(
      height: 180,
      color: Colors.white.withValues(alpha: 13),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "Just now";
    final now = DateTime.now();
    final difference = now.difference(timestamp.toDate());
    if (difference.inDays > 0) return "${difference.inDays}d ago";
    if (difference.inHours > 0) return "${difference.inHours}h ago";
    if (difference.inMinutes > 0) return "${difference.inMinutes}m ago";
    return "Just now";
  }

  String? _initialsFromName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final parts = name.trim().split(RegExp(r'\\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';
    final initials = "$first$last".trim().toUpperCase();
    return initials.isEmpty ? null : initials;
  }

  Widget _headerCircleButton(IconData icon) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 13), shape: BoxShape.circle),
      child: IconButton(icon: Icon(icon, color: const Color(0xFF00C09E), size: 20), onPressed: () {}),
    );
  }

  Widget _avatar(String text) {
    return CircleAvatar(
      backgroundColor: const Color(0xFF00C09E).withValues(alpha: 25),
      child: Text(text, style: const TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold)),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 13), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: const TextStyle(color: Color(0xFF00C09E), fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _tabButton(String label, bool isSelected, VoidCallback onTap, {IconData? icon}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E243A) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 25)) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: isSelected ? const Color(0xFF00C09E) : Colors.white38, size: 16),
                  const SizedBox(width: 8),
                ],
                Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
