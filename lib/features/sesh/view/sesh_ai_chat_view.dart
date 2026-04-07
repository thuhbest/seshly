import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:seshly/services/app_analytics_service.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/sesh_ai_api.dart';
import 'package:seshly/services/sesh_ai_chat_store.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatActionResult {
  const ChatActionResult({required this.messages, this.primaryUrl});

  final List<String> messages;
  final String? primaryUrl;
}

typedef ChatInitialAction = Future<ChatActionResult> Function();

class SeshAiChatView extends StatefulWidget {
  const SeshAiChatView({
    super.key,
    required this.title,
    this.subject,
    this.initialMessage,
    this.initialAttachments,
    this.autoSend = false,
    this.initialAction,
    this.threadId,
  });

  final String title;
  final String? subject;
  final String? initialMessage;
  final List<String>? initialAttachments;
  final bool autoSend;
  final ChatInitialAction? initialAction;
  final String? threadId;

  @override
  State<SeshAiChatView> createState() => _SeshAiChatViewState();
}

class _SeshAiChatViewState extends State<SeshAiChatView> {
  final _api = SeshAiApi();
  final _store = SeshAiChatStore();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  String? _threadId;
  bool _isSending = false;
  String? _primaryUrl;
  int _lastMessageCount = 0;
  String? _currentUserId;
  String _threadTitle = '';
  bool _isPinned = false;

  final _reactionOptions = const ['👍', '💡', '✅', '⭐', '❓', '👀'];

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _controller.text = widget.initialMessage!;
    }
    _currentUserId = null;
    _initThread();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initThread() async {
    try {
      _currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final id = await _store.ensureThread(
        threadId: widget.threadId,
        title: widget.title,
        subject: widget.subject,
      );
      if (!mounted) return;
      setState(() => _threadId = id);
      await _loadThreadMeta(id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialAction != null) {
          _runInitialAction();
        } else if (widget.autoSend && widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
          _sendMessage(widget.initialMessage!, attachments: widget.initialAttachments);
        }
      });
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'init_thread',
      );
      if (!mounted) return;
      setState(() => _threadId = '');
      _showSnack(
        AppErrorService.instance.userMessageFor(
          error,
          fallback: 'Failed to start chat. Please try again.',
        ),
      );
    }
  }

  Future<void> _loadThreadMeta(String threadId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_threads')
        .doc(threadId)
        .get();
    final data = snap.data() ?? {};
    if (!mounted) return;
    setState(() {
      _threadTitle = (data['title'] ?? widget.title).toString();
      _isPinned = (data['pinned'] ?? false) == true;
    });
  }

  Future<void> _runInitialAction() async {
    setState(() => _isSending = true);
    try {
      final result = await widget.initialAction!();
      if (!mounted) return;
      if (_threadId == null || _threadId!.isEmpty) return;
      for (final message in result.messages) {
        await _store.addMessage(
          threadId: _threadId!,
          role: 'assistant',
          text: message,
        );
      }
      setState(() => _primaryUrl = result.primaryUrl);
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'chat_initial_action',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'chat_initial_action',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'chat_initial_action',
      );
      await _appendAssistant(_mapError(error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendMessage(String text, {List<String>? attachments}) async {
    if (_isSending) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_threadId == null || _threadId!.isEmpty) return;

    setState(() => _isSending = true);
    _controller.clear();

    try {
      await _store.addMessage(
        threadId: _threadId!,
        role: 'user',
        text: trimmed,
        attachments: attachments,
      );
      final response = await _api.chatSocratic(
        message: trimmed,
        subject: widget.subject,
        attachments: attachments,
        threadId: _threadId,
      );
      final reply = response['replyText']?.toString().trim();
      await _appendAssistant(reply?.isNotEmpty == true ? reply! : 'No response.');
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'chat_message',
        status: 'success',
      );
    } catch (error, stackTrace) {
      await AppAnalyticsService.instance.trackAiUsage(
        action: 'chat_message',
        status: 'error',
      );
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'ai',
        source: 'chat_message',
      );
      await _appendAssistant(_mapError(error));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _appendAssistant(String text) async {
    if (_threadId == null || _threadId!.isEmpty) return;
    await _store.addMessage(
      threadId: _threadId!,
      role: 'assistant',
      text: text,
    );
  }

  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    final userId = _currentUserId;
    if (userId == null || _threadId == null || _threadId!.isEmpty) return;
    await _store.toggleReaction(
      threadId: _threadId!,
      messageId: message.id,
      emoji: emoji,
      userId: userId,
    );
  }

  void _showReactionPicker(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141B2F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 12,
          children: _reactionOptions
              .map((emoji) => InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _toggleReaction(message, emoji);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _openPrimaryUrl() async {
    final url = _primaryUrl;
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.contains('image');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _mapError(Object error) {
    return AppErrorService.instance.userMessageFor(
      error,
      fallback: 'Request failed. Please try again in a moment.',
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color assistantBg = Color(0xFF1E243A);
    const Color userBg = Color(0xFF00C09E);
    const Color border = Color(0xFF232A44);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1024),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: Text(
          _threadTitle.isEmpty ? widget.title : _threadTitle,
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_primaryUrl != null)
            TextButton(
              onPressed: _openPrimaryUrl,
              child: Text(
                'Open PDF',
                style: GoogleFonts.spaceGrotesk(color: const Color(0xFF7CF1D6)),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF141B2F),
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameDialog();
              } else if (value == 'pin') {
                _togglePin();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'rename',
                child: Text('Rename', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
              ),
              PopupMenuItem(
                value: 'pin',
                child: Text(_isPinned ? 'Unpin' : 'Pin', style: GoogleFonts.spaceGrotesk(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackground(),
          if (_threadId == null)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: _threadId!.isEmpty ? const Stream.empty() : _store.streamMessages(_threadId!),
                    builder: (context, snap) {
                      final messages = snap.data ?? const <ChatMessage>[];
                      if (messages.length != _lastMessageCount) {
                        _lastMessageCount = messages.length;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!_scrollController.hasClients) return;
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent + 120,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        });
                      }
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text('Ask Sesh AI to get started', style: TextStyle(color: Colors.white38)),
                        );
                      }
                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isUser = msg.isUser;
                          final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
                          final bubbleColor = isUser ? userBg : assistantBg;
                          final textColor = isUser ? const Color(0xFF0F142B) : Colors.white70;
                          return Column(
                            crossAxisAlignment: alignment,
                            children: [
                              Row(
                                mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  if (!isUser)
                                    const CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Color(0xFF00C09E),
                                      child: Icon(Icons.auto_awesome, size: 14, color: Color(0xFF0F142B)),
                                    ),
                                  if (!isUser) const SizedBox(width: 8),
                                  Flexible(
                                    child: GestureDetector(
                                      onLongPress: () => _showReactionPicker(msg),
                                      child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: bubbleColor,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: border.withValues(alpha: 0.5)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                        if (isUser)
                                          Text(
                                            msg.text,
                                            style: GoogleFonts.spaceGrotesk(
                                              color: textColor,
                                              fontSize: 14,
                                              height: 1.4,
                                            ),
                                          )
                                        else
                                          MarkdownBody(
                                            data: msg.text,
                                            selectable: true,
                                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                              p: GoogleFonts.spaceGrotesk(
                                                color: textColor,
                                                fontSize: 14,
                                                height: 1.4,
                                              ),
                                              strong: GoogleFonts.spaceGrotesk(
                                                color: textColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              em: GoogleFonts.spaceGrotesk(
                                                color: textColor,
                                                fontStyle: FontStyle.italic,
                                              ),
                                              code: GoogleFonts.spaceGrotesk(
                                                color: const Color(0xFF7CF1D6),
                                              ),
                                              blockquote: GoogleFonts.spaceGrotesk(
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                        if (msg.attachments.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: msg.attachments.map((url) {
                                              if (_isImageUrl(url)) {
                                                return ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: GestureDetector(
                                                    onTap: () => _openImagePreview(url),
                                                    child: Image.network(
                                                      url,
                                                      width: 120,
                                                      height: 90,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => Container(
                                                        width: 120,
                                                        height: 90,
                                                        color: Colors.white10,
                                                        alignment: Alignment.center,
                                                        child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }
                                              return OutlinedButton.icon(
                                                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                                                icon: const Icon(Icons.attach_file, size: 14),
                                                  label: Text('Open file', style: GoogleFonts.spaceGrotesk()),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                          if (!isUser) ...[
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                onPressed: () async {
                                                  await Clipboard.setData(ClipboardData(text: msg.text));
                                                  if (!mounted) return;
                                                  _showSnack('Copied to clipboard.');
                                                },
                                                icon: const Icon(Icons.copy, size: 14, color: Colors.white54),
                                                label: Text(
                                                  'Copy',
                                                  style: GoogleFonts.spaceGrotesk(color: Colors.white54, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (msg.reactions.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              children: msg.reactions.entries.map((entry) {
                                                final users = entry.value;
                                                if (users.isEmpty) return const SizedBox.shrink();
                                                final selected = users.contains(_currentUserId);
                                                return InkWell(
                                                  onTap: () => _toggleReaction(msg, entry.key),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: selected
                                                          ? const Color(0xFF00C09E).withValues(alpha: 0.2)
                                                          : Colors.white.withValues(alpha: 0.08),
                                                      borderRadius: BorderRadius.circular(999),
                                                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(entry.key, style: const TextStyle(fontSize: 12)),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          users.length.toString(),
                                                          style: GoogleFonts.spaceGrotesk(
                                                            color: Colors.white70,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_isSending)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(0xFF00C09E),
                          child: Icon(Icons.auto_awesome, size: 12, color: Color(0xFF0F142B)),
                        ),
                        const SizedBox(width: 8),
                        _TypingDots(color: Colors.white70),
                      ],
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B2F).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: GoogleFonts.spaceGrotesk(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Ask Sesh AI...',
                            hintStyle: GoogleFonts.spaceGrotesk(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7CF1D6), Color(0xFF00C09E)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: _isSending ? null : () => _sendMessage(_controller.text),
                          icon: _isSending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send, color: Color(0xFF0F142B)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog() async {
    if (_threadId == null || _threadId!.isEmpty) return;
    final controller = TextEditingController(text: _threadTitle.isEmpty ? widget.title : _threadTitle);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141B2F),
        title: Text('Rename chat', style: GoogleFonts.playfairDisplay(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: GoogleFonts.spaceGrotesk(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Chat title',
            hintStyle: GoogleFonts.spaceGrotesk(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.spaceGrotesk(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('Save', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF7CF1D6))),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _store.updateThread(threadId: _threadId!, title: result);
      if (!mounted) return;
      setState(() => _threadTitle = result);
    }
  }

  Future<void> _togglePin() async {
    if (_threadId == null || _threadId!.isEmpty) return;
    final next = !_isPinned;
    await _store.updateThread(threadId: _threadId!, pinned: next);
    if (!mounted) return;
    setState(() => _isPinned = next);
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B1024), Color(0xFF0E2233), Color(0xFF0B1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -60,
            child: _glow(const Color(0xFF00C09E), 220),
          ),
          Positioned(
            bottom: -140,
            left: -80,
            child: _glow(const Color(0xFF6F8FE4), 260),
          ),
          Positioned(
            top: 120,
            left: 40,
            child: _glow(const Color(0xFF7CF1D6), 120),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  void _openImagePreview(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final dots = [0.2, 0.5, 0.8].map((p) => (t > p ? 1.0 : 0.3)).toList();
        return Row(
          children: List.generate(3, (index) {
            return Container(
              margin: const EdgeInsets.only(right: 4),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: dots[index]),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
