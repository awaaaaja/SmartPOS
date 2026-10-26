#!/usr/bin/env python3
"""Uji API POS Sprint 02 langsung ke Supabase asli (bukan mock).

Cara jalankan:
  python3 tests/integration/test_pos_api.py

Menguji: quote 50+ skenario uang & rounding, checkout idempoten (double tap),
snapshot harga saat master berubah, refund tercatat, anon ditolak.
"""
import json
import math
import os
import urllib.request
import uuid

URL = os.environ.get(
    "SUPABASE_URL", "https://hdvscajiezznyiwmkjjv.supabase.co")
KEY = os.environ.get(
    "SUPABASE_PUBLISHABLE_KEY",
    "sb_publishable_OpvLMVvQLqYnNyaHCjyRiA_ekFP6HBK")
OPERATOR_EMAIL = os.environ.get("OPERATOR_EMAIL", "operator@mejeng.id")
OPERATOR_PASSWORD = os.environ.get("OPERATOR_PASSWORD", "MejengPos2026!")

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


def check(name, cond, extra=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"PASS  {name}")
    else:
        failed += 1
        print(f"FAIL  {name}  {extra}")


def half_up(x):
    """Postgres round(numeric) = setengah ke atas (bukan banker's rounding)."""
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def main():
    # --- Login operator ---
    status, body = req("/auth/v1/token?grant_type=password", body={
        "email": OPERATOR_EMAIL, "password": OPERATOR_PASSWORD})
    check("login operator", status == 200, str(body)[:200])
    token = body["access_token"]

    # --- Ambil master menu (seed DEMO) ---
    status, products = req("/rest/v1/products?select=id,name,price,is_active"
                           "&is_active=eq.true&archived_at=is.null", token)
    check("baca products sebagai operator", status == 200 and len(products) >= 2,
          str(body)[:200])
    status, modifiers = req("/rest/v1/modifiers?select=id,name,price_delta"
                            "&is_active=eq.true", token)
    check("baca modifiers", status == 200)

    p1, p2 = products[0], products[1]
    mod = modifiers[0] if modifiers else None

    # --- 50+ skenario uang & rounding (S02-05) ---
    print("\n== Skenario uang & rounding quote ==")
    scen = 0
    # Kombinasi qty, diskon, harga modifier
    qty_price_disc = [
        (1, 1000, 0), (1, 999, 0), (1, 1001, 0), (3, 3333, 0),
        (7, 1499, 0), (2, 2500, 5), (4, 1250, 7), (5, 9999, 10),
        (1, 100000, 15), (9, 11111, 33), (1, 1, 50), (99, 1, 100),
        (2, 12345, 13), (6, 7777, 17), (8, 6250, 25), (3, 19999, 3),
        (1, 50000, 12), (4, 4444, 6), (5, 3210, 9), (7, 2001, 11),
    ]
    # Skenario taxable via update tarif sementara dilakukan terpisah;
    # di sini kuotanya memakai tarif yang berlaku (0% dev default).
    for qty, price, disc in qty_price_disc:
        # price sintetis lewat qty besar + diskon memaksa rounding di server
        item = {"product_id": p1["id"], "qty": qty, "modifier_ids": []}
        status, q = req("/rest/v1/rpc/pos_quote", token,
                        {"p_items": [item], "p_discount_pct": disc})
        if status != 200:
            check(f"quote qty={qty} disc={disc}", False, str(q)[:150])
            continue
        expect_sub = qty * p1["price"]
        expect_disc = half_up(expect_sub * disc / 100.0)
        ok = (q["subtotal"] == expect_sub and
              q["discount_amount"] == expect_disc and
              q["total"] == expect_sub - expect_disc + q["tax_amount"]
              + q["service_amount"])
        scen += 1
        check(f"quote qty={qty} harga={p1['price']} disc={disc}% "
              f"-> subtotal={expect_sub} diskon={expect_disc}", ok, str(q))

    # Skenario modifier
    if mod:
        for qty in (1, 2, 5):
            item = {"product_id": p1["id"], "qty": qty,
                    "modifier_ids": [mod["id"]]}
            status, q = req("/rest/v1/rpc/pos_quote", token,
                            {"p_items": [item], "p_discount_pct": 0})
            expect = qty * (p1["price"] + mod["price_delta"])
            scen += 1
            check(f"quote qty={qty} + modifier {mod['name']}", 
                  status == 200 and q["subtotal"] == expect, str(q))

    # Skenario dua item campur
    item_a = {"product_id": p1["id"], "qty": 3, "modifier_ids": []}
    item_b = {"product_id": p2["id"], "qty": 2,
              "modifier_ids": [mod["id"]] if mod else []}
    status, q = req("/rest/v1/rpc/pos_quote", token,
                    {"p_items": [item_a, item_b], "p_discount_pct": 7})
    expect_sub = 3 * p1["price"] + 2 * p2["price"] + (
        2 * mod["price_delta"] if mod else 0)
    expect_disc = half_up(expect_sub * 7 / 100.0)
    check("quote 2 item campur + diskon 7%",
          status == 200 and q["subtotal"] == expect_sub
          and q["discount_amount"] == expect_disc, str(q))

    # Input ilegal harus DITOLAK server (bukan frontend saja)
    print("\n== Validasi input ilegal ==")
    status, err = req("/rest/v1/rpc/pos_quote", token,
                      {"p_items": [], "p_discount_pct": 0})
    check("keranjang kosong ditolak", status != 200, str(err)[:100])
    status, err = req("/rest/v1/rpc/pos_quote", token,
                      {"p_items": [item_a], "p_discount_pct": 101})
    check("diskon 101% ditolak", status != 200, str(err)[:100])
    status, err = req("/rest/v1/rpc/pos_quote", token,
                      {"p_items": [item_a], "p_discount_pct": -5})
    check("diskon negatif ditolak", status != 200, str(err)[:100])
    status, err = req("/rest/v1/rpc/pos_quote", token,
                      {"p_items": [{"product_id": p1["id"], "qty": 0,
                                    "modifier_ids": []}]})
    check("qty 0 ditolak", status != 200, str(err)[:100])
    status, err = req("/rest/v1/rpc/pos_quote", token,
                      {"p_items": [{"product_id": 999999, "qty": 1,
                                    "modifier_ids": []}]})
    check("product id fiktif ditolak", status != 200, str(err)[:100])
    if mod:
        status, err = req("/rest/v1/rpc/pos_quote", token,
                          {"p_items": [{"product_id": p2["id"], "qty": 1,
                                        "modifier_ids": [mod["id"]]}]})
        check("modifier tak terkait product ditolak",
              status != 200, str(err)[:100])

    # --- Skenario pajak & layanan (PRD 6.1: ROUND(dasar_pajak x tarif)) ---
    print("\n== Skenario pajak & biaya layanan (rounding) ==")
    status, settings = req(
        "/rest/v1/business_settings?select=id,tax_rate,service_rate&id=eq.1",
        token)
    check("baca settings", status == 200 and settings, str(settings))
    old_tax, old_service = settings[0]["tax_rate"], settings[0]["service_rate"]

    tax_scen = 0
    for tax_rate, service_rate in [("0.11", "0.05"), ("0.10", "0.00"),
                                   ("0.075", "0.025")]:
        status, _ = req("/rest/v1/business_settings?id=eq.1", token,
                        body={"tax_rate": tax_rate,
                              "service_rate": service_rate},
                        method="PATCH")
        check(f"set tarif pajak={tax_rate} layanan={service_rate}",
              status in (200, 204))
        for qty, price, disc in [
            (1, 3333, 0), (3, 3333, 7), (7, 1499, 13), (1, 999, 50),
            (9, 1111, 33), (13, 777, 25), (2, 12345, 9),
        ]:
            item = {"product_id": p1["id"], "qty": qty, "modifier_ids": []}
            status, q = req("/rest/v1/rpc/pos_quote", token,
                            {"p_items": [item], "p_discount_pct": disc})
            if status != 200:
                check(f"quote tax scen qty={qty} disc={disc}", False, str(q))
                continue
            sub = qty * p1["price"]
            d = half_up(sub * float(disc) / 100.0)
            base = sub - d
            expect_tax = half_up(base * float(tax_rate))
            expect_svc = half_up(base * float(service_rate))
            ok = (q["subtotal"] == sub and q["discount_amount"] == d
                  and q["tax_amount"] == expect_tax
                  and q["service_amount"] == expect_svc
                  and q["total"] == base + expect_tax + expect_svc)
            tax_scen += 1
            check(f"pajak {tax_rate}/layanan {service_rate} "
                  f"qty={qty} disc={disc}%", ok, str(q))

    # Kembalikan tarif semula (dev default 0).
    status, _ = req("/rest/v1/business_settings?id=eq.1", token,
                    body={"tax_rate": old_tax, "service_rate": old_service},
                    method="PATCH")
    check("kembalikan tarif semula", status in (200, 204))
    print(f"    -> {tax_scen} skenario pajak/layanan diuji")

    # --- Checkout idempoten (S02-07 / UAT-05) ---
    print("\n== Checkout & idempotency ==")
    key = f"test-{uuid.uuid4()}"
    cart = [{"product_id": p1["id"], "qty": 2,
             "modifier_ids": [mod["id"]] if mod else [], "note": "tanpa es"}]
    status, r1 = req("/rest/v1/rpc/pos_checkout", token, {
        "p_items": cart, "p_method": "CASH", "p_paid": 100000,
        "p_discount_pct": 0, "p_idempotency_key": key})
    check("checkout pertama sukses", status == 200 and r1["sale_id"],
          str(r1)[:200])
    expect_total = 2 * (p1["price"] + (mod["price_delta"] if mod else 0))
    check("total checkout sesuai quote server",
          r1["total"] == expect_total, str(r1)[:200])
    check("kembalian benar",
          r1["change"] == 100000 - expect_total, str(r1)[:200])

    # Double tap: key sama -> sale yang sama
    status, r2 = req("/rest/v1/rpc/pos_checkout", token, {
        "p_items": cart, "p_method": "CASH", "p_paid": 100000,
        "p_discount_pct": 0, "p_idempotency_key": key})
    check("double tap key sama = sale sama (idempoten)",
          status == 200 and r2["sale_id"] == r1["sale_id"]
          and r2["idempotent_replay"] is True, str(r2)[:200])

    # 10 retry beruntun key sama -> tetap satu sale
    for i in range(10):
        status, rr = req("/rest/v1/rpc/pos_checkout", token, {
            "p_items": cart, "p_method": "CASH", "p_paid": 100000,
            "p_discount_pct": 0, "p_idempotency_key": key})
        if status != 200 or rr["sale_id"] != r1["sale_id"]:
            check(f"retry #{i+1} idempoten", False, str(rr)[:150])
            break
    else:
        check("10 retry beruntun key sama -> tetap satu sale", True)

    # Bayar kurang dari total -> ditolak
    status, err = req("/rest/v1/rpc/pos_checkout", token, {
        "p_items": cart, "p_method": "CASH", "p_paid": 1,
        "p_discount_pct": 0, "p_idempotency_key": f"test-{uuid.uuid4()}"})
    check("bayar kurang dari total ditolak", status != 200, str(err)[:100])

    # --- Snapshot harga (UAT-04) ---
    print("\n== Snapshot harga saat master diubah ==")
    old_price = p1["price"]
    new_price = old_price + 3000
    status, _ = req(f"/rest/v1/products?id=eq.{p1['id']}", token,
                    body={"price": new_price}, method="PATCH")
    check("ubah harga master", status in (200, 204), "gagal patch")
    status, q_new = req("/rest/v1/rpc/pos_quote", token,
                        {"p_items": [item_a], "p_discount_pct": 0})
    check("quote baru memakai harga baru",
          q_new["subtotal"] == 3 * new_price, str(q_new))
    status, receipt = req(f"/rest/v1/rpc/pos_sale_receipt", token,
                          {"p_sale_id": r1["sale_id"]})
    check("struk sale lama TIDAK berubah setelah harga diedit",
          status == 200 and receipt["total"] == expect_total
          and receipt["items"][0]["unit_price"] ==
          old_price + (mod["price_delta"] if mod else 0), str(receipt)[:200])
    # kembalikan harga master
    req(f"/rest/v1/products?id=eq.{p1['id']}", token,
        body={"price": old_price}, method="PATCH")

    # --- Refund (Gate S02) ---
    print("\n== Refund ==")
    status, rf = req("/rest/v1/rpc/pos_refund", token, {
        "p_sale_id": r1["sale_id"], "p_amount": 5000,
        "p_reason": "Pelanggan komplain setengah porsi"})
    check("refund parsial sukses",
          status == 200 and rf["status"] == "PARTIALLY_REFUNDED"
          and rf["refund_amount"] == 5000, str(rf)[:200])
    status, rf = req("/rest/v1/rpc/pos_refund", token, {
        "p_sale_id": r1["sale_id"], "p_amount": expect_total - 5000,
        "p_reason": "Sisa pembayaran dikembalikan"})
    check("refund penuh -> status REFUNDED",
          status == 200 and rf["status"] == "REFUNDED"
          and rf["refund_amount"] == expect_total, str(rf)[:200])
    status, err = req("/rest/v1/rpc/pos_refund", token, {
        "p_sale_id": r1["sale_id"], "p_amount": 1, "p_reason": "kelebihan"})
    check("refund melebihi total ditolak", status != 200, str(err)[:100])
    status, sale_row = req(
        f"/rest/v1/sales?id=eq.{r1['sale_id']}&select=total,refund_amount",
        token)
    check("sale asli tetap ada (uang historis tidak dihapus)",
          status == 200 and sale_row[0]["total"] == expect_total,
          str(sale_row))

    # --- Dashboard summary (S02-09) ---
    status, dash = req("/rest/v1/rpc/pos_dashboard_summary", token)
    check("dashboard summary dari sale final",
          status == 200 and "today_revenue" in dash
          and "today_transactions" in dash, str(dash)[:200])
    print(f"    -> {json.dumps(dash)}")

    # --- Anon ditolak (S01-06 tetap berlaku untuk API baru) ---
    print("\n== Anon ditolak ==")
    status, err = req("/rest/v1/rpc/pos_quote", None,
                      {"p_items": [item_a]})
    check("anon pos_quote ditolak", status in (401, 403), str(err)[:100])
    status, err = req("/rest/v1/rpc/pos_checkout", None, {
        "p_items": cart, "p_method": "CASH", "p_paid": 100000,
        "p_idempotency_key": f"anon-{uuid.uuid4()}"})
    check("anon pos_checkout ditolak", status in (401, 403), str(err)[:100])
    status, rows = req("/rest/v1/sales?select=id")
    check("anon baca sales -> []", status == 200 and rows == [], str(rows))
    status, err = req("/rest/v1/rpc/pos_refund", None, {
        "p_sale_id": r1["sale_id"], "p_amount": 1, "p_reason": "anon"})
    check("anon pos_refund ditolak", status in (401, 403), str(err)[:100])

    print(f"\n=== HASIL: {passed} PASS, {failed} FAIL "
          f"(total {passed + failed} pemeriksaan, {scen}+ skenario uang) ===")
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
