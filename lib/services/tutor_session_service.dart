enum TutorBookingMode {
  instant,
  prep5,
}

extension TutorBookingModeX on TutorBookingMode {
  String get value {
    switch (this) {
      case TutorBookingMode.prep5:
        return 'prep_5';
      case TutorBookingMode.instant:
        return 'instant';
    }
  }

  String get label {
    switch (this) {
      case TutorBookingMode.prep5:
        return 'Give tutor 5 minutes';
      case TutorBookingMode.instant:
        return 'Start now';
    }
  }

  int get prepMinutes {
    switch (this) {
      case TutorBookingMode.prep5:
        return 5;
      case TutorBookingMode.instant:
        return 0;
    }
  }

  static TutorBookingMode fromValue(String? raw) {
    switch (raw) {
      case 'prep_5':
      case 'prep5':
        return TutorBookingMode.prep5;
      default:
        return TutorBookingMode.instant;
    }
  }
}

class TutorPricingBreakdown {
  const TutorPricingBreakdown({
    required this.tutorRatePerMinute,
    required this.platformFeePerMinute,
    required this.totalRatePerMinute,
  });

  final double tutorRatePerMinute;
  final double platformFeePerMinute;
  final double totalRatePerMinute;

  Map<String, dynamic> toMap() {
    return {
      'tutorRatePerMinute': tutorRatePerMinute,
      'platformFeePerMinute': platformFeePerMinute,
      'totalRatePerMinute': totalRatePerMinute,
    };
  }
}

class TutorSessionService {
  static const double platformFeePercent = 20;
  static const double _platformFeeFactor = platformFeePercent / 100;
  static const String currency = 'ZAR';

  static TutorPricingBreakdown buildPricing(Map<String, dynamic> tutorData) {
    final profile = tutorData['tutorProfile'] as Map<String, dynamic>? ?? {};

    final double baseRate = _readPositiveNumber(profile['displayRate']) ??
        _readPositiveNumber(tutorData['displayRate']) ??
        _readPositiveNumber(profile['ratePerMinute']) ??
        25;
    final double fee = baseRate * _platformFeeFactor;
    final double total = baseRate + fee;

    return TutorPricingBreakdown(
      tutorRatePerMinute: _roundToTwo(baseRate),
      platformFeePerMinute: _roundToTwo(fee),
      totalRatePerMinute: _roundToTwo(total),
    );
  }

  static DateTime computeRequestedStart({
    required TutorBookingMode bookingMode,
    DateTime? now,
  }) {
    final base = now ?? DateTime.now();
    return base.add(Duration(minutes: bookingMode.prepMinutes));
  }

  static double? _readPositiveNumber(dynamic value) {
    final parsed = (value as num?)?.toDouble();
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static double _roundToTwo(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}
