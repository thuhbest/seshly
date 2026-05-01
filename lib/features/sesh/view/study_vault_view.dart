import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:seshly/access/app_access.dart';
import 'package:seshly/access/access_controller.dart';
import 'package:seshly/features/tutors/view/recharge_view.dart';
import 'package:seshly/services/billing_profile_service.dart';
import 'package:seshly/services/secure_entitlements_service.dart';
import 'package:seshly/services/study_vault_service.dart';
import 'package:seshly/widgets/pressable_scale.dart';
import 'package:url_launcher/url_launcher.dart';

import 'study_vault_upload_view.dart';

class StudyVaultView extends StatefulWidget {
  const StudyVaultView({super.key});

  @override
  State<StudyVaultView> createState() => _StudyVaultViewState();
}

class _StudyVaultViewState extends State<StudyVaultView> {
  String _filterMode = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final SecureEntitlementsService _secureEntitlements =
      SecureEntitlementsService();

  static const Color _tealAccent = Color(0xFF00C09E);
  static const Color _backgroundColor = Color(0xFF0F142B);
  static const Color _cardColor = Color(0xFF1E243A);

  bool _canUseStudyVault(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      return true;
    }
    return AccessController.can(context, AppCapability.viewStudyVault);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUseStudyVault(context)) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('StudyVault'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardColor.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: _tealAccent,
                    size: 30,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'StudyVault requires a full account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Instant Tutor Mode supports tutor discovery and booking only.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: const Text('Go Back'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('StudyVault'),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 1180
                ? 1180.0
                : constraints.maxWidth;
            final bool isCompact = contentWidth < 760;
            final double horizontalPadding = contentWidth >= 900 ? 28 : 20;
            final int crossAxisCount = contentWidth >= 1080
                ? 3
                : (contentWidth >= 760 ? 2 : 1);

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    12,
                    horizontalPadding,
                    32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroSection(isCompact: isCompact),
                      const SizedBox(height: 12),
                      _buildDiscoveryPanel(),
                      const SizedBox(height: 20),
                      _buildMaterialList(crossAxisCount: crossAxisCount),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroSection({required bool isCompact}) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: const [
        _StudyVaultHeroChip(label: 'Academic resources', accent: _tealAccent),
        SizedBox(height: 10),
        Text(
          'StudyVault',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Upload and discover academic resources.',
          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
        ),
      ],
    );

    final uploadButton = SizedBox(
      width: isCompact ? double.infinity : null,
      child: StudyVaultActionButton(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const StudyVaultUploadView()),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: _tealAccent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.upload_file_rounded,
                size: 18,
                color: _backgroundColor,
              ),
              SizedBox(width: 8),
              Text(
                'Upload resource',
                style: TextStyle(
                  color: _backgroundColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Material(
      color: _cardColor.withValues(alpha: 0.84),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: isCompact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 14), uploadButton],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  uploadButton,
                ],
              ),
      ),
    );
  }

  Widget _buildDiscoveryPanel() {
    return Material(
      color: _cardColor.withValues(alpha: 0.84),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Discover resources',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search by title, module, institute, or resource type.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _buildSearchBar(),
            const SizedBox(height: 14),
            _buildFilterRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) =>
          setState(() => _searchQuery = value.toLowerCase().trim()),
      textInputAction: TextInputAction.search,
      cursorColor: _tealAccent,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search title, institute, module, course, or type',
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: _tealAccent.withValues(alpha: 0.72),
            width: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _filterChip('All resources', 'all'),
        _filterChip('Free', 'free'),
        _filterChip('Paid', 'paid'),
        _filterChip('My uploads', 'mine'),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final bool selected = _filterMode == value;
    return StudyVaultActionButton(
      onTap: () => setState(() => _filterMode = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _tealAccent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _tealAccent.withValues(alpha: 0.42)
                : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildMaterialList({required int crossAxisCount}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(StudyVaultService.collectionName)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _tealAccent),
          );
        }

        final docs =
            snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final searchIndex = (data['searchIndex'] ?? '')
                  .toString()
                  .toLowerCase();
              final fallback = [
                data['title'],
                data['subject'],
                data['moduleName'],
                data['courseName'],
                data['institute'],
                data['academicYear'],
                data['resourceType'],
                data['type'],
              ].join(' ').toLowerCase();
              final haystack = searchIndex.isNotEmpty ? searchIndex : fallback;
              final matchesSearch =
                  _searchQuery.isEmpty || haystack.contains(_searchQuery);
              final isMine =
                  uid != null && (data['userId'] ?? '').toString() == uid;
              final isPaid = StudyVaultService.isPaidResource(data);

              switch (_filterMode) {
                case 'mine':
                  return matchesSearch && isMine;
                case 'free':
                  return matchesSearch && !isPaid;
                case 'paid':
                  return matchesSearch && isPaid;
                default:
                  return matchesSearch;
              }
            }).toList()..sort((a, b) {
              final dataA = a.data() as Map<String, dynamic>;
              final dataB = b.data() as Map<String, dynamic>;
              final starsA = (dataA['stars'] as num?)?.toInt() ?? 0;
              final starsB = (dataB['stars'] as num?)?.toInt() ?? 0;
              if (starsA != starsB) return starsB.compareTo(starsA);
              final createdA = dataA['createdAt'] as Timestamp?;
              final createdB = dataB['createdAt'] as Timestamp?;
              return (createdB?.millisecondsSinceEpoch ?? 0).compareTo(
                createdA?.millisecondsSinceEpoch ?? 0,
              );
            });

        if (docs.isEmpty) {
          return Material(
            color: _cardColor.withValues(alpha: 0.78),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    color: Colors.white24,
                    size: 42,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No StudyVault resources found.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Try another search term or publish the first resource in this lane.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        if (crossAxisCount <= 1) {
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _buildStudyVaultCard(docs[index].id, data);
            },
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: crossAxisCount == 3 ? 0.97 : 0.88,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildStudyVaultCard(docs[index].id, data);
          },
        );
      },
    );
  }

  Widget _buildStudyVaultCard(String docId, Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final List starredBy = data['starredBy'] ?? [];
    final bool isStarred = starredBy.contains(uid);
    final bool isPaid = StudyVaultService.isPaidResource(data);
    final bool canAccess = StudyVaultService.userCanAccess(
      data: data,
      userId: uid,
    );
    final int priceZar = StudyVaultService.priceFrom(data);
    final String institute = (data['institute'] ?? 'Unknown Institute')
        .toString();
    final String title =
        (data['title'] ??
                data['moduleName'] ??
                data['subject'] ??
                'Study resource')
            .toString();
    final String moduleName = (data['moduleName'] ?? '').toString();
    final String moduleCode = (data['moduleCode'] ?? data['subject'] ?? '')
        .toString();
    final String courseName = (data['courseName'] ?? 'Course not set')
        .toString();
    final String year = (data['academicYear'] ?? data['year'] ?? 'Year not set')
        .toString();
    final String resourceType =
        (data['resourceType'] ?? data['type'] ?? 'Resource').toString();
    final String description =
        (data['description'] ?? data['previewText'] ?? '').toString();
    final stars = (data['stars'] as num?)?.toInt() ?? 0;
    final secondaryLine = [
      moduleCode,
      moduleName.isEmpty ? courseName : moduleName,
    ].where((part) => part.trim().isNotEmpty).join(' • ');

    return Material(
      color: _cardColor.withValues(alpha: 0.74),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _tealAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _iconForResourceType(resourceType),
                    color: _tealAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    institute,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _tealAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _accessBadge(isPaid: isPaid, priceZar: priceZar),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                height: 1.3,
              ),
            ),
            if (secondaryLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                secondaryLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StudyVaultMetaChip(label: resourceType),
                if (moduleCode.trim().isNotEmpty)
                  _StudyVaultMetaChip(label: moduleCode),
                _StudyVaultMetaChip(label: 'Year $year'),
              ],
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                StudyVaultActionButton(
                  onTap: () => _toggleStar(docId, isStarred),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isStarred
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: isStarred ? Colors.amber : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$stars',
                          style: TextStyle(
                            color: isStarred ? Colors.amber : Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StudyVaultActionButton(
                    onTap: () => canAccess
                        ? _openResource(data)
                        : _unlockPaidResource(docId, data),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: canAccess
                            ? _tealAccent
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: canAccess
                              ? Colors.transparent
                              : Colors.white10,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            canAccess
                                ? Icons.download_for_offline_rounded
                                : Icons.lock_open_rounded,
                            color: canAccess ? _backgroundColor : Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              canAccess
                                  ? 'Open resource'
                                  : 'Unlock for R$priceZar',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: canAccess
                                    ? _backgroundColor
                                    : Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _accessBadge({required bool isPaid, required int priceZar}) {
    final Color background = isPaid
        ? Colors.amber.withValues(alpha: 0.14)
        : _tealAccent.withValues(alpha: 0.12);
    final Color foreground = isPaid ? Colors.amberAccent : _tealAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Text(
        isPaid ? 'Paid R$priceZar' : 'Free',
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  IconData _iconForResourceType(String resourceType) {
    final normalized = resourceType.toLowerCase();
    if (normalized.contains('book')) return Icons.menu_book_rounded;
    if (normalized.contains('paper')) return Icons.quiz_outlined;
    if (normalized.contains('question')) return Icons.fact_check_outlined;
    if (normalized.contains('guide')) return Icons.map_outlined;
    return Icons.description_outlined;
  }

  Future<void> _openResource(Map<String, dynamic> data) async {
    final fileUrl = (data['fileUrl'] ?? '').toString();
    if (fileUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This resource is missing its file link.'),
        ),
      );
      return;
    }
    await launchUrl(Uri.parse(fileUrl), mode: LaunchMode.platformDefault);
  }

  Future<void> _unlockPaidResource(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to unlock paid StudyVault resources.'),
        ),
      );
      return;
    }

    if ((data['userId'] ?? '').toString() == user.uid) {
      await _openResource(data);
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted) return;
    final userData = userDoc.data() ?? <String, dynamic>{};
    final billingProfile = BillingProfileService.fromUserData(
      userData,
      isAnonymousAuth: user.isAnonymous,
    );

    if (!billingProfile.isReady || !billingProfile.hasDigits) {
      await _promptBillingSetup();
      return;
    }

    final int priceZar = StudyVaultService.priceFrom(data);
    final String title =
        (data['title'] ?? data['moduleName'] ?? 'Study resource').toString();
    final String paymentSummary = billingProfile.summary;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          'Unlock StudyVault resource',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Charge $paymentSummary for R$priceZar to unlock this resource.',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _secureEntitlements.purchaseStudyVaultResource(resourceId: docId);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title unlocked successfully.')));
    await _openResource(data);
  }

  Future<void> _promptBillingSetup() async {
    final bool? shouldOpen = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        title: const Text(
          'Card setup required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Paid StudyVault resources use the same saved billing card as tutor sessions. Set up your card first, then return to unlock this resource.',
          style: TextStyle(color: Colors.white60, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Set up card'),
          ),
        ],
      ),
    );

    if (shouldOpen != true || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RechargeView()),
    );
  }

  Future<void> _toggleStar(String docId, bool isStarred) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection(StudyVaultService.collectionName)
        .doc(docId);
    if (isStarred) {
      await ref.update({
        'stars': FieldValue.increment(-1),
        'starredBy': FieldValue.arrayRemove([uid]),
      });
      return;
    }
    await ref.update({
      'stars': FieldValue.increment(1),
      'starredBy': FieldValue.arrayUnion([uid]),
    });
  }
}

class _StudyVaultHeroChip extends StatelessWidget {
  const _StudyVaultHeroChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StudyVaultMetaChip extends StatelessWidget {
  const _StudyVaultMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class StudyVaultActionButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const StudyVaultActionButton({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<StudyVaultActionButton> createState() => _StudyVaultActionButtonState();
}

class _StudyVaultActionButtonState extends State<StudyVaultActionButton> {
  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: widget.onTap,
      pressedScale: 0.96,
      child: widget.child,
    );
  }
}
