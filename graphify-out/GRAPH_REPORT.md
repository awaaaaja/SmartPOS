# Graph Report - Smart_POS  (2026-10-27)

## Corpus Check
- 107 files · ~454,179 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1320 nodes · 1842 edges · 81 communities (73 shown, 8 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `0b95afee`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- StatelessWidget
- pos_page.dart
- catalog_repository.dart
- history_page.dart
- pos_repository.dart
- dashboard_page.dart
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
- package:flutter_riverpod/flutter_riverpod.dart
- package:supabase_flutter/supabase_flutter.dart
- categoriesProvider
- TablesQrPage
- recipes_page.dart
- test_qr_drafts.py
- expenses_page.dart
- stock_page.dart
- remaining_mutation_retry_test.dart
- inventory_pages_test.dart
- MutationRetryTest
- test_inventory.py
- destinations.dart
- energy_page.dart
- login_page.dart
- cash_page.dart
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
- ../../core/error_mapper.dart
- fix-refund-stock-retry.md
- auth_repository.dart
- reportProvider
- _SaleDetailSheetState
- AuthRepository
- _EnergyPageState

## God Nodes (most connected - your core abstractions)
1. `_` - 105 edges
2. `MutationRetryTest` - 30 edges
3. `catalogRepositoryProvider` - 8 edges
4. `inventoryRepositoryProvider` - 8 edges
5. `ingredientsProvider` - 8 edges
6. `_PosPageState` - 8 edges
7. `_RecipesHppPageState` - 8 edges
8. `quoted()` - 8 edges
9. `5. PROMPT PER SPRINT — EKSEKUSI BERURUTAN` - 7 edges
10. `Serah terima QA MVP — 27 Oktober 2026` - 7 edges

## Surprising Connections (you probably didn't know these)
- `_AppShellState` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/app/shell.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `build` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/app/shell.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `_` --references--> `MutationRetryStore`  [EXTRACTED]
  apps/pos_flutter/lib/features/operating_cost/operating_repository.dart → apps/pos_flutter/lib/core/mutation_retry.dart
- `_submit` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/auth/login_page.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `_openShift` --references--> `operatingRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/cash_shift/cash_page.dart → apps/pos_flutter/lib/features/operating_cost/operating_repository.dart

## Import Cycles
- None detected.

## Communities (81 total, 8 thin omitted)

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
Nodes (40): add, basePrice, build, CartController, CartLine, CartState, changeQty, checkout (+32 more)

### Community 5 - "dashboard_page.dart"
Cohesion: 0.22
Nodes (8): color, icon, _StatCard, subtitle, title, value, Color, ../pos/pos_repository.dart

### Community 6 - "shell.dart"
Cohesion: 0.06
Nodes (32): AuthGate, build, createState, _current, destination, onRetry, onSelected, onTap (+24 more)

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
Cohesion: 0.08
Nodes (23): archivedAt, categoryId, categoryName, effectiveAt, fromJson, id, isActive, isArchived (+15 more)

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
Nodes (40): Acceptance Criteria, Acceptance Criteria, Alur bukti end-to-end (Chrome, bukan mock), Blocker yang ditemukan: K06-01 — retry menggandakan mutasi (DIPERBAIKI), Bukti E2E (Chrome, build web final), Bukti E2E (Chrome, build web final, tablet 1280×800), Gate S04, Gate S05 (+32 more)

### Community 16 - "theme.dart"
Cohesion: 0.14
Nodes (13): borderColor, brandDark, brandPrimary, brandSoft, buildAppTheme, canvasColor, errorColor, scheme (+5 more)

### Community 17 - "mutation_retry_forms_test.dart"
Cohesion: 0.07
Nodes (29): adjustStock, _app, balance, _fields, ingredient, main, movements, noSuchMethod (+21 more)

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
Nodes (78): _, actualAmount, actualCash, allocate, allocatedTotal, allocations, amount, cashSales (+70 more)

### Community 22 - "_PosPageState"
Cohesion: 0.29
Nodes (8): _claimDraft, _completeClaimedDrafts, _openCartSheet, _openPayment, PosPage, _PosPageState, cartControllerProvider, qrDraftRepositoryProvider

### Community 23 - "shell_test.dart"
Cohesion: 0.18
Nodes (10): currentUser, main, _setSurface, signedOut, signIn, signOut, _wrap, package:pos_flutter/app/shell.dart (+2 more)

### Community 24 - "package:flutter/material.dart"
Cohesion: 0.16
Nodes (12): main, main, main, main, package:flutter/material.dart, package:flutter_test/flutter_test.dart, package:pos_flutter/app/theme.dart, package:pos_flutter/core/formatters.dart (+4 more)

### Community 25 - "App.vue"
Cohesion: 0.06
Nodes (24): supabase, cart, cartCount, cartOpen, cartSubtotal, categories, clientKey, confirmation (+16 more)

### Community 26 - "catalogRepositoryProvider"
Cohesion: 0.29
Nodes (7): _addCategory, _confirmArchive, _editProduct, _ProductTile, _ProductTileState, _showPriceHistory, catalogRepositoryProvider

### Community 27 - "Serah terima QA MVP — 27 Oktober 2026"
Cohesion: 0.07
Nodes (27): Backup dan latihan restore Sprint 06, Bukti yang sudah ada, Prosedur pengulangan (staging saja), Evidence Sprint 06 — QA, bukan persetujuan produksi, 1. Blocker / known issues, 2. Setup Supabase, 3. Build, signing dan pemasangan Android, 4. Migrasi, backup dan rollback (+19 more)

### Community 28 - "Decision Log"
Cohesion: 0.29
Nodes (6): D-01 (2026-10-26) — API bisnis authoritative = fungsi Postgres (bukan FastAPI terpisah), D-02 (2026-10-26) — Penanda satu operator = `business_settings.operator_email`, D-03 (2026-10-26) — Token meja disimpan sebagai hash SHA-256, D-04 (2026-10-26) — WIB dihitung manual (UTC+7), bukan paket zona waktu, D-05 (2026-10-26) — Konfigurasi Flutter via `--dart-define`, layar konfigurasi jujur, Decision Log

### Community 29 - "API Contracts"
Cohesion: 0.25
Nodes (7): API Contracts, Keamanan, Mutasi yang wajib idempotency key (S06, migrasi `0013`–`0014`), Operator (sesi login, via authenticated + RLS), Publik (tanpa sesi, via anon key), `rpc get_public_menu(p_table_token text) -> jsonb`, RPC lain dalam audit retry uang/stok

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
Nodes (59): adjustStock, balance, balanceAfter, baseUnit, _client, cost, createdAt, createPurchase (+51 more)

### Community 36 - "reports_page.dart"
Cohesion: 0.16
Nodes (12): app/theme.dart, build, QrInboxSheet, b, _card, _stat, _statsGrid, toString (+4 more)

### Community 44 - "purchases_page.dart"
Cohesion: 0.13
Nodes (16): Purchase, purchasesProvider, build, _formatDate, ingredientId, _LineState, onReceive, price (+8 more)

### Community 45 - "qr_page.dart"
Cohesion: 0.13
Nodes (14): _createTable, onRotate, onToggle, qrUrlFor, qrWebBaseUrl, _rotate, _showTokenDialog, table (+6 more)

### Community 46 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.22
Nodes (8): _draft, _harness, main, _open, pumpAndSettle, tap, package:flutter_riverpod/flutter_riverpod.dart, package:pos_flutter/features/pos/qr_inbox_sheet.dart

### Community 47 - "package:supabase_flutter/supabase_flutter.dart"
Cohesion: 0.16
Nodes (11): file, saveCsvFile, writeAsString, m, _mapBusinessError, mapErrorToMessage, main, dart:async (+3 more)

### Community 48 - "categoriesProvider"
Cohesion: 0.33
Nodes (7): build, CatalogPage, _CategorySheet, _CategorySheetState, categoriesProvider, productsProvider, build

### Community 49 - "TablesQrPage"
Cohesion: 0.40
Nodes (5): build, TablesQrPage, _toggle, tablesListProvider, tablesRepositoryProvider

### Community 50 - "recipes_page.dart"
Cohesion: 0.11
Nodes (20): hppProvider, RecipeProduct, recipeProductsProvider, recipeVersionsProvider, build, createState, _HppDetail, ingredientId (+12 more)

### Community 51 - "test_qr_drafts.py"
Cohesion: 0.80
Nodes (4): check(), main(), req(), rpc()

### Community 52 - "expenses_page.dart"
Cohesion: 0.08
Nodes (29): _allocate, AllocationSheet, _AllocationSheetState, _amount, build, createState, _date, _desc (+21 more)

### Community 53 - "stock_page.dart"
Cohesion: 0.11
Nodes (22): Ingredient, ingredientSearchProvider, ingredientsProvider, inventoryRepositoryProvider, _adjust, build, createState, dispose (+14 more)

### Community 54 - "remaining_mutation_retry_test.dart"
Cohesion: 0.07
Nodes (26): _app, calls, client, close, inventory, loseFirst, main, _open (+18 more)

### Community 55 - "inventory_pages_test.dart"
Cohesion: 0.29
Nodes (6): _app, main, package:pos_flutter/features/inventory/inventory_repository.dart, package:pos_flutter/features/inventory/stock_page.dart, package:pos_flutter/features/purchases/purchases_page.dart, package:pos_flutter/features/recipes_hpp/recipes_page.dart

### Community 57 - "test_inventory.py"
Cohesion: 0.57
Nodes (6): check(), main(), make_product(), POST products tidak mengembalikan baris -> query balik by name., req(), rpc()

### Community 58 - "destinations.dart"
Cohesion: 0.14
Nodes (13): AppDestination, byGroup, group, _groupFinance, _groupMain, _groupProduct, groups, icon (+5 more)

### Community 59 - "energy_page.dart"
Cohesion: 0.06
Nodes (31): _batchHours, build, createState, dispose, _effHours, _electricForm, _error, _field (+23 more)

### Community 60 - "login_page.dart"
Cohesion: 0.14
Nodes (15): authRepositoryProvider, build, createState, dispose, _emailController, _error, _formKey, LoginPage (+7 more)

### Community 61 - "cash_page.dart"
Cohesion: 0.24
Nodes (9): build, CashShiftPage, _closeShift, _openShift, _row, _loadPending, cashStatusProvider, operatingRepositoryProvider (+1 more)

### Community 62 - "page_layout_test.dart"
Cohesion: 0.09
Nodes (24): OperatingRepository, main, noSuchMethod, _Operating, pages, pendingEnergyEstimate, report, state (+16 more)

### Community 63 - "module_placeholder.dart"
Cohesion: 0.25
Nodes (7): build, description, icon, ModulePlaceholder, targetSprint, title, IconData

### Community 64 - "test_operating_cost.py"
Cohesion: 0.52
Nodes (6): check(), err_code(), main(), Ambil message dari error PostgREST (P0001 -> pesan kita)., req(), rpc()

### Community 65 - "ConsumerState"
Cohesion: 0.20
Nodes (14): AppShell, _AppShellState, _ProductDialog, _ProductDialogState, _ExpenseEditor, _ExpenseEditorState, _ModifierSheet, _ModifierSheetState (+6 more)

### Community 66 - "csv_export_web.dart"
Cohesion: 0.33
Nodes (5): blob, saveCsvFile, url, dart:js_interop, package:web/web.dart

### Community 67 - "mutation_retry.dart"
Cohesion: 0.12
Nodes (16): _active, decode, encode, key, mutationRetryStoreProvider, params, pending, PendingMutation (+8 more)

### Community 69 - "main.dart"
Cohesion: 0.22
Nodes (8): app/shell.dart, build, initialize, main, MissingConfigApp, PosApp, supabasePublishableKey, supabaseUrl

### Community 70 - "mutation_retry_test.dart"
Cohesion: 0.17
Nodes (11): MutationRetryStore, main, params, preferences, store, submit, FormatException, ../helpers/memory_preferences.dart (+3 more)

### Community 71 - "pos_mobile_test.dart"
Cohesion: 0.13
Nodes (13): PosRepository, line, main, _Pos, main, noSuchMethod, quote, quotedQty (+5 more)

### Community 72 - "memory_preferences.dart"
Cohesion: 0.20
Nodes (9): failures, getString, MemoryPreferences, noSuchMethod, remove, setString, values, package:shared_preferences/shared_preferences.dart (+1 more)

### Community 73 - "Qty"
Cohesion: 0.40
Nodes (5): InventoryRepository, RecipeHpp, RecipeVersion, _Inventory, Qty

### Community 74 - "../../core/error_mapper.dart"
Cohesion: 0.20
Nodes (10): build, DashboardPage, dashboardReportProvider, dashboardSummaryProvider, build, businessSettingsProvider, SettingsPage, ../auth/auth_repository.dart (+2 more)

### Community 76 - "auth_repository.dart"
Cohesion: 0.18
Nodes (10): async, _client, currentUser, isAuthenticatedProvider, maybeWhen, signIn, signOut, supabaseClientProvider (+2 more)

### Community 77 - "reportProvider"
Cohesion: 0.33
Nodes (7): reportProvider, reportRangeProvider, build, buildReportCsv, _pickRange, _refresh, ReportsPage

### Community 78 - "_SaleDetailSheetState"
Cohesion: 0.50
Nodes (4): posRepositoryProvider, initState, _SaleDetailSheet, _SaleDetailSheetState

### Community 79 - "AuthRepository"
Cohesion: 0.67
Nodes (3): AuthRepository, _FakeAuthRepository, _RecordingAuthRepository

### Community 80 - "_EnergyPageState"
Cohesion: 0.67
Nodes (3): EnergyPage, _EnergyPageState, SingleTickerProviderStateMixin

## Knowledge Gaps
- **824 isolated node(s):** `label`, `icon`, `group`, `mobileLabel`, `_groupMain` (+819 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `_` connect `_` to `inventory_repository.dart`, `reports_page.dart`, `mutation_retry_test.dart`, `sale_models.dart`, `../../core/error_mapper.dart`, `catalog_models.dart`, `auth_repository.dart`, `reportProvider`, `package:flutter_riverpod/flutter_riverpod.dart`, `package:supabase_flutter/supabase_flutter.dart`, `recipes_page.dart`, `login_page_test.dart`, `expenses_page.dart`, `stock_page.dart`, `energy_page.dart`, `cash_page.dart`, `page_layout_test.dart`?**
  _High betweenness centrality (0.123) - this node is a cross-community bridge._
- **Why does `MutationRetryStore` connect `mutation_retry_test.dart` to `inventory_repository.dart`, `mutation_retry.dart`, `pos_repository.dart`, `mutation_retry_forms_test.dart`, `_`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Why does `Product` connect `@immutable` to `pos_page.dart`, `catalog_models.dart`, `catalog_page.dart`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **What connects `label`, `icon`, `group` to the rest of the system?**
  _824 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `StatelessWidget` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `pos_page.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.03773584905660377 - nodes in this community are weakly interconnected._
- **Should `catalog_repository.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._