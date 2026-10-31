#!/usr/bin/env python3
"""Uji API QR draft Sprint 03 langsung ke Supabase asli (bukan mock).

Cara jalankan:
  python3 tests/integration/test_qr_drafts.py

Menguji: submit valid, dua "HP" bersamaan -> dua draft terpisah, retry
idempoten, invalid token, rate limit, anon tidak bisa baca/tulis draft,
claim sekali saja, cancel, draft tidak memengaruhi omzet sampai dibayar,
checkout draft -> sale final muncul sekali.
"""
import hashlib
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


def main():
    status, body = req("/auth/v1/token?grant_type=password", body={
        "email": OPERATOR_EMAIL, "password": OPERATOR_PASSWORD})
    check("login operator", status == 200, str(body)[:200])
    token = body["access_token"]

    status, products = req("/rest/v1/products?select=id,name,price"
                           "&is_active=eq.true&archived_at=is.null", token)
    check("baca products", status == 200 and len(products) >= 2)
    p1 = products[0]

    # --- S03: buat meja uji (token di-hash SHA-256; hash yang disimpan) ---
    print("\n== Persiapan meja uji ==")
    tok_a = "qrtest-token-a-" + uuid.uuid4().hex[:8]   # meja HP-1
    tok_b = "qrtest-token-b-" + uuid.uuid4().hex[:8]   # meja HP-2
    tok_bad = "token-tidak-ada-" + uuid.uuid4().hex[:8]

    def make_table(label, tok):
        h = hashlib.sha256(tok.encode()).hexdigest()
        status, rows = req(
            "/rest/v1/dining_tables?select=id,label", token,
            {"label": label, "qr_token_hash": h, "is_enabled": True},
            method="POST")
        if status == 201 and rows:
            return rows[0]["id"]
        # Sudah pernah ada (label unik) -> ambil id-nya.
        status, rows = req(
            f"/rest/v1/dining_tables?select=id&label=eq.{label}", token)
        return rows[0]["id"]

    table_a = make_table("UJI-QR-A-" + uuid.uuid4().hex[:6], tok_a)
    table_b = make_table("UJI-QR-B-" + uuid.uuid4().hex[:6], tok_b)
    check("meja uji terbuat", table_a and table_b,
          f"a={table_a} b={table_b}")

    items = [{"product_id": p1["id"], "qty": 2, "modifier_ids": [],
              "note": "tanpa gula"}]
    expect_sub = p1["price"] * 2

    # --- Submit valid (anon, seperti HP pelanggan) ---
    print("\n== Submit draft publik ==")
    key_hp1 = "hp1-" + uuid.uuid4().hex
    status, d1 = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": key_hp1, "p_items": items})
    check("submit valid (anon) -> 200", status == 200, str(d1)[:200])
    check("draft PENDING", d1 and d1.get("status") == "PENDING")
    check("subtotal = harga server x qty",
          d1 and d1.get("subtotal") == expect_sub,
          f"{d1 and d1.get('subtotal')} vs {expect_sub}")
    check("ada ref_code", d1 and d1.get("ref_code", "").startswith("Q"))
    check("snapshot nama produk", d1 and d1["items"][0]["product_name"]
          == p1["name"])

    # --- Dua HP submit bersamaan -> dua draft terpisah ---
    print("\n== Dua HP bersamaan ==")
    key_hp2 = "hp2-" + uuid.uuid4().hex
    status, d2 = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": key_hp2,
        "p_items": [{"product_id": p1["id"], "qty": 1,
                     "modifier_ids": []}]})
    check("HP kedua submit -> draft kedua", status == 200
          and d2["draft_id"] != d1["draft_id"],
          f"d1={d1 and d1.get('draft_id')} d2={status} {str(d2)[:120]}")

    # --- Retry idempoten (key sama) -> draft yang sama ---
    print("\n== Retry idempoten ==")
    status, d1r = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": key_hp1, "p_items": items})
    check("retry key sama -> draft sama", status == 200
          and d1r["draft_id"] == d1["draft_id"]
          and d1r.get("idempotent_replay") is True, str(d1r)[:200])

    # --- Invalid token ---
    print("\n== Token salah ==")
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_bad, "p_client_key": "x-" + uuid.uuid4().hex,
        "p_items": items})
    check("token salah ditolak", status >= 400
          and "invalid_table_token" in str(body), str(body)[:160])

    # --- Validasi item (qty/product) ---
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": "q-" + uuid.uuid4().hex,
        "p_items": [{"product_id": p1["id"], "qty": 0,
                     "modifier_ids": []}]})
    check("qty 0 ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": "q-" + uuid.uuid4().hex,
        "p_items": []})
    check("items kosong ditolak", status >= 400, str(body)[:120])

    # --- Draft tidak memengaruhi omzet (S03: draft bukan sale) ---
    print("\n== Omzet sebelum/sesudah draft ==")
    status, before = rpc(token, "pos_dashboard_summary", {})
    check("omzet terbaca", status == 200, str(before)[:160])
    key_hp3 = "hp3-" + uuid.uuid4().hex
    status, d3 = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_a, "p_client_key": key_hp3, "p_items": items})
    status, after = rpc(token, "pos_dashboard_summary", {})
    check("draft tidak menambah omzet", status == 200
          and after["today_revenue"] == before["today_revenue"]
          and after["all_time_revenue"] == before["all_time_revenue"],
          f"{before} -> {after}")

    # --- Rate limit (meja B: 5 draft bebas, ke-6 ditolak) ---
    print("\n== Rate limit ==")
    limited = False
    for i in range(6):
        status, body = rpc(None, "qr_submit_draft", {
            "p_table_token": tok_b,
            "p_client_key": f"rl-{i}-" + uuid.uuid4().hex,
            "p_items": items})
        if status >= 400 and "rate_limited" in str(body):
            limited = True
            check(f"percobaan ke-{i + 1} ditolak rate limit", True)
            break
    check("rate limit aktif (<=6 percobaan)", limited)

    # --- Anon tidak bisa membaca/mengubah draft langsung ---
    print("\n== Anon tertutup rapat ==")
    status, rows = req("/rest/v1/qr_drafts?select=id", None)
    check("anon baca qr_drafts = kosong/403", status in (200, 401, 403)
          and (rows == [] or isinstance(rows, dict)), f"{status} {rows}")
    status, body = rpc(None, "qr_list_drafts", {})
    check("anon qr_list_drafts ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "qr_claim_draft", {"p_draft_id": d1["draft_id"]})
    check("anon qr_claim_draft ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "qr_cancel_draft", {"p_draft_id": d1["draft_id"]})
    check("anon qr_cancel_draft ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "qr_complete_draft",
                       {"p_draft_id": d1["draft_id"], "p_sale_id": 1})
    check("anon qr_complete_draft ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "qr_mark_preparing", {"p_draft_id": d1["draft_id"]})
    check("anon qr_mark_preparing ditolak", status >= 400, str(body)[:120])
    status, body = rpc(None, "pos_checkout", {
        "p_items": items, "p_method": "CASH", "p_paid": 999999,
        "p_idempotency_key": "anon-" + uuid.uuid4().hex})
    check("anon pos_checkout ditolak", status >= 400, str(body)[:120])

    # --- Operator: list -> claim sekali saja ---
    print("\n== List & claim (operator) ==")
    status, drafts = rpc(token, "qr_list_drafts", {})
    check("list drafts berisi PENDING", status == 200
          and any(x["draft_id"] == d1["draft_id"] for x in drafts),
          str(drafts)[:200])
    check("draft ke-2 (HP-2) juga tampil",
          any(x["draft_id"] == d2["draft_id"] for x in drafts))

    status, claimed = rpc(token, "qr_claim_draft",
                          {"p_draft_id": d1["draft_id"]})
    check("claim sukses", status == 200 and claimed["status"] == "CLAIMED",
          str(claimed)[:200])
    check("item terbawa saat claim", claimed["items"][0]["qty"] == 2
          and claimed["items"][0]["note"] == "tanpa gula")

    status, body = rpc(token, "qr_claim_draft", {"p_draft_id": d1["draft_id"]})
    check("claim kedua ditolak (sudah CLAIMED)", status >= 400
          and "draft_not_claimable" in str(body), str(body)[:160])

    status, drafts2 = rpc(token, "qr_list_drafts", {})
    # 0019: daftar = papan aktif — draft CLAIMED tetap tampil (status baru),
    # hanya yang sudah CANCELLED/EXPIRED/COMPLETED-bayar yang hilang.
    check("draft ter-claim tetap di papan (status CLAIMED)",
          any(x["draft_id"] == d1["draft_id"]
              and x["status"] == "CLAIMED" for x in drafts2),
          str(drafts2)[:200])

    # --- Checkout draft memakai mesin Sprint 02 -> sale final sekali ---
    print("\n== Checkout draft (mesin POS Sprint 02) ==")
    idem = "qr-draft-" + uuid.uuid4().hex
    co_items = [{"product_id": i["product_id"], "qty": i["qty"],
                 "modifier_ids": [m["modifier_id"] for m in i["modifiers"]],
                 "note": i["note"] or ""} for i in claimed["items"]]
    # Total sale = subtotal draft + pajak/layanan usaha (PRD 6.1), bukan
    # subtotal mentah; nominal bayar harus menutup total itu.
    status, st = req("/rest/v1/business_settings"
                     "?select=tax_rate,service_rate", token)
    tax = float(st[0]["tax_rate"]); svc = float(st[0]["service_rate"])
    sub = claimed["subtotal"]
    expected_total = (sub + int(sub * tax + 0.5) + int(sub * svc + 0.5))
    status, sale = rpc(token, "pos_checkout", {
        "p_items": co_items, "p_method": "CASH",
        "p_paid": expected_total, "p_dining_type": "DINE_IN",
        "p_table_id": claimed["table_id"], "p_idempotency_key": idem})
    check("checkout draft sukses", status == 200, str(sale)[:200])
    check("total = subtotal draft + pajak aktif",
          status == 200 and sale["total"] == expected_total,
          f"{sale and sale.get('total')} vs {expected_total}")

    status, sale2 = rpc(token, "pos_checkout", {
        "p_items": co_items, "p_method": "CASH",
        "p_paid": expected_total, "p_dining_type": "DINE_IN",
        "p_table_id": claimed["table_id"], "p_idempotency_key": idem})
    check("retry checkout = sale yang sama", status == 200
          and sale2["sale_id"] == sale["sale_id"]
          and sale2.get("idempotent_replay") is True, str(sale2)[:200])

    status, done = rpc(token, "qr_complete_draft",
                       {"p_draft_id": d1["draft_id"],
                        "p_sale_id": sale["sale_id"]})
    check("draft ditandai COMPLETED", status == 200
          and done["status"] == "COMPLETED"
          and done["sale_id"] == sale["sale_id"], str(done)[:200])

    # --- Setelah dibayar, omzet naik tepat sebesar total sale ---
    status, fin = rpc(token, "pos_dashboard_summary", {})
    check("omzet naik setelah bayar", status == 200
          and fin["today_revenue"] == after["today_revenue"]
          + sale["total"] - 0,
          f"{after['today_revenue']} + {sale['total']} != "
          f"{fin['today_revenue']}")

    # --- Cancel draft kedua (milik HP-2 yang belum diambil) ---
    print("\n== Cancel draft ==")
    status, cancelled = rpc(token, "qr_cancel_draft",
                            {"p_draft_id": d2["draft_id"]})
    check("cancel sukses", status == 200
          and cancelled["status"] == "CANCELLED", str(cancelled)[:160])
    status, body = rpc(token, "qr_claim_draft", {"p_draft_id": d2["draft_id"]})
    check("draft ter-cancel tidak bisa di-claim", status >= 400)
    status, body = rpc(token, "qr_cancel_draft", {"p_draft_id": 2 ** 62})
    check("cancel id asing ditolak", status >= 400, str(body)[:120])

    # --- Preferensi bayar + identitas pelanggan (migrasi 0018) ---
    print("\n== Preferensi bayar & identitas (0018) ==")
    tok_c = "qrtest-token-c-" + uuid.uuid4().hex[:8]
    table_c = make_table("UJI-QR-C-" + uuid.uuid4().hex[:6], tok_c)

    # PAY_NOW + QRIS + identitas lengkap.
    key_c1 = "pc1-" + uuid.uuid4().hex
    status, dp = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": key_c1, "p_items": items,
        "p_pay_intent": "PAY_NOW", "p_pay_method": "QRIS",
        "p_customer_name": "  Budi Santoso  ",
        "p_customer_phone": "+62 812-3456-7890"})
    check("submit PAY_NOW+QRIS sukses", status == 200, str(dp)[:200])
    check("pay_intent tercatat", dp and dp.get("pay_intent") == "PAY_NOW")
    check("pay_method tercatat", dp and dp.get("pay_method") == "QRIS")
    check("nama di-trim & tersimpan",
          dp and dp.get("customer_name") == "Budi Santoso",
          str(dp and dp.get("customer_name")))
    check("no. WA tersimpan",
          dp and dp.get("customer_phone") == "+62 812-3456-7890")

    # OPEN_BILL: boleh tanpa method.
    key_c2 = "pc2-" + uuid.uuid4().hex
    status, dob = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": key_c2, "p_items": items,
        "p_pay_intent": "OPEN_BILL"})
    check("submit OPEN_BILL tanpa method sah", status == 200
          and dob.get("pay_intent") == "OPEN_BILL"
          and dob.get("pay_method") is None, str(dob)[:200])

    # Tanpa preferensi (klien lama, 3 argumen) -> semua null.
    key_c3 = "pc3-" + uuid.uuid4().hex
    status, dlegacy = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": key_c3, "p_items": items})
    check("submit 3 argumen (klien lama) tetap sah", status == 200)
    check("preferensi default null", dlegacy.get("pay_intent") is None
          and dlegacy.get("pay_method") is None
          and dlegacy.get("customer_name") is None
          and dlegacy.get("customer_phone") is None)

    # Method TANPA PAY_NOW -> ditolak.
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": "bad1-" + uuid.uuid4().hex,
        "p_items": items, "p_pay_method": "QRIS"})
    check("method tanpa PAY_NOW ditolak", status >= 400
          and "pay_method_requires_pay_now" in str(body), str(body)[:160])

    # Nilai enum salah -> ditolak.
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": "bad2-" + uuid.uuid4().hex,
        "p_items": items, "p_pay_intent": "COD"})
    check("pay_intent salah ditolak", status >= 400
          and "invalid_pay_intent" in str(body), str(body)[:160])
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": "bad3-" + uuid.uuid4().hex,
        "p_items": items, "p_pay_intent": "PAY_NOW",
        "p_pay_method": "BITCOIN"})
    check("pay_method salah ditolak", status >= 400
          and "invalid_pay_method" in str(body), str(body)[:160])

    # Nama kepanjangan -> ditolak.
    status, body = rpc(None, "qr_submit_draft", {
        "p_table_token": tok_c, "p_client_key": "bad4-" + uuid.uuid4().hex,
        "p_items": items, "p_customer_name": "x" * 61})
    check("nama > 60 char ditolak", status >= 400
          and "invalid_customer_name" in str(body), str(body)[:160])

    # Operator melihat preferensi & identitas di daftar draft.
    status, allc = rpc(token, "qr_list_drafts", {})
    rowp = next((x for x in allc if x["draft_id"] == dp["draft_id"]), None)
    check("draft PAY_NOW tampil di list dengan preferensi",
          status == 200 and rowp is not None
          and rowp.get("pay_method") == "QRIS"
          and rowp.get("customer_name") == "Budi Santoso",
          str(rowp)[:200])

    # Draft OPEN_BILL bisa diklaim tanpa memaksa pembayaran (Open Bill =
    # tetap lewat keranjang POS; total final = keranjang saat checkout).
    status, cl = rpc(token, "qr_claim_draft", {"p_draft_id": dob["draft_id"]})
    check("draft OPEN_BILL bisa diklaim", status == 200
          and cl["status"] == "CLAIMED", str(cl)[:160])

    # --- Siklus hidup pesanan & papan aktif (migrasi 0019) ---
    print("\n== Siklus hidup pesanan & papan aktif (0019) ==")
    tok_d = "qrtest-token-d-" + uuid.uuid4().hex[:8]
    table_d = make_table("UJI-QR-D-" + uuid.uuid4().hex[:6], tok_d)

    def submit_d(key):
        return rpc(None, "qr_submit_draft", {
            "p_table_token": tok_d, "p_client_key": key, "p_items": items})

    # a) PENDING tidak boleh langsung PREPARING (harus lewat Diterima).
    status, dseed = submit_d("lc0-" + uuid.uuid4().hex)
    check("submit draft siklus", status == 200, str(dseed)[:160])
    status, body = rpc(token, "qr_mark_preparing",
                       {"p_draft_id": dseed["draft_id"]})
    check("mark_preparing dari PENDING ditolak", status >= 400
          and "draft_not_claimed" in str(body), str(body)[:160])

    # b) PENDING -> CLAIMED -> PREPARING -> COMPLETED (tanpa sale = Open Bill).
    status, cl0 = rpc(token, "qr_claim_draft", {"p_draft_id": dseed["draft_id"]})
    check("claim draft siklus", status == 200
          and cl0["status"] == "CLAIMED", str(cl0)[:160])
    status, prep = rpc(token, "qr_mark_preparing",
                       {"p_draft_id": dseed["draft_id"]})
    check("CLAIMED -> PREPARING", status == 200
          and prep["status"] == "PREPARING", str(prep)[:160])
    status, body = rpc(token, "qr_mark_preparing",
                       {"p_draft_id": dseed["draft_id"]})
    check("mark_preparing ulang ditolak (sudah PREPARING)",
          status >= 400 and "draft_not_claimed" in str(body), str(body)[:160])
    status, comp0 = rpc(token, "qr_complete_draft",
                        {"p_draft_id": dseed["draft_id"]})
    check("PREPARING -> COMPLETED tanpa sale", status == 200
          and comp0["status"] == "COMPLETED" and comp0["sale_id"] is None,
          str(comp0)[:200])

    # c) Idempoten + pelunasan mengaitkan sale ke COMPLETED-sale-null.
    status, comp0r = rpc(token, "qr_complete_draft",
                         {"p_draft_id": dseed["draft_id"]})
    check("complete ulang (tanpa sale) idempoten", status == 200
          and comp0r["sale_id"] is None, str(comp0r)[:160])
    idem_d = "qr-draft-d-" + uuid.uuid4().hex
    status, sale_d = rpc(token, "pos_checkout", {
        "p_items": co_items, "p_method": "CASH",
        "p_paid": expected_total, "p_dining_type": "DINE_IN",
        "p_table_id": table_d, "p_idempotency_key": idem_d})
    check("checkout draft siklus", status == 200, str(sale_d)[:200])
    status, paid = rpc(token, "qr_complete_draft", {
        "p_draft_id": dseed["draft_id"], "p_sale_id": sale_d["sale_id"]})
    check("pelunasan mengaitkan sale", status == 200
          and paid["sale_id"] == sale_d["sale_id"], str(paid)[:200])
    status, paidr = rpc(token, "qr_complete_draft", {
        "p_draft_id": dseed["draft_id"], "p_sale_id": sale_d["sale_id"]})
    check("pelunasan ulang idempoten", status == 200
          and paidr["sale_id"] == sale_d["sale_id"], str(paidr)[:200])
    status, body = rpc(token, "qr_complete_draft", {
        "p_draft_id": dseed["draft_id"], "p_sale_id": sale_d["sale_id"] + 1})
    check("kaitkan sale berbeda ditolak", status >= 400
          and "draft_not_completable" in str(body), str(body)[:160])

    # d) Papan aktif: CLAIMED/PREPARING/COMPLETED-bayar-nanti tampil;
    #    COMPLETED-sudah-bayar tidak.
    status, dpre = submit_d("lc1-" + uuid.uuid4().hex)   # -> PREPARING
    status, dpay = submit_d("lc2-" + uuid.uuid4().hex)   # -> COMPLETED null
    status, dpend = submit_d("lc3-" + uuid.uuid4().hex)  # tetap PENDING
    rpc(token, "qr_claim_draft", {"p_draft_id": dpre["draft_id"]})
    rpc(token, "qr_mark_preparing", {"p_draft_id": dpre["draft_id"]})
    rpc(token, "qr_claim_draft", {"p_draft_id": dpay["draft_id"]})
    rpc(token, "qr_complete_draft", {"p_draft_id": dpay["draft_id"]})

    status, board = rpc(token, "qr_list_drafts", {})
    by_id = {x["draft_id"]: x for x in board}
    check("papan: PREPARING tampil",
          by_id.get(dpre["draft_id"], {}).get("status") == "PREPARING",
          str(board)[:200])
    check("papan: PENDING tampil",
          by_id.get(dpend["draft_id"], {}).get("status") == "PENDING")
    check("papan: COMPLETED belum bayar tampil",
          by_id.get(dpay["draft_id"], {}).get("status") == "COMPLETED"
          and by_id.get(dpay["draft_id"], {}).get("sale_id") is None)
    check("papan: COMPLETED sudah bayar tidak tampil",
          dseed["draft_id"] not in by_id)

    # e) Cancel dari PREPARING; kartu hilang dari papan.
    status, cx = rpc(token, "qr_cancel_draft", {"p_draft_id": dpre["draft_id"]})
    check("cancel dari PREPARING", status == 200
          and cx["status"] == "CANCELLED", str(cx)[:160])
    status, board2 = rpc(token, "qr_list_drafts", {})
    check("draft ter-cancel hilang dari papan",
          not any(x["draft_id"] == dpre["draft_id"] for x in board2))

    # f) Tanpa sale_id argumen (klien baru) = p_opsional default null.
    status, body = rpc(token, "qr_complete_draft",
                       {"p_draft_id": dpend["draft_id"]})
    check("complete tanpa sale_id pada PENDING ditolak", status >= 400
          and "draft_not_completable" in str(body), str(body)[:160])

    print(f"\n{passed} PASS, {failed} FAIL")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
