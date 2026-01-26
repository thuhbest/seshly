import 'package:flutter/material.dart';
import 'sesh_ai_panel.dart';

class RightRail extends StatefulWidget {
  const RightRail({super.key});

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF00C09E),
            tabs: const [Tab(text: "AI"), Tab(text: "Tasks")],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const SeshAIPanel(),
                const Center(child: Text("Tasks", style: TextStyle(color: Colors.white38))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
