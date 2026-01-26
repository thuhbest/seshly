import 'package:flutter/material.dart';

class SeshLockDialog extends StatefulWidget {
  const SeshLockDialog({super.key});

  @override
  State<SeshLockDialog> createState() => _SeshLockDialogState();
}

class _SeshLockDialogState extends State<SeshLockDialog> {
  final PageController _pageController = PageController();
  String? selectedDuration;
  final TextEditingController _customController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        height: 520, // Fixed height to prevent jumping during transition
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _dialogHeader("SeshLock Warning", Icons.warning_amber_rounded),
          const SizedBox(height: 10),
          const Text(
            "This will lock your entire phone except Seshly\nfor the duration you set.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const SizedBox(height: 25),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Important:", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _bulletPoint("All other apps will be inaccessible"),
                _bulletPoint("You get 2 FREE unlock passes per week"),
                _bulletPoint("Additional unlocks cost Sesh Minutes"),
              ],
            ),
          ),
          const Spacer(),
          const Text("Ready to lock in and focus?", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _actionButton("Cancel", isOutlined: true, onTap: () => Navigator.pop(context))),
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
    const Color tealAccent = Color(0xFF00C09E);
    
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _dialogHeader("Set SeshLock Duration", Icons.lock_clock_outlined),
          const SizedBox(height: 10),
          const Text("How long do you want to stay focused?", style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 25),
          
          // Preset Duration Chips
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ["30 min", "60 min", "90 min", "120 min"].map((time) {
              bool isSelected = selectedDuration == time;
              return GestureDetector(
                onTap: () => setState(() => selectedDuration = time),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? tealAccent : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? tealAccent : Colors.grey.shade300),
                  ),
                  child: Text(time, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 25),
          const Align(alignment: Alignment.centerLeft, child: Text("Or set custom duration (minutes)", style: TextStyle(color: Colors.black54, fontSize: 13))),
          const SizedBox(height: 8),
          TextField(
            controller: _customController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: "Enter minutes...",
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          
          // Passes Info
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Free passes remaining:", style: TextStyle(color: Colors.black54)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(20)),
                  child: const Text("2 / 2", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                )
              ],
            ),
          ),
          
          const Spacer(),
          _actionButton("Activate SeshLock", 
            color: selectedDuration != null ? tealAccent : Colors.grey.shade200,
            textColor: selectedDuration != null ? Colors.white : Colors.grey.shade500,
            onTap: selectedDuration != null ? () => Navigator.pop(context) : null
          ),
          const SizedBox(height: 10),
          _actionButton("Cancel", isOutlined: true, onTap: () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)),
        ],
      ),
    );
  }

  // --- HELPERS ---
  Widget _dialogHeader(String title, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 24),
        Row(children: [Icon(icon, color: const Color(0xFF00C09E), size: 24), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
      ],
    );
  }

  Widget _actionButton(String label, {bool isOutlined = false, VoidCallback? onTap, Color? color, Color? textColor}) {
    if (isOutlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF00C09E),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: TextStyle(color: textColor ?? Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(children: [const Text("• ", style: TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold)), Expanded(child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13)))]),
    );
  }
}