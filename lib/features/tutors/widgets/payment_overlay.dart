import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentOverlay extends StatefulWidget {
  final String packageName;
  final String price;
  final int minutes;
  const PaymentOverlay({
    super.key,
    required this.packageName,
    required this.price,
    required this.minutes,
  });

  @override
  State<PaymentOverlay> createState() => _PaymentOverlayState();
}

class _PaymentOverlayState extends State<PaymentOverlay> {
  bool _isProcessing = false;

  void _processPayment() async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2)); // Mock delay
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to recharge.')),
        );
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'seshMinutes': FieldValue.increment(widget.minutes),
      }, SetOptions(merge: true));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Added ${widget.minutes} Sesh Minutes.')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recharge failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color tealAccent = Color(0xFF00C09E);

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: const BoxDecoration(
        color: Color(0xFF1E243A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 25),
          const Text("Confirm Purchase", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text("You are purchasing the ${widget.packageName} package", style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 30),
          _buildDetailRow("Package", widget.packageName),
          _buildDetailRow("Total Price", widget.price, isTotal: true),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _processPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: tealAccent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: _isProcessing 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Color(0xFF0F142B), strokeWidth: 2))
                : Text("Pay ${widget.price}", style: const TextStyle(color: Color(0xFF0F142B), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 15),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 15)),
          Text(value, style: TextStyle(color: isTotal ? Colors.white : Colors.white70, fontWeight: isTotal ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
        ],
      ),
    );
  }
}
