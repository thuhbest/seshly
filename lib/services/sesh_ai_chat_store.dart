import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class SeshAiChatStore {
  SeshAiChatStore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  Future<String> ensureThread({
    String? threadId,
    String? title,
    String? subject,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final id = threadId ?? _uuid.v4();
    final doc = _db.collection('users').doc(user.uid).collection('ai_threads').doc(id);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'title': title ?? 'Sesh AI',
        'subject': subject ?? '',
        'pinned': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
    }
    return id;
  }

  Stream<List<ChatMessage>> streamMessages(String threadId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return _db
        .collection('users')
        .doc(user.uid)
        .collection('ai_threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> addMessage({
    required String threadId,
    required String role,
    required String text,
    List<String>? attachments,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final threadRef = _db.collection('users').doc(user.uid).collection('ai_threads').doc(threadId);
    final msgRef = threadRef.collection('messages').doc();
    await _db.runTransaction((tx) async {
      tx.set(msgRef, {
        'role': role,
        'text': text,
        'attachments': attachments ?? [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(threadRef, {
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': text,
      }, SetOptions(merge: true));
    });
  }

  Future<void> updateThread({
    required String threadId,
    String? title,
    bool? pinned,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final threadRef = _db.collection('users').doc(user.uid).collection('ai_threads').doc(threadId);
    await threadRef.set({
      if (title != null) 'title': title,
      if (pinned != null) 'pinned': pinned,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.attachments,
    required this.reactions,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String text;
  final List<String> attachments;
  final Map<String, List<String>> reactions;
  final DateTime? createdAt;

  bool get isUser => role == 'user';

  static ChatMessage fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final rawReactions = (data['reactions'] as Map<String, dynamic>?) ?? {};
    final reactions = <String, List<String>>{};
    rawReactions.forEach((key, value) {
      if (value is List) {
        reactions[key] = value.map((e) => e.toString()).toList();
      }
    });
    return ChatMessage(
      id: doc.id,
      role: (data['role'] ?? 'assistant').toString(),
      text: (data['text'] ?? '').toString(),
      attachments: (data['attachments'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      reactions: reactions,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

extension SeshAiChatReactions on SeshAiChatStore {
  Future<void> toggleReaction({
    required String threadId,
    required String messageId,
    required String emoji,
    required String userId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    final msgRef = _db
        .collection('users')
        .doc(user.uid)
        .collection('ai_threads')
        .doc(threadId)
        .collection('messages')
        .doc(messageId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final reactions = (data['reactions'] as Map<String, dynamic>?) ?? {};
      final current = (reactions[emoji] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      if (current.contains(userId)) {
        tx.set(msgRef, {
          'reactions.$emoji': FieldValue.arrayRemove([userId]),
        }, SetOptions(merge: true));
      } else {
        tx.set(msgRef, {
          'reactions.$emoji': FieldValue.arrayUnion([userId]),
        }, SetOptions(merge: true));
      }
    });
  }
}
