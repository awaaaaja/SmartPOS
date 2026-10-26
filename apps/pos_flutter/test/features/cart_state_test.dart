import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/features/pos/pos_repository.dart';

void main() {
  CartLine line(int id, {int qty = 1, List<int> mods = const [], String note = ''}) =>
      CartLine(
        productId: id,
        productName: 'Menu $id',
        basePrice: 10000,
        qty: qty,
        modifierIds: mods,
        note: note,
      );

  test('item beda produk jadi baris terpisah', () {
    var cart = const CartState().add(line(1)).add(line(2));
    expect(cart.lines.length, 2);
    expect(cart.itemCount, 2);
  });

  test('item sama (produk+modifier+catatan) digabung, qty dijumlah', () {
    var cart = const CartState().add(line(1)).add(line(1, qty: 2));
    expect(cart.lines.length, 1);
    expect(cart.lines.first.qty, 3);
    expect(cart.itemCount, 3);
  });

  test('modifier berbeda tidak digabung', () {
    var cart = const CartState().add(line(1)).add(line(1, mods: const [7]));
    expect(cart.lines.length, 2);
  });

  test('urutan modifier tak mempengaruhi kunci gabung', () {
    var cart = const CartState()
        .add(line(1, mods: const [3, 5]))
        .add(line(1, mods: const [5, 3]));
    expect(cart.lines.length, 1);
    expect(cart.lines.first.qty, 2);
  });

  test('lineTotal memakai harga dasar + delta modifier', () {
    final l = CartLine(
      productId: 1,
      productName: 'x',
      basePrice: 10000,
      qty: 2,
      modifiers: const [
        {'price_delta': 2000},
        {'price_delta': 1000},
      ],
    );
    expect(l.unitPrice, 13000);
    expect(l.lineTotal, 26000);
  });

  test('changeQty minus nol pada qty 1 = baris dihapus', () {
    var cart = const CartState().add(line(1));
    cart = cart.changeQty(0, -1);
    expect(cart.isEmpty, isTrue);
  });

  test('changeQty keluar batas tidak crash', () {
    final cart = const CartState().add(line(1));
    expect(cart.changeQty(-1, 1).lines.length, 1);
    expect(cart.changeQty(5, 1).lines.length, 1);
  });

  test('discount disimpan dan estimatedSubtotal tidak berubah', () {
    var cart = const CartState().add(line(1, qty: 2));
    cart = cart.withDiscount(10);
    expect(cart.discountPct, 10);
    expect(cart.estimatedSubtotal, 20000);
  });

  test('clear mengosongkan keranjang', () {
    final cart = const CartState().add(line(1)).clear();
    expect(cart.isEmpty, isTrue);
    expect(cart.discountPct, 0);
  });
}
