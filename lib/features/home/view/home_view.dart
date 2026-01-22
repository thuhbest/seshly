import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:seshly/services/sesh_focus_service.dart';
import '../widgets/post_card.dart';
import '../widgets/category_selector.dart';
import '../controllers/home_controller.dart';
import '../widgets/sesh_focus_dialog.dart'; 
import '../VIEW/notifications_view.dart'; 
import '../VIEW/marketplace_view.dart'; 
import '../VIEW/new_question_view.dart';

class HomeView extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const HomeView({
    super.key,
    this.refreshSignal,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late HomeController _homeController;
  final ScrollController _scrollController = ScrollController();
  bool _isHeaderVisible = true;
  bool _isStoppingFocus = false;

  @override
  void initState() {
    super.initState();
    _homeController = HomeController(context);
    widget.refreshSignal?.addListener(_handleExternalRefresh);
    
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
  void _handleExternalRefresh() {
    if (!mounted) return;
    _refreshPosts();
  }

  Future<void> _refreshPosts() async {
    setState(() {
      // Re-trigger the controller to fetch fresh data
      _homeController.updateCategory(_homeController.selectedCategory, setState);
    });
    // Optional: Scroll to top when refreshing
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
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

  Future<void> _stopExpiredFocus() async {
    if (_isStoppingFocus) return;
    _isStoppingFocus = true;
    try {
      await SeshFocusService.stop();
    } catch (_) {
      // Ignore failures; we'll retry on next snapshot update.
    } finally {
      _isStoppingFocus = false;
    }
  }

  Widget _buildFocusButton() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return HeaderIconButton(
        icon: Icons.lock_outline,
        onTap: () => showDialog(context: context, builder: (_) => const SeshFocusDialog()),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final bool isActiveFlag = data['seshFocusActive'] == true;
        final Timestamp? endsAt = data['seshFocusEndsAt'] as Timestamp?;

        bool isActive = isActiveFlag;
        if (endsAt != null) {
          final DateTime now = DateTime.now();
          if (endsAt.toDate().isAfter(now)) {
            isActive = true;
          } else if (isActiveFlag) {
            isActive = false;
            // ignore: unawaited_futures
            _stopExpiredFocus();
          }
        }

        final Color iconColor = isActive ? Colors.redAccent : const Color(0xFF00C09E);
        final Color backgroundColor = isActive
            ? Colors.redAccent.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.1);
        final Color pressedBackgroundColor = isActive
            ? Colors.redAccent.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.2);

        return HeaderIconButton(
          icon: isActive ? Icons.lock_rounded : Icons.lock_outline,
          iconColor: iconColor,
          backgroundColor: backgroundColor,
          pressedBackgroundColor: pressedBackgroundColor,
          onTap: () => showDialog(context: context, builder: (_) => const SeshFocusDialog()),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefresh);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal?.removeListener(_handleExternalRefresh);
      widget.refreshSignal?.addListener(_handleExternalRefresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
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
                      if (currentUserId == null)
                        HeaderIconButton(
                          icon: Icons.notifications_none,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsView())),
                        )
                      else
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUserId)
                              .collection('notifications')
                              .where('isRead', isEqualTo: false)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final unreadCount = snapshot.data?.docs.length ?? 0;
                            return HeaderIconButton(
                              icon: Icons.notifications_none,
                              count: unreadCount > 0 ? unreadCount.toString() : null,
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsView())),
                            );
                          },
                        ),
                      _buildFocusButton(),
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
                      return ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 140),
                          Center(child: Text("No posts found", style: TextStyle(color: Colors.white38))),
                        ],
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController, // Attach controller
                      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
  final Color? iconColor;
  final Color? backgroundColor;
  final Color? pressedBackgroundColor;

  const HeaderIconButton({
    super.key,
    required this.icon,
    this.count,
    required this.onTap,
    this.iconColor,
    this.backgroundColor,
    this.pressedBackgroundColor,
  });

  @override
  State<HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<HeaderIconButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _isPressed ? 0.9 : 1.0;
    final Color baseBackground = widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1);
    final Color pressedBackground = widget.pressedBackgroundColor ?? Colors.white.withValues(alpha: 0.2);
    final Color iconColor = widget.iconColor ?? const Color(0xFF00C09E);

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
                color: _isPressed ? pressedBackground : baseBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.icon,
                color: iconColor,
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
