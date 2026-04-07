import 'package:flutter/material.dart';
import 'package:seshly/services/sesh_focus_service.dart';
import 'package:seshly/services/secure_entitlements_service.dart';
import 'package:seshly/widgets/pressable_scale.dart';

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
  final SecureEntitlementsService _secureEntitlements =
      SecureEntitlementsService();

  int freePasses = 5;
  bool _loadingPasses = true;

  @override
  void initState() {
    super.initState();
    _loadFreePasses();
  }

  // 🔥 Logic: Load/Initialize monthly free passes
  Future<void> _loadFreePasses() async {
    try {
      final status = await _secureEntitlements.fetchSeshFocusStatus();
      if (mounted) {
        setState(() {
          freePasses = status.freeFocusPasses;
          _loadingPasses = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPasses = false);
      }
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

  Widget _dialogHeader(String title, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tealAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: tealAccent.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: tealAccent, size: 20),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    String label, {
    VoidCallback? onTap,
    bool isOutlined = false,
    Color? color,
    Color? textColor,
  }) {
    final Color background = color ?? (isOutlined ? Colors.transparent : tealAccent);
    final Color foreground = textColor ?? (isOutlined ? tealAccent : backgroundColor);
    final BorderSide border = BorderSide(color: isOutlined ? tealAccent : Colors.transparent);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.fromBorderSide(border),
          ),
          child: Text(
            label,
            style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
          ),
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
              return PressableScale(
                onTap: () => setState(() {
                  selectedMinutes = mins;
                  _customController.clear();
                }),
                borderRadius: BorderRadius.circular(12),
                pressedScale: 0.96,
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
  String resourceUsed = "Free Pass";
  try {
    final result = await _secureEntitlements.consumeSeshFocusAccess(
      durationMinutes: selectedMinutes!,
    );
    resourceUsed = result.resourceUsed;
    if (mounted) {
      setState(() => freePasses = result.freeFocusPasses);
    }
  } catch (error) {
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            error.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    return;
  }

  // Start focus service (pins on Android via method channel)
  try {
    await SeshFocusService.start(selectedMinutes!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: tealAccent,
          content: Text(
            "🔒 SeshFocus Locked ($selectedMinutes min) - Used: $resourceUsed",
            style: TextStyle(
              color: backgroundColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange,
          content: Text(
            "SeshFocus Started ($selectedMinutes min) - Manual lock recommended",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
  }

  if (!mounted) return;

  // Close dialog
  Navigator.pop(context);

  // 🚨 REQUIRED FIX — FORCE BLOCKING SCREEN
  Navigator.of(context).pushNamedAndRemoveUntil(
    '/seshFocusActive',
    (_) => false,
  );
}
}
