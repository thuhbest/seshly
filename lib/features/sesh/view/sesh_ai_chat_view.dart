import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
      _controller.text = widget.initialMessage!;
    }
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
      final id = await _store.ensureThread(
        threadId: widget.threadId,
        title: widget.title,
        subject: widget.subject,
      );
      if (!mounted) return;
      setState(() => _threadId = id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialAction != null) {
          _runInitialAction();
        } else if (widget.autoSend && widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
          _sendMessage(widget.initialMessage!, attachments: widget.initialAttachments);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _threadId = '');
      _showSnack('Failed to start chat: $error');
    }
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
    } catch (error) {
      await _appendAssistant('Action failed: $error');
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
    } catch (error) {
      await _appendAssistant('Request failed: $error');
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

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0F142B);
    const Color assistantBg = Color(0xFF1E243A);
    const Color userBg = Color(0xFF00C09E);
    const Color border = Color(0xFF232A44);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          if (_primaryUrl != null)
            TextButton(
              onPressed: _openPrimaryUrl,
              child: const Text('Open PDF', style: TextStyle(color: Color(0xFF00C09E))),
            ),
        ],
      ),
      body: _threadId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                                        Text(msg.text, style: TextStyle(color: textColor, fontSize: 14, height: 1.4)),
                                        if (msg.attachments.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: msg.attachments.map((url) {
                                                if (_isImageUrl(url)) {
                                                  return ClipRRect(
                                                    borderRadius: BorderRadius.circular(10),
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
                                                  );
                                                }
                                                return OutlinedButton.icon(
                                                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                                                  icon: const Icon(Icons.attach_file, size: 14),
                                                  label: const Text('Open file'),
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
                                                label: const Text('Copy', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                              ),
                                            ),
                                          ],
                                        ],
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B2F),
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Ask Sesh AI...',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _isSending ? null : () => _sendMessage(_controller.text),
                        icon: _isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send, color: Color(0xFF00C09E)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
