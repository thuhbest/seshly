import 'package:flutter/material.dart';

class VaultCard extends StatelessWidget {
  final String title;
  final String courseCode;
  final String subject;
  final String author;
  final String date;
  final String rating;
  final String downloads;

  const VaultCard({
    super.key,
    required this.title,
    required this.courseCode,
    required this.subject,
    required this.author,
    required this.date,
    required this.rating,
    required this.downloads,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Color(0xFF00C09E),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _tag(courseCode, const Color(0xFF1E243A)),
                        const SizedBox(width: 8),
                        _tag(
                          subject,
                          const Color(0xFF1E243A),
                          textColor: const Color(0xFF5D5FEF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check, color: Colors.green, size: 12),
                    SizedBox(width: 4),
                    Text(
                      "Verified",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statLabel("First Year"),
              _dot(),
              _statLabel("2.4 MB"),
              _dot(),
              _statLabel("Past Paper"),
            ],
          ),
          const Divider(color: Colors.white10, height: 25),
          Row(
            children: [
              const Icon(Icons.star, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Text(
                rating,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                " (45)",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.download_outlined, color: Colors.white54, size: 16),
              const SizedBox(width: 4),
              Text(
                downloads,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 16),
              const SizedBox(width: 4),
              const Text(
                "12",
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "by $author • $date",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _tag(String label, Color bg, {Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static Widget _statLabel(String text) =>
      Text(text, style: const TextStyle(color: Colors.white54, fontSize: 11));

  static Widget _dot() =>
      const Text("•", style: TextStyle(color: Colors.white24));
}
