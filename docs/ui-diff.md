# UI Diff — Flutter vs `index.html`

`index.html` dipakai sebagai referensi struktur/hierarki/interaksi. Deviasi wajib
dicatat di sini (Prompt.md §1).

| Bagian mockup | Keadaan mockup | Keputusan Flutter | Alasan |
|---|---|---|---|
| Palet warna | Hijau `#24543a`/`#2f7550` | Brand `#930031` + token Prompt.md §3.1 | PRD v2.1 §9.1 mengungguli mockup |
| Ikon menu | Emoji (`🍗 🍜 🥘`) | `Icons.*` Material (mis. `restaurant_menu_rounded`) | Larangan emoji; ikon native |
| Halaman "AI Insights" | Kartu AI + angka simulasi | Tidak dibuat sama sekali | MVP tanpa ML (PRD §9) |
| Halaman "Promo" | Terpisah di nav | Tidak ada di Sprint 01 (menu promo menyusul di Sprint 02 sesuai PRD SCR-04) | S01-03 tidak memasukkan Promo |
| Kartu Kitchen/Pesanan | Board dapur + status PREPARING/READY | Tidak ada | Scope single-operator v2.1 |
| Data demo | localStorage browser | Database Supabase, fixture dev berlabel `[DEMO]` | Larangan localStorage sebagai DB |
| Bottom nav HP | 4 item + tombol aksi | Beranda, Kasir, Stok, Laporan, Lainnya | PRD §4.1 |
| Header modul HP | Mockup lebar tetap | Header dapat membungkus; kartu laporan setinggi konten | Regresi S06: tujuh modul overflow di 390×844 |
| POS tablet 1024 | Katalog + keranjang | Breakpoint area konten 720dp setelah sidebar | Dua kolom tetap tampil di tablet landscape |
| Pengaturan | Form preferensi | Profil/tarif aktual dapat diedit dari UI via RPC guarded + audit (`0016`); printer/offline tetap tidak tersedia | Bukan placeholder; validasi dan audit di server, belum diuji di device |
