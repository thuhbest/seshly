import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/settings_group.dart';
import '../widgets/tutor_banner.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool pushNotify = true;
  bool emailNotify = false;
  bool studyReminders = true;

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color errorRed = Color(0xFFFF5252);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              
              // --- Notifications Section ---
              const _SectionHeader(title: "Notifications"),
              SettingsGroup(
                children: [
                  _SwitchTile(
                    title: "Push Notifications",
                    subtitle: "Receive notifications on your device",
                    value: pushNotify,
                    onChanged: (val) => setState(() => pushNotify = val),
                  ),
                  _SwitchTile(
                    title: "Email Notifications",
                    subtitle: "Get updates via email",
                    value: emailNotify,
                    onChanged: (val) => setState(() => emailNotify = val),
                  ),
                  _SwitchTile(
                    title: "Study Reminders",
                    subtitle: "Reminders for classes and assignments",
                    value: studyReminders,
                    onChanged: (val) => setState(() => studyReminders = val),
                  ),
                ],
              ),

              const SizedBox(height: 25),
              
              // --- Tutor Banner ---
              const TutorBanner(),

              const SizedBox(height: 25),

              // --- Account Section ---
              const _SectionHeader(title: "Account"),
              SettingsGroup(
                children: [
                  _LinkTile(icon: Icons.person_outline, title: "Edit Profile", onTap: () {}),
                  _LinkTile(icon: Icons.lock_outline, title: "Privacy & Security", onTap: () {}),
                ],
              ),

              const SizedBox(height: 25),

              // --- Preferences Section ---
              const _SectionHeader(title: "Preferences"),
              SettingsGroup(
                children: [
                  _LinkTile(icon: Icons.language, title: "Language", trailingText: "English", onTap: () {}),
                  _LinkTile(icon: Icons.notifications_none, title: "Notification Settings", onTap: () {}),
                ],
              ),
              
              const SizedBox(height: 35),

              // --- Logout Button ---
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    // Store context in local variable to check mounted properly
                    final currentContext = context;
                    await FirebaseAuth.instance.signOut();
                    // Check mounted on the current widget state, not the context
                    if (mounted) {
                      Navigator.of(currentContext).pop();
                    }
                  },
                  icon: const Icon(Icons.logout, color: errorRed),
                  label: const Text(
                    "Log Out",
                    style: TextStyle(color: errorRed, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: errorRed.withValues(alpha: 25), // 0.1 * 255 = 25
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  // KEEP the icon parameter but remove from constructor calls if not needed
  final IconData? icon;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon, // Keep the parameter but it's optional
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      leading: icon != null 
          ? Icon(icon, color: const Color(0xFF00C09E), size: 22)
          : null,
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: Colors.white.withValues(alpha: 128), fontSize: 13), // 0.5 * 255 = 128
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        // FIX: Replace deprecated 'activeColor' with 'activeThumbColor'
        activeThumbColor: const Color(0xFF00C09E),
        activeTrackColor: const Color(0xFF00C09E).withValues(alpha: 25), // 0.1 * 255 = 25
        // Keep other switch properties
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  const _LinkTile({
    required this.icon,
    required this.title,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      leading: Icon(icon, color: const Color(0xFF00C09E), size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(
              trailingText!,
              style: TextStyle(color: Colors.white.withValues(alpha: 128), fontSize: 14), // 0.5 * 255 = 128
            ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 128), size: 20), // 0.5 * 255 = 128
        ],
      ),
      onTap: onTap,
    );
  }
}