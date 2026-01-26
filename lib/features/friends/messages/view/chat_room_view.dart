import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:seshly/features/calendar/models/calendar_event.dart';
import 'package:seshly/features/video_call/view/parallel_practice_view.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class ChatRoomView extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final bool isGroup;

  const ChatRoomView({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.isGroup,
  });

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _showEmojiPicker = false;
  String? _playingMessageId;
  final List<String> _emojiOptions = const ['😀', '😂', '😍', '😮', '😢', '😡', '👍', '🙏', '🔥', '💯', '🎯', '✅'];

  bool get _supportsVoiceNotes =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _markAsRead();
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingMessageId = null);
    });
  }

  void _markAsRead() async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update({
      'unreadCounts.$currentUserId': 0,
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String text = _messageController.text.trim();
    _messageController.clear();
    setState(() => _showEmojiPicker = false);

    // 1. Add message document
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .add({
      'senderId': currentUserId,
      'text': text,
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'reactions': {},
      'deletedFor': [],
    });

    // 2. Identify receiver and update chat preview + unread count
    final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
    final List participants = chatDoc.data()?['participants'] ?? [];
    final String receiverId = participants.firstWhere((id) => id != currentUserId, orElse: () => '');

    final Map<String, dynamic> updates = {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    };

    if (receiverId.isNotEmpty) {
      updates['unreadCounts.$receiverId'] = FieldValue.increment(1); // Increments receiver's badge
    }

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update(updates);

    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _startRecording() async {
    if (!_supportsVoiceNotes) {
      _showVoiceNotSupported();
      return;
    }
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Microphone permission denied.")));
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (mounted) setState(() => _isRecording = false);
    if (path == null) return;
    await _sendVoiceMessage(path);
  }

  Future<void> _sendVoiceMessage(String filePath) async {
    try {
      final bytes = await XFile(filePath).readAsBytes();
      final messageRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_voice_notes')
          .child(widget.chatId)
          .child('${messageRef.id}.m4a');

      await storageRef.putData(bytes, SettableMetadata(contentType: 'audio/m4a'));
      final audioUrl = await storageRef.getDownloadURL();

      await messageRef.set({
        'senderId': currentUserId,
        'type': 'voice',
        'audioUrl': audioUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'reactions': {},
        'deletedFor': [],
      });

      final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
      final List participants = chatDoc.data()?['participants'] ?? [];
      final String receiverId = participants.firstWhere((id) => id != currentUserId, orElse: () => '');

      final Map<String, dynamic> updates = {
        'lastMessage': 'Voice note',
        'lastMessageTime': FieldValue.serverTimestamp(),
      };

      if (receiverId.isNotEmpty) {
        updates['unreadCounts.$receiverId'] = FieldValue.increment(1);
      }

      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).update(updates);

      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send voice note.")));
    }
  }

  void _showVoiceNotSupported() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Voice notes are available on mobile only right now.")),
    );
  }

  void _showBackgroundPicker(Color currentColor) {
    final colors = [
      const Color(0xFF0F142B),
      const Color(0xFF111827),
      const Color(0xFF1C1B2E),
      const Color(0xFF1B2638),
      const Color(0xFF15202B),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        final navigator = Navigator.of(sheetContext);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Chat background", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: colors.map((color) {
                  final bool selected = color.toARGB32() == currentColor.toARGB32();
                  return PressableScale(
                    onTap: () async {
                      await _setBackgroundColor(color);
                      if (!mounted) return;
                      navigator.pop();
                    },
                    borderRadius: BorderRadius.circular(999),
                    pressedScale: 0.92,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? const Color(0xFF00C09E) : Colors.white24, width: 2),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await _setBackgroundColor(const Color(0xFF0F142B));
                  if (!mounted) return;
                  navigator.pop();
                },
                child: const Text("Reset to default", style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _setBackgroundColor(Color color) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('chatSettings')
        .doc(widget.chatId)
        .set({'backgroundColor': color.toARGB32()}, SetOptions(merge: true));
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final int start = selection.start < 0 ? text.length : selection.start;
    final int end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, emoji);
    _messageController.text = newText;
    _messageController.selection = TextSelection.collapsed(offset: start + emoji.length);
  }

  Future<void> _toggleReaction(String messageId, String emoji, bool hasReacted) async {
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(messageId);
    if (hasReacted) {
      await ref.update({'reactions.$emoji': FieldValue.arrayRemove([currentUserId])});
    } else {
      await ref.update({'reactions.$emoji': FieldValue.arrayUnion([currentUserId])});
    }
  }

  void _showMessageActions(String messageId, Map<String, dynamic> data, bool isMe) {
    final String text = (data['text'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E243A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                children: _emojiOptions.map((emoji) {
                  return PressableScale(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final reactions = data['reactions'] as Map<String, dynamic>? ?? {};
                      final List<dynamic> users = reactions[emoji] as List<dynamic>? ?? [];
                      final bool hasReacted = users.contains(currentUserId);
                      _toggleReaction(messageId, emoji, hasReacted);
                    },
                    borderRadius: BorderRadius.circular(12),
                    pressedScale: 0.9,
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.event_available, color: Colors.white70),
                  title: const Text("Add to calendar", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _addToCalendar(text);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white70),
                title: Text(isMe ? "Delete for everyone" : "Remove for me", style: const TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (isMe) {
                    await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .doc(messageId)
                        .delete();
                  } else {
                    await FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .doc(messageId)
                        .update({'deletedFor': FieldValue.arrayUnion([currentUserId])});
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addToCalendar(String text) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (date == null) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (!mounted) return;
    if (time == null) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final end = start.add(const Duration(hours: 1));

    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('calendarEvents')
        .add({
      'title': text.isEmpty ? "Tutoring session" : text,
      'start': Timestamp.fromDate(start.toUtc()),
      'end': Timestamp.fromDate(end.toUtc()),
      'location': widget.chatTitle,
      'type': 'Meeting',
      'colorHex': EventTypePalette.colorHexForType('Meeting'),
      'source': 'manual',
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Added to calendar.")));
  }

  Future<void> _togglePlayback(String messageId, String? audioUrl) async {
    if (audioUrl == null || audioUrl.isEmpty) return;
    if (_playingMessageId == messageId) {
      await _audioPlayer.stop();
      if (mounted) setState(() => _playingMessageId = null);
      return;
    }
    setState(() => _playingMessageId = messageId);
    await _audioPlayer.play(UrlSource(audioUrl));
  }

  @override
  Widget build(BuildContext context) {
    const Color defaultBackgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('chatSettings')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, settingsSnap) {
        final settings = settingsSnap.data?.data() as Map<String, dynamic>? ?? {};
        final int? bgValue = settings['backgroundColor'] as int?;
        final Color backgroundColor = bgValue != null ? Color(bgValue) : defaultBackgroundColor;

        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            backgroundColor: backgroundColor,
            elevation: 0,
            leadingWidth: 70,
            leading: Center(
              child: PressableScale(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(999),
                pressedScale: 0.92,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.chatTitle, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                _buildPresenceLine(tealAccent),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.palette_outlined, color: Colors.white70),
                onPressed: () => _showBackgroundPicker(backgroundColor),
              ),
              IconButton(
                icon: const Icon(Icons.videocam_outlined, color: Colors.white70),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ParallelPracticeView()),
                ),
              ),
              const SizedBox(width: 5),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: tealAccent));

                    final messages = snapshot.data!.docs;

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final doc = messages[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final deletedFor = (data['deletedFor'] as List?)?.map((e) => e.toString()).toList() ?? [];
                        if (deletedFor.contains(currentUserId)) {
                          return const SizedBox.shrink();
                        }
                        return _buildBubble(doc.id, data);
                      },
                    );
                  },
                ),
              ),
              _buildInputBar(cardColor, tealAccent),
              if (_showEmojiPicker)
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E243A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: GridView.count(
                    crossAxisCount: 8,
                    children: _emojiOptions.map((emoji) {
                      return PressableScale(
                        onTap: () => _insertEmoji(emoji),
                        borderRadius: BorderRadius.circular(10),
                        pressedScale: 0.9,
                        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresenceLine(Color tealAccent) {
    if (widget.isGroup) {
      return Text(
        "Group chat",
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, chatSnap) {
        final chatData = chatSnap.data?.data() as Map<String, dynamic>? ?? {};
        final participants = chatData['participants'] as List<dynamic>? ?? [];
        String? otherUserId;
        for (final participant in participants) {
          if (participant != currentUserId) {
            otherUserId = participant.toString();
            break;
          }
        }

        if (otherUserId == null) {
          return Text(
            "Last seen recently",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
          );
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final Timestamp? lastSeen = userData['lastSeenAt'] as Timestamp? ?? userData['lastLoginAt'] as Timestamp?;
            bool isOnline = userData['isOnline'] == true;
            if (!isOnline && lastSeen != null) {
              final minutes = DateTime.now().difference(lastSeen.toDate()).inMinutes;
              if (minutes <= 2) {
                isOnline = true;
              }
            }

            final String label = isOnline ? "Online" : "Last seen ${_timeAgo(lastSeen)}";
            final Color labelColor = isOnline ? tealAccent : Colors.white.withValues(alpha: 0.4);

            return Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? tealAccent : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: labelColor, fontSize: 12)),
              ],
            );
          },
        );
      },
    );
  }

  String _timeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "recently";
    final now = DateTime.now();
    final diff = now.difference(timestamp.toDate());
    if (diff.inDays > 0) return "${diff.inDays}d ago";
    if (diff.inHours > 0) return "${diff.inHours}h ago";
    if (diff.inMinutes > 0) return "${diff.inMinutes}m ago";
    return "just now";
  }

  Widget _buildBubble(String messageId, Map<String, dynamic> data) {
    const Color tealAccent = Color(0xFF00C09E);
    final bool isMe = data['senderId'] == currentUserId;
    final String type = (data['type'] ?? 'text').toString();
    final String text = (data['text'] ?? '').toString();
    final String? audioUrl = data['audioUrl'] as String?;
    final String status = (data['status'] ?? 'sent').toString();
    final Timestamp? time = data['timestamp'] as Timestamp?;
    final Map<String, dynamic> reactions = data['reactions'] as Map<String, dynamic>? ?? {};
    final Color outgoingBubble = tealAccent.withValues(alpha: 0.85);
    final Color incomingBubble = const Color(0xFF1E243A).withValues(alpha: 0.85);
    final Color bubbleTextColor = isMe ? const Color(0xFF0F142B) : Colors.white.withValues(alpha: 0.92);
    final Color metaColor = isMe ? const Color(0xFF0F142B).withValues(alpha: 0.55) : Colors.white38;
    final BorderRadius bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(isMe ? 16 : 6),
      topRight: Radius.circular(isMe ? 6 : 16),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );

    String formattedTime = "";
    if (time != null) {
      DateTime dt = time.toDate();
      formattedTime = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: PressableScale(
        onLongPress: () => _showMessageActions(messageId, data, isMe),
        pressedScale: 0.99,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              decoration: BoxDecoration(
                color: isMe ? outgoingBubble : incomingBubble,
                borderRadius: bubbleRadius,
                border: isMe ? null : Border.all(color: Colors.white.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (type == 'voice')
                    PressableScale(
                      onTap: () => _togglePlayback(messageId, audioUrl),
                      borderRadius: BorderRadius.circular(12),
                      pressedScale: 0.96,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _playingMessageId == messageId ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: isMe ? const Color(0xFF0F142B) : Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Voice note",
                            style: TextStyle(
                              color: bubbleTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      text,
                      style: TextStyle(
                        color: bubbleTextColor,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formattedTime,
                        style: TextStyle(
                          color: metaColor,
                          fontSize: 10,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          status == 'read' ? Icons.done_all : Icons.done,
                          size: 14,
                          color: status == 'read'
                              ? const Color(0xFF0F142B).withValues(alpha: 0.8)
                              : const Color(0xFF0F142B).withValues(alpha: 0.45),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (reactions.isNotEmpty) _buildReactionsRow(reactions),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsRow(Map<String, dynamic> reactions) {
    final items = reactions.entries
        .where((entry) => entry.value is List && (entry.value as List).isNotEmpty)
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      children: items.map((entry) {
        final users = List<String>.from(entry.value as List);
        final bool hasReacted = users.contains(currentUserId);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasReacted ? const Color(0xFF00C09E).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.key, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(users.length.toString(), style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInputBar(Color cardColor, Color tealAccent) {
    final bool hasText = _messageController.text.trim().isNotEmpty;
    final bool supportsVoiceNotes = _supportsVoiceNotes;
    final Color actionColor = hasText
        ? tealAccent
        : (_isRecording ? Colors.redAccent : (supportsVoiceNotes ? tealAccent : Colors.white24));
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 25),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  PressableScale(
                    onTap: _toggleEmojiPicker,
                    borderRadius: BorderRadius.circular(14),
                    pressedScale: 0.9,
                    child: Icon(Icons.sentiment_satisfied_alt_rounded, color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: TextStyle(color: Colors.white24),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Icon(Icons.attach_file_rounded, color: Colors.white.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          PressableScale(
            onTap: () {
              if (hasText) {
                _sendMessage();
                return;
              }
              if (!supportsVoiceNotes) {
                _showVoiceNotSupported();
                return;
              }
              if (_isRecording) {
                _stopRecording();
              } else {
                _startRecording();
              }
            },
            borderRadius: BorderRadius.circular(999),
            pressedScale: 0.9,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: actionColor,
              child: Icon(
                hasText
                    ? Icons.send_rounded
                    : (_isRecording
                        ? Icons.stop_rounded
                        : (supportsVoiceNotes ? Icons.mic_rounded : Icons.mic_off_rounded)),
                color: const Color(0xFF0F142B),
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
