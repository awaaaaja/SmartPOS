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

### Mutasi yang wajib idempotency key (S06, migrasi `0013`–`0014`)

| RPC | Signature | Params |
|---|---|---|
| `pos_refund` | `pos_refund(bigint, integer, text, text) -> jsonb` | `p_sale_id`, `p_amount`, `p_reason`, **`p_idempotency_key` (wajib, 8–128 char)** |
| `inv_adjust_stock` | `inv_adjust_stock(bigint, numeric, text, text, text, text) -> jsonb` | `p_ingredient_id`, `p_qty`, `p_unit`, `p_reason`, `p_source` (`ADJUSTMENT`/`WASTE`), **`p_idempotency_key` (wajib, 8–128 char)** |
| `inv_create_purchase` | `inv_create_purchase(text, jsonb, date, text, text) -> jsonb` | `p_supplier`, `p_items`, `p_purchased_at`, `p_status`, **`p_idempotency_key`** |
| `inv_produce_batch` | `inv_produce_batch(bigint, numeric, text, text) -> jsonb` | `p_product_id`, `p_qty_produced`, `p_note`, **`p_idempotency_key`** |
| `exp_save` (CREATE) | `exp_save(bigint, text, text, integer, text, date, text, text) -> jsonb` | `p_id=null`, `p_type`, `p_description`, `p_amount`, `p_kind`, `p_expense_date`, `p_evidence_url`, **`p_idempotency_key`** |
| `energy_save_estimate` | `energy_save_estimate(text, numeric, numeric, numeric, numeric, integer, numeric, numeric, integer, text, text) -> jsonb` | `p_kind`, `p_watt`, `p_hours`, `p_load_factor`, `p_tariff`, `p_refill_price`, `p_effective_hours`, `p_batch_hours`, `p_portions`, `p_note`, **`p_idempotency_key`** |

- Key tanpa baris → efek dieksekusi sekali dan respons disimpan di
  `mutation_requests` (private, tanpa RLS SELECT untuk klien) pada transaksi yang sama.
- Key sudah ada + payload identik → respons tersimpan dikembalikan,
  `idempotent_replay: true`; efek tidak diulang.
- Key sudah ada + payload berbeda (termasuk baris pembelian/tanggal/catatan) →
  exception `idempotency_key_conflict`, tanpa efek.
- Key hilang/pendek/terlalu panjang → `missing_idempotency_key` (jalur lama tanpa
  key ditutup; implementasi lama tersimpan sebagai `*_once` tanpa grant klien).
- Kunci diadopsi per `(operation, key)` + advisory lock transaksi sehingga
  permintaan serentak dengan key sama hanya meng-commit satu efek.
- Koreksi `ADJUSTMENT` boleh negatif (stok turun); `WASTE` selalu positif
  dan dikurangi server — validasi memakai magnitudo, bukan tanda.
- `exp_save` UPDATE (`p_id` terisi) tidak membutuhkan key/cache: menetapkan nilai
  baris yang sama aman diulang; edit berikutnya tetap diizinkan. CREATE dan UPDATE
  sama-sama memeriksa `is_operator()`. Replay CREATE mengembalikan snapshot awal,
  bukan hasil edit terbaru; muat ulang daftar sebelum mengedit.
- `mutation_run_once(text,text,jsonb,text)` adalah helper internal `0014`;
  anon/authenticated tidak boleh memanggilnya atau `*_once` secara langsung.
- Klien menyimpan key+payload sebelum RPC, memulihkan isian terkunci saat form
  dibuka ulang, dan membandingkan list/map secara mendalam. Satu slot pending per
  operator/operasi (produksi per produk). Tidak ada tombol buang pending: selesaikan
  replay dahulu; jangan clear data aplikasi untuk memaksa key baru.

### RPC lain dalam audit retry uang/stok

`pos_checkout` dan `qr_submit_draft` sudah mempunyai key sendiri.
`inv_receive_purchase`, `cash_shift_open`, `cash_shift_close` memakai lock/guard
status; retry bisa ditolak tetapi tidak menambah efek. `cost_allocate` memakai
upsert `(expense_id,target_ref)`; retry identik tidak menambah alokasi (dapat ditolak
validasi batas sumber). Master bahan/resep tidak diperlakukan sebagai ledger uang/stok.

## Keamanan

- `anon` tidak punya policy SELECT/INSERT apa pun pada tabel privat.
- `is_operator()` dan `get_public_menu()` adalah SECURITY DEFINER; `is_operator()`
  hanya dieksekusi `authenticated`.
- Kunci `service_role` tidak pernah dikirim ke Flutter/web.
- **Guard seragam (migrasi 0015)**: SETIAP RPC yang dipanggil langsung oleh
  klien memeriksa `is_operator()` di baris pertama dan menolak non-operator
  dengan `operator_required` (errcode `42501`). Ini menutup celah bahwa fungsi
  `SECURITY DEFINER` melewati RLS — sebelumnya akun `authenticated` kedua bisa
  memanggil RPC Sprint 02-05 via PostgREST. Daftar RPC ber-guard:
  `pos_quote`, `pos_checkout`, `pos_sale_receipt`, `pos_dashboard_summary`,
  `qr_list_drafts`, `qr_claim_draft`, `qr_cancel_draft`, `qr_complete_draft`,
  `qr_create_table`, `qr_rotate_token`, `inv_save_ingredient`,
  `inv_receive_purchase`, `inv_save_recipe`, `inv_hpp`, `cost_allocate`,
  `cash_shift_status`, `cash_shift_open`, `cash_shift_close`, `pos_reports`
  (ditambah `pos_refund`, `inv_adjust_stock`, `inv_create_purchase`,
  `inv_produce_batch`, `exp_save`, `energy_save_estimate` dari 0013/0014).
- Helper internal `pos_line_total`, `qr_draft_json`, dan `hash_table_token`
  dicabut grant-nya dari semua role klien; hanya dipanggil dari dalam fungsi
  `SECURITY DEFINER` lain (termasuk jalur anon `qr_submit_draft`). Badan lama
  RPC yang dibungkus tersimpan sebagai `*_impl` tanpa grant klien.
- Jalur publik anon tidak terpengaruh: `get_public_menu` dan `qr_submit_draft`
  tetap berjalan (dikuji `test_mutation_retry.py`).
