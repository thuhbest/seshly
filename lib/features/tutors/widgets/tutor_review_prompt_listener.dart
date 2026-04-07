import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:seshly/services/tutor_review_service.dart';
import 'package:seshly/theme/seshly_theme.dart';

class TutorReviewPromptListener extends StatefulWidget {
  const TutorReviewPromptListener({super.key});

  @override
  State<TutorReviewPromptListener> createState() =>
      _TutorReviewPromptListenerState();
}

class _TutorReviewPromptListenerState extends State<TutorReviewPromptListener> {
  final TutorReviewService _reviewService = TutorReviewService();
  StreamSubscription<List<PendingTutorReview>>? _subscription;
  String? _activeIntentId;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _bind() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    _subscription = _reviewService.pendingReviewsForStudent(user.uid).listen((
      pending,
    ) {
      if (!mounted || _showing || pending.isEmpty) return;
      final next = pending.first;
      if (_activeIntentId == next.paymentIntentId) return;
      _activeIntentId = next.paymentIntentId;
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openPrompt(next);
        _showing = false;
      });
    });
  }

  Future<void> _openPrompt(PendingTutorReview pending) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ratingController = ValueNotifier<double>(8);
    final noteController = TextEditingController();

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return Container(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: SeshlyPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: ValueListenableBuilder<double>(
              valueListenable: ratingController,
              builder: (context, rating, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Rate Your Tutor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your session with ${pending.tutorName} has settled. Rate the experience out of 10 so Seshly can keep tutor quality trustworthy.',
                      style: const TextStyle(
                        color: Colors.white60,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SeshlyPalette.surfaceRaised.withValues(
                          alpha: 0.75,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pending.topic.isEmpty
                                ? pending.subject
                                : '${pending.subject} • ${pending.topic}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${pending.billableMinutes} min session${pending.qualifiesForGoldTick ? ' • counts toward Gold Tick quality' : ' • too short for Gold Tick quality'}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '${rating.toStringAsFixed(1)}/10',
                      style: const TextStyle(
                        color: SeshlyPalette.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                      ),
                    ),
                    Slider(
                      value: rating,
                      min: 1,
                      max: 10,
                      divisions: 18,
                      activeColor: SeshlyPalette.gold,
                      inactiveColor: Colors.white12,
                      label: rating.toStringAsFixed(1),
                      onChanged: (value) => ratingController.value = value,
                    ),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Optional note',
                        hintText: 'What stood out in the session?',
                        filled: true,
                        fillColor: SeshlyPalette.surfaceRaised.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('Later'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              try {
                                await _reviewService.submitReview(
                                  user: user,
                                  pending: pending,
                                  ratingOutOf10: ratingController.value,
                                  note: noteController.text,
                                );
                                if (!sheetContext.mounted) return;
                                Navigator.pop(sheetContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Tutor rating submitted.'),
                                  ),
                                );
                              } on TutorReviewException catch (error) {
                                if (!sheetContext.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(error.message)),
                                );
                              }
                            },
                            child: const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    } finally {
      ratingController.dispose();
      noteController.dispose();
      if (_activeIntentId == pending.paymentIntentId) {
        _activeIntentId = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
