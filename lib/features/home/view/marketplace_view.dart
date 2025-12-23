import 'package:flutter/material.dart';
import '../widgets/market_item_card.dart';
import '../widgets/market_category_bar.dart';

class MarketplaceView extends StatelessWidget {
  const MarketplaceView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF0F142B);
    const Color tealAccent = Color(0xFF00C09E);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // --- Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                  // Back to Posts Button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.tune, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- Search Bar ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E243A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const TextField(
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    icon: Icon(Icons.search, color: Colors.white54, size: 20),
                    hintText: "Search marketplace...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- Categories ---
              const MarketCategoryBar(),
              const SizedBox(height: 25),

              // --- Product Grid ---
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: 0.65,
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    MarketItemCard(
                      title: "Complete Calculus 1 Notes - Semester 1",
                      price: "R45",
                      author: "Thuhbest",
                      category: "Notes",
                      isDigital: true,
                    ),
                    MarketItemCard(
                      title: "Organic Chemistry Study Guide & Notes",
                      price: "R60",
                      author: "Tinswaole",
                      category: "Notes",
                      isDigital: true,
                    ),
                    MarketItemCard(
                      title: "Physics 101 - Full Year Notes",
                      price: "R80",
                      author: "Thimna",
                      category: "Notes",
                      isDigital: true,
                    ),
                    MarketItemCard(
                      title: "Introduction to Programming - Python",
                      price: "R55",
                      author: "Luko",
                      category: "Notes",
                      isDigital: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: tealAccent,
        child: const Icon(Icons.add, color: backgroundColor, size: 30),
      ),
    );
  }
}