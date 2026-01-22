import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/market_item_model.dart';
import '../widgets/market_item_card.dart';
import '../widgets/market_category_bar.dart';
import 'create_listing_view.dart';
import 'market_item_detail_view.dart';

class MarketplaceView extends StatefulWidget {
  const MarketplaceView({super.key});

  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView> {
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String _selectedCategory = "All Items";

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Query _itemsQuery() {
    Query query = _db.collection('marketplace_items').where('status', isEqualTo: 'active');
    if (_selectedCategory != "All Items") {
      query = query.where('category', isEqualTo: _selectedCategory);
    }
    return query.orderBy('createdAt', descending: true);
  }

  bool _matchesSearch(MarketItem item, String term) {
    if (term.isEmpty) return true;
    final haystack = [
      item.title,
      item.description,
      item.category,
      item.sellerName,
    ].join(' ').toLowerCase();
    return haystack.contains(term);
  }

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);

    final searchTerm = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Marketplace",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Serif',
                            ),
                          ),
                          Text(
                            "Buy & sell school essentials",
                            style: TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 25),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search, color: Colors.white54, size: 20),
                    hintText: "Search marketplace...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              MarketCategoryBar(
                selected: _selectedCategory,
                onSelected: (category) => setState(() => _selectedCategory = category),
              ),
              const SizedBox(height: 25),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _itemsQuery().snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: tealAccent));
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text("Error loading marketplace", style: TextStyle(color: Colors.white54)),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final items = docs
                        .map((doc) => MarketItem.fromDoc(doc))
                        .where((item) => _matchesSearch(item, searchTerm))
                        .toList();

                    if (items.isEmpty) {
                      return const Center(
                        child: Text("No items found", style: TextStyle(color: Colors.white38)),
                      );
                    }

                    return GridView.builder(
                      itemCount: items.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 20,
                        childAspectRatio: 0.65,
                      ),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return MarketItemCard(
                          title: item.title,
                          price: item.priceLabel,
                          author: item.sellerName,
                          category: item.category,
                          isDigital: item.isDigital,
                          imageUrl: item.imageUrl,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MarketItemDetailView(itemId: item.id),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateListingView()),
        ),
        backgroundColor: tealAccent,
        child: const Icon(Icons.add, color: backgroundColor, size: 30),
      ),
    );
  }
}
