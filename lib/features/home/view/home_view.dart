import 'package:flutter/material.dart';
import '../widgets/post_card.dart';
import '../widgets/category_selector.dart';
import '../controllers/home_controller.dart';
import '../widgets/sesh_lock_dialog.dart'; 
import '../VIEW/notifications_view.dart'; 
import '../VIEW/marketplace_view.dart'; 
import '../VIEW/new_question_view.dart';

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
                    Text(
                      "Home",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "Discover academic questions",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Marketplace Button with Pressed Effect
                    HeaderIconButton(
                      icon: Icons.shopping_basket_outlined,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MarketplaceView()),
                        );
                      },
                    ),
                    // Notifications Button with Pressed Effect
                    HeaderIconButton(
                      icon: Icons.notifications_none,
                      count: "5",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const NotificationsView()),
                        );
                      },
                    ),
                    // SeshLock Button with Pressed Effect
                    HeaderIconButton(
                      icon: Icons.lock_outline,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => const SeshLockDialog(),
                        );
                      },
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 25),
            // Search Bar Placeholder with Pressed Effect
            SearchPlaceholderButton(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NewQuestionView()),
                );
              },
            ),
            const SizedBox(height: 20),
            CategorySelector(
              selectedCategory: _homeController.selectedCategory,
              onCategorySelected: (category) =>
                  _homeController.updateCategory(category, setState),
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
}

/// A dedicated button for the header that shrinks when pressed
class HeaderIconButton extends StatefulWidget {
  final IconData icon;
  final String? count;
  final VoidCallback onTap;

  const HeaderIconButton({
    super.key,
    required this.icon,
    this.count,
    required this.onTap,
  });

  @override
  State<HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<HeaderIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Animation scale: 1.0 is normal, 0.9 is shrunk
    final double scale = _isPressed ? 0.9 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                // Visual feedback: Brighten background slightly when pressed
                color: _isPressed 
                    ? Colors.white.withValues(alpha: 0.2) 
                    : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                color: const Color(0xFF00C09E),
                size: 22,
              ),
            ),
            if (widget.count != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00C09E),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    widget.count!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}

/// A search placeholder button with pressed effect
class SearchPlaceholderButton extends StatefulWidget {
  final VoidCallback onTap;

  const SearchPlaceholderButton({
    super.key,
    required this.onTap,
  });

  @override
  State<SearchPlaceholderButton> createState() => _SearchPlaceholderButtonState();
}

class _SearchPlaceholderButtonState extends State<SearchPlaceholderButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    // Animation scale: 1.0 is normal, 0.95 is shrunk
    final double scale = _isPressed ? 0.95 : 1.0;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isPressed ? Colors.white.withValues(alpha: 0.2) : Colors.white12,
            ),
            borderRadius: BorderRadius.circular(15),
            color: _isPressed 
                ? Colors.white.withValues(alpha: 0.1) // Brighter when pressed
                : Colors.white.withValues(alpha: 0.05),
          ),
          child: const Center(
            child: Text(
              "What are you stuck on today?",
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}