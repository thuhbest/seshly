import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:seshly/access/app_access.dart';
import 'package:seshly/access/app_identity.dart';
import 'package:seshly/access/app_session_scope.dart';
import 'package:seshly/features/seshfocus/sesh_focus_active_screen.dart';
import 'package:seshly/features/startpage/views/start_page_view.dart';
import 'package:seshly/features/home/view/main_wrapper.dart';
import 'package:seshly/services/app_analytics_service.dart';
import 'package:seshly/services/app_error_service.dart';
import 'package:seshly/services/auth_service.dart';
import 'package:seshly/services/community_backend_service.dart';
import 'package:seshly/services/tutor_identity_service.dart';
import 'package:seshly/services/tutor_organization_service.dart';
import 'package:seshly/theme/seshly_theme.dart';

const Color backgroundColor = SeshlyPalette.background;

void main() async {
  // Ensure Flutter is initialized before calling Firebase
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = true;
  try {
    // Initialize Firebase with platform-specific options.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await AuthService.ensureWebPersistenceConfigured();
  } on UnsupportedError {
    firebaseReady = false;
  } on MissingPluginException {
    firebaseReady = false;
  } on FirebaseException {
    firebaseReady = false;
  }

  if (firebaseReady) {
    await AppErrorService.instance.initialize();
  }

  // Match the navigation bar color to your app theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: backgroundColor,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(MyApp(firebaseReady: firebaseReady));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seshly',
      debugShowCheckedModeBanner: false,
      theme: SeshlyTheme.dark(),
      // AuthWrapper acts as the gatekeeper for the session
      home: firebaseReady
          ? const AuthWrapper()
          : const _PlatformNotConfiguredView(),
      routes: {'/seshFocusActive': (_) => const SeshFocusActiveScreen()},
    );
  }
}

class _PlatformNotConfiguredView extends StatelessWidget {
  const _PlatformNotConfiguredView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Firebase is not configured for this platform in the current build.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        debugPrint(
          'AuthWrapper: state=${snapshot.connectionState} hasUser=${user != null} isAnonymous=${user?.isAnonymous}',
        );
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SessionLoadingView();
        }

        if (user != null && !user.isAnonymous) {
          unawaited(AppErrorService.instance.setUserContext(user.uid));
          return _SignedInAccountRouter(
            key: ValueKey('signed-in-router-${user.uid}'),
            user: user,
          );
        }

        if (user != null && user.isAnonymous) {
          unawaited(AppErrorService.instance.setUserContext(user.uid));
          debugPrint(
            'AuthWrapper: entering Instant Tutor session for uid=${user.uid}.',
          );
          return _AuthenticatedSession(
            key: ValueKey('session-${user.uid}-instant'),
            user: user,
          );
        }

        CommunityBackendService.instance.clearSessionCache();
        unawaited(AppErrorService.instance.setUserContext(null));
        debugPrint(
          'AuthWrapper: no authenticated user, showing StartPageView.',
        );
        return const StartPageView();
      },
    );
  }
}

class _SignedInAccountRouter extends StatefulWidget {
  const _SignedInAccountRouter({super.key, required this.user});

  final User user;

  @override
  State<_SignedInAccountRouter> createState() => _SignedInAccountRouterState();
}

class _SignedInAccountRouterState extends State<_SignedInAccountRouter> {
  final AuthService _authService = AuthService();
  late Future<bool> _verificationFuture;

  @override
  void initState() {
    super.initState();
    _verificationFuture = _resolveVerification();
  }

  @override
  void didUpdateWidget(covariant _SignedInAccountRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.emailVerified != widget.user.emailVerified) {
      _verificationFuture = _resolveVerification();
    }
  }

  Future<bool> _resolveVerification() async {
    final traceId =
        'route-${widget.user.uid}-${DateTime.now().microsecondsSinceEpoch}';
    debugPrint(
      'AuthWrapper: verification route check start uid=${widget.user.uid} trace=$traceId',
    );
    final verified = await _authService.refreshVerificationStatus(
      widget.user,
      traceId: traceId,
    );
    debugPrint(
      'AuthWrapper: verification route check complete uid=${widget.user.uid} trace=$traceId verified=$verified',
    );
    return verified;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _verificationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SessionLoadingView();
        }

        if (snapshot.hasError) {
          debugPrint(
            'AuthWrapper: verification route check failed for uid=${widget.user.uid}: ${snapshot.error}',
          );
          unawaited(
            AppErrorService.instance.recordError(
              snapshot.error!,
              StackTrace.current,
              category: 'auth',
              source: 'AuthWrapper.verificationRoute',
            ),
          );
        }

        final verified = snapshot.hasData
            ? snapshot.data == true
            : widget.user.emailVerified;
        debugPrint(
          'AuthWrapper: final route decision uid=${widget.user.uid} verified=$verified',
        );

        if (!verified) {
          return _EmailVerificationGate(user: widget.user);
        }

        return _AuthenticatedSession(
          key: ValueKey('session-${widget.user.uid}-full'),
          user: widget.user,
        );
      },
    );
  }
}

class _AuthenticatedSession extends StatefulWidget {
  const _AuthenticatedSession({super.key, required this.user});

  final User user;

  @override
  State<_AuthenticatedSession> createState() => _AuthenticatedSessionState();
}

class _AuthenticatedSessionState extends State<_AuthenticatedSession> {
  final AuthService _authService = AuthService();
  late Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    CommunityBackendService.instance.clearSessionCache();
    _bootstrapFuture = _bootstrapUser();
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.isAnonymous != widget.user.isAnonymous) {
      debugPrint(
        'AuthenticatedSession: session changed from uid=${oldWidget.user.uid} isAnonymous=${oldWidget.user.isAnonymous} '
        'to uid=${widget.user.uid} isAnonymous=${widget.user.isAnonymous}. Rebootstrapping access state.',
      );
      CommunityBackendService.instance.clearSessionCache();
      _bootstrapFuture = _bootstrapUser();
    }
  }

  Future<void> _bootstrapUser() {
    final traceId =
        'session-${widget.user.uid}-${DateTime.now().microsecondsSinceEpoch}';
    if (widget.user.isAnonymous) {
      unawaited(
        _authService.ensureInstantTutorModeProfile(
          widget.user,
          traceId: traceId,
        ),
      );
      return Future.value();
    }
    unawaited(
      _authService.ensureVerifiedStudentAccessProfile(
        widget.user,
        traceId: traceId,
      ),
    );
    return Future.value();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _SessionLoadingView();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.hasError) {
              debugPrint(
                'AuthenticatedSession: user document stream error for ${widget.user.uid}: ${userSnapshot.error}',
              );
            }
            if (userSnapshot.connectionState == ConnectionState.waiting &&
                !userSnapshot.hasData) {
              return const _SessionLoadingView();
            }

            final userData =
                userSnapshot.data?.data() ?? const <String, dynamic>{};
            final identity = AppIdentity.fromUserData(
              userData,
              isAnonymousAuth: widget.user.isAnonymous,
            );
            final access = AppAccessProfile.fromIdentity(identity);
            final tutor = TutorIdentityService.fromUserData(
              userData,
              userId: widget.user.uid,
            );
            final organization =
                TutorOrganizationService.membershipFromUserData(userData);

            debugPrint(
              'AuthenticatedSession: built session for uid=${widget.user.uid} isAnonymous=${widget.user.isAnonymous} accessTier=${identity.accessTierValue} accountType=${identity.accountTypeValue}',
            );
            unawaited(AppAnalyticsService.instance.setUserId(widget.user.uid));

            return AppSessionScope(
              session: AppSession(
                userId: widget.user.uid,
                userData: userData,
                identity: identity,
                tutor: tutor,
                organization: organization,
                access: access,
              ),
              child: MainWrapper(
                key: ValueKey(
                  'main-wrapper-${widget.user.uid}-${widget.user.isAnonymous ? 'instant' : 'full'}',
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EmailVerificationGate extends StatefulWidget {
  const _EmailVerificationGate({required this.user});

  final User user;

  @override
  State<_EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<_EmailVerificationGate> {
  final AuthService _authService = AuthService();
  bool _isSending = false;
  bool _isRefreshing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _statusMessage =
        'Verify your email to continue. If you did not receive an email, you can resend it below.';
    unawaited(_maybeSendVerificationEmailOnEntry());
  }

  Future<void> _maybeSendVerificationEmailOnEntry() async {
    try {
      final result = await _authService.maybeSendVerificationEmail(
        widget.user,
        reason: 'verification_gate_entry',
      );
      if (!mounted) return;
      setState(() {
        if (result.status == VerificationEmailDispatchStatus.sent ||
            result.status == VerificationEmailDispatchStatus.cooldown) {
          _statusMessage =
              'Verify your email to continue. We sent a verification email to ${widget.user.email ?? 'your address'}.';
        }
      });
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'verification',
        source: 'verification_gate_entry',
      );
    }
  }

  Future<void> _resendVerification() async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final result = await _authService.maybeSendVerificationEmail(
        widget.user,
        reason: 'manual_resend',
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = result.sent
            ? 'Verify your email to continue. We sent a verification email to ${widget.user.email ?? 'your address'}.'
            : 'Verify your email to continue. ${result.userMessage}';
      });
      AppErrorService.instance.showSnackBar(
        context,
        result.userMessage,
        backgroundColor: result.sent
            ? const Color(0xFF00C09E)
            : const Color(0xFF1E243A),
      );
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'verification',
        source: 'resend_verification',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        error is AuthFlowException
            ? error.userMessage
            : AppErrorService.instance.userMessageFor(
                error,
                fallback:
                    'Could not send another verification email right now.',
              ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _refreshVerification() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final verified = await _authService.refreshVerificationStatus(
        widget.user,
      );
      await AppAnalyticsService.instance.trackVerification(
        action: 'email_verification',
        status: verified ? 'confirmed' : 'pending',
      );
      if (!verified && mounted) {
        setState(() {
          _statusMessage =
              'Your email is still unverified. Open the email link, then retry.';
        });
        AppErrorService.instance.showSnackBar(
          context,
          'Your email is still unverified. Open the email link, then retry.',
          backgroundColor: const Color(0xFF1E243A),
        );
      }
    } catch (error, stackTrace) {
      await AppErrorService.instance.recordError(
        error,
        stackTrace,
        category: 'verification',
        source: 'refresh_verification',
      );
      if (!mounted) return;
      AppErrorService.instance.showSnackBar(
        context,
        error is AuthFlowException
            ? error.userMessage
            : AppErrorService.instance.userMessageFor(
                error,
                fallback: 'Could not refresh verification status.',
              ),
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    CommunityBackendService.instance.clearSessionCache();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E243A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    color: Color(0xFF00C09E),
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Verify your email to continue',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusMessage ??
                        'Seshly requires email verification before full-account features are unlocked.',
                    style: const TextStyle(color: Colors.white70, height: 1.45),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isRefreshing ? null : _refreshVerification,
                      child: _isRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0F142B),
                              ),
                            )
                          : const Text('I Verified My Email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isSending ? null : _resendVerification,
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Resend Verification Email'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('Use a different account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionLoadingView extends StatelessWidget {
  const _SessionLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: backgroundColor,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00C09E))),
    );
  }
}
