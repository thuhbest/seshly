import 'package:flutter/material.dart';

import 'package:seshly/services/sesh_credit_service.dart';

class SeshCreditSummaryCard extends StatelessWidget {
  const SeshCreditSummaryCard({
    super.key,
    required this.balance,
    required this.title,
    required this.subtitle,
    required this.onBuy,
    this.footnote,
    this.accent = const Color(0xFF00C09E),
  });

  final int balance;
  final String title;
  final String subtitle;
  final String? footnote;
  final VoidCallback onBuy;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF112842),
            accent.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.bolt_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetricChip(
                  label: 'Balance',
                  value: '$balance credits',
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: _MetricChip(
                  label: 'Price',
                  value: 'R2 each',
                ),
              ),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 12),
            Text(
              footnote!,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11.5),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onBuy,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF0F142B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'Buy SeshCredit',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showSeshCreditPurchaseSheet({
  required BuildContext context,
  required int currentBalance,
  required Future<void> Function(SeshCreditBundle bundle) onPurchase,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E243A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      bool isProcessing = false;
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> handlePurchase(SeshCreditBundle bundle) async {
            if (isProcessing) return;
            setModalState(() => isProcessing = true);
            try {
              await onPurchase(bundle);
              if (sheetContext.mounted) Navigator.pop(sheetContext);
            } finally {
              if (sheetContext.mounted) {
                setModalState(() => isProcessing = false);
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top up SeshCredit',
                  style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Current balance: $currentBalance credits. Use credits for lecture capture and premium note workflows.',
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                ...SeshCreditService.bundles.map((bundle) {
                  final amount = bundle.amountZar.toStringAsFixed(0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PurchaseBundleCard(
                      bundle: bundle,
                      amountLabel: 'R$amount',
                      busy: isProcessing,
                      onTap: () => handlePurchase(bundle),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );
    },
  );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _PurchaseBundleCard extends StatelessWidget {
  const _PurchaseBundleCard({
    required this.bundle,
    required this.amountLabel,
    required this.busy,
    required this.onTap,
  });

  final SeshCreditBundle bundle;
  final String amountLabel;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color accent = Color(0xFF00C09E);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: bundle.popular ? accent : Colors.white.withValues(alpha: 0.06),
          width: bundle.popular ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${bundle.credits} credits',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (bundle.popular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Popular',
                          style: TextStyle(color: accent, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'R2 per credit. Perfect for lecture capture unlocks.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ElevatedButton(
            onPressed: busy ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF0F142B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F142B)),
                  )
                : Text(amountLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
