import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:seshly/services/billing_profile_service.dart';
import 'package:seshly/services/tutoring_backend_service.dart';
import 'package:seshly/theme/seshly_theme.dart';
import 'package:seshly/widgets/responsive.dart';

class RechargeView extends StatelessWidget {
  const RechargeView({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: SeshlyPalette.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payments', style: Theme.of(context).textTheme.titleLarge),
            Text(
              'Manage the card used for tutor bookings and session charges.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: ResponsiveCenter(
        maxWidth: 780,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: user == null
            ? _InstantTutorModePaymentsView(
                onPrimaryAction: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  final userData =
                      snapshot.data?.data() ?? const <String, dynamic>{};
                  final bool isInstantTutorMode =
                      BillingProfileService.isInstantTutorModeUser(
                        userData,
                        isAnonymousAuth: user.isAnonymous,
                      );
                  final billingProfile = BillingProfileService.fromUserData(
                    userData,
                    isAnonymousAuth: user.isAnonymous,
                  );

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionCard(
                          title: billingProfile.title,
                          subtitle: billingProfile.isTemporary
                              ? 'This temporary card is kept purpose-limited to tutor booking and payment flow.'
                              : 'This is the card used for tutor bookings and session charges.',
                          trailing: FilledButton(
                            onPressed: () => _openCardSheet(
                              context,
                              holderName: billingProfile.holder,
                              isTemporary: billingProfile.isTemporary,
                            ),
                            child: Text(billingProfile.manageLabel),
                          ),
                          child: _BillingCardSummary(
                            isReady: billingProfile.isReady,
                            brand: billingProfile.brand,
                            last4: billingProfile.last4.isEmpty
                                ? '0000'
                                : billingProfile.last4,
                            expMonth: billingProfile.expMonth,
                            expYear: billingProfile.expYear,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isInstantTutorMode
                              ? 'This card stays limited to tutor booking in Instant Tutor Mode.'
                              : 'This card is used for tutor bookings and final session charges.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  static void _openCardSheet(
    BuildContext context, {
    String holderName = '',
    bool isTemporary = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CardSetupSheet(
        initialHolderName: holderName,
        isTemporary: isTemporary,
      ),
    );
  }
}

class _InstantTutorModePaymentsView extends StatelessWidget {
  const _InstantTutorModePaymentsView({required this.onPrimaryAction});

  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Payment setup',
      subtitle: 'Sign in or continue in Instant Tutor Mode to manage a card.',
      trailing: FilledButton(
        onPressed: onPrimaryAction,
        child: const Text('Back to login'),
      ),
      child: const _FlowList(
        steps: [
          'Link one card for tutor requests.',
          'Your card is confirmed when a tutor accepts.',
          'The final session amount is charged after the session ends.',
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SeshlyPalette.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(subtitle),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _BillingCardSummary extends StatelessWidget {
  const _BillingCardSummary({
    required this.isReady,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });

  final bool isReady;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SeshlyPalette.surfaceRaised.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: isReady
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand.toUpperCase(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: SeshlyPalette.gold),
                ),
                const SizedBox(height: 18),
                Text(
                  '•••• •••• •••• $last4',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Expires ${expMonth.toString().padLeft(2, '0')}/${expYear.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.credit_card_outlined,
                  color: SeshlyPalette.gold,
                  size: 28,
                ),
                const SizedBox(height: 12),
                Text(
                  'No default card yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text('Attach one card to move straight into tutor requests.'),
              ],
            ),
    );
  }
}

class _FlowList extends StatelessWidget {
  const _FlowList({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        steps.length,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SeshlyPalette.aqua.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: SeshlyPalette.aqua),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(steps[index])),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardSetupSheet extends StatefulWidget {
  const _CardSetupSheet({
    required this.initialHolderName,
    required this.isTemporary,
  });

  final String initialHolderName;
  final bool isTemporary;

  @override
  State<_CardSetupSheet> createState() => _CardSetupSheetState();
}

class _CardSetupSheetState extends State<_CardSetupSheet> {
  final TutoringBackendService _backend = TutoringBackendService();
  late final TextEditingController _holderController;
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _holderController = TextEditingController(text: widget.initialHolderName);
  }

  @override
  void dispose() {
    _holderController.dispose();
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  Future<void> _saveCard() async {
    if (_saving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final holder = _holderController.text.trim();
    final digits = _numberController.text.replaceAll(RegExp(r'\D'), '');
    final expiry = _expiryController.text.trim();
    final cvv = _cvvController.text.trim();

    if (holder.isEmpty ||
        digits.length < 12 ||
        expiry.length != 5 ||
        cvv.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a valid card holder name, card number, expiry, and CVV.',
          ),
        ),
      );
      return;
    }

    final parts = expiry.split('/');
    final int? month = int.tryParse(parts.first);
    final int? year = int.tryParse(parts.last);
    if (month == null || year == null || month < 1 || month > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expiry must be in MM/YY format.')),
      );
      return;
    }

    setState(() => _saving = true);
    final String brand = _inferBrand(digits);
    final String last4 = digits.substring(digits.length - 4);

    try {
      await _backend.setupTutoringPaymentMethod(
        isTemporary: widget.isTemporary,
        brand: brand,
        holder: holder,
        last4: last4,
        expMonth: month,
        expYear: year,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isTemporary
                ? '$brand ending in $last4 is ready for tutor booking.'
                : '$brand ending in $last4 is ready for tutor bookings.',
          ),
        ),
      );
    } on TutoringBackendException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card setup failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: SeshlyPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.isTemporary
                ? 'Set up temporary tutor-booking card'
                : 'Set up default card',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            widget.isTemporary
                ? 'This card is used only for tutor booking in Instant Tutor Mode.'
                : 'This card is used for tutor bookings and final session charges.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _holderController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Card holder',
              prefixIcon: const Icon(Icons.person_outline),
              filled: true,
              fillColor: SeshlyPalette.surfaceRaised.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _numberController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Card number',
              prefixIcon: const Icon(Icons.credit_card_outlined),
              filled: true,
              fillColor: SeshlyPalette.surfaceRaised.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _expiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: InputDecoration(
                    labelText: 'MM/YY',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    filled: true,
                    fillColor: SeshlyPalette.surfaceRaised.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cvvController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'CVV',
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: SeshlyPalette.surfaceRaised.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _saveCard,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.isTemporary
                          ? 'Save temporary card'
                          : 'Save default card',
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _inferBrand(String digits) {
    if (digits.startsWith('4')) return 'Visa';
    if (RegExp(r'^5[1-5]').hasMatch(digits)) return 'Mastercard';
    if (digits.startsWith('34') || digits.startsWith('37')) {
      return 'American Express';
    }
    return 'Card';
  }
}
