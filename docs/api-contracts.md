# API Contracts

Kontrak antarmuka data. Backend authoritative = Postgres (lihat decision-log D-01).
Frontend tidak pernah mengirim harga/total sebagai otoritas.

## Publik (tanpa sesi, via anon key)

### `rpc get_public_menu(p_table_token text) -> jsonb`

Menu aktif untuk satu meja. Token salah/dirotasi → exception `invalid_table_token`.

```json
{
  "table": { "id": 1, "label": "Meja 01" },
  "categories": [
    {
      "id": 1, "name": "Makanan",
      "products": [
        {
          "id": 3, "name": "Ayam Kremes", "price": 18000, "photo_url": null,
          "modifiers": [
            { "id": 1, "name": "Sambal ekstra", "price_delta": 2000,
              "min_select": 0, "max_select": 2 }
          ]
        }
      ]
    }
  ]
}
```

- `price` = integer Rupiah (harga aktif saat dibaca; checkout dihitung ulang di server).
- Produk non-aktif/terarsip dan kategori kosong tidak ikut.
- Endpoint QR draft (`POST public/qr-drafts`) dibangun Sprint 03.

## Operator (sesi login, via authenticated + RLS)

- Tabel privat: `business_settings`, `product_categories`, `products`,
  `product_price_history`, `modifiers`, `product_modifiers`, `dining_tables`.
- Semua operasi lewat RLS `operator_all` (hanya email di `business_settings.operator_email`).
- Perubahan `products.price` otomatis mencatat `product_price_history`
  (trigger `trg_products_price_history`), termasuk pelaku (`auth.uid()`).
- Quote/checkout/refund/stok: Sprint 02–04, dipindahkan ke fungsi RPC atomik
  dengan idempotency key (belum ada di Sprint 01).

### Mutasi yang wajib idempotency key (S06, migrasi `0013`)

| RPC | Signature | Params |
|---|---|---|
| `pos_refund` | `pos_refund(bigint, integer, text, text) -> jsonb` | `p_sale_id`, `p_amount`, `p_reason`, **`p_idempotency_key` (wajib, 8–128 char)** |
| `inv_adjust_stock` | `inv_adjust_stock(bigint, numeric, text, text, text, text) -> jsonb` | `p_ingredient_id`, `p_qty`, `p_unit`, `p_reason`, `p_source` (`ADJUSTMENT`/`WASTE`), **`p_idempotency_key` (wajib, 8–128 char)** |

- Key tanpa baris → efek dieksekusi sekali dan respons disimpan di
  `mutation_requests` (private, tanpa RLS SELECT untuk klien) pada transaksi yang sama.
- Key sudah ada + payload identik → respons tersimpan dikembalikan,
  `idempotent_replay: true`; efek tidak diulang.
- Key sudah ada + payload berbeda (target/qty/unit/reason/sumber) →
  exception `idempotency_key_conflict`, tanpa efek.
- Key hilang/pendek/terlalu panjang → `missing_idempotency_key` (jalur lama tanpa
  key ditutup; implementasi lama tersimpan sebagai `pos_refund_once` /
  `inv_adjust_stock_once` tanpa grant).
- Kunci diadopsi per `(operation, key)` + advisory lock transaksi sehingga
  permintaan serentak dengan key sama hanya meng-commit satu efek.
- Koreksi `ADJUSTMENT` boleh negatif (stok turun); `WASTE` selalu positif
  dan dikurangi server — validasi memakai magnitudo, bukan tanda.

## Keamanan

- `anon` tidak punya policy SELECT/INSERT apa pun pada tabel privat.
- `is_operator()` dan `get_public_menu()` adalah SECURITY DEFINER; `is_operator()`
  hanya dieksekusi `authenticated`.
- Kunci `service_role` tidak pernah dikirim ke Flutter/web.
