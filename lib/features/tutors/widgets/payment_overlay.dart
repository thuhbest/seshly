import 'package:flutter/material.dart';

class PaymentOverlay extends StatefulWidget {
  final String packageName, price;
  const PaymentOverlay({super.key, required this.packageName, required this.price});

  @override
  State<PaymentOverlay> createState() => _PaymentOverlayState();
}

class _PaymentOverlayState extends State<PaymentOverlay> {
  bool _isProcessing = false;

  void _processPayment() async {
    setState(() => _isProcessing = true);
    await Future.delayed(const Duration(seconds: 2)); // Mock delay
    if (mounted) Navigator.pop(context);
    // Add success snackbar here
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