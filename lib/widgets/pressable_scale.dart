import 'package:flutter/material.dart';

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration duration;
  final BorderRadius? borderRadius;
  final Color? splashColor;
  final Color? highlightColor;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 110),
    this.borderRadius,
    this.splashColor,
    this.highlightColor,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final content = AnimatedScale(
      scale: _isPressed ? widget.pressedScale : 1.0,
      duration: widget.duration,
      child: widget.child,
    );

    if (widget.onTap == null && widget.onLongPress == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: widget.borderRadius,
        splashColor: widget.splashColor,
        highlightColor: widget.highlightColor,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: content,
      ),
    );
  }
}
