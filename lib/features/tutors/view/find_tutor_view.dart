import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/step_card.dart';
import '../view/recharge_view.dart'; // Import RechargeView

class FindTutorView extends StatefulWidget {
  final String? initialSubject;
  final String? questionText;
  final String? postId;

  const FindTutorView({
    super.key,
    this.initialSubject,
    this.questionText,
    this.postId,
  });

  @override
  State<FindTutorView> createState() => _FindTutorViewState();
}

class _FindTutorViewState extends State<FindTutorView> {
  String? selectedSubject;
  bool showOtherField = false;
  bool showResults = false;
  final TextEditingController _otherController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();
  final List<String> subjects = [
    "Mathematics", "Physics", "Chemistry", 
    "Programming", "Biology", "Statistics", "Other"
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSubject?.trim();
    if (initial != null && initial.isNotEmpty) {
      if (subjects.contains(initial)) {
        selectedSubject = initial;
      } else {
        showOtherField = true;
        selectedSubject = initial;
        _otherController.text = initial;
      }
    }
  }

  @override
  void dispose() {
    _otherController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Row(
                children: [
                  // Back button with pressing effect
                  PressableIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Find Tutor", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        Text("Instant matching like a ride", style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Recharge button with pressing effect - Updated to navigate to RechargeView
                  PressableTextButton(
                    text: "Recharge",
                    icon: Icons.bolt_outlined,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RechargeView()));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- Balance Card ---
              _buildBalanceCard(tealAccent),
              const SizedBox(height: 35),
              if ((widget.questionText ?? '').isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Question from your post",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.questionText!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Tutors will see the full question before accepting.",
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const Text("What subject do you need help with?", 
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
              const SizedBox(height: 15),

              // --- Subject Grid ---
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: subjects.map((sub) => _subjectChip(sub)).toList(),
              ),
              const SizedBox(height: 20),

              // --- Other Subject Input (Shows only when "Other" is selected) ---
              if (showOtherField)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tealAccent.withValues(alpha: 0.3)),
                    ),
                    child: TextField(
                      controller: _otherController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF00C09E), size: 20),
                        hintText: "Type your subject here...",
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                        border: InputBorder.none,
                        suffixIcon: PressableIconButton(
                          icon: Icons.clear,
                          size: 18,
                          color: Colors.white54,
                          onTap: () {
                            setState(() {
                              _otherController.clear();
                              selectedSubject = null;
                              showOtherField = false;
                            });
                          },
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          selectedSubject = value;
                        } else {
                          selectedSubject = null;
                        }
                        showResults = false;
                      },
                    ),
                  ),
                ),
              
              if (showOtherField) const SizedBox(height: 20),

              const Text("Topic or chapter (optional)",
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: _topicController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "e.g. Chain Rule, Normal Distribution",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- Find Button with pressing effect ---
              PressableElevatedButton(
                onPressed: selectedSubject != null ? () {
                  // Handle find tutor action
                  setState(() => showResults = true);
                } : null,
                icon: Icons.send_outlined,
                label: "Find Tutor Instantly",
              ),
              if (showResults) ...[
                const SizedBox(height: 30),
                const Text(
                  "Available tutors",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Serif'),
                ),
                const SizedBox(height: 12),
                _buildTutorResults(),
              ],
              const SizedBox(height: 40),

              const Text("How it works", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Serif')),
              const SizedBox(height: 20),
              
              // --- Steps ---
              const StepCard(number: "1", title: "Choose Your Subject", desc: "Tell us what you need help with"),
              const StepCard(number: "2", title: "Instant Match", desc: "We find an available tutor instantly"),
              const StepCard(number: "3", title: "Start Learning", desc: "Connect and start your session right away"),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(Color tealAccent) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildBalanceContent(tealAccent, '--', isGuest: true);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final int minutes = (data['seshMinutes'] as num?)?.toInt() ?? 0;
        return _buildBalanceContent(tealAccent, minutes.toString());
      },
    );
  }

  Widget _buildBalanceContent(Color tealAccent, String minutesText, {bool isGuest = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tealAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tealAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isGuest ? "Sign in to see balance" : "Your Sesh Minutes",
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                minutesText,
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Icon(Icons.bolt, color: tealAccent.withValues(alpha: 0.5), size: 40),
        ],
      ),
    );
  }

  Widget _subjectChip(String label) {
    bool isSelected = selectedSubject == label || (label == "Other" && showOtherField);
    
    return PressableChip(
      label: label,
      isSelected: isSelected,
      onTap: () {
        setState(() {
          if (label == "Other") {
            showOtherField = !showOtherField;
            if (showOtherField) {
              selectedSubject = null;
            } else {
              _otherController.clear();
            }
          } else {
            selectedSubject = label;
            showOtherField = false;
            _otherController.clear();
          }
          showResults = false;
        });
      },
    );
  }

  Widget _buildTutorResults() {
    const Color tealAccent = Color(0xFF00C09E);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final String subject = (selectedSubject ?? "").trim().toLowerCase();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('tutorStatus', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: tealAccent));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Unable to load tutors right now.",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final matches = docs.where((doc) {
          if (doc.id == currentUserId) return false;
          final data = doc.data() as Map<String, dynamic>;
          final bool isOnline = data['isOnline'] == true;
          final bool requestsEnabled = data['tutorRequestsEnabled'] == true;
          if (!isOnline && !requestsEnabled) return false;

          final tutorSubjects = _extractSubjects(data);
          if (subject.isEmpty) return true;
          return tutorSubjects.any((subj) => subj.toLowerCase() == subject);
        }).toList();

        if (matches.isEmpty) {
          return Text(
            "No tutors online for that subject yet.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          );
        }

        return Column(
          children: matches.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['fullName'] ?? data['displayName'] ?? "Tutor").toString();
            final tutorProfile = data['tutorProfile'] as Map<String, dynamic>? ?? {};
            final int displayRate = (tutorProfile['displayRate'] as num?)?.toInt() ?? 0;
            final String tutorType = (tutorProfile['tutorType'] ?? "Individual").toString();
            final String orgName = (tutorProfile['organizationName'] ?? "").toString();
            final List<String> tutorSubjects = _extractSubjects(data);
            final bool requestsEnabled = data['tutorRequestsEnabled'] == true;
            final bool isOnline = data['isOnline'] == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: tealAccent.withValues(alpha: 0.15),
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1) : "T",
                          style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              tutorSubjects.isNotEmpty ? tutorSubjects.join(", ") : "Subjects not set",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                            if (tutorType != "Individual" && orgName.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                "$tutorType: $orgName",
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            displayRate > 0 ? "R$displayRate/min" : "Rate N/A",
                            style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (requestsEnabled ? Colors.orangeAccent : Colors.green).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              requestsEnabled ? "Requests on" : "Online",
                              style: TextStyle(color: requestsEnabled ? Colors.orangeAccent : Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _createTutorRequest(doc.id, data),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: const Color(0xFF0F142B),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(isOnline ? "Request Tutor" : "Send Request"),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _createTutorRequest(String tutorId, Map<String, dynamic> tutorData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please sign in to request a tutor.")));
      return;
    }

    final String subject = (selectedSubject ?? "").trim();
    if (subject.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select a subject first.")));
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final studentName = (userData['fullName'] ?? userData['displayName'] ?? "Student").toString();
      final tutorName = (tutorData['fullName'] ?? tutorData['displayName'] ?? "Tutor").toString();
      final String topic = _topicController.text.trim();
      final String questionText = (widget.questionText ?? '').trim();
      final String snippet = questionText.length > 160 ? questionText.substring(0, 160) : questionText;

      await FirebaseFirestore.instance.collection('tutor_requests').add({
        'tutorId': tutorId,
        'tutorName': tutorName,
        'studentId': user.uid,
        'studentName': studentName,
        'subject': subject,
        'topic': topic,
        'questionText': questionText,
        'questionSnippet': snippet,
        'postId': widget.postId,
        'status': 'pending',
        'source': widget.postId != null ? 'post' : 'manual',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tutor request sent.")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not send request.")));
    }
  }

  List<String> _extractSubjects(Map<String, dynamic> data) {
    final List<String> subjects = [];
    final profile = data['tutorProfile'] as Map<String, dynamic>? ?? {};

    void addList(dynamic raw) {
      if (raw is List) {
        for (final value in raw) {
          final text = value.toString().trim();
          if (text.isNotEmpty && !subjects.contains(text)) {
            subjects.add(text);
          }
        }
      }
    }

    addList(data['tutorSubjects']);
    addList(profile['mainSubjects']);
    addList(profile['minorSubjects']);
    return subjects;
  }
}

/// A pressable icon button with scale animation
class PressableIconButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const PressableIconButton({
    super.key,
    required this.icon,
    this.size = 24,
    this.color = Colors.white,
    required this.onTap,
  });

  @override
  State<PressableIconButton> createState() => _PressableIconButtonState();
}

class _PressableIconButtonState extends State<PressableIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Icon(
          widget.icon,
          color: widget.color,
          size: widget.size,
        ),
      ),
    );
  }
}

/// A pressable text button with scale animation
class PressableTextButton extends StatefulWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onTap;

  const PressableTextButton({
    super.key,
    required this.text,
    this.icon,
    required this.onTap,
  });

  @override
  State<PressableTextButton> createState() => _PressableTextButtonState();
}

class _PressableTextButtonState extends State<PressableTextButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00C09E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.icon != null) Icon(widget.icon, color: const Color(0xFF0F142B), size: 16),
              if (widget.icon != null) const SizedBox(width: 4),
              Text(widget.text, style: const TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pressable elevated button with scale animation
class PressableElevatedButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const PressableElevatedButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<PressableElevatedButton> createState() => _PressableElevatedButtonState();
}

class _PressableElevatedButtonState extends State<PressableElevatedButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final double scale = _isPressed ? 0.98 : 1.0;
    final bool isDisabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: (_) {
        if (!isDisabled) setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        if (!isDisabled) setState(() => _isPressed = false);
      },
      onTapCancel: () {
        if (!isDisabled) setState(() => _isPressed = false);
      },
      onTap: !isDisabled ? widget.onPressed : null,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 18),
            label: Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDisabled ? Colors.white.withValues(alpha: 0.05) : tealAccent.withValues(alpha: 0.6),
              foregroundColor: Colors.white.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pressable chip with scale animation
class PressableChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const PressableChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<PressableChip> createState() => _PressableChipState();
}

class _PressableChipState extends State<PressableChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    final double scale = _isPressed ? 0.95 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected ? tealAccent : const Color(0xFF1E243A).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: widget.isSelected ? tealAccent : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected ? const Color(0xFF0F142B) : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
