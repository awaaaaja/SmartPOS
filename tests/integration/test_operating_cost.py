#!/usr/bin/env python3
"""Uji biaya operasional/kas/laporan Sprint 05 langsung ke Supabase asli.

Cara jalankan:
  python3 tests/integration/test_operating_cost.py

Menguji (S05-01…S05-09 / UAT-09..11):
  - UAT-09 rumus listrik: kWh = watt x jam x load% / 100 / 1000
  - UAT-09 rumus LPG: (isi_ulang / jam_efektif) x jam_batch
  - estimasi selalu tersimpan sebagai ESTIMATED, tidak otomatis aktual
  - alokasi total <= sumber biaya; melebihi ditolak server (UAT-10)
  - kas: hanya pembayaran CASH menambah expected; selisih benar (UAT-11)
  - laporan: refund mengurangi net sales; nilai cocok DB
  - anon tidak bisa membaca/menulis tabel biaya/kas
"""
import json
import os
import urllib.request
import uuid

URL = os.environ.get(
    "SUPABASE_URL", "https://hdvscajiezznyiwmkjjv.supabase.co")
KEY = os.environ.get(
    "SUPABASE_PUBLISHABLE_KEY",
    "sb_publishable_OpvLMVvQLqYnNyaHCjyRiA_ekFP6HBK")
OPERATOR_EMAIL = os.environ.get("OPERATOR_EMAIL", "operator@mejeng.id")
OPERATOR_PASSWORD = os.environ["OPERATOR_PASSWORD"]

passed = 0
failed = 0


def req(path, token=None, body=None, method=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(
        URL + path, data=data, method=method or ("POST" if data else "GET"))
    r.headers["apikey"] = KEY
    r.headers["Content-Type"] = "application/json"
    if token:
        r.headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def rpc(token, name, body):
    return req(f"/rest/v1/rpc/{name}", token, body)


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS  {name}")
    else:
        failed += 1
        print(f"FAIL  {name}  {extra}")


def err_code(body):
    """Ambil message dari error PostgREST (P0001 -> pesan kita)."""
    if isinstance(body, dict):
        return body.get("message", "")
    return str(body)


def main():
    status, body = req("/auth/v1/token?grant_type=password", body={
        "email": OPERATOR_EMAIL, "password": OPERATOR_PASSWORD})
    check("login operator", status == 200, str(body)[:200])
    token = body["access_token"]

    # ------------------------------------------------------------------
    print("\n== S05-01: kalkulator listrik 800W x 3j x 80% x Rp1.500 ==")
    # kWh = 800 * 3 * 80 / 100 / 1000 = 1.92 kWh
    # biaya = 1.92 * 1500 = Rp 2.880
    status, est = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "ELECTRICITY", "p_watt": 800, "p_hours": 3,
        "p_load_factor": 80, "p_tariff": 1500, "p_portions": 10,
        "p_note": "uji kompor listrik"})
    check("estimasi listrik tersimpan", status == 200 and est.get("estimate_id"),
          str(est)[:200])
    check("kWh = 1.92", est.get("kwh") == 1.92, str(est.get("kwh")))
    check("biaya = Rp 2.880", est.get("cost") == 2880, str(est.get("cost")))
    est_id = est.get("estimate_id")
    exp_from_est = est.get("expense_id")

    status, rows = req(
        f"/rest/v1/expenses?select=kind,amount,type,source_ref"
        f"&id=eq.{exp_from_est}", token)
    check("estimasi ikut sebagai expense ESTIMATED (bukan ACTUAL)",
          status == 200 and rows and rows[0]["kind"] == "ESTIMATED"
          and rows[0]["amount"] == 2880, str(rows))

    # Input tidak valid ditolak server
    status, bad = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "ELECTRICITY", "p_watt": 0, "p_hours": 3,
        "p_load_factor": 80, "p_tariff": 1500, "p_portions": 10})
    check("watt 0 ditolak", status == 400, str(status))
    status, bad = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "ELECTRICITY", "p_watt": 800, "p_hours": 3,
        "p_load_factor": 150, "p_tariff": 1500, "p_portions": 10})
    check("faktor beban > 100% ditolak", status == 400, str(status))
    status, bad = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "SOLAR", "p_portions": 1})
    check("jenis energi asing ditolak", status == 400, str(status))

    # ------------------------------------------------------------------
    print("\n== S05-01: kalkulator LPG (isi ulang Rp22.000 / 20 jam, "
          "batch 2.5 jam) ==")
    # biaya = (22000 / 20) * 2.5 = Rp 2.750
    status, lpg = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "LPG", "p_refill_price": 22000, "p_effective_hours": 20,
        "p_batch_hours": 2.5, "p_portions": 8})
    check("estimasi LPG tersimpan", status == 200, str(lpg)[:200])
    check("biaya LPG = Rp 2.750", lpg.get("cost") == 2750,
          str(lpg.get("cost")))
    status, lpg2 = rpc(token, "energy_save_estimate", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_kind": "LPG", "p_refill_price": 22000, "p_effective_hours": 0,
        "p_batch_hours": 2.5, "p_portions": 8})
    check("jam efektif 0 ditolak", status == 400, str(status))

    # ------------------------------------------------------------------
    print("\n== S05-03: biaya aktual vs estimasi ==")
    suffix = uuid.uuid4().hex[:6].upper()
    status, exp_a = rpc(token, "exp_save", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_type": "SEWA", "p_description": f"Sewa ruko {suffix}",
        "p_amount": 1500000, "p_kind": "ACTUAL"})
    check("expense aktual tersimpan", status == 200 and exp_a.get("id"),
          str(exp_a)[:200])
    a_id = exp_a["id"]
    status, exp_e = rpc(token, "exp_save", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_type": "AIR", "p_description": f"Perkiraan air {suffix}",
        "p_amount": 200000, "p_kind": "ESTIMATED"})
    check("expense estimasi tersimpan", status == 200 and exp_e.get("id"),
          str(exp_e)[:200])
    e_id = exp_e["id"]

    status, bad = rpc(token, "exp_save", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_type": "PENERANGAN", "p_description": "tipe asing",
        "p_amount": 1000, "p_kind": "ACTUAL"})
    check("tipe biaya asing ditolak", status == 400, str(status))
    status, bad = rpc(token, "exp_save", {
        "p_idempotency_key": uuid.uuid4().hex,
        "p_type": "AIR", "p_description": "ab",
        "p_amount": 1000, "p_kind": "ACTUAL"})
    check("keterangan < 3 huruf ditolak", status == 400, str(status))

    # ------------------------------------------------------------------
    print("\n== S05-04: alokasi tidak boleh melebihi sumber (UAT-10) ==")
    status, alloc = rpc(token, "cost_allocate", {
        "p_expense_id": a_id, "p_target_ref": "batch-gorengan",
        "p_amount": 500000})
    check("alokasi 500.000 dari 1.500.000 diterima",
          status == 200 and alloc.get("allocated_total") == 500000,
          str(alloc)[:200])
    status, alloc2 = rpc(token, "cost_allocate", {
        "p_expense_id": a_id, "p_target_ref": "periode-oktober",
        "p_amount": 1000000})
    check("total alokasi tepat = sumber diterima",
          status == 200 and alloc2.get("allocated_total") == 1500000,
          str(alloc2)[:200])
    status, over = rpc(token, "cost_allocate", {
        "p_expense_id": a_id, "p_target_ref": "melebihi",
        "p_amount": 1})
    check("alokasi melebihi sumber ditolak server",
          status == 400 and "allocation_exceeds_source" in err_code(over),
          str(over)[:200])

    # Ubah sumber lebih kecil dari alokasi lama -> ditolak
    status, shrink = rpc(token, "exp_save", {
        "p_id": a_id, "p_type": "SEWA",
        "p_description": f"Sewa ruko {suffix}", "p_amount": 10,
        "p_kind": "ACTUAL"})
    check("mengecilkan sumber di bawah alokasi ditolak",
          status == 400 and "allocation_exceeds_source" in err_code(shrink),
          str(shrink)[:200])

    # ------------------------------------------------------------------
    print("\n== S05-05: kas shift (UAT-11) ==")
    # Pastikan tidak ada shift terbisa sisa dari uji sebelumnya.
    status, st = rpc(token, "cash_shift_status", {})
    check("status shift terbaca", status == 200, str(st)[:200])
    if st.get("open"):
        rpc(token, "cash_shift_close", {
            "p_actual_cash": st.get("expected_cash", 0),
            "p_note": "cleanup uji"})

    status, opened = rpc(token, "cash_shift_open",
                         {"p_opening_cash": 100000})
    check("buka shift dengan kas awal Rp100.000",
          status == 200 and opened.get("opening_cash") == 100000,
          str(opened)[:200])
    status, again = rpc(token, "cash_shift_open", {"p_opening_cash": 0})
    check("shift kedua ditolak (satu shift terbuka)",
          status == 400 and "shift_already_open" in err_code(again),
          str(again)[:200])

    # Bayar tunai 20.000 lewat checkout nyata
    status, prod = req(
        "/rest/v1/products?select=id,price&is_active=eq.true&limit=2", token)
    p = prod[0]
    key = f"UAT11-{suffix}"
    status, sale = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": p["id"], "qty": 1, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 20000, "p_dining_type": "TAKEAWAY",
        "p_idempotency_key": key})
    check("checkout tunai sukses", status == 200, str(sale)[:200])
    sale_id = sale.get("sale_id")

    # Bayar transfer 50.000 (tidak boleh masuk expected kas)
    status, sale2 = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": p["id"], "qty": 1, "modifier_ids": []}],
        "p_method": "TRANSFER", "p_paid": 50000, "p_dining_type": "TAKEAWAY",
        "p_idempotency_key": f"UAT11T-{suffix}"})
    check("checkout transfer sukses", status == 200, str(sale2)[:200])

    status, st = rpc(token, "cash_shift_status", {})
    # Sale final membawa pajak/layanan usaha; kas harian memakai total sale.
    total = sale["total"]
    check("expected = awal + penjualan tunai (transfer dikecualikan)",
          st.get("expected_cash") == 100000 + total
          and st.get("cash_sales") == total, str(st)[:300])

    # Tutup kas dengan selisih -500
    status, closed = rpc(token, "cash_shift_close",
                         {"p_actual_cash": 100000 + total - 500,
                          "p_note": "uji selisih"})
    check("tutup kas menghitung selisih -500",
          status == 200 and closed.get("variance") == -500,
          str(closed)[:300])
    check("expected tercatat saat tutup",
          closed.get("expected_cash") == 100000 + total, str(closed)[:300])
    status, none = rpc(token, "cash_shift_close", {"p_actual_cash": 0})
    check("tutup tanpa shift terbuka ditolak",
          status == 400 and "no_open_shift" in err_code(none), str(none))

    # ------------------------------------------------------------------
    print("\n== S05-07: laporan (refund mengurangi net sales) ==")
    # Refund penuh sale tunai
    status, refund = rpc(token, "pos_refund", {
        "p_sale_id": sale_id, "p_amount": total, "p_reason": "uji laporan",
        "p_idempotency_key": uuid.uuid4().hex})
    check("refund penuh sukses", status == 200, str(refund)[:200])

    status, rep = rpc(token, "pos_reports",
                      {"p_from": "2020-01-01", "p_to": "2099-12-31"})
    check("laporan terbaca", status == 200, str(rep)[:200])
    status, db_sales = req(
        "/rest/v1/sales?select=total,refund_amount,status"
        "&created_at=gte.2020-01-01", token)
    expect_net = sum(s["total"] - s["refund_amount"]
                     for s in db_sales if s["status"] != "REFUNDED")
    check("net sales laporan = hitungan DB",
          rep.get("net_sales") == expect_net,
          f"rpc={rep.get('net_sales')} db={expect_net}")
    expect_refunds = sum(s["refund_amount"] for s in db_sales)
    check("refund laporan = total refund DB",
          rep.get("refunds") == expect_refunds,
          f"rpc={rep.get('refunds')} db={expect_refunds}")

    status, db_exp = req(
        "/rest/v1/expenses?select=amount,kind", token)
    exp_a_db = sum(e["amount"] for e in db_exp if e["kind"] == "ACTUAL")
    exp_e_db = sum(e["amount"] for e in db_exp if e["kind"] == "ESTIMATED")
    check("biaya aktual laporan = DB",
          rep.get("expenses_actual") == exp_a_db,
          f"rpc={rep.get('expenses_actual')} db={exp_a_db}")
    check("biaya estimasi laporan = DB",
          rep.get("expenses_estimated") == exp_e_db,
          f"rpc={rep.get('expenses_estimated')} db={exp_e_db}")
    check("estimasi tidak dijumlahkan ke aktual",
          rep.get("expenses_actual") != (exp_a_db + exp_e_db))

    status, db_alloc = req("/rest/v1/cost_allocations?select=amount", token)
    alloc_db = sum(a["amount"] for a in db_alloc)
    check("total alokasi laporan = DB dan <= sumber",
          rep.get("allocated_total") == alloc_db
          and alloc_db <= exp_a_db, str(rep.get("allocated_total")))

    # ------------------------------------------------------------------
    print("\n== S05-09: anon ditolak ==")
    for name, body in [("exp_save", {"p_idempotency_key": uuid.uuid4().hex,
                                     "p_type": "AIR", "p_description": "x y",
                                     "p_amount": 1, "p_kind": "ACTUAL"}),
                       ("cash_shift_open", {"p_opening_cash": 0}),
                       ("cost_allocate", {"p_expense_id": 1,
                                          "p_target_ref": "anon",
                                          "p_amount": 1})]:
        status, _ = req(f"/rest/v1/rpc/{name}", None, body)
        check(f"anon ditolak {name}", status in (401, 403), str(status))
    status, rows = req("/rest/v1/expenses?select=id", None)
    check("anon baca expenses = tertutup", status in (401, 403)
          or rows == [], str(status)[:100])
    status, rows = req("/rest/v1/cash_shifts?select=id", None)
    check("anon baca cash_shifts = tertutup", status in (401, 403)
          or rows == [], str(status)[:100])

    # ------------------------------------------------------------------
    print(f"\n{'=' * 60}")
    print(f"TOTAL: {passed} PASS, {failed} FAIL")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
