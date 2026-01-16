import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/services/sesh_focus_service.dart';

class SeshFocusDialog extends StatefulWidget {
  const SeshFocusDialog({super.key});

  @override
  State<SeshFocusDialog> createState() => _SeshFocusDialogState();
}

class _SeshFocusDialogState extends State<SeshFocusDialog> {
  final PageController _pageController = PageController();
  int? selectedMinutes;
  final TextEditingController _customController = TextEditingController();
  
  // 🔥 SESHLY THEME COLORS
  final Color tealAccent = const Color(0xFF00C09E);
  final Color cardColor = const Color(0xFF1E243A);
  final Color backgroundColor = const Color(0xFF0F142B);

  int freePasses = 5;
  bool _loadingPasses = true;

  @override
  void initState() {
    super.initState();
    _loadFreePasses();
  }

  // 🔥 Logic: Load/Initialize monthly free passes
  Future<void> _loadFreePasses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    
    // Check if it's a new month to reset passes to 5
    final lastReset = (data?['lastPassReset'] as Timestamp?)?.toDate();
    final now = DateTime.now();
    
    if (lastReset == null || lastReset.month != now.month || lastReset.year != now.year) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'freeFocusPasses': 5,
        'lastPassReset': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() { freePasses = 5; _loadingPasses = false; });
    } else {
      if (mounted) setState(() { freePasses = data?['freeFocusPasses'] ?? 0; _loadingPasses = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: tealAccent.withValues(alpha: 0.1))),
      child: SizedBox(
        height: 550,
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildWarningScreen(),
            _buildDurationScreen(),
          ],
        ),
      ),
    );
  }

  // --- SCREEN 1: WARNING ---
  Widget _buildWarningScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _dialogHeader("SeshFocus", Icons.bolt_rounded),
          const SizedBox(height: 15),
          Text(
            "Lock your phone to unlock your potential. Seshly will be the only app accessible.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: backgroundColor.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("PROTOCOL:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                _bulletPoint("System UI and other apps will be locked"),
                _bulletPoint("Sesh AI remains active for assistance"),
                _bulletPoint("5 Free Monthly emergency passkeys"),
                _bulletPoint("Excessive unlocking costs XP/Sesh Minutes"),
              ],
            ),
          ),
          const Spacer(),
          Text("Ready to reach peak focus?", style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _actionButton("Not Now", isOutlined: true, onTap: () => Navigator.pop(context))),
              const SizedBox(width: 12),
              Expanded(child: _actionButton("Continue", onTap: () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut))),
            ],
          ),
        ],
      ),
    );
  }

  // --- SCREEN 2: DURATION SELECTION ---
  Widget _buildDurationScreen() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _dialogHeader("Set Session", Icons.timer_outlined),
          const SizedBox(height: 10),
          const Text("Select your deep work duration", style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 25),
          
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [30, 60, 90, 120].map((mins) {
              bool isSelected = selectedMinutes == mins;
              return GestureDetector(
                onTap: () => setState(() {
                  selectedMinutes = mins;
                  _customController.clear();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? tealAccent : backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? tealAccent : Colors.white10),
                  ),
                  child: Text("$mins min", style: TextStyle(color: isSelected ? backgroundColor : Colors.white, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 25),
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            onChanged: (val) => setState(() => selectedMinutes = int.tryParse(val)),
            decoration: InputDecoration(
              hintText: "Custom minutes...",
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: backgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          
          // Passes Info
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: backgroundColor.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Free Monthly Passkeys:", style: TextStyle(color: Colors.white38)),
                _loadingPasses 
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text("$freePasses / 5", style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          const Spacer(),
          _actionButton("Initiate SeshFocus", 
            color: selectedMinutes != null ? tealAccent : Colors.white10,
            textColor: selectedMinutes != null ? backgroundColor : Colors.white24,
            onTap: selectedMinutes != null ? _startFocusSession : null
          ),
          const SizedBox(height: 10),
          _actionButton("Back", isOutlined: true, onTap: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)),
        ],
      ),
    );
  }

  void _startFocusSession() async {
  if (selectedMinutes == null) return;
  
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    Navigator.pop(context);
    return;
  }

  // Check if user has free passes
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  
  final data = doc.data();
  final currentPasses = data?['freeFocusPasses'] ?? 0;
  
  if (currentPasses > 0) {
    // User has free passes - use one and start session
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({
      'freeFocusPasses': FieldValue.increment(-1),
      'lastFocusSession': FieldValue.serverTimestamp(),
    });
    
    // Start the focus session
    SeshFocusService.start(durationMinutes: selectedMinutes!);
    
    // Show success message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: tealAccent,
          content: Text(
            "SeshFocus Initiated: $selectedMinutes Minutes",
            style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)
          ),
        ),
      );
    }
  } else {
    // No free passes - check XP or Sesh Minutes
    final userXP = data?['xp'] ?? 0;
    final seshMinutes = data?['seshMinutes'] ?? 0;
    const xpCost = 50; // Example XP cost for emergency unlock
    const minuteCost = 10; // Example Sesh Minutes cost
    
    if (userXP >= xpCost) {
      // Use XP to start session
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'xp': FieldValue.increment(-xpCost),
        'lastFocusSession': FieldValue.serverTimestamp(),
      });
      
      SeshFocusService.start(durationMinutes: selectedMinutes!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: tealAccent,
            content: Text(
              "Session started using $xpCost XP",
              style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)
            ),
          ),
        );
      }
    } else if (seshMinutes >= minuteCost) {
      // Use Sesh Minutes to start session
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'seshMinutes': FieldValue.increment(-minuteCost),
        'lastFocusSession': FieldValue.serverTimestamp(),
      });
      
      SeshFocusService.start(durationMinutes: selectedMinutes!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: tealAccent,
            content: Text(
              "Session started using $minuteCost Sesh Minutes",
              style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold)
            ),
          ),
        );
      }
    } else {
      // Not enough resources
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: const Text(
              "No free passes available. Need 50 XP or 10 Sesh Minutes",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
            ),
          ),
        );
      }
      return;
    }
  }
  
  // Log the focus session
  await FirebaseFirestore.instance
      .collection('focusSessions')
      .add({
    'userId': user.uid,
    'duration': selectedMinutes,
    'timestamp': FieldValue.serverTimestamp(),
    'usedPass': currentPasses > 0,
  });
  
  Navigator.pop(context);
}

  // --- HELPERS ---
  Widget _dialogHeader(String title, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 24),
        Row(children: [Icon(icon, color: tealAccent, size: 28), const SizedBox(width: 10), Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))]),
        GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: Colors.white38, size: 20)),
      ],
    );
  }

  Widget _actionButton(String label, {bool isOutlined = false, VoidCallback? onTap, Color? color, Color? textColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isOutlined ? Colors.transparent : (color ?? tealAccent),
          borderRadius: BorderRadius.circular(14),
          border: isOutlined ? Border.all(color: Colors.white10) : null,
        ),
        child: Center(child: Text(label, style: TextStyle(color: textColor ?? (isOutlined ? Colors.white : backgroundColor), fontWeight: FontWeight.bold, fontSize: 16))),
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("⚡ ", style: TextStyle(color: tealAccent, fontSize: 12)), 
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13)))
        ],
      ),
    );
  }
}