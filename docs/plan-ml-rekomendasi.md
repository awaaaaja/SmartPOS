# Rencana Konkret: Rekomendasi Non-ML (Peringatan HPP + Kalibrasi Energi)

Status: **RENCANA — EKSEKUSI SELESAI (1 Nov 2026).**
RFC: `docs/rfc-rekomendasi-hpp-energi.md`.
Migrasi: `supabase/migrations/20261101000020_recommendations.sql`.

Bagian ini adalah rencana + bukti eksekusi Fase R1: dua rekomendasi
**non-ML** yang memakai data HPP & biaya yang sudah ada, tanpa model,
tanpa prediksi, tanpa otomasi belanja (PRD §9 & guardrail `ml-roadmap.md` §7).

## Status eksekusi

| Bagian | Status |
|---|---|
| SQL: `inv_hpp_alerts` + `exp_energy_calibration` (0020) | **SELESAI** — 20 migrasi lulus di Postgres polos (Zonky lokal port 54339); `SECURITY DEFINER` + guard `is_operator`, grant hanya `authenticated` |
| Perbaikan deviasi seimbang (`compared_estimated`/`compared_actual`) | **SELESAI** — deviasi/faktor kini hanya dari jenis dengan dua sisi > 0; bug deviasi campur-jenis (LPG tanpa tagihan mengencerkan listrik) ditemukan saat uji fixture & diperbaiki sebelum rilis |
| Test integrasi `tests/integration/test_recommendations.py` | **SELESAI** — 7 test lulus lokal (psycopg2 + psql shim); wired ke CI job `migrations` |
| Terapkan 0020 ke hosted | **SELESAI** — psycopg2 via `Kredensial.md` (password tidak dicetak); tercatat di `supabase_migrations.schema_migrations` (`20261101000020`); REST smoke: operator 200 (output jujur), anon 401 |
| Flutter: model+provider `hppAlerts`/`energyCalibration` + kartu UI | **SELESAI** — `inventory_repository.dart` (model `HppAlert`/`HppAlerts` + `hppAlertsProvider`), `operating_repository.dart` (model `EnergyCalibration`/`ByType` + `energyCalibrationProvider`), kartu di `recipes_page.dart` & `energy_page.dart`; analyzer 0 |
| Test Flutter: override provider baru | **SELESAI** — `page_layout_test.dart` (state loading/error/empty), `inventory_pages_test.dart`; suite **195/195** |
| Dokumen: RFC, roadmap kandidat sekunder, amendemen PRD §9, api-contracts, sprint-log | **SELESAI** — lihat bagian "Dokumen" di bawah |

## Fakta codebase (dasar keputusan)

- Uang selalu **integer Rupiah**; total dihitung server-side.
- `inv_create_purchase` menulis `purchase_items.qty` (satuan dasar) dan
  `unit_cost` (harga per satuan dasar) — cukup untuk rata-rata tertimbang.
- `purchases.status` `ORDERED` → `RECEIVED` (guard `inv_receive_purchase`);
  hanya `RECEIVED` yang mengubah `unit_cost` bahan.
- `expenses.kind` `ESTIMATED` vs `ACTUAL` dipisah sejak migrasi `0012`;
  `energy_save_estimate` selalu `ESTIMATED` — tidak pernah otomatis aktual.
- Pola guard operator: `SECURITY DEFINER set search_path = public` +
  `is_operator()` + `operator_required` (errcode `42501`), grant hanya
  `authenticated` (pola 0015/0019).

## SQL (migrasi 0020)

### `inv_hpp_alerts(p_threshold_pct integer default 10, p_window_days integer default 90)`

- Guard: `threshold` 1–500, `window` 7–730 (selain itu `invalid_*`).
- Riwayat = `purchase_items` gabung `purchases` **RECEIVED**, `purchased_at >= (WIB hari ini − window)`; per bahan: `avg_cost = sum(qty*unit_cost)/sum(qty)` (tertimang), `purchases = count(distinct purchase_id)`.
- Peringatan bila `unit_cost` sekarang (bahan pada resep aktif) menyimpang
  `>= threshold%` dari `avg_cost`; **tanpa riwayat → tidak masuk daftar**.
- Dampak per porsi per menu: `qty resep × (unit_cost − avg_cost) / yield_qty`
  (satuan dasar sama), dari `recipe_versions.is_active`.
- Urut: `abs(delta_pct) DESC, name`.

### `exp_energy_calibration(p_from date default null, p_to date default null)`

- Default: 30 hari WIB inklusif (`d_to − 29` … `d_to`); `invalid_range`
  bila `from > to`; `range_too_long` bila span > 730 hari.
- Per jenis (`LISTRIK`/`LPG`): `estimated`/`actual` (sum `amount` per
  `kind`) + jumlah baris; per jenis juga `deviation_pct`/`suggested_factor`
  **hanya bila dua sisi > 0**, selain itu `null`.
- Agregat: `estimated_total`/`actual_total` = seluruh data (tampilan);
  `compared_estimated`/`compared_actual` = subset seimbang;
  `deviation_pct`/`suggested_factor` global dihitung dari subset itu;
  `enough_data = (compared dua sisi > 0)`.

### Grants

`revoke ... from public, anon` + `grant execute ... to authenticated`
untuk kedua fungsi (pola 0019).

## Test integrasi (`tests/integration/test_recommendations.py`)

Pola sama dengan `test_mutation_retry.py` (DB sementara + stub + semua
migrasi + `set role authenticated` + klaim operator), 7 test:

1. `test_hpp_alert_weighted_avg_and_impact` — 2 pembelian RECEIVED
   (2 g Rp3.000 + 10 g Rp17.000 → tertimbang 1.667), unit_cost dinaikkan
   ke 2.000 → `delta_pct` 20.0, `direction` NAIK, `purchases` 2, dampak
   per porsi 66.667 (yield 2, qty 400 g).
2. `test_hpp_alert_threshold_too_high_is_empty` — threshold 500 → `[]`.
3. `test_hpp_alert_rejects_out_of_range_params` — threshold 0 / window 6
   ditolak (`invalid_*`).
4. `test_energy_calibration_balanced_subset_only` — listrik 2.880/3.200
   (+11,1%, faktor 1,111, `compared_*` 2.880→3.200) + LPG 2.750 ESTIMATED
   tanpa ACTUAL → `by_type['LPG'].deviation_pct == None` (bukan 0),
   `estimated_total` 5.630 (tampilan), `enough_data` true.
5. `test_energy_calibration_empty_range_is_honest_null` — rentang 2020 →
   `enough_data` false, deviasi/faktor `null`, `by_type` `[]`.
6. `test_energy_calibration_rejects_inverted_range` — `from > to` ditolak.
7. `test_non_operator_rejected` — role `authenticated` tanpa klaim operator
   → `operator_required` (42501).

Jalankan lokal: `export OPERATOR_PASSWORD=...` tidak diperlukan (klaim
JWT dipalsukan); cukup `DATABASE_URL` + `psql` (CI sudah punya).

## Flutter

- `inventory_repository.dart`: class `HppAlertProduct`, `HppAlert`,
  `HppAlerts` + method `fetchHppAlerts()` (RPC `inv_hpp_alerts`) +
  `hppAlertsProvider`.
- `operating_repository.dart`: class `EnergyCalibration`,
  `EnergyCalibrationByType` + method `energyCalibration()` (RPC
  `exp_energy_calibration`) + `energyCalibrationProvider`.
- `recipes_page.dart`: kartu ringkas collapsible `_HppAlertsCard` (arah +
  persen + dampak per porsi per menu; empty state sunyi bila tidak ada
  peringatan).
- `energy_page.dart`: kartu `_EnergyCalibrationCard` (deviasi + faktor
  koreksi + daftar jenis tanpa tagihan asli; saran-tampilan saja, biaya
  aktual tetap yang mengurangi margin).
- Test: override kedua provider baru di `page_layout_test.dart`
  (loading/error/empty) dan `inventory_pages_test.dart`.

## Dokumen

| Dokumen | Perubahan |
|---|---|
| `docs/rfc-rekomendasi-hpp-energi.md` | RFC desain (keputusan, kontrak, bukti fixture, batasan jujur) |
| `docs/ml-roadmap.md` | §2b kandidat sekunder A2/B1 (live non-ML) + B2 (menunggu) + catatan status amendemen di §7 |
| `PRD.md` §9.0a | Amendemen tertulis: statistik non-ML diperbolehkan; panggung ML tetap tertutup sampai amendemen berikutnya + guardrail §7 terpenuhi |
| `docs/api-contracts.md` | Kontrak dua RPC baru (parameter, output, guard) |
| `docs/sprint-log.md` | Entri Fase R1 (migrasi + test + hosted) |

## Risiko & mitigasi

| Risiko | Mitigasi |
|---|---|
| Angka menyesatkan saat data tidak seimbang | Deviasi/faktor hanya dari subset `compared_*`; tanpa tagihan asli → `enough_data` false + `null` (bukan 0) |
| Riwayat pembelian palsu dari ORDERED | Hanya `RECEIVED` yang dihitung |
| Rerata baris menyetarakan pembelian kecil/besar | Rata-rata **tertimbang** `sum total / sum qty` |
| Kueri mahal pada jendela besar | Batas `window` 7–730 hari, `threshold` 1–500% |
| Data sensitif (harga beli, biaya) bocor ke anon | `SECURITY DEFINER` + `is_operator` + grant hanya `authenticated`; anon 401 terverifikasi |
| Operator salah baca sebagai prediksi | Label UI "ini statistik, bukan prediksi"; saran-tampilan, biaya tetap yang mengurangi margin |
