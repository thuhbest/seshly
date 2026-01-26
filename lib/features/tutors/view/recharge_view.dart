import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/package_card.dart';
import '../widgets/payment_overlay.dart';
import 'package:seshly/widgets/responsive.dart';

class RechargeView extends StatelessWidget {
  const RechargeView({super.key});

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);
    const Color backgroundColor = Color(0xFF0F142B);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Buy Sesh Minutes", 
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Recharge to connect with tutors", 
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
      body: ResponsiveCenter(
        maxWidth: 720,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Current Balance Card ---
              _buildBalanceSection(tealAccent),
              const SizedBox(height: 30),

              // --- Rates Info (From Screenshot) ---
              _buildRatesInfo(),
              const SizedBox(height: 35),

              // --- Starter Packages ---
              const _TierHeader(title: "Starter Packages", color: Colors.greenAccent),
              PackageCard(
                minutes: 30,
                price: "R150",
                rateInfo: "R5.00/min",
                onBuy: () => _showPayment(context, "Starter 30", "R150", 30),
              ),
              const SizedBox(height: 15),
              PackageCard(
                minutes: 60,
                price: "R280",
                rateInfo: "R4.67/min",
                saveAmount: "R20",
                onBuy: () => _showPayment(context, "Starter 60", "R280", 60),
              ),

              const SizedBox(height: 30),

              // --- Core Study Packages ---
              const _TierHeader(title: "Core Study Packages", color: Colors.blueAccent),
              PackageCard(
                minutes: 120,
                price: "R540",
                rateInfo: "R4.50/min",
                saveAmount: "R60",
                isPopular: true,
                onBuy: () => _showPayment(context, "Study 120", "R540", 120),
              ),
              const SizedBox(height: 15),
              PackageCard(
                minutes: 180,
                price: "R780",
                rateInfo: "R4.33/min",
                saveAmount: "R120",
                onBuy: () => _showPayment(context, "Study 180", "R780", 180),
              ),

              const SizedBox(height: 30),

              // --- Power User Packages ---
              const _TierHeader(title: "Power User Packages", color: Colors.purpleAccent),
              PackageCard(
                minutes: 300,
                price: "R1,250",
                rateInfo: "R4.17/min",
                saveAmount: "R250",
                onBuy: () => _showPayment(context, "Focus 300", "R1,250", 300),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  void _showPayment(BuildContext context, String packageName, String price, int minutes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PaymentOverlay(
        packageName: packageName,
        price: price,
        minutes: minutes,
      ),
    );
  }

  Widget _buildBalanceSection(Color teal) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _buildBalanceCard(teal, 0, isGuest: true);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final int minutes = (data['seshMinutes'] as num?)?.toInt() ?? 0;
        return _buildBalanceCard(teal, minutes);
      },
    );
  }

  Widget _buildBalanceCard(Color teal, int minutes, {bool isGuest = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            isGuest ? "Sign in to see balance" : "Current Balance",
            style: const TextStyle(color: Color(0xFF00C09E), fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            isGuest ? "--" : minutes.toString(),
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
          ),
          const Text("Sesh Minutes", style: TextStyle(color: Colors.white54, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildRatesInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E243A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(15),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("How Sesh Minutes Work", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          SizedBox(height: 15),
          Text("- 1.5x rate: 1 real minute = 1.5 Sesh minutes", style: TextStyle(color: Colors.white70, fontSize: 13)),
          Text("- 2x rate: 1 real minute = 2 Sesh minutes", style: TextStyle(color: Colors.white70, fontSize: 13)),
          Text("- 3x rate: 1 real minute = 3 Sesh minutes", style: TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _TierHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _TierHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15, left: 5),
      child: Row(
        children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
