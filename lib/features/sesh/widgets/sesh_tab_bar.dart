import 'package:flutter/material.dart';
import 'package:seshly/widgets/pressable_scale.dart';

class SeshTabBar extends StatelessWidget {
  final String selectedTab;
  final Function(String) onTabChanged;

  const SeshTabBar({
    super.key,
    required this.selectedTab,
    required this.onTabChanged,
  });

  static const List<_SeshTabItem> _tabs = [
    _SeshTabItem(label: "Sesh Help", icon: Icons.auto_awesome_rounded),
    _SeshTabItem(label: "Notes & Archive", icon: Icons.edit_note_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: _tabs.map((tab) {
          final isSelected = selectedTab == tab.label;
          return Expanded(
            child: PressableScale(
              onTap: () => onTabChanged(tab.label),
              borderRadius: BorderRadius.circular(14),
              pressedScale: 0.96,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [Color(0xFF172742), Color(0xFF1D2235)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isSelected
                      ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab.icon,
                      size: 17,
                      color: isSelected
                          ? const Color(0xFF85F5DD)
                          : Colors.white.withValues(alpha: 0.54),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        tab.label,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.54),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SeshTabItem {
  const _SeshTabItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
