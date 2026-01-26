import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/market_item_model.dart';
import 'market_order_detail_view.dart';
import 'package:seshly/widgets/responsive.dart';

class MarketItemDetailView extends StatefulWidget {
  final String itemId;
  const MarketItemDetailView({super.key, required this.itemId});

  @override
  State<MarketItemDetailView> createState() => _MarketItemDetailViewState();
}

class _MarketItemDetailViewState extends State<MarketItemDetailView> {
  bool _isOrdering = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _ordersKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createOrder(MarketItem item) async {
    if (_isOrdering) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("Please sign in to place an order.");
      return;
    }
    if (user.uid == item.sellerId) {
      _showSnack("You cannot order your own item.");
      return;
    }
    if (item.status != 'active') {
      _showSnack("This item is no longer available.");
      return;
    }

    setState(() => _isOrdering = true);
    try {
      final existing = await FirebaseFirestore.instance
          .collection('marketplace_orders')
          .where('itemId', isEqualTo: item.id)
          .where('buyerId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final orderId = existing.docs.first.id;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MarketOrderDetailView(orderId: orderId)),
          );
        }
        return;
      }

      final buyerDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final buyerName = (buyerDoc.data()?['fullName'] ?? buyerDoc.data()?['displayName'] ?? "Student").toString();

      final orderRef = await FirebaseFirestore.instance.collection('marketplace_orders').add({
        'itemId': item.id,
        'sellerId': item.sellerId,
        'sellerName': item.sellerName,
        'buyerId': user.uid,
        'buyerName': buyerName,
        'itemTitle': item.title,
        'price': item.price,
        'currency': item.currency,
        'sellerPrice': item.sellerPrice,
        'platformFee': item.platformFee,
        'priceIncludesFee': item.priceIncludesFee,
        'listingType': item.listingType,
        'fulfillment': item.fulfillment,
        'itemCategory': item.category,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MarketOrderDetailView(orderId: orderRef.id)),
        );
      }
    } catch (_) {
      _showSnack("Could not place order.");
    } finally {
      if (mounted) setState(() => _isOrdering = false);
    }
  }

  Future<void> _markOrderComplete(String orderId) async {
    try {
      await FirebaseFirestore.instance
          .collection('marketplace_orders')
          .doc(orderId)
          .update({'status': 'completed'});
    } catch (_) {
      _showSnack("Could not update order.");
    }
  }

  String _formatPrice(String currency, int amount) {
    if (currency == 'ZAR' || currency == 'R') {
      return "R$amount";
    }
    return "$currency $amount";
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToOrders() {
    final target = _ordersKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color cardColor = Color(0xFF1E243A);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Item details", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ResponsiveCenter(
        padding: EdgeInsets.zero,
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('marketplace_items').doc(widget.itemId).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: tealAccent));
            }
            if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
              return const Center(child: Text("Item not found", style: TextStyle(color: Colors.white54)));
            }

            final item = MarketItem.fromDoc(snapshot.data!);
            final userId = FirebaseAuth.instance.currentUser?.uid;
            final bool isSeller = userId != null && userId == item.sellerId;
            final bool isSold = item.status == 'sold';
            final bool isNotes = item.isNotesListing;
            final int? sellerPrice = item.sellerPrice;
            final int? platformFee = item.platformFee;
            final int sellerEarns = sellerPrice ?? (item.price - (platformFee ?? 0)).clamp(0, item.price).toInt();
            final int feeAmount = platformFee ?? (item.price - (sellerPrice ?? 0)).clamp(0, item.price).toInt();

            return SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: item.imageUrl == null
                      ? Icon(Icons.layers, color: Colors.white.withValues(alpha: 0.2), size: 70)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            item.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.layers,
                              color: Colors.white.withValues(alpha: 0.2),
                              size: 70,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                Text(item.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(item.priceLabel, style: const TextStyle(color: tealAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(item.category, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    if (item.isDigital)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text("Digital", style: TextStyle(color: tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text("Seller: ${item.sellerName}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 12),
                if (item.description.isNotEmpty)
                  Text(item.description, style: const TextStyle(color: Colors.white70, height: 1.5)),
                const SizedBox(height: 20),
                if (isNotes)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
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
                          "We store the notes and release them after payment. Price includes a 10% Seshly fee.",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        if (sellerPrice != null || platformFee != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Seller earns ${_formatPrice(item.currency, sellerEarns)}",
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            "Seshly fee ${_formatPrice(item.currency, feeAmount)}",
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (isNotes) const SizedBox(height: 16),
                if (isSold)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text("Sold", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  )
                else if (!isSeller)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isOrdering ? null : () => _createOrder(item),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tealAccent,
                        foregroundColor: const Color(0xFF0F142B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(_isOrdering ? "Placing order..." : "Place Order"),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: _scrollToOrders,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: const Center(
                        child: Text("Your listing - View orders", style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                if (userId != null)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('marketplace_orders')
                        .where('itemId', isEqualTo: item.id)
                        .snapshots(),
                    builder: (context, orderSnap) {
                      if (!orderSnap.hasData) {
                        return const SizedBox.shrink();
                      }

                      final docs = orderSnap.data!.docs;
                      if (docs.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final orders = docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
                      final relevantOrders = orders.where((order) {
                        if (isSeller) return true;
                        return order['buyerId'] == userId;
                      }).toList();

                      if (relevantOrders.isEmpty) return const SizedBox.shrink();

                      return Column(
                        key: _ordersKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isSeller ? "Orders" : "Your order",
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          ...docs.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            if (isSeller) return true;
                            return data['buyerId'] == userId;
                          }).map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final status = (data['status'] ?? 'pending').toString();
                            final buyerName = (data['buyerName'] ?? "Student").toString();
                            final bool canComplete = isSeller && status == 'pending';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardColor.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isSeller ? "Buyer: $buyerName" : "Status: $status",
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      Text(
                                        status.toUpperCase(),
                                        style: const TextStyle(color: tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => MarketOrderDetailView(orderId: doc.id),
                                          ),
                                        ),
                                        child: const Text("View order", style: TextStyle(color: tealAccent)),
                                      ),
                                      const Spacer(),
                                      if (canComplete)
                                        TextButton(
                                          onPressed: () => _markOrderComplete(doc.id),
                                          child: const Text("Mark completed", style: TextStyle(color: Colors.orangeAccent)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
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
