import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_analytics_service.dart';
import 'app_error_service.dart';

class CommunityBackendService {
  CommunityBackendService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');

  static final CommunityBackendService instance = CommunityBackendService();

  final FirebaseFunctions _functions;
  final Map<String, _TutorSearchCacheEntry> _tutorSearchCache =
      <String, _TutorSearchCacheEntry>{};
  Future<void>? _syncAccessProfileInFlight;
  String? _syncAccessProfileUserId;
  DateTime? _lastAccessProfileSyncAt;

  void clearSessionCache() {
    _tutorSearchCache.clear();
    _syncAccessProfileInFlight = null;
    _syncAccessProfileUserId = null;
    _lastAccessProfileSyncAt = null;
  }

  Future<void> initializeAccountProfile({
    required String fullName,
    required String studentNumber,
    required String university,
    required String levelOfStudy,
  }) async {
    await _call('initializeAccountProfile', <String, dynamic>{
      'fullName': fullName,
      'studentNumber': studentNumber,
      'university': university,
      'levelOfStudy': levelOfStudy,
    });
  }

  Future<void> syncAccessProfile({
    String reason = 'unspecified',
    String? traceId,
    bool force = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';
    final now = DateTime.now();

    if (!force &&
        _syncAccessProfileInFlight != null &&
        _syncAccessProfileUserId == userId) {
      debugPrint(
        '[functions][syncAccessProfile] trace=${traceId ?? 'n/a'} '
        'uid=$userId reusing_in_flight=true reason=$reason',
      );
      return _syncAccessProfileInFlight!;
    }

    if (!force &&
        _lastAccessProfileSyncAt != null &&
        _syncAccessProfileUserId == userId &&
        now.difference(_lastAccessProfileSyncAt!) <
            const Duration(seconds: 10)) {
      debugPrint(
        '[functions][syncAccessProfile] trace=${traceId ?? 'n/a'} '
        'uid=$userId skipped_recent=true reason=$reason',
      );
      return;
    }

    debugPrint(
      '[functions][syncAccessProfile] trace=${traceId ?? 'n/a'} '
      'uid=$userId start reason=$reason force=$force',
    );

    late final Future<void> future;
    future = _call('syncAccessProfile', const <String, dynamic>{})
        .then((_) {
          _lastAccessProfileSyncAt = DateTime.now();
          debugPrint(
            '[functions][syncAccessProfile] trace=${traceId ?? 'n/a'} '
            'uid=$userId success reason=$reason',
          );
        })
        .catchError((Object error, StackTrace stackTrace) async {
          debugPrint(
            '[functions][syncAccessProfile] trace=${traceId ?? 'n/a'} '
            'uid=$userId failure reason=$reason error=$error',
          );
          await AppErrorService.instance.recordError(
            error,
            stackTrace,
            category: 'functions',
            source: 'syncAccessProfile',
          );
          throw error;
        })
        .whenComplete(() {
          if (identical(_syncAccessProfileInFlight, future)) {
            _syncAccessProfileInFlight = null;
          }
        });

    _syncAccessProfileInFlight = future;
    _syncAccessProfileUserId = userId;
    return future;
  }

  Future<String> createPost({
    required String subject,
    required String question,
    String? link,
    String? attachmentUrl,
    String? attachmentPath,
    String? repostText,
    Map<String, dynamic>? repostOf,
  }) async {
    final result = await _call('createPost', <String, dynamic>{
      'subject': subject,
      'question': question,
      if (link != null && link.trim().isNotEmpty) 'link': link.trim(),
      if (attachmentUrl != null && attachmentUrl.trim().isNotEmpty)
        'attachmentUrl': attachmentUrl.trim(),
      if (attachmentPath != null && attachmentPath.trim().isNotEmpty)
        'attachmentPath': attachmentPath.trim(),
      if (repostText != null && repostText.trim().isNotEmpty)
        'repostText': repostText.trim(),
      if (repostOf != null) 'repostOf': repostOf,
    });
    return (result['postId'] ?? '').toString();
  }

  Future<String> createComment({
    required String postId,
    required String text,
  }) async {
    final result = await _call('createComment', <String, dynamic>{
      'postId': postId,
      'text': text,
    });
    return (result['commentId'] ?? '').toString();
  }

  Future<String> ensureDirectChat(String participantId) async {
    final result = await _call('ensureDirectChat', <String, dynamic>{
      'participantId': participantId,
    });
    return (result['chatId'] ?? '').toString();
  }

  Future<String> sendTextChatMessage({
    required String chatId,
    required String text,
  }) async {
    final result = await _call('sendChatMessage', <String, dynamic>{
      'chatId': chatId,
      'type': 'text',
      'text': text,
    });
    return (result['messageId'] ?? '').toString();
  }

  Future<String> sendVoiceChatMessage({
    required String chatId,
    required String audioUrl,
    required String audioPath,
  }) async {
    final result = await _call('sendChatMessage', <String, dynamic>{
      'chatId': chatId,
      'type': 'voice',
      'audioUrl': audioUrl,
      'audioPath': audioPath,
    });
    return (result['messageId'] ?? '').toString();
  }

  Future<String> sendFriendRequest(String toUserId) async {
    final result = await _call('sendFriendRequest', <String, dynamic>{
      'toUserId': toUserId,
    });
    return (result['requestId'] ?? '').toString();
  }

  Future<String> respondToFriendRequest({
    required String requestId,
    required String action,
  }) async {
    final result = await _call('respondToFriendRequest', <String, dynamic>{
      'requestId': requestId,
      'action': action,
    });
    return (result['status'] ?? '').toString();
  }

  Future<void> markChatRead(String chatId) async {
    await _call('markChatRead', <String, dynamic>{'chatId': chatId});
  }

  Future<bool> toggleChatReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final result = await _call('toggleChatReaction', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
      'emoji': emoji,
    });
    return result['reacted'] == true;
  }

  Future<void> deleteChatMessage({
    required String chatId,
    required String messageId,
  }) async {
    await _call('deleteChatMessage', <String, dynamic>{
      'chatId': chatId,
      'messageId': messageId,
    });
  }

  Future<bool> toggleHelpfulReaction(String postId) async {
    final result = await _call('toggleHelpfulReaction', <String, dynamic>{
      'postId': postId,
    });
    return result['reacted'] == true;
  }

  Future<void> updateProfile({
    String? fullName,
    String? middleName,
    int? age,
    String? major,
    String? levelOfStudy,
    String? bio,
    String? profilePicUrl,
    String? profilePicPath,
  }) async {
    await _call('updateProfileSecure', <String, dynamic>{
      if (fullName != null) 'fullName': fullName,
      if (middleName != null) 'middleName': middleName,
      if (age != null) 'age': age,
      if (major != null) 'major': major,
      if (levelOfStudy != null) 'levelOfStudy': levelOfStudy,
      if (bio != null) 'bio': bio,
      if (profilePicUrl != null) 'profilePicUrl': profilePicUrl,
      if (profilePicPath != null) 'profilePicPath': profilePicPath,
    });
  }

  Future<String> createStudyVaultResource(Map<String, dynamic> data) async {
    final result = await _call('createStudyVaultResource', data);
    return (result['resourceId'] ?? '').toString();
  }

  Future<List<Map<String, dynamic>>> searchTutors({
    required String subject,
    double? maxPrice,
    List<String>? availability,
    double? minRating,
    int limit = 20,
  }) async {
    final userKey = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final cacheKey = [
      userKey,
      subject.trim().toLowerCase(),
      maxPrice?.toString() ?? '',
      minRating?.toString() ?? '',
      (availability ?? const <String>[]).join(','),
      limit.toString(),
    ].join('|');
    final now = DateTime.now();
    final cached = _tutorSearchCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      unawaited(
        AppAnalyticsService.instance.trackTutorSearch(
          subject: subject,
          resultCount: cached.items.length,
          cached: true,
        ),
      );
      return cached.items;
    }

    final result = await _call('searchTutorsSecure', <String, dynamic>{
      'subject': subject,
      if (maxPrice != null) 'maxPrice': maxPrice,
      if (availability != null && availability.isNotEmpty)
        'availability': availability,
      if (minRating != null) 'minRating': minRating,
      'limit': limit,
    });

    final items = (result['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
    _tutorSearchCache[cacheKey] = _TutorSearchCacheEntry(
      items: items,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    await AppAnalyticsService.instance.trackTutorSearch(
      subject: subject,
      resultCount: items.length,
      cached: false,
    );
    return items;
  }

  Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(functionName).call(data);
      final payload = result.data;
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return <String, dynamic>{};
    } on FirebaseFunctionsException catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'functions',
        source: functionName,
      );
      rethrow;
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'functions',
        source: functionName,
      );
      rethrow;
    }
  }
}

class _TutorSearchCacheEntry {
  const _TutorSearchCacheEntry({required this.items, required this.expiresAt});

  final List<Map<String, dynamic>> items;
  final DateTime expiresAt;
}
