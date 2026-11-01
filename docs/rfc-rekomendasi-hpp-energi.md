# RFC — Rekomendasi Non-ML: Peringatan HPP & Kalibrasi Kalkulator Energi

- **Status:** DISETUJUI, diimplementasikan (Fase R1)
- **Tanggal:** 1 November 2026
- **Migrasi:** `20261101000020_recommendations.sql` (RPC `inv_hpp_alerts`, `exp_energy_calibration`)
- **Terbit dari:** analisa "HPP & Kalkulator Energi berpengaruh kemana → bisa jadi rekomendasi ML?"
- **Guardrail:** PRD §9 — tanpa ML di klien, tanpa prediksi, hanya statistik deskriptif

---

## 1. Ringkasan

Membangun dua **rekomendasi non-ML** yang memakai data yang sudah ada
(HPP resep aktif, pembelian bahan, biaya ESTIMATED/ACTUAL) untuk memberi
operator dua sinyal yang bisa ditindaklanjuti, **tanpa model, tanpa
prediksi, tanpa otomasi belanja**:

1. **R1-01 `inv_hpp_alerts`** — bahan yang harganya menyimpang dari
   rata-rata pembelian N hari terakhir, beserta **dampak per porsi** pada
   setiap menu yang memakai bahan itu di resep aktif.
2. **R1-02 `exp_energy_calibration`** — apakah kalkulator energi meleset
   dari tagihan asli (ESTIMATED vs ACTUAL) pada rentang tanggal, dengan
   **faktor koreksi** yang disarankan.

Keduanya murni **baca-saja** (tidak mengubah uang/stok), berjalan di server
(`SECURITY DEFINER` + guard `is_operator`), dan tidak menampilkan angka
karangan — tanpa pembanding berarti **tidak ditampilkan** (lihat §4).

## 2. Latar & pertanyaan yang dijawab

Analisa pengaruh fitur HPP dan Kalkulator Energi menemukan dua titik yang
layak jadi rekomendasi (bukan prediksi):

- **HPP** mengalir: resep aktif → potong stok saat bayar →
  `hpp_ingredient_cost` → Dashboard/Laporan → `operatingMarginEstimate`.
  Ketika harga bahan berubah, HPP per porsi ikut berubah — operator perlu
  tahu **mana bahan yang naik dan berapa dampaknya per menu**, bukan hanya
  angka total.
- **Kalkulator energi** menghasilkan biaya ESTIMATED yang **tidak pernah**
  mengurangi margin (hanya ACTUAL yang mengurangi). Pertanyaannya: apakah
  asumsi kalkulator meleset dari tagihan nyata? Jika ya, berapa faktor
  koreksinya?

## 3. Keputusan desain

| Aspek | Keputusan | Alasan |
|---|---|---|
| Pembanding HPP | **Rata-rata tertimbang** (`sum total / sum qty`) pembelian `RECEIVED` dalam jendela | Rerata baris menyetarakan pembelian besar & kecil; tertimbang mencerminkan harga beli sesungguhnya |
| Sumber riwayat | Hanya `purchases.status = 'RECEIVED'` | `ORDERED` belum menambah saldo/unit_cost; memasukkannya menyesatkan |
| Tanpa riwayat | Bahan **tidak masuk** daftar peringatan | "Belum ada pembanding" ≠ deviasi 0; jangan menampilkan angka palsu |
| Deviasi kalibrasi | Hanya dari **jenis yang punya KEDUA sisi** (`estimated > 0` **dan** `actual > 0`) | Mencampur jenis yang belum punya tagihan asli mengencerkan deviasi (dibuktikan saat pengujian: LPG tanpa tagihan membuat deviasi listrik +11% tampak −43%) |
| Field pembanding | `compared_estimated` / `compared_actual` terpisah dari `estimated_total` / `actual_total` | Total = seluruh data (untuk tampilan); pembanding = subset seimbang (untuk deviasi/faktor) — dua makna berbeda, jangan digabung buta |
| Tanpa tagihan asli | `enough_data = false`, deviasi/faktor `null` | Bukan nol karangan; tampil "belum ada tagihan asli" |
| Alokasi | Hanya `LISTRIK` dan `LPG` | Jenis lain (AIR/SEWA/KEMASAN/INTERNET/LAINNYA) tidak punya kalkulator; mencampurnya tidak berarti |
| Batas jendela | `p_window_days` 7–730 (default 90); kalibrasi default 30 hari WIB inklusif | Mencegah kueri mahal & jendela nol hari |
| Batas threshold | `p_threshold_pct` 1–500 (default 10) | Di luar itu tidak masuk akal sebagai "peringatan" |
| Otomasi belanja | **DITOLAK** | PRD melarang tindakan otomatis tanpa persetujuan operator; rekomendasi hanya menampilkan saran |

## 4. Kontrak keluaran (jujur terhadap data)

**`inv_hpp_alerts(p_threshold_pct, p_window_days) -> jsonb`**

```
{
  "threshold_pct": 10, "window_days": 90,
  "alerts": [{
    "ingredient_id": 1, "name": "Cabai", "base_unit": "g",
    "unit_cost": 2000, "avg_cost": 1667, "delta_pct": 20.0,
    "direction": "NAIK", "purchases": 2,
    "products": [{"product_id": 1, "product_name": "Nasi Goreng",
                  "hpp_delta_per_portion": 66667.0}]
  }]
}
```

- `avg_cost` = rata-rata **tertimbang** pembelian `RECEIVED` (dibulatkan).
- `delta_pct` = penyimpangan `unit_cost` vs `avg_cost`, ≥ threshold.
- `hpp_delta_per_portion` = selisih harga per satuan dasar × qty resep ÷
  yield (rupiah per porsi, memakai satuan dasar yang sama).
- `direction` = `NAIK` | `TURUN` (turun pun dilaporkan — bukan hanya masalah).

**`exp_energy_calibration(p_from, p_to) -> jsonb`**

```
{
  "d_from": "2026-10-03", "d_to": "2026-11-01",
  "estimated_total": 5630, "actual_total": 3200,
  "compared_estimated": 2880, "compared_actual": 3200,
  "deviation_pct": 11.1, "suggested_factor": 1.111,
  "enough_data": true,
  "by_type": [{"type": "LISTRIK", "estimated": 2880, "actual": 3200,
               "estimated_count": 1, "actual_count": 1,
               "deviation_pct": 11.1, "suggested_factor": 1.111}]
}
```

- `deviation_pct` & `suggested_factor` dihitung **hanya** dari subset
  `compared_*` (jenis dengan dua sisi > 0).
- `by_type[].deviation_pct` = null untuk jenis tanpa tagihan asli
  (mis. LPG) — tampil jujur, tidak dihitung buta.

## 5. Bukti saat pengujian (fixture lokal, DB polos)

Deviasi campur-jenis ditemukan & diperbaiki sebelum rilis:

- **Sebelum perbaikan:** listrik ESTIMATED 2.880 / ACTUAL 3.200 (+11,1%) +
  LPG ESTIMATED 2.750 tanpa tagihan → deviasi dilaporkan **−43,2%** dan
  faktor 0,568 (menyesatkan — LPG "mengencerkan" listrik).
- **Sesudah perbaikan:** deviasi **+11,1%**, faktor **1,111**, dari
  `compared_*` = 2.880 → 3.200 (listrik saja); LPG tetap tampil di
  `by_type` dengan deviasi `null`.

Peringatan HPP terverifikasi: bahan dengan 2 pembelian (2 g Rp3.000 +
10 g Rp17.000 → tertimbang 1.667) dinaikkan ke 2.000 → `delta_pct` 20.0,
`direction` NAIK, dampak per porsi 66.667 (yield 2, qty 400 g). Threshold
500% → daftar kosong.

## 6. Keamanan

- Kedua fungsi `SECURITY DEFINER set search_path = public` + guard
  `is_operator()` (pola 0015/0019); `operator_required` errcode `42501`.
- Grant: hanya `authenticated`; di-`revoke` dari `public`, `anon`.
- Verifikasi hosted: anon → **401**; operator → 200 dengan output jujur
  (daftar kosong / `enough_data: false` bila belum ada data).

## 7. Batasan yang diakui (jujur)

- Ini **statistik deskriptif**, bukan prediksi. Tidak ada klaim "besok
  harga naik" — hanya "harga sekarang menyimpang dari rata-rata pembelian".
- `hpp_delta_per_portion` memakai `unit_cost` terkini vs rata-rata
  pembelian; bila pembelian terakhir sudah lama, pembandingnya juga tua
  (itu sebabnya jendela `window_days` dibatasi).
- Kalibrasi hanya bermakna bila tagihan asli benar-benar dicatat sebagai
  `ACTUAL`. Estimasi tanpa tagihan = `enough_data: false`, bukan nol.
- Tidak ada library ML di klien maupun server; tidak ada training/inferensi
  di mana pun (PRD §9).

## 8. Rencana lanjut (B2 — kandidat sekunder, belum dikerjakan)

Proyeksi kebutuhan energi masa depan (mis. "bulan depan listrik ± RpX")
terdaftar sebagai **kandidat sekunder** di `docs/ml-roadmap.md` — hanya
layak setelah ada ≥ 3 bulan tagihan ACTUAL tercatat, dan tetap harus
melewati amendemen PRD §9 (guardrail §7 roadmap) sebelum kode model masuk.
