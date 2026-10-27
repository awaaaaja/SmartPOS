# Graph Report - Smart_POS  (2026-10-27)

## Corpus Check
- 105 files · ~507,027 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1252 nodes · 1694 edges · 76 communities (68 shown, 8 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `4019874c`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- StatelessWidget
- pos_page.dart
- catalog_repository.dart
- history_page.dart
- pos_repository.dart
- package:flutter_riverpod/flutter_riverpod.dart
- shell.dart
- catalog_page.dart
- sale_models.dart
- Prompt.md
- PRD.md
- catalog_models.dart
- Sprints.md
- package.json
- formatters.dart
- Sprint 02 — Katalog & Kasir POS (End-to-End)
- theme.dart
- mutation_retry_forms_test.dart
- login_page_test.dart
- manifest.json
- @immutable
- _
- _PosPageState
- shell_test.dart
- package:flutter/material.dart
- App.vue
- catalogRepositoryProvider
- Serah terima QA MVP — 27 Oktober 2026
- Decision Log
- API Contracts
- test_pos_api.py
- _NewModifierForm
- tables_repository.dart
- MainActivity
- inventory_repository.dart
- pos_flutter
- reports_page.dart
- ui-diff.md
- apply_migrations.sh
- supabase.ts
- purchases_page.dart
- qr_page.dart
- qr_inbox_sheet_test.dart
- package:supabase_flutter/supabase_flutter.dart
- categoriesProvider
- TablesQrPage
- recipes_page.dart
- test_qr_drafts.py
- expenses_page.dart
- stock_page.dart
- _HppDetail
- inventory_pages_test.dart
- MutationRetryTest
- test_inventory.py
- package:flutter_test/flutter_test.dart
- energy_page.dart
- login_page.dart
- ConsumerWidget
- page_layout_test.dart
- module_placeholder.dart
- test_operating_cost.py
- ConsumerState
- csv_export_web.dart
- mutation_retry.dart
- csv_export.dart
- main.dart
- mutation_retry_test.dart
- pos_mobile_test.dart
- memory_preferences.dart
- Qty
- DashboardPage
- fix-refund-stock-retry.md

## God Nodes (most connected - your core abstractions)
1. `_` - 96 edges
2. `MutationRetryTest` - 15 edges
3. `catalogRepositoryProvider` - 8 edges
4. `ingredientsProvider` - 8 edges
5. `_PosPageState` - 8 edges
6. `operatingRepositoryProvider` - 7 edges
7. `_RecipesHppPageState` - 7 edges
8. `5. PROMPT PER SPRINT — EKSEKUSI BERURUTAN` - 7 edges
9. `Serah terima QA MVP — 27 Oktober 2026` - 7 edges
10. `Sprint Log` - 7 edges

## Surprising Connections (you probably didn't know these)
- `_AppShellState` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/app/shell.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `_submit` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/auth/login_page.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `CashShiftPage` --references--> `operatingRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/cash_shift/cash_page.dart → apps/pos_flutter/lib/features/operating_cost/operating_repository.dart
- `_openShift` --references--> `operatingRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/cash_shift/cash_page.dart → apps/pos_flutter/lib/features/operating_cost/operating_repository.dart
- `CatalogPage` --references--> `catalogRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/catalog/catalog_page.dart → apps/pos_flutter/lib/features/catalog/catalog_repository.dart

## Import Cycles
- None detected.

## Communities (76 total, 8 thin omitted)

### Community 0 - "StatelessWidget"
Cohesion: 0.12
Nodes (17): _SessionErrorScreen, _Sidebar, _SidebarTile, _SplashScreen, _EmptyCatalog, _ErrorRetry, _PhotoThumb, _CartLineTile (+9 more)

### Community 1 - "pos_page.dart"
Cohesion: 0.04
Nodes (52): cart, _categoryFilter, categoryNames, _claimedDraftIds, createState, dispose, _error, _fetchQuote (+44 more)

### Community 2 - "catalog_repository.dart"
Cohesion: 0.11
Nodes (17): archiveCategory, archiveProduct, CatalogRepository, _client, createCategory, createModifier, fetchCategories, fetchModifiers (+9 more)

### Community 3 - "history_page.dart"
Cohesion: 0.08
Nodes (26): _amount, build, _busy, createState, dispose, _error, _loadPending, _maxRefund (+18 more)

### Community 4 - "pos_repository.dart"
Cohesion: 0.05
Nodes (43): add, basePrice, build, CartController, CartLine, CartState, changeQty, checkout (+35 more)

### Community 5 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.12
Nodes (19): app/theme.dart, _closeShift, _row, color, icon, _StatCard, subtitle, title (+11 more)

### Community 6 - "shell.dart"
Cohesion: 0.07
Nodes (29): createState, _current, destination, onRetry, onSelected, onTap, _openOthers, _pageFor (+21 more)

### Community 7 - "catalog_page.dart"
Cohesion: 0.06
Nodes (35): _allModifiers, _attached, _busy, _categoryId, _chipStyle, _controller, createState, _delta (+27 more)

### Community 8 - "sale_models.dart"
Cohesion: 0.06
Nodes (31): allTimeRevenue, allTimeTransactions, changeAmount, createdAt, diningType, discountAmount, fromJson, id (+23 more)

### Community 9 - "Prompt.md"
Cohesion: 0.07
Nodes (28): 1. Urutan Sumber Kebenaran, 2. MASTER PROMPT — SALIN KE CODING AGENT, 3.1 Identitas visual dan token, 3.2 Ikon open-source yang didukung Flutter, 3.3 Layout dan navigasi yang meniru perilaku `index.html`, 3.4 Animasi yang layak untuk produk, 3.5 Standar responsivitas dan UX, 3. Kontrak Desain Flutter: Tidak Generic AI, Tidak Emoji (+20 more)

### Community 10 - "PRD.md"
Cohesion: 0.07
Nodes (26): 10. Persyaratan Non-Fungsional, 11. Uji Penerimaan Utama (UAT), 12. Release Scope dan Rencana Implementasi, 13. Kriteria Rilis, 1.1 Masalah yang diselesaikan, 1.2 Ukuran keberhasilan yang harus diuji, 1. Ringkasan Produk, 2.1 Dalam cakupan (+18 more)

### Community 11 - "catalog_models.dart"
Cohesion: 0.09
Nodes (22): archivedAt, categoryId, categoryName, effectiveAt, fromJson, id, isActive, isArchived (+14 more)

### Community 12 - "Sprints.md"
Cohesion: 0.10
Nodes (19): 10. Kontrak Halaman dan File yang Direkomendasikan, 11. Integrasi CRUD dan UI Prioritas, 12. Template Issue Pengembangan, 13. Catatan Progres dan Change Log, 1.1 Prioritas, 1.2 Status tiket, 1.3 Definition of Done umum, 1. Prinsip Arsitektur yang Tidak Boleh Dilanggar (+11 more)

### Community 13 - "package.json"
Cohesion: 0.11
Nodes (18): dependencies, @supabase/supabase-js, vue, devDependencies, vite, @vitejs/plugin-vue, name, private (+10 more)

### Community 14 - "formatters.dart"
Cohesion: 0.12
Nodes (15): abs, base, body, formatNumber, formatRupiah, formatWib, formatWibDate, formatWibTime (+7 more)

### Community 15 - "Sprint 02 — Katalog & Kasir POS (End-to-End)"
Cohesion: 0.05
Nodes (39): Acceptance Criteria, Acceptance Criteria, Alur bukti end-to-end (Chrome, bukan mock), Blocker yang ditemukan: K06-01 — retry menggandakan mutasi (DIPERBAIKI), Bukti E2E (Chrome, build web final), Bukti E2E (Chrome, build web final, tablet 1280×800), Gate S04, Gate S05 (+31 more)

### Community 16 - "theme.dart"
Cohesion: 0.14
Nodes (13): borderColor, brandDark, brandPrimary, brandSoft, buildAppTheme, canvasColor, errorColor, scheme (+5 more)

### Community 17 - "mutation_retry_forms_test.dart"
Cohesion: 0.06
Nodes (31): adjustStock, _app, balance, _fields, ingredient, main, movements, noSuchMethod (+23 more)

### Community 18 - "login_page_test.dart"
Cohesion: 0.18
Nodes (10): currentUser, lastEmail, lastPassword, main, _pumpLogin, pumpWidget, signIn, signOut (+2 more)

### Community 19 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 20 - "@immutable"
Cohesion: 0.20
Nodes (10): @immutable, Modifier, PriceHistoryEntry, Product, ProductCategory, DashboardSummary, Quote, Receipt (+2 more)

### Community 21 - "_"
Cohesion: 0.03
Nodes (74): _, actualAmount, actualCash, allocate, allocatedTotal, allocations, amount, cashSales (+66 more)

### Community 22 - "_PosPageState"
Cohesion: 0.20
Nodes (12): build, _claimDraft, _completeClaimedDrafts, _openCartSheet, _openPayment, PosPage, _PosPageState, cartControllerProvider (+4 more)

### Community 23 - "shell_test.dart"
Cohesion: 0.14
Nodes (13): AuthRepository, currentUser, _FakeAuthRepository, main, _setSurface, signedOut, signIn, signOut (+5 more)

### Community 24 - "package:flutter/material.dart"
Cohesion: 0.20
Nodes (9): main, main, main, package:flutter/material.dart, package:pos_flutter/app/theme.dart, package:pos_flutter/core/models/catalog_models.dart, package:pos_flutter/core/widgets/module_placeholder.dart, package:pos_flutter/features/catalog/catalog_page.dart (+1 more)

### Community 25 - "App.vue"
Cohesion: 0.06
Nodes (24): supabase, cart, cartCount, cartOpen, cartSubtotal, categories, clientKey, confirmation (+16 more)

### Community 26 - "catalogRepositoryProvider"
Cohesion: 0.29
Nodes (7): _addCategory, _confirmArchive, _editProduct, _ProductTile, _ProductTileState, _showPriceHistory, catalogRepositoryProvider

### Community 27 - "Serah terima QA MVP — 27 Oktober 2026"
Cohesion: 0.07
Nodes (26): Backup dan latihan restore Sprint 06, Bukti yang sudah ada, Prosedur pengulangan (staging saja), Evidence Sprint 06 — QA, bukan persetujuan produksi, 1. Blocker / known issues, 2. Setup Supabase, 3. Build, signing dan pemasangan Android, 4. Migrasi, backup dan rollback (+18 more)

### Community 28 - "Decision Log"
Cohesion: 0.29
Nodes (6): D-01 (2026-10-26) — API bisnis authoritative = fungsi Postgres (bukan FastAPI terpisah), D-02 (2026-10-26) — Penanda satu operator = `business_settings.operator_email`, D-03 (2026-10-26) — Token meja disimpan sebagai hash SHA-256, D-04 (2026-10-26) — WIB dihitung manual (UTC+7), bukan paket zona waktu, D-05 (2026-10-26) — Konfigurasi Flutter via `--dart-define`, layar konfigurasi jujur, Decision Log

### Community 29 - "API Contracts"
Cohesion: 0.29
Nodes (6): API Contracts, Keamanan, Mutasi yang wajib idempotency key (S06, migrasi `0013`), Operator (sesi login, via authenticated + RLS), Publik (tanpa sesi, via anon key), `rpc get_public_menu(p_table_token text) -> jsonb`

### Community 30 - "test_pos_api.py"
Cohesion: 0.53
Nodes (5): check(), half_up(), main(), Postgres round(numeric) = setengah ke atas (bukan banker's rounding)., req()

### Community 31 - "_NewModifierForm"
Cohesion: 0.50
Nodes (4): _NewModifierForm, _NewModifierFormState, State, StatefulWidget

### Community 32 - "tables_repository.dart"
Cohesion: 0.06
Nodes (35): cancel, claim, _client, complete, createdAt, createTable, draftId, fetchTables (+27 more)

### Community 34 - "inventory_repository.dart"
Cohesion: 0.03
Nodes (57): adjustStock, balance, balanceAfter, baseUnit, _client, cost, createdAt, createPurchase (+49 more)

### Community 36 - "reports_page.dart"
Cohesion: 0.20
Nodes (13): reportProvider, reportRangeProvider, b, build, buildReportCsv, _card, _pickRange, _refresh (+5 more)

### Community 44 - "purchases_page.dart"
Cohesion: 0.13
Nodes (15): Purchase, purchasesProvider, build, _formatDate, ingredientId, _LineState, onReceive, price (+7 more)

### Community 45 - "qr_page.dart"
Cohesion: 0.13
Nodes (14): _createTable, onRotate, onToggle, qrUrlFor, qrWebBaseUrl, _rotate, _showTokenDialog, table (+6 more)

### Community 46 - "qr_inbox_sheet_test.dart"
Cohesion: 0.22
Nodes (8): _draft, _harness, main, _open, pumpAndSettle, tap, package:pos_flutter/features/pos/qr_inbox_sheet.dart, package:pos_flutter/features/tables_qr/tables_repository.dart

### Community 47 - "package:supabase_flutter/supabase_flutter.dart"
Cohesion: 0.16
Nodes (11): file, saveCsvFile, writeAsString, m, _mapBusinessError, mapErrorToMessage, main, dart:async (+3 more)

### Community 48 - "categoriesProvider"
Cohesion: 0.25
Nodes (8): build, CatalogPage, _CategorySheet, _CategorySheetState, _ProductDialog, _ProductDialogState, categoriesProvider, productsProvider

### Community 49 - "TablesQrPage"
Cohesion: 0.40
Nodes (5): build, TablesQrPage, _toggle, tablesListProvider, tablesRepositoryProvider

### Community 50 - "recipes_page.dart"
Cohesion: 0.12
Nodes (16): RecipeProduct, createState, ingredientId, onBatch, onChanged, onEdit, _produceBatch, product (+8 more)

### Community 51 - "test_qr_drafts.py"
Cohesion: 0.80
Nodes (4): check(), main(), req(), rpc()

### Community 52 - "expenses_page.dart"
Cohesion: 0.05
Nodes (42): AppDestination, byGroup, group, _groupFinance, _groupMain, _groupProduct, groups, icon (+34 more)

### Community 53 - "stock_page.dart"
Cohesion: 0.13
Nodes (18): Ingredient, ingredientSearchProvider, ingredientsProvider, build, createState, dispose, _editIngredient, ingredient (+10 more)

### Community 54 - "_HppDetail"
Cohesion: 0.50
Nodes (5): hppProvider, recipeProductsProvider, recipeVersionsProvider, build, _HppDetail

### Community 55 - "inventory_pages_test.dart"
Cohesion: 0.29
Nodes (6): _app, main, package:pos_flutter/features/inventory/inventory_repository.dart, package:pos_flutter/features/inventory/stock_page.dart, package:pos_flutter/features/purchases/purchases_page.dart, package:pos_flutter/features/recipes_hpp/recipes_page.dart

### Community 57 - "test_inventory.py"
Cohesion: 0.57
Nodes (6): check(), main(), make_product(), POST products tidak mengembalikan baris -> query balik by name., req(), rpc()

### Community 58 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.25
Nodes (6): main, line, main, package:flutter_test/flutter_test.dart, package:pos_flutter/core/formatters.dart, package:pos_flutter/features/pos/pos_repository.dart

### Community 59 - "energy_page.dart"
Cohesion: 0.07
Nodes (26): _batchHours, build, createState, dispose, _effHours, _electricForm, _field, _hours (+18 more)

### Community 60 - "login_page.dart"
Cohesion: 0.07
Nodes (28): AuthGate, build, async, authRepositoryProvider, authStateProvider, _client, currentUser, isAuthenticatedProvider (+20 more)

### Community 61 - "ConsumerWidget"
Cohesion: 0.22
Nodes (9): build, CashShiftPage, inventoryRepositoryProvider, _adjust, cashStatusProvider, PurchasesPage, _receive, SettingsPage (+1 more)

### Community 62 - "page_layout_test.dart"
Cohesion: 0.13
Nodes (17): main, pages, report, _app, _day0, _day1, main, package:pos_flutter/features/cash_shift/cash_page.dart (+9 more)

### Community 63 - "module_placeholder.dart"
Cohesion: 0.25
Nodes (7): build, description, icon, ModulePlaceholder, targetSprint, title, IconData

### Community 64 - "test_operating_cost.py"
Cohesion: 0.52
Nodes (6): check(), err_code(), main(), Ambil message dari error PostgREST (P0001 -> pesan kita)., req(), rpc()

### Community 65 - "ConsumerState"
Cohesion: 0.15
Nodes (17): AppShell, _AppShellState, EnergyPage, _EnergyPageState, _ModifierSheet, _ModifierSheetState, _PaymentSheet, _PaymentSheetState (+9 more)

### Community 66 - "csv_export_web.dart"
Cohesion: 0.33
Nodes (5): blob, saveCsvFile, url, dart:js_interop, package:web/web.dart

### Community 67 - "mutation_retry.dart"
Cohesion: 0.12
Nodes (15): _active, decode, encode, key, mutationRetryStoreProvider, params, pending, PendingMutation (+7 more)

### Community 69 - "main.dart"
Cohesion: 0.22
Nodes (8): app/shell.dart, build, initialize, main, MissingConfigApp, PosApp, supabasePublishableKey, supabaseUrl

### Community 70 - "mutation_retry_test.dart"
Cohesion: 0.17
Nodes (11): MutationRetryStore, main, params, preferences, store, submit, FormatException, ../helpers/memory_preferences.dart (+3 more)

### Community 71 - "pos_mobile_test.dart"
Cohesion: 0.29
Nodes (6): main, noSuchMethod, quote, quotedQty, package:pos_flutter/core/models/sale_models.dart, package:pos_flutter/features/pos/pos_page.dart

### Community 72 - "memory_preferences.dart"
Cohesion: 0.20
Nodes (9): failures, getString, MemoryPreferences, noSuchMethod, remove, setString, values, package:shared_preferences/shared_preferences.dart (+1 more)

### Community 73 - "Qty"
Cohesion: 0.40
Nodes (5): InventoryRepository, RecipeHpp, RecipeVersion, _Inventory, Qty

### Community 74 - "DashboardPage"
Cohesion: 0.67
Nodes (4): build, DashboardPage, dashboardReportProvider, dashboardSummaryProvider

## Knowledge Gaps
- **783 isolated node(s):** `label`, `icon`, `group`, `mobileLabel`, `_groupMain` (+778 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_` connect `_` to `inventory_repository.dart`, `reports_page.dart`, `package:flutter_riverpod/flutter_riverpod.dart`, `sale_models.dart`, `DashboardPage`, `catalog_models.dart`, `package:supabase_flutter/supabase_flutter.dart`, `recipes_page.dart`, `login_page_test.dart`, `expenses_page.dart`, `energy_page.dart`, `login_page.dart`, `ConsumerWidget`?**
  _High betweenness centrality (0.108) - this node is a cross-community bridge._
- **Why does `MutationRetryStore` connect `mutation_retry_test.dart` to `mutation_retry_forms_test.dart`, `inventory_repository.dart`, `mutation_retry.dart`, `pos_repository.dart`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Why does `_RecipesHppPageState` connect `recipes_page.dart` to `Qty`, `ConsumerState`, `stock_page.dart`, `_HppDetail`?**
  _High betweenness centrality (0.008) - this node is a cross-community bridge._
- **What connects `label`, `icon`, `group` to the rest of the system?**
  _783 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `StatelessWidget` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `pos_page.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.03773584905660377 - nodes in this community are weakly interconnected._
- **Should `catalog_repository.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._