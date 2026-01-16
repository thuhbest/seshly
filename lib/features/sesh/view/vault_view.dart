import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'vault_upload_view.dart';
import '../widgets/contribution_stats.dart';

class VaultView extends StatefulWidget {
  const VaultView({super.key});

  @override
  State<VaultView> createState() => _VaultViewState();
}

class _VaultViewState extends State<VaultView> {
  bool isAllMaterials = true;
  String _searchQuery = "";
  final Color tealAccent = const Color(0xFF00C09E);
  final Color backgroundColor = const Color(0xFF0F142B);
  final Color cardColor = const Color(0xFF1E243A);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildHeader(),
            const SizedBox(height: 25),
            _buildSearchBar(),
            const SizedBox(height: 20),
            Row(
              children: [
                _toggleBtn("All Materials", isAllMaterials, () => setState(() => isAllMaterials = true)),
                const SizedBox(width: 12),
                _toggleBtn("My Uploads", !isAllMaterials, () => setState(() => isAllMaterials = false)),
              ],
            ),
            const SizedBox(height: 30),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isAllMaterials ? _buildMaterialList(false) : _buildMaterialList(true),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Study Vault", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text("Free PDFs shared by students", style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        VaultActionButton(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultUploadView())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: tealAccent, borderRadius: BorderRadius.circular(12)),
            child: const Row(
              children: [
                Icon(Icons.add_rounded, size: 20, color: Color(0xFF0F142B)),
                SizedBox(width: 4),
                Text("Upload", style: TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search course code (e.g. MAM1000W)",
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 20),
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildMaterialList(bool onlyMine) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Query query = FirebaseFirestore.instance.collection('vault').orderBy('stars', descending: true);

    if (onlyMine) query = query.where('userId', isEqualTo: uid);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final docs = snapshot.data!.docs.where((doc) {
          final subject = (doc['subject'] as String).toLowerCase();
          return subject.contains(_searchQuery);
        }).toList();

        if (docs.isEmpty) return const Center(child: Text("No documents found.", style: TextStyle(color: Colors.white24)));

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildVaultCard(docs[index].id, data);
          },
        );
      },
    );
  }

  Widget _buildVaultCard(String docId, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final List starredBy = data['starredBy'] ?? [];
    final bool isStarred = starredBy.contains(uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: tealAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.picture_as_pdf_rounded, color: tealAccent, size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['subject'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text("${data['type']} • ${data['year']}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          VaultActionButton(
            onTap: () => _toggleStar(docId, isStarred),
            child: Column(
              children: [
                Icon(isStarred ? Icons.star_rounded : Icons.star_outline_rounded, color: isStarred ? Colors.amber : Colors.white24),
                Text("${data['stars']}", style: TextStyle(color: isStarred ? Colors.amber : Colors.white24, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          VaultActionButton(
            onTap: () => launchUrl(Uri.parse(data['fileUrl'])),
            child: Icon(Icons.download_for_offline_rounded, color: tealAccent.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  void _toggleStar(String docId, bool isStarred) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection('vault').doc(docId);
    if (isStarred) {
      ref.update({'stars': FieldValue.increment(-1), 'starredBy': FieldValue.arrayRemove([uid])});
    } else {
      ref.update({'stars': FieldValue.increment(1), 'starredBy': FieldValue.arrayUnion([uid])});
    }
  }

  Widget _toggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return VaultActionButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? tealAccent : cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? null : Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class VaultActionButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const VaultActionButton({super.key, required this.child, required this.onTap});
  @override
  State<VaultActionButton> createState() => _VaultActionButtonState();
}

class _VaultActionButtonState extends State<VaultActionButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _isPressed ? 0.94 : 1.0, duration: const Duration(milliseconds: 100), child: widget.child),
    );
  }
}