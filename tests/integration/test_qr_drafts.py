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
    check("draft ter-claim hilang dari daftar PENDING",
          not any(x["draft_id"] == d1["draft_id"] for x in drafts2))

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

    print(f"\n{passed} PASS, {failed} FAIL")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
