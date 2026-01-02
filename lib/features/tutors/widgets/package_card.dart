import 'package:flutter/material.dart';

class PackageCard extends StatelessWidget {
  final String minutes;
  final String price;
  final String rateInfo;
  final String? saveAmount;
  final bool isPopular;
  final VoidCallback onBuy;

  const PackageCard({
    super.key,
    required this.minutes,
    required this.price,
    required this.rateInfo,
    this.saveAmount,
    this.isPopular = false,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardBg = Color(0xFF1E243A);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isPopular ? tealAccent : Colors.white.withValues(alpha: 0.05),
              width: isPopular ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bolt, color: tealAccent, size: 24),
                      const SizedBox(width: 8),
                      Text("$minutes Minutes", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(price, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(rateInfo, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  )
                ],
              ),
              if (saveAmount != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text("Save $saveAmount", style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onBuy,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPopular ? tealAccent : Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text("Buy Now", style: TextStyle(color: isPopular ? const Color(0xFF0F142B) : Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
        if (isPopular)
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: tealAccent, borderRadius: BorderRadius.circular(20)),
                child: const Text("Most Popular", style: TextStyle(color: Color(0xFF0F142B), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
      ],
    );
  }
}