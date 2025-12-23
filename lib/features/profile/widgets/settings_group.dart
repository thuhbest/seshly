import 'package:flutter/material.dart';

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A), // Removed .withValues(alpha: 0.5)
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x0DFFFFFF)), // Equivalent to Colors.white.withOpacity(0.05)
      ),
      child: Column(children: children),
    );
  }
}

// Remove the duplicate _SwitchTile and _LinkTile definitions here
// They should only be defined in your main settings_view.dart file