import 'package:flutter/foundation.dart';

/// Model katalog dari Supabase (tabel products, product_categories, modifiers).
@immutable
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.archivedAt,
  });

  final int id;
  final String name;
  final int sortOrder;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  factory ProductCategory.fromJson(Map<String, dynamic> json) =>
      ProductCategory(
        id: json['id'] as int,
        name: json['name'] as String,
        sortOrder: (json['sort_order'] as int?) ?? 0,
        archivedAt: json['archived_at'] == null
            ? null
            : DateTime.parse(json['archived_at'] as String),
      );
}

@immutable
class Modifier {
  const Modifier({
    required this.id,
    required this.name,
    this.priceDelta = 0,
    this.isActive = true,
    this.minSelect = 0,
    this.maxSelect = 1,
  });

  final int id;
  final String name;
  final int priceDelta;
  final bool isActive;

  /// Batas pilihan bila terkait ke produk tertentu (varian/topping).
  final int minSelect;
  final int maxSelect;

  factory Modifier.fromJson(Map<String, dynamic> json) => Modifier(
        id: json['id'] as int,
        name: json['name'] as String,
        priceDelta: (json['price_delta'] as int?) ?? 0,
        isActive: (json['is_active'] as bool?) ?? true,
        minSelect: (json['min_select'] as int?) ?? 0,
        maxSelect: (json['max_select'] as int?) ?? 1,
      );
}

@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.categoryId,
    this.categoryName,
    this.photoUrl,
    this.isActive = true,
    this.archivedAt,
    this.modifiers = const [],
  });

  final int id;
  final String name;
  final int price;
  final int? categoryId;
  final String? categoryName;
  final String? photoUrl;
  final bool isActive;
  final DateTime? archivedAt;
  final List<Modifier> modifiers;

  bool get isArchived => archivedAt != null;
  bool get sellable => isActive && !isArchived;

  factory Product.fromJson(Map<String, dynamic> json) {
    final links = (json['product_modifiers'] as List<dynamic>?) ?? const [];
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      price: json['price'] as int,
      categoryId: json['category_id'] as int?,
      categoryName:
          (json['category'] as Map<String, dynamic>?)?['name'] as String?,
      photoUrl: json['photo_url'] as String?,
      isActive: (json['is_active'] as bool?) ?? true,
      archivedAt: json['archived_at'] == null
          ? null
          : DateTime.parse(json['archived_at'] as String),
      modifiers: links
          .map((l) {
            final map = l as Map<String, dynamic>;
            final mod = map['modifier'] as Map<String, dynamic>?;
            if (mod == null) return null;
            return Modifier.fromJson({
              ...mod,
              'min_select': map['min_select'],
              'max_select': map['max_select'],
            });
          })
          .whereType<Modifier>()
          .toList(),
    );
  }
}

@immutable
class PriceHistoryEntry {
  const PriceHistoryEntry({
    required this.oldPrice,
    required this.newPrice,
    required this.effectiveAt,
    this.reason,
  });

  final int oldPrice;
  final int newPrice;
  final DateTime effectiveAt;
  final String? reason;

  factory PriceHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PriceHistoryEntry(
        oldPrice: json['old_price'] as int,
        newPrice: json['new_price'] as int,
        effectiveAt: DateTime.parse(json['effective_at'] as String),
        reason: json['reason'] as String?,
      );
}
