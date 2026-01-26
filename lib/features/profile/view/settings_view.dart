import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:seshly/services/notification_service.dart';
import '../widgets/settings_group.dart';
import 'edit_profile_view.dart';
import 'package:seshly/widgets/responsive.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool pushNotify = true;
  bool emailNotify = false;
  bool studyReminders = true;
  bool _loadingPrefs = true;
  final Color tealAccent = const Color(0xFF00C09E);
  final Color logoutColor = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final NotificationService _notificationService = NotificationService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadNotificationPrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const _SectionHeader(title: "Notifications"),
              SettingsGroup(
                children: [
                  _SwitchTile(
                    title: "Push Notifications",
                    subtitle: "Receive notifications on your device",
                    value: pushNotify,
                    onChanged: _loadingPrefs ? null : (val) => _updateNotificationPref('push', val),
                  ),
                  _SwitchTile(
                    title: "Email Notifications",
                    subtitle: "Get updates via email",
                    value: emailNotify,
                    onChanged: _loadingPrefs ? null : (val) => _updateNotificationPref('email', val),
                  ),
                  _SwitchTile(
                    title: "Study Reminders",
                    subtitle: "Reminders for classes and assignments",
                    value: studyReminders,
                    onChanged: _loadingPrefs ? null : (val) => _updateNotificationPref('studyReminders', val),
                  ),
                ],
              ),
              const _SectionHeader(title: "Account"),
              SettingsGroup(
                children: [
                  // 🔥 TACTILE EDIT PROFILE BUTTON
                  _LinkTile(
                    icon: Icons.person_outline, 
                    title: "Edit Profile", 
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileView()))
                  ),
                  // 🔥 TACTILE PRIVACY BUTTON
                  _LinkTile(
                    icon: Icons.lock_outline, 
                    title: "Privacy & Security", 
                    onTap: () => _showPrivacyPolicy(context)
                  ),
                ],
              ),
              const SizedBox(height: 35),
              // 🔥 FIXED LOGOUT BUTTON: High visibility solid colors
              _BuildTactileButton(
                onTap: () async {
                  final nav = Navigator.of(context);
                  await FirebaseAuth.instance.signOut();
                  if (mounted) nav.pop();
                },
                color: logoutColor,
                label: "Log Out",
                icon: Icons.logout_rounded,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadNotificationPrefs() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingPrefs = false);
      return;
    }

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final prefs = data['notificationPrefs'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          pushNotify = prefs['push'] ?? pushNotify;
          emailNotify = prefs['email'] ?? emailNotify;
          studyReminders = prefs['studyReminders'] ?? studyReminders;
          _loadingPrefs = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPrefs = false);
      }
    }
  }

  bool _prefForKey(String key) {
    switch (key) {
      case 'push':
        return pushNotify;
      case 'email':
        return emailNotify;
      case 'studyReminders':
        return studyReminders;
      default:
        return false;
    }
  }

  void _applyPref(String key, bool value) {
    switch (key) {
      case 'push':
        pushNotify = value;
        break;
      case 'email':
        emailNotify = value;
        break;
      case 'studyReminders':
        studyReminders = value;
        break;
    }
  }

  Future<void> _updateNotificationPref(String key, bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final previous = _prefForKey(key);
    setState(() => _applyPref(key, value));

    try {
      await _db.collection('users').doc(user.uid).set({
        'notificationPrefs': {key: value},
      }, SetOptions(merge: true));

      if (key == 'push') {
        if (value) {
          await _notificationService.initForUser(user);
        } else {
          await _notificationService.disableForUser(user);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _applyPref(key, previous));
        _showSnack("Could not update notification settings.");
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showPrivacyPolicy(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        iconTheme: const IconThemeData(color: Colors.white), 
        title: const Text("Privacy & Security", style: TextStyle(color: Colors.white))
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                  children: [
                    const TextSpan(text: "Seshly — ", style: TextStyle(color: Colors.white)),
                    TextSpan(text: "Ai as your teacher not your academic slave.", style: TextStyle(color: tealAccent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            _policySection("1. About Us", "Seshly is an education-focused digital platform developed and operated by AutoXyrium, a technology company dedicated to transforming complexity into accessibility. Seshly is designed to connect students across campuses, enable academic collaboration, facilitate tutoring services, and provide AI-assisted learning tools that enhance understanding and productivity.\nOur mission is to make education more accessible, affordable, and effective while maintaining the highest standards of privacy, security, and data integrity.\nThis Privacy & Security Policy explains how we collect, use, store, protect, and disclose information when you use Seshly’s mobile applications, web services, features, and related technologies (collectively, the “Services”).\nBy accessing or using Seshly, you agree to the practices described in this Policy."),
            _policySection("2. Scope of This Policy", "This Policy applies to:\n• Students, tutors, mentors, and all registered users of Seshly\n• Visitors to Seshly’s website or applications\n• All data processed through Seshly’s systems, whether collected directly or generated through usage\nThis Policy should be read together with Seshly’s Terms of Service."),
            _policySection("3. Information We Collect", "3.1 Information You Provide Directly\nFull name or display name, student number or institutional identifier, email address, profile information, messages, posts, and shared academic content.\n\n3.2 Automatically Collected Information\nDevice type, operating system, log data (IP address), usage analytics, and diagnostic data.\n\n3.3 Payment and Transaction Data\nTransaction identifiers and status. Seshly does not store full card numbers."),
            _policySection("4. How We Use Your Information", "To manage accounts, provide academic collaboration, tutoring, and AI-assisted features, personalize learning experiences, and monitor misuse. We do not sell user data."),
            _policySection("5. AI and Educational Content", "User-submitted content may be processed by AI systems to generate learning aids. AI systems are designed to minimize data retention beyond what is required."),
            _policySection("6. Data Storage and Retention", "User data is stored securely. We retain personal data only for as long as necessary. Upon account deletion, personal data is removed or anonymized."),
            _policySection("7. Data Sharing", "We share limited data with trusted service providers and if required by legal obligations to comply with laws or protect users."),
            _policySection("8. Security Measures", "We implement encrypted transmission (HTTPS), secure cloud infrastructure, and firewalls to protect your data."),
            _policySection("9. User Responsibilities", "Users are responsible for keeping login credentials confidential and ensuring information accuracy."),
            _policySection("10. Children and Minors", "Parental consent is required where applicable by law. We do not knowingly collect data from children in violation of laws."),
            _policySection("11. International Data", "Information may be stored outside your residence country with appropriate safeguards in place."),
            _policySection("12. Your Rights", "Access, correct, or request deletion of your data via support."),
            _policySection("13. Policy Updates", "Updates will be posted in-app; continued use constitutes acceptance."),
            _policySection("14. Contact", "autoxyrium@gmail.com\nCompany: AutoXyrium\nProduct: Seshly"),
            
            const SizedBox(height: 40),
            const Divider(color: Colors.white12),
            const SizedBox(height: 20),
            
            _BuildDangerButton(
              label: "Disable Account",
              subtitle: "Temporary. Your profile is hidden. Logging back in re-enables it instantly.",
              onTap: () => _confirmAction("Disable", "Your profile will be hidden from everyone until you log back in.", true),
            ),
            const SizedBox(height: 15),
            _BuildDangerButton(
              label: "Delete Account",
              subtitle: "Permanent. XP, documents, and academic progress will be lost forever in real-time.",
              isDelete: true,
              onTap: () => _confirmAction("Delete", "This is irreversible. Your account will be deleted from our systems immediately.", false),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    )));
  }

  Widget _policySection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: tealAccent, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.6)),
        ],
      ),
    );
  }

  void _confirmAction(String action, String warning, bool isDisable) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E243A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text("$action Account?", style: const TextStyle(color: Colors.white)),
      content: Text(warning, style: const TextStyle(color: Colors.white70)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: isDisable ? Colors.orangeAccent : Colors.redAccent),
          onPressed: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            
            if (isDisable) {
              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'status': 'disabled'});
              await FirebaseAuth.instance.signOut();
            } else {
              await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
              await user.delete();
            }
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
          child: Text("Confirm $action", style: const TextStyle(fontWeight: FontWeight.bold)),
        )
      ],
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 12),
      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchTile({required this.title, this.subtitle, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
      subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: Colors.white.withValues(alpha: 128), fontSize: 13)) : null,
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: const Color(0xFF00C09E), activeTrackColor: const Color(0xFF00C09E).withValues(alpha: 25)),
    );
  }
}

// 🔥 UPGRADED LINK TILE WITH TACTILE MOTION
class _LinkTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _LinkTile({required this.icon, required this.title, required this.onTap});

  @override
  State<_LinkTile> createState() => _LinkTileState();
}

class _LinkTileState extends State<_LinkTile> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15),
          leading: Icon(widget.icon, color: const Color(0xFF00C09E), size: 22),
          title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
        ),
      ),
    );
  }
}

class _BuildTactileButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color color;
  final String label;
  final IconData icon;
  const _BuildTactileButton({required this.onTap, required this.color, required this.label, required this.icon});
  @override
  State<_BuildTactileButton> createState() => _BuildTactileButtonState();
}

class _BuildTactileButtonState extends State<_BuildTactileButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    const Color foreground = Color(0xFF0F142B);
    final Color fillColor = _isPressed ? widget.color.withValues(alpha: 220) : widget.color;
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: widget.color.withValues(alpha: 120)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 60),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, 
            children: [
              Icon(widget.icon, color: foreground), 
              const SizedBox(width: 10), 
              Text(widget.label, style: const TextStyle(color: foreground, fontWeight: FontWeight.bold, fontSize: 16))
            ]
          ),
        ),
      ),
    );
  }
}

class _BuildDangerButton extends StatelessWidget {
  final String label, subtitle;
  final bool isDelete;
  final VoidCallback onTap;
  const _BuildDangerButton({required this.label, required this.subtitle, this.isDelete = false, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: isDelete ? Colors.redAccent : Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ]),
      ),
    );
  }
}


