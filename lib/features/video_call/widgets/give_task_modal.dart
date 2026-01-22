import 'package:flutter/material.dart';

class GiveTaskModal extends StatefulWidget {
  const GiveTaskModal({super.key});

  @override
  State<GiveTaskModal> createState() => _GiveTaskModalState();
}

class _GiveTaskModalState extends State<GiveTaskModal> {
  final TextEditingController _taskController = TextEditingController();
  final TextEditingController _timerController = TextEditingController(text: "10");
  
  bool _allowSeshAI = true;
  String _selectedFormat = "Show full working";
  
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  final List<String> _formats = [
    "Show final answer",
    "Show full working",
    "Explain in words"
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 25),
            
            _buildLabel("Task Description"),
            _buildTextField(
              controller: _taskController,
              hint: "Enter the problem or instructions here...",
              maxLines: 4,
            ),
            
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("Timer (min)"),
                      _buildTextField(
                        controller: _timerController,
                        hint: "10",
                        isNumber: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("Format"),
                      _buildDropdown(),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 25),
            _buildOptionToggle(
              title: "Allow Sesh AI assistance",
              subtitle: "Students can ask Sesh for hints during work",
              value: _allowSeshAI,
              onChanged: (val) => setState(() => _allowSeshAI = val),
            ),
            
            const SizedBox(height: 35),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Assign Task",
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        text,
        style: TextStyle(color: tealAccent.withValues(alpha: 200), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, int maxLines = 1, bool isNumber = false}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(15)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFormat,
          dropdownColor: cardColor,
          icon: Icon(Icons.keyboard_arrow_down, color: tealAccent),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          isExpanded: true,
          items: _formats.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
          onChanged: (val) => setState(() => _selectedFormat = val!),
        ),
      ),
    );
  }

  Widget _buildOptionToggle({required String title, required String subtitle, required bool value, required Function(bool) onChanged}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 128),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: tealAccent,
            activeTrackColor: tealAccent.withValues(alpha: 50),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return _TactileButton(
      onTap: () {
        // Logic to transition session to Practice Mode
        Navigator.pop(context);
        debugPrint("Starting Practice: ${_taskController.text}");
      },
      color: tealAccent,
      child: Center(
        child: Text(
          "Start Practice Phase",
          style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

class _TactileButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color color;

  const _TactileButton({required this.child, required this.onTap, required this.color});

  @override
  State<_TactileButton> createState() => _TactileButtonState();
}

class _TactileButtonState extends State<_TactileButton> {
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
        child: Container(
          width: double.infinity,
          height: 55,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 76),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}