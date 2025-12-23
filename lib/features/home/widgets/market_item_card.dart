import 'package:flutter/material.dart';

class MarketItemCard extends StatelessWidget {
  final String title;
  final String price;
  final String author;
  final String category;
  final bool isDigital;

  const MarketItemCard({
    super.key,
    required this.title,
    required this.price,
    required this.author,
    required this.category,
    this.isDigital = false,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Stack(
        children: [
          // Digital Tag
          if (isDigital)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: tealAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "Digital",
                  style: TextStyle(
                    color: tealAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                // Placeholder for Item Image/Icon
                Center(
                  child: Icon(
                    Icons.layers,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: 60,
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        color: tealAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      author,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  category,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}