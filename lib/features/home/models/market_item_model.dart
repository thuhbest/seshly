import 'package:cloud_firestore/cloud_firestore.dart';

class MarketItem {
  final String id;
  final String title;
  final String description;
  final int price;
  final String currency;
  final String sellerId;
  final String sellerName;
  final String category;
  final bool isDigital;
  final String? imageUrl;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String status;
  final Timestamp? createdAt;

  MarketItem({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.currency,
    required this.sellerId,
    required this.sellerName,
    required this.category,
    required this.isDigital,
    required this.imageUrl,
    required this.fileUrl,
    required this.fileName,
    required this.fileType,
    required this.status,
    required this.createdAt,
  });

  factory MarketItem.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final dynamic rawPrice = data['price'];
    int parsedPrice = 0;
    if (rawPrice is num) {
      parsedPrice = rawPrice.toInt();
    } else if (rawPrice is String) {
      final cleaned = rawPrice.replaceAll(RegExp(r'[^0-9]'), '');
      parsedPrice = int.tryParse(cleaned) ?? 0;
    }
    return MarketItem(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString(),
      price: parsedPrice,
      currency: (data['currency'] ?? 'ZAR').toString(),
      sellerId: (data['sellerId'] ?? '').toString(),
      sellerName: (data['sellerName'] ?? 'Student').toString(),
      category: (data['category'] ?? 'Other').toString(),
      isDigital: data['isDigital'] == true,
      imageUrl: data['imageUrl'] as String?,
      fileUrl: data['fileUrl'] as String?,
      fileName: data['fileName'] as String?,
      fileType: data['fileType'] as String?,
      status: (data['status'] ?? 'active').toString(),
      createdAt: data['createdAt'] as Timestamp?,
    );
  }

  String get priceLabel {
    if (currency == 'ZAR' || currency == 'R') {
      return "R$price";
    }
    return "$currency $price";
  }
}
