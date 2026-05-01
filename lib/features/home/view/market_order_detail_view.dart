import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/market_item_model.dart';
import 'package:seshly/widgets/responsive.dart';

class MarketOrderDetailView extends StatefulWidget {
  final String orderId;
  const MarketOrderDetailView({super.key, required this.orderId});

  @override
  State<MarketOrderDetailView> createState() => _MarketOrderDetailViewState();
}

class _MarketOrderDetailViewState extends State<MarketOrderDetailView> {
  bool _isUpdating = false;

  Future<void> _openFileUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack("Could not open file.");
    }
  }

  String _formatPrice(String currency, int price) {
    if (currency == 'ZAR' || currency == 'R') {
      return "R$price";
    }
    return "$currency $price";
  }

  Future<void> _markCompleted() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      await FirebaseFirestore.instance
          .collection('marketplace_orders')
          .doc(widget.orderId)
          .update({'status': 'completed'});
    } catch (_) {
      _showSnack("Could not update order.");
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);
    const Color cardColor = Color(0xFF1E243A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Order details", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('marketplace_orders').doc(widget.orderId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: tealAccent));
            }
            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text("Order not found", style: TextStyle(color: Colors.white54)));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final String status = (data['status'] ?? 'pending').toString();
            final String itemId = (data['itemId'] ?? '').toString();
            final String sellerId = (data['sellerId'] ?? '').toString();
            final String itemTitle = (data['itemTitle'] ?? "Item").toString();
            final String buyerName = (data['buyerName'] ?? "Student").toString();
            final String sellerName = (data['sellerName'] ?? "Student").toString();
            final int price = (data['price'] as num?)?.toInt() ?? 0;
            final String currency = (data['currency'] ?? 'ZAR').toString();
            final bool isSeller = FirebaseAuth.instance.currentUser?.uid == sellerId;
            final int? sellerPrice = (data['sellerPrice'] as num?)?.toInt();
            final int? platformFee = (data['platformFee'] as num?)?.toInt();
            final String listingType = (data['listingType'] ?? '').toString();
            final String itemCategory = (data['itemCategory'] ?? '').toString();
            final bool isNotesOrder = listingType == 'notes' || itemCategory.toLowerCase() == 'notes';
            final int sellerEarns = sellerPrice ?? (price - (platformFee ?? 0)).clamp(0, price).toInt();
            final int feeAmount = platformFee ?? (price - (sellerPrice ?? 0)).clamp(0, price).toInt();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(itemTitle, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(_formatPrice(currency, price), style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text("Seller: $sellerName", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      Text("Buyer: $buyerName", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text("Status:", style: TextStyle(color: Colors.white70)),
                          const SizedBox(width: 8),
                          Text(
                            status.toUpperCase(),
                            style: const TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (isNotesOrder)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Seshly notes delivery",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          "Seshly releases the notes after payment. Price includes a 10% fee.",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        if (sellerPrice != null || platformFee != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Seller earns ${_formatPrice(currency, sellerEarns)}",
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            "Seshly fee ${_formatPrice(currency, feeAmount)}",
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (isNotesOrder) const SizedBox(height: 16),
                if (itemId.isNotEmpty)
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('marketplace_items').doc(itemId).snapshots(),
                    builder: (context, itemSnap) {
                      if (!itemSnap.hasData || !itemSnap.data!.exists) {
                        return const SizedBox.shrink();
                      }
                      final item = MarketItem.fromDoc(itemSnap.data!);
                      final bool canDownload = item.isDigital &&
                          item.fileUrl != null &&
                          status == 'completed' &&
                          !isSeller;
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cardColor.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: item.imageUrl == null
                                      ? Icon(Icons.layers, color: Colors.white.withValues(alpha: 0.2))
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            item.imageUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Icon(
                                              Icons.layers,
                                              color: Colors.white.withValues(alpha: 0.2),
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text(item.category, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canDownload) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _openFileUrl(item.fileUrl!),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: tealAccent,
                                  foregroundColor: const Color(0xFF0F142B),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.download_for_offline_outlined),
                                label: const Text("Download notes"),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 20),
                if (isSeller && status == 'pending')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isUpdating ? null : _markCompleted,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: const Color(0xFF0F142B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_isUpdating ? "Updating..." : "Mark as completed"),
                    ),
                  )
                else if (!isSeller && status == 'pending')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text("Waiting for seller", style: TextStyle(color: Colors.white54)),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: tealAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text("Order completed", style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
