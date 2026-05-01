import 'package:flutter/material.dart';

class SharedBoard extends StatelessWidget {
  const SharedBoard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.boardId,
    required this.modeLabel,
    required this.canAnnotate,
    required this.isLive,
    this.secondaryLabel,
    this.details = const <String>[],
  });

  final String title;
  final String subtitle;
  final String? boardId;
  final String modeLabel;
  final bool canAnnotate;
  final bool isLive;
  final String? secondaryLabel;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F7FB), Color(0xFFE8EEF7)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F142B),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF44506B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(isLive ? 'Live board' : 'Recovering', isLive),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _metaPill(modeLabel),
              _metaPill(boardId == null ? 'Board pending' : 'Board $boardId'),
              _metaPill(canAnnotate ? 'Tutor can write' : 'Read only'),
              if (secondaryLabel != null && secondaryLabel!.trim().isNotEmpty)
                _metaPill(secondaryLabel!),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD7DFEC)),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BoardGridPainter(),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          canAnnotate ? Icons.draw_rounded : Icons.visibility_rounded,
                          size: 72,
                          color: const Color(0xFFBAC4D6),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          boardId == null
                              ? 'Waiting for the authoritative board route'
                              : 'Board route is authoritative and synced.',
                          style: const TextStyle(
                            color: Color(0xFF53627F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...details.take(4).map(
                                (detail) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    detail,
                                    style: const TextStyle(
                                      color: Color(0xFF6A7690),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String label, bool live) {
    final color = live ? const Color(0xFF00C09E) : const Color(0xFFFFB703);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record_rounded, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _metaPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F142B).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF26324B),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _BoardGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE3E9F3)
      ..strokeWidth = 1;

    const gap = 28.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
