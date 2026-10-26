import 'package:flutter/foundation.dart';

/// Model transaksi POS. Semua uang integer Rupiah; hasil server yang final.
@immutable
class Quote {
  const Quote({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceAmount,
    required this.total,
  });

  final int subtotal;
  final int discountAmount;
  final int taxAmount;
  final int serviceAmount;
  final int total;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        subtotal: json['subtotal'] as int,
        discountAmount: json['discount_amount'] as int,
        taxAmount: json['tax_amount'] as int,
        serviceAmount: json['service_amount'] as int,
        total: json['total'] as int,
      );
}

@immutable
class ReceiptItem {
  const ReceiptItem({
    required this.productName,
    required this.unitPrice,
    required this.qty,
    this.note,
    this.modifiers = const [],
  });

  final String productName;
  final int unitPrice;
  final int qty;
  final String? note;

  /// Snapshot modifier: [{modifier_id, name, price_delta}].
  final List<Map<String, dynamic>> modifiers;

  int get lineTotal => unitPrice * qty;

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
        productName: json['product_name'] as String,
        unitPrice: json['unit_price'] as int,
        qty: json['qty'] as int,
        note: json['note'] as String?,
        modifiers: ((json['modifiers'] as List<dynamic>?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

@immutable
class Receipt {
  const Receipt({
    required this.saleId,
    required this.receiptNo,
    required this.createdAt,
    required this.status,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceAmount,
    required this.total,
    required this.refundAmount,
    required this.items,
    this.method,
    this.paid,
    this.changeAmount,
    this.diningType,
    this.idempotentReplay = false,
    this.refunds = const [],
  });

  final int saleId;
  final String receiptNo;
  final DateTime createdAt;
  final String status;
  final int subtotal;
  final int discountAmount;
  final int taxAmount;
  final int serviceAmount;
  final int total;
  final int refundAmount;
  final List<ReceiptItem> items;
  final String? method;
  final int? paid;
  final int? changeAmount;
  final String? diningType;
  final bool idempotentReplay;
  final List<Map<String, dynamic>> refunds;

  factory Receipt.fromJson(Map<String, dynamic> json) {
    final payment = json['payment'];
    return Receipt(
      saleId: json['sale_id'] as int,
      receiptNo: json['receipt_no'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String,
      subtotal: json['subtotal'] as int,
      discountAmount: json['discount_amount'] as int,
      taxAmount: json['tax_amount'] as int,
      serviceAmount: json['service_amount'] as int,
      total: json['total'] as int,
      refundAmount: (json['refund_amount'] as int?) ?? 0,
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .map((e) => ReceiptItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      method: payment is Map ? payment['method'] as String? : null,
      paid: payment is Map ? payment['paid'] as int? : null,
      changeAmount:
          payment is Map ? payment['change_amount'] as int? : null,
      diningType: json['dining_type'] as String?,
      idempotentReplay: (json['idempotent_replay'] as bool?) ?? false,
      refunds: ((json['refunds'] as List<dynamic>?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

@immutable
class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.receiptNo,
    required this.status,
    required this.total,
    required this.refundAmount,
    required this.createdAt,
    this.method,
  });

  final int id;
  final String receiptNo;
  final String status;
  final int total;
  final int refundAmount;
  final DateTime createdAt;
  final String? method;

  factory SaleSummary.fromJson(Map<String, dynamic> json) => SaleSummary(
        id: json['id'] as int,
        receiptNo: json['receipt_no'] as String,
        status: json['status'] as String,
        total: json['total'] as int,
        refundAmount: (json['refund_amount'] as int?) ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        method: ((json['payments'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>?>()
            .firstOrNull?['method'] as String?,
      );
}

@immutable
class DashboardSummary {
  const DashboardSummary({
    required this.todayRevenue,
    required this.todayTransactions,
    required this.todayRefunds,
    required this.allTimeRevenue,
    required this.allTimeTransactions,
  });

  final int todayRevenue;
  final int todayTransactions;
  final int todayRefunds;
  final int allTimeRevenue;
  final int allTimeTransactions;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        todayRevenue: (json['today_revenue'] as num?)?.toInt() ?? 0,
        todayTransactions:
            (json['today_transactions'] as num?)?.toInt() ?? 0,
        todayRefunds: (json['today_refunds'] as num?)?.toInt() ?? 0,
        allTimeRevenue: (json['all_time_revenue'] as num?)?.toInt() ?? 0,
        allTimeTransactions:
            (json['all_time_transactions'] as num?)?.toInt() ?? 0,
      );
}
