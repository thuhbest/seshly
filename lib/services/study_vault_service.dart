class StudyVaultService {
  static const String collectionName = 'vault';
  static const String currency = 'ZAR';
  static const int commissionPercent = 20;
  static const List<String> resourceTypes = <String>[
    'Notes',
    'Book',
    'Past Paper',
    'Question Bank',
    'Study Guide',
  ];

  static int sanitizePrice(int rawPriceZar) {
    if (rawPriceZar < 0) return 0;
    return rawPriceZar;
  }

  static int platformFeeFromPrice(int priceZar) {
    final safePrice = sanitizePrice(priceZar);
    return ((safePrice * commissionPercent) / 100).round();
  }

  static int sellerNetFromPrice(int priceZar) {
    final safePrice = sanitizePrice(priceZar);
    return safePrice - platformFeeFromPrice(safePrice);
  }

  static bool isPaidResource(Map<String, dynamic> data) {
    final String accessType = (data['accessType'] ?? '').toString().toLowerCase();
    final bool isPaidFlag = data['isPaid'] == true;
    final int priceZar = priceFrom(data);
    return accessType == 'paid' || isPaidFlag || priceZar > 0;
  }

  static int priceFrom(Map<String, dynamic> data) {
    final dynamic raw = data['priceZar'] ?? data['price'] ?? 0;
    return (raw as num?)?.round() ?? 0;
  }

  static int sellerNetFrom(Map<String, dynamic> data) {
    final dynamic raw = data['sellerNetZar'];
    if (raw is num) return raw.round();
    return sellerNetFromPrice(priceFrom(data));
  }

  static int platformFeeFrom(Map<String, dynamic> data) {
    final dynamic raw = data['platformFeeZar'];
    if (raw is num) return raw.round();
    return platformFeeFromPrice(priceFrom(data));
  }

  static List<String> purchasedByFrom(Map<String, dynamic> data) {
    final raw = data['purchasedBy'];
    if (raw is List) {
      return raw.map((entry) => entry.toString()).toList();
    }
    return const <String>[];
  }

  static bool userCanAccess({
    required Map<String, dynamic> data,
    required String? userId,
  }) {
    if (!isPaidResource(data)) return true;
    if (userId == null) return false;
    final ownerId = (data['userId'] ?? data['ownerId'] ?? '').toString();
    if (ownerId == userId) return true;
    return purchasedByFrom(data).contains(userId);
  }

  static String accessLabel(Map<String, dynamic> data) {
    if (!isPaidResource(data)) return 'Free';
    return 'Paid';
  }

  static String buildSearchIndex({
    required String title,
    required String subject,
    required String moduleCode,
    required String moduleName,
    required String courseName,
    required String institute,
    required String academicYear,
    required String resourceType,
    required String description,
  }) {
    return [
      title,
      subject,
      moduleCode,
      moduleName,
      courseName,
      institute,
      academicYear,
      resourceType,
      description,
    ].join(' ').toLowerCase();
  }
}
