#!/usr/bin/env python3
"""Uji inventori Sprint 04 langsung ke Supabase asli (bukan mock).

Cara jalankan:
  python3 tests/integration/test_inventory.py

Menguji (S04-01…S04-09 / UAT-06..08):
  - konversi satuan kg->g dan L->ml saat pembelian diterima
  - pembelian menambah saldo tepat sekali; ORDERED belum menambah
  - HPP per porsi = sum(qty x unit_cost) / yield, telusur ke bahan
  - sale final memotong bahan tepat sekali; retry idempoten tidak dobel
  - stok kurang -> checkout ditolak, sale tidak tersimpan (UAT-06)
  - produk tanpa resep -> tidak ada klaim stok, inv_hpp has_recipe=false
  - produk BATCH: bahan dipotong saat produksi, penjualan tidak dobel
  - waste/koreksi wajib beralasan; ledger mutasi tidak bisa diubah/dihapus
  - anon tidak bisa membaca/menulis tabel inventori
  - Tidak ada AI/rekomendasi apa pun dijalankan di sini.
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


def make_product(token, name, price, category_id):
    """POST products tidak mengembalikan baris -> query balik by name."""
    status, _ = req("/rest/v1/products", token, {
        "name": name, "price": price,
        "category_id": category_id, "is_active": True}, method="POST")
    if status != 201:
        return None
    status, rows = req(f"/rest/v1/products?select=id&name=eq.{name}", token)
    return rows[0]["id"] if status == 200 and rows else None


def main():
    status, body = req("/auth/v1/token?grant_type=password", body={
        "email": OPERATOR_EMAIL, "password": OPERATOR_PASSWORD})
    check("login operator", status == 200, str(body)[:200])
    token = body["access_token"]
    suffix = uuid.uuid4().hex[:6].upper()

    # ------------------------------------------------------------------
    print("\n== S04-01: master bahan + satuan dasar ==")
    status, ing_g = rpc(token, "inv_save_ingredient", {
        "p_name": f"TEPUNG-UJI-{suffix}", "p_base_unit": "g",
        "p_reorder_level": 500, "p_unit_cost": 0})
    check("bahan gram terbuat", status == 200 and ing_g.get("id"),
          str(status))
    ing_g = ing_g["id"]
    status, ing_ml = rpc(token, "inv_save_ingredient", {
        "p_name": f"SUSU-UJI-{suffix}", "p_base_unit": "ml",
        "p_reorder_level": 0, "p_unit_cost": 0})
    check("bahan mililiter terbuat", status == 200, str(status))
    ing_ml = ing_ml["id"]
    status, ing_pcs = rpc(token, "inv_save_ingredient", {
        "p_name": f"TELUR-UJI-{suffix}", "p_base_unit": "pcs",
        "p_reorder_level": 2, "p_unit_cost": 0})
    check("bahan pcs terbuat", status == 200, str(status))
    ing_pcs = ing_pcs["id"]

    status, rows = rpc(token, "inv_save_ingredient", {
        "p_name": f"X-{suffix}", "p_base_unit": "kg"})
    check("satuan dasar selain g/ml/pcs ditolak",
          status == 400, str(status))

    # ------------------------------------------------------------------
    print("\n== S04-03: pembelian 1 kg -> saldo +1000 g (konversi) ==")
    status, po = rpc(token, "inv_create_purchase", {
        "p_supplier": "Toko Uji",
        "p_items": [{"ingredient_id": ing_g, "qty": 1, "unit": "kg",
                     "total_price": 13000}],
        "p_status": "RECEIVED"})
    check("pembelian kg diterima", status == 200, str(po)[:200])
    check("total = harga beli", po and po.get("total") == 13000)
    status, ing = req(
        f"/rest/v1/ingredients?select=balance,unit_cost&"
        f"id=eq.{ing_g}", token)
    bal = ing[0]["balance"] if ing else None
    check("saldo 1 kg = 1000 g", bal == 1000, str(bal))
    check("unit_cost = 13.000/1000g = 13",
          ing and ing[0]["unit_cost"] == 13, str(ing))

    status, po_ml = rpc(token, "inv_create_purchase", {
        "p_items": [{"ingredient_id": ing_ml, "qty": 2, "unit": "l",
                     "total_price": 10000}],
        "p_status": "RECEIVED"})
    check("pembelian 2 L -> 2000 ml", status == 200 and any(
        m["qty"] == 2000 for m in
        req(f"/rest/v1/purchase_items?select=qty&"
            f"purchase_id=eq.{po_ml['purchase_id']}", token)[1]),
        str(po_ml)[:200])

    # ------------------------------------------------------------------
    print("\n== S04-03: ORDERED belum menambah saldo; RECEIVE sekali ==")
    status, po2 = rpc(token, "inv_create_purchase", {
        "p_items": [{"ingredient_id": ing_pcs, "qty": 10, "unit": "pcs",
                     "total_price": 25000}],
        "p_status": "ORDERED"})
    check("pembelian ORDERED dibuat", status == 200, str(po2)[:200])
    status, ing = req(f"/rest/v1/ingredients?select=balance&"
                      f"id=eq.{ing_pcs}", token)
    check("ORDERED belum menambah saldo", ing and ing[0]["balance"] == 0,
          str(ing))
    status, rcv = rpc(token, "inv_receive_purchase",
                      {"p_purchase_id": po2["purchase_id"]})
    check("receive -> RECEIVED", status == 200 and
          rcv.get("status") == "RECEIVED", str(rcv)[:200])
    status, ing = req(f"/rest/v1/ingredients?select=balance&"
                      f"id=eq.{ing_pcs}", token)
    check("saldo +10 sekali", ing and ing[0]["balance"] == 10, str(ing))
    status, again = rpc(token, "inv_receive_purchase",
                        {"p_purchase_id": po2["purchase_id"]})
    check("receive kedua ditolak (tak dobel)",
          status == 400 and "already_received" in str(again),
          str(again)[:200])
    status, ing = req(f"/rest/v1/ingredients?select=balance&"
                      f"id=eq.{ing_pcs}", token)
    check("saldo tetap 10 setelah retry",
          ing and ing[0]["balance"] == 10, str(ing))

    status, moves = req(
        f"/rest/v1/stock_movements?select=source,ref&"
        f"ingredient_id=eq.{ing_pcs}", token)
    check("ledger PURCHASE tercatat tepat 1 baris untuk po ini",
          moves and len([m for m in moves
                         if m["ref"] == f"po:{po2['purchase_id']}"]) == 1,
          str(moves))

    # ------------------------------------------------------------------
    print("\n== S04-04: resep versi + HPP per porsi ==")
    status, cat = req("/rest/v1/product_categories?select=id&limit=1", token)
    pid = make_product(token, f"MENU-RESEP-{suffix}", 20000,
                       cat[0]["id"])
    check("produk uji resep terbuat", pid is not None)

    # yield 2 porsi: 200 g tepung + 100 ml susu per batch
    status, hpp0 = rpc(token, "inv_hpp", {"p_product_id": pid})
    check("sebelum resep: has_recipe=false",
          status == 200 and hpp0.get("has_recipe") is False, str(hpp0))
    status, saved = rpc(token, "inv_save_recipe", {
        "p_product_id": pid, "p_yield_qty": 2,
        "p_items": [{"ingredient_id": ing_g, "qty": 200},
                    {"ingredient_id": ing_ml, "qty": 100}]})
    check("resep v1 tersimpan", status == 200 and
          saved.get("has_recipe") is True, str(saved)[:200])
    # HPP = (200 g x 13 + 100 ml x 5) / 2 = (2600 + 500) / 2 = 1550
    status, hpp = rpc(token, "inv_hpp", {"p_product_id": pid})
    check("yield terbaca", hpp and hpp.get("yield_qty") == 2, str(hpp))
    check("HPP per porsi sesuai formula",
          hpp and hpp.get("hpp_per_portion") == 1550,
          f"{hpp and hpp.get('hpp_per_portion')} != 1550")
    check("item HPP telusur ke bahan+satuan+unit_cost",
          hpp and len(hpp.get("items", [])) == 2 and
          all("unit_cost" in it and "base_unit" in it
              for it in hpp["items"]), str(hpp))

    # Versi kedua (perubahan resep) -> versi lama tetap tersimpan.
    status, saved2 = rpc(token, "inv_save_recipe", {
        "p_product_id": pid, "p_yield_qty": 4,
        "p_items": [{"ingredient_id": ing_g, "qty": 400}]})
    check("resep v2 tersimpan", status == 200, str(saved2)[:200])
    status, vers = req(
        f"/rest/v1/recipe_versions?select=version,is_active&"
        f"product_id=eq.{pid}&order=version", token)
    check("riwayat versi lengkap (v1 nonaktif tetap ada)",
          vers and len(vers) == 2 and vers[0]["is_active"] is False
          and vers[1]["is_active"] is True, str(vers))
    # Kembalikan resep v1 sebagai aktif untuk uji checkout berikutnya.
    status, saved3 = rpc(token, "inv_save_recipe", {
        "p_product_id": pid, "p_yield_qty": 2,
        "p_items": [{"ingredient_id": ing_g, "qty": 200},
                    {"ingredient_id": ing_ml, "qty": 100}]})
    check("resep v3 (kembali ke komposisi uji)",
          status == 200 and saved3.get("hpp_per_portion") == 1550,
          str(saved3)[:200])

    # ------------------------------------------------------------------
    print("\n== S04-06: sale final memotong bahan tepat sekali ==")
    bal_before = req(f"/rest/v1/ingredients?select=balance&"
                     f"id=eq.{ing_g}", token)[1][0]["balance"]
    key = "inv-" + uuid.uuid4().hex
    status, r1 = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": pid, "qty": 2, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 100000, "p_dining_type": "TAKEAWAY",
        "p_discount_pct": 0, "p_idempotency_key": key})
    check("checkout sukses", status == 200, str(r1)[:250])
    sale_id = r1.get("sale_id") or (r1.get("sale") or {}).get("id")
    bal_after = req(f"/rest/v1/ingredients?select=balance&"
                    f"id=eq.{ing_g}", token)[1][0]["balance"]
    # 2 porsi x (200 g / yield 2) = 200 g terpakai.
    check("stok tepung berkurang 200 g sekali",
          bal_after == bal_before - 200,
          f"{bal_before} -> {bal_after}")
    status, moves = req(
        f"/rest/v1/stock_movements?select=id,ingredient_id,qty_delta&"
        f"source=eq.RECIPE&ref=eq.{sale_id}", token)
    # Satu baris per bahan resep (tepung + susu = 2), bukan per retry.
    check("ledger RECIPE per sale = 1 baris per bahan",
          status == 200 and len(moves) == 2 and
          all(m["ingredient_id"] in (ing_g, ing_ml) for m in moves),
          str(moves))

    # --- retry idempoten: key sama -> mutasi tidak bertambah ---
    status, r2 = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": pid, "qty": 2, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 100000, "p_dining_type": "TAKEAWAY",
        "p_discount_pct": 0, "p_idempotency_key": key})
    check("retry idempoten -> sale sama",
          status == 200 and r2.get("idempotent_replay") is True,
          str(r2)[:250])
    bal_retry = req(f"/rest/v1/ingredients?select=balance&"
                    f"id=eq.{ing_g}", token)[1][0]["balance"]
    check("retry TIDAK menggandakan pengurangan",
          bal_retry == bal_after, f"{bal_after} vs {bal_retry}")
    status, moves = req(
        f"/rest/v1/stock_movements?select=id&source=eq.RECIPE&"
        f"ref=eq.{sale_id}", token)
    check("ledger RECIPE tetap 2 baris setelah retry (tak bertambah)",
          len(moves) == 2, str(moves))

    # ------------------------------------------------------------------
    print("\n== UAT-06: stok kurang -> checkout ditolak ==")
    # Buat produk yang butuh 5000 g tepung per porsi (saldo jauh kurang).
    pid2 = make_product(token, f"MENU-KURANG-{suffix}", 10000,
                        cat[0]["id"])
    check("produk uji boros terbuat", pid2 is not None)
    status, s2 = rpc(token, "inv_save_recipe", {
        "p_product_id": pid2, "p_yield_qty": 1,
        "p_items": [{"ingredient_id": ing_g, "qty": 5000}]})
    check("resep boros tersimpan", status == 200, str(s2)[:200])
    key2 = "inv-" + uuid.uuid4().hex
    status, err = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": pid2, "qty": 1, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 100000, "p_dining_type": "TAKEAWAY",
        "p_discount_pct": 0, "p_idempotency_key": key2})
    check("checkout ditolak insufficient_stock",
          status == 400 and "insufficient_stock" in str(err),
          str(err)[:250])
    status, sales = req(f"/rest/v1/sales?select=id&"
                        f"idempotency_key=eq.{key2}", token)
    check("sale TIDAK tersimpan saat ditolak (rollback)",
          sales == [], str(sales))

    # ------------------------------------------------------------------
    print("\n== S04-07: produk tanpa resep -> tanpa klaim ==")
    pid3 = make_product(token, f"MENU-TANPA-RESEP-{suffix}", 5000,
                        cat[0]["id"])
    check("produk tanpa resep terbuat", pid3 is not None)
    status, hpp3 = rpc(token, "inv_hpp", {"p_product_id": pid3})
    check("tanpa resep: has_recipe=false (status jujur)",
          hpp3.get("has_recipe") is False, str(hpp3))
    bal_before = req(f"/rest/v1/ingredients?select=balance&"
                     f"id=eq.{ing_g}", token)[1][0]["balance"]
    status, r3 = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": pid3, "qty": 3, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 100000, "p_dining_type": "TAKEAWAY",
        "p_discount_pct": 0, "p_idempotency_key": "inv-" + uuid.uuid4().hex})
    check("checkout produk tanpa resep sukses", status == 200,
          str(r3)[:250])
    bal_after = req(f"/rest/v1/ingredients?select=balance&"
                    f"id=eq.{ing_g}", token)[1][0]["balance"]
    check("stok TIDAK diklaim untuk produk tanpa resep",
          bal_before == bal_after, f"{bal_before} -> {bal_after}")

    # ------------------------------------------------------------------
    print("\n== S04-07: produk BATCH — potong saat produksi saja ==")
    pid4 = make_product(token, f"MENU-GORENGAN-{suffix}", 8000,
                        cat[0]["id"])
    check("produk gorengan terbuat", pid4 is not None)
    status, patched = req(f"/rest/v1/products?id=eq.{pid4}", token,
                          {"stock_mode": "BATCH"}, method="PATCH")
    status, mode = req(f"/rest/v1/products?select=stock_mode&"
                       f"id=eq.{pid4}", token)
    check("produk gorengan ber-mode BATCH",
          mode and mode[0]["stock_mode"] == "BATCH", str(mode))
    # Resep batch: 300 g tepung -> yield 6 pcs gorengan.
    status, sb = rpc(token, "inv_save_recipe", {
        "p_product_id": pid4, "p_yield_qty": 6,
        "p_items": [{"ingredient_id": ing_g, "qty": 300}]})
    check("resep batch tersimpan", status == 200, str(sb)[:200])
    bal0 = req(f"/rest/v1/ingredients?select=balance&"
               f"id=eq.{ing_g}", token)[1][0]["balance"]
    status, batch = rpc(token, "inv_produce_batch", {
        "p_product_id": pid4, "p_qty_produced": 6, "p_note": "uji"})
    check("produksi batch sukses", status == 200, str(batch)[:200])
    bal1 = req(f"/rest/v1/ingredients?select=balance&"
               f"id=eq.{ing_g}", token)[1][0]["balance"]
    check("produksi memotong 300 g sekali", bal1 == bal0 - 300,
          f"{bal0} -> {bal1}")

    # Jual 2 gorengan: stok bahan tidak boleh berkurang lagi.
    status, r4 = rpc(token, "pos_checkout", {
        "p_items": [{"product_id": pid4, "qty": 2, "modifier_ids": []}],
        "p_method": "CASH", "p_paid": 100000, "p_dining_type": "TAKEAWAY",
        "p_discount_pct": 0, "p_idempotency_key": "inv-" + uuid.uuid4().hex})
    check("penjualan batch sukses", status == 200, str(r4)[:250])
    bal2 = req(f"/rest/v1/ingredients?select=balance&"
               f"id=eq.{ing_g}", token)[1][0]["balance"]
    check("penjualan TIDAK memotong bahan lagi (tanpa dobel)",
          bal2 == bal1, f"{bal1} -> {bal2}")

    # ------------------------------------------------------------------
    print("\n== S04-02: waste/koreksi beralasan ==")
    status, werr = rpc(token, "inv_adjust_stock", {
        "p_ingredient_id": ing_g, "p_qty": 50, "p_reason": "x",
        "p_idempotency_key": uuid.uuid4().hex})
    check("alasan < 3 huruf ditolak", status == 400, str(status))
    status, waste = rpc(token, "inv_adjust_stock", {
        "p_ingredient_id": ing_g, "p_qty": 50, "p_source": "WASTE",
        "p_reason": "jatuh ke lantai", "p_idempotency_key": uuid.uuid4().hex})
    check("waste tercatat", status == 200, str(waste)[:200])
    status, moves = req(
        f"/rest/v1/stock_movements?select=reason,source&"
        f"ingredient_id=eq.{ing_g}&source=eq.WASTE&order=id.desc&limit=1",
        token)
    check("ledger WASTE beralasan", status == 200 and moves and
          "jatuh ke lantai" in moves[0]["reason"], str(moves))
    status, adj = rpc(token, "inv_adjust_stock", {
        "p_ingredient_id": ing_g, "p_qty": 25, "p_source": "ADJUSTMENT",
        "p_reason": "stock opname fisik", "p_idempotency_key": uuid.uuid4().hex})
    check("koreksi +25 tercatat", status == 200, str(adj)[:200])
    status, bad = rpc(token, "inv_adjust_stock", {
        "p_ingredient_id": ing_g, "p_qty": 10, "p_source": "MAGIC",
        "p_reason": "sumber tidak dikenal", "p_idempotency_key": uuid.uuid4().hex})
    check("sumber selain ADJUSTMENT/WASTE ditolak", status == 400,
          str(status))

    # ------------------------------------------------------------------
    print("\n== S04-05: ledger append-only ==")
    status, mv = req(f"/rest/v1/stock_movements?select=id,balance_after"
                     f"&limit=1", token)
    mid = mv[0]["id"]
    status, upd = req(f"/rest/v1/stock_movements?id=eq.{mid}", token,
                      {"balance_after": 999999}, method="PATCH")
    # RLS operator hanya SELECT: patch tidak mengubah baris apa pun.
    status2, mv2 = req(f"/rest/v1/stock_movements?select=balance_after"
                       f"&id=eq.{mid}", token)
    check("UPDATE ledger tidak mengubah baris (SELECT-only)",
          mv2 and mv2[0]["balance_after"] == mv[0]["balance_after"],
          str(mv2))
    status, dl = req(f"/rest/v1/stock_movements?id=eq.{mid}", token,
                     method="DELETE")
    status2, mv3 = req(f"/rest/v1/stock_movements?select=id"
                       f"&id=eq.{mid}", token)
    check("DELETE ledger tidak menghapus baris", mv3 == [mv[0]]
          or mv3 == [{"id": mid}], str(mv3))

    # ------------------------------------------------------------------
    print("\n== RLS: anon tertutup ==")
    status, anon = req("/rest/v1/ingredients?select=id")
    check("anon tidak bisa baca bahan", status in (401, 403) or anon == [],
          str(status))
    status, anon = req("/rest/v1/stock_movements?select=id")
    check("anon tidak bisa baca ledger", status in (401, 403) or anon == [],
          str(status))
    status, anon = req("/rest/v1/rpc/inv_create_purchase", body={
        "p_items": []})
    check("anon tidak bisa memanggil RPC inventori",
          status in (401, 403), str(status))

    # ------------------------------------------------------------------
    print(f"\nRingkasan: {passed} PASS, {failed} FAIL")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
