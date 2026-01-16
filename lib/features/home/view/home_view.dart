import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/post_card.dart';
import '../widgets/category_selector.dart';
import '../controllers/home_controller.dart';
import '../widgets/sesh_focus_dialog.dart'; 
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
  final ScrollController _scrollController = ScrollController();
  bool _isHeaderVisible = true;

  @override
  void initState() {
    super.initState();
    _homeController = HomeController(context);
    
    // 🔥 Listen to scroll to hide/show the "What are you stuck on" button
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isHeaderVisible) setState(() => _isHeaderVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isHeaderVisible) setState(() => _isHeaderVisible = true);
      }
    });
  }

  // 🔥 REFRESH LOGIC: Similar to social media home buttons
  Future<void> _refreshPosts() async {
    setState(() {
      // Re-trigger the controller to fetch fresh data
      _homeController.updateCategory(_homeController.selectedCategory, setState);
    });
    // Optional: Scroll to top when refreshing
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  String _getTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return "Just now";
    final now = DateTime.now();
    final difference = now.difference(timestamp.toDate());
    if (difference.inDays > 0) return "${difference.inDays}d ago";
    if (difference.inHours > 0) return "${difference.inHours}h ago";
    if (difference.inMinutes > 0) return "${difference.inMinutes}m ago";
    return "Just now";
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 🔥 HEADER SECTION (Always Visible)
            GestureDetector(
              onTap: _refreshPosts, // Clicking "Home" refreshes posts
              child: Row(
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
                      HeaderIconButton(
                        icon: Icons.shopping_basket_outlined,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplaceView())),
                      ),
                      HeaderIconButton(
                        icon: Icons.notifications_none,
                        count: "5",
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsView())),
                      ),
                      HeaderIconButton(
                        icon: Icons.lock_outline,
                        onTap: () => showDialog(context: context, builder: (_) => const SeshFocusDialog()),
                      ),
                    ],
                  )
                ],
              ),
            ),

            // 🔥 DISAPPEARING SEARCH BUTTON
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              crossFadeState: _isHeaderVisible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              secondChild: const SizedBox(width: double.infinity), // Hidden state
              firstChild: Column(
                children: [
                  const SizedBox(height: 25),
                  SearchPlaceholderButton(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewQuestionView())),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            CategorySelector(
              selectedCategory: _homeController.selectedCategory,
              onCategorySelected: (category) => _homeController.updateCategory(category, setState),
            ),
            const SizedBox(height: 25),
            
            // 🔥 POSTS LIST
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF00C09E),
                backgroundColor: const Color(0xFF1E243A),
                onRefresh: _refreshPosts,
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _homeController.getRankedPosts(), 
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF00C09E)));
                    }
                    final posts = snapshot.data ?? [];
                    if (posts.isEmpty) {
                      return const Center(child: Text("No posts found", style: TextStyle(color: Colors.white38)));
                    }

                    return ListView.builder(
                      controller: _scrollController, // Attach controller
                      physics: const BouncingScrollPhysics(),
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final data = posts[index];
                        return PostCard(
                          postId: data['id'],
                          authorId: data['authorId'] ?? "",
                          subject: data['subject'] ?? "General",
                          time: _getTimeAgo(data['createdAt']),
                          question: data['question'] ?? "",
                          author: data['author'] ?? "Anonymous",
                          likes: data['likes'] ?? 0,
                          comments: data['comments'] ?? 0,
                          attachmentUrl: data['attachmentUrl'], 
                          link: data['link'], 
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class SearchPlaceholderButton extends StatefulWidget {
  final VoidCallback onTap;

  const SearchPlaceholderButton({
    super.key,
    required this.onTap,  // Fixed: Added required onTap parameter
  });

  @override
  State<SearchPlaceholderButton> createState() => _SearchPlaceholderButtonState();
}

class _SearchPlaceholderButtonState extends State<SearchPlaceholderButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
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
                ? Colors.white.withValues(alpha: 0.1) 
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