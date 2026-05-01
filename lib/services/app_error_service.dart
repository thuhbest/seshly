import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_analytics_service.dart';
import 'sesh_ai_api.dart';

class AppErrorService {
  AppErrorService._();

  static final AppErrorService instance = AppErrorService._();

  Future<void> initialize() async {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        recordError(
          details.exception,
          details.stack ?? StackTrace.current,
          category: 'flutter',
          source: 'FlutterError.onError',
          fatal: kReleaseMode,
        ),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        recordError(
          error,
          stack,
          category: 'platform',
          source: 'PlatformDispatcher',
          fatal: true,
        ),
      );
      return true;
    };
  }

  Future<void> setUserContext(String? userId) async {
    try {
      if (userId == null || userId.isEmpty) {
        await FirebaseCrashlytics.instance.setUserIdentifier('');
      } else {
        await FirebaseCrashlytics.instance.setUserIdentifier(userId);
      }
    } catch (_) {}
    await AppAnalyticsService.instance.setUserId(userId);
  }

  String userMessageFor(
    Object error, {
    String fallback = 'Something went wrong. Please try again.',
  }) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'resource-exhausted') {
        return 'Too many attempts right now. Please try again later.';
      }
      if (error.code == 'unauthenticated') {
        return 'Please sign in and try again.';
      }
      if (error.code == 'unavailable') {
        return 'The service is temporarily unavailable. Please try again.';
      }
      if (error.code == 'internal') {
        return 'Something went wrong on our side. Please try again.';
      }
      if (error.code == 'failed-precondition') {
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : fallback;
      }
      if (error.code == 'invalid-argument') {
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Some information is invalid. Please review and try again.';
      }
      return fallback;
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'too-many-requests':
          return 'Too many attempts right now. Please try again later.';
        case 'network-request-failed':
          return 'Network error. Check your connection and retry.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Invalid login credentials. Please try again.';
        default:
          return fallback;
      }
    }
    if (error is FirebaseException) {
      if (error.code.contains('network')) {
        return 'Network error. Check your connection and retry.';
      }
      return fallback;
    }
    if (error is SeshAiApiException) {
      switch (error.code) {
        case 'rate_limited':
        case 'provider_quota':
        case 'insufficient_quota':
          return 'Sesh AI is busy right now. Please try again later.';
        case 'temporarily_busy':
          return 'Sesh is handling a lot right now. Please try again in a moment.';
        case 'token_budget_exceeded':
          return 'Your AI limit has been reached for now. Please try again later.';
        case 'missing_auth':
        case 'missing_user':
          return 'Please sign in to continue.';
        case 'invalid_request':
          return 'Some information is invalid. Please review and try again.';
        case 'network_unavailable':
        case 'client_error':
        case 'http_error':
          return 'Network error. Check your connection and retry.';
        default:
          return fallback;
      }
    }
    if (error is SocketException || error is TimeoutException) {
      return 'Network error. Check your connection and retry.';
    }
    final rawMessage = error.toString();
    if (rawMessage.contains(
      'Please wait a moment before requesting another email',
    )) {
      return 'Please wait a moment before requesting another verification email.';
    }
    if (rawMessage.contains('rate_limited') || rawMessage.contains('429')) {
      return 'Too many attempts right now. Please try again later.';
    }
    return fallback;
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required String category,
    required String source,
    bool fatal = false,
  }) async {
    debugPrint('[$category][$source] $error');
    try {
      await FirebaseCrashlytics.instance.setCustomKey(
        'error_category',
        category,
      );
      await FirebaseCrashlytics.instance.setCustomKey('error_source', source);
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: category,
        fatal: fatal,
      );
    } catch (_) {}
    await AppAnalyticsService.instance.trackHandledError(
      category: category,
      source: source,
      status: fatal ? 'fatal' : 'handled',
    );
  }

  void showSnackBar(
    BuildContext context,
    String message, {
    Color backgroundColor = Colors.redAccent,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
