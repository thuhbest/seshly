import 'package:flutter/material.dart';
import '../widgets/post_card.dart';
import '../widgets/category_selector.dart';
import '../controllers/home_controller.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late HomeController _homeController;

  @override
  void initState() {
    super.initState();
    _homeController = HomeController(context);
  }

  @override
  Widget build(BuildContext context) {
    // We use a Container or Column instead of a Scaffold
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Home", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text("Discover academic questions", style: TextStyle(color: Colors.white54)),
                  ],
                ),
                Row(
                  children: [
                    _headerIcon(Icons.shopping_basket_outlined),
                    _headerIcon(Icons.notifications_none, count: "5"),
                    _headerIcon(Icons.lock_outline),
                  ],
                )
              ],
            ),
            const SizedBox(height: 25),
            // Search Bar Placeholder
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(15),
                color: Colors.white.withOpacity(0.05),
              ),
              child: const Center(
                child: Text("What are you stuck on today?", style: TextStyle(color: Colors.white70, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
            CategorySelector(
              selectedCategory: _homeController.selectedCategory,
              onCategorySelected: (category) => _homeController.updateCategory(category, setState),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: const [
                  PostCard(
                    subject: "Mathematics",
                    time: "5m ago",
                    question: "How do I solve quadratic equations using the quadratic formula?",
                    author: "Thuhbest",
                    likes: 24,
                    comments: 12,
                  ),
                  PostCard(
                    subject: "Physics",
                    time: "15m ago",
                    question: "Can someone explain the difference between kinetic and potential energy?",
                    author: "Tinswaole",
                    likes: 16,
                    comments: 8,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, {String? count}) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 10),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF00C09E), size: 22),
        ),
        if (count != null)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0xFF00C09E), shape: BoxShape.circle),
              child: Text(count, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          )
      ],
    );
  }
}