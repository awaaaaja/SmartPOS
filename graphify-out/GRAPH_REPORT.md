# Graph Report - Smart_POS  (2026-10-27)

## Corpus Check
- 75 files · ~406,882 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 924 nodes · 1221 edges · 59 communities (53 shown, 6 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `96c2c080`
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
- auth_repository.dart
- login_page_test.dart
- manifest.json
- @immutable
- main.dart
- _PosPageState
- shell_test.dart
- package:flutter_test/flutter_test.dart
- App.vue
- catalogRepositoryProvider
- Smart POS — Waroeng MeJeng Kampoeng
- Decision Log
- API Contracts
- test_pos_api.py
- _NewModifierForm
- tables_repository.dart
- MainActivity
- inventory_repository.dart
- pos_flutter
- package:flutter/material.dart
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
- _RecipesHppPageState
- package:flutter_riverpod/flutter_riverpod.dart
- ../../core/error_mapper.dart
- test_inventory.py
- cart_state_test.dart

## God Nodes (most connected - your core abstractions)
1. `inventoryRepositoryProvider` - 9 edges
2. `catalogRepositoryProvider` - 8 edges
3. `ingredientsProvider` - 8 edges
4. `_PosPageState` - 8 edges
5. `_RecipesHppPageState` - 8 edges
6. `_InventoryPageState` - 7 edges
7. `cartControllerProvider` - 7 edges
8. `5. PROMPT PER SPRINT — EKSEKUSI BERURUTAN` - 7 edges
9. `Sprint 02 — Katalog & Kasir POS (End-to-End)` - 7 edges
10. `categoriesProvider` - 6 edges

## Surprising Connections (you probably didn't know these)
- `build` --references--> `authStateProvider`  [EXTRACTED]
  apps/pos_flutter/lib/app/shell.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `_submit` --references--> `authRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/auth/login_page.dart → apps/pos_flutter/lib/features/auth/auth_repository.dart
- `CatalogPage` --references--> `catalogRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/catalog/catalog_page.dart → apps/pos_flutter/lib/features/catalog/catalog_repository.dart
- `_CategorySheetState` --references--> `categoriesProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/catalog/catalog_page.dart → apps/pos_flutter/lib/features/catalog/catalog_repository.dart
- `_editProduct` --references--> `catalogRepositoryProvider`  [EXTRACTED]
  apps/pos_flutter/lib/features/catalog/catalog_page.dart → apps/pos_flutter/lib/features/catalog/catalog_repository.dart

## Import Cycles
- None detected.

## Communities (59 total, 6 thin omitted)

### Community 0 - "StatelessWidget"
Cohesion: 0.12
Nodes (17): _SessionErrorScreen, _Sidebar, _SidebarTile, _SplashScreen, _EmptyCatalog, _ErrorRetry, _PhotoThumb, _CartLineTile (+9 more)

### Community 1 - "pos_page.dart"
Cohesion: 0.04
Nodes (51): cart, _categoryFilter, categoryNames, _claimedDraftIds, createState, dispose, _error, _fetchQuote (+43 more)

### Community 2 - "catalog_repository.dart"
Cohesion: 0.11
Nodes (18): archiveCategory, archiveProduct, CatalogRepository, _client, createCategory, createModifier, fetchCategories, fetchModifiers (+10 more)

### Community 3 - "history_page.dart"
Cohesion: 0.07
Nodes (37): _ModifierSheet, _ModifierSheetState, _PaymentSheet, _PaymentSheetState, _submit, posRepositoryProvider, _amount, build (+29 more)

### Community 4 - "pos_repository.dart"
Cohesion: 0.05
Nodes (39): add, basePrice, build, CartController, CartLine, CartState, changeQty, checkout (+31 more)

### Community 5 - "dashboard_page.dart"
Cohesion: 0.06
Nodes (33): app/theme.dart, AppDestination, byGroup, group, _groupFinance, _groupMain, _groupProduct, groups (+25 more)

### Community 6 - "shell.dart"
Cohesion: 0.04
Nodes (47): AppShell, _AppShellState, build, createState, _current, destination, onRetry, onSelected (+39 more)

### Community 7 - "catalog_page.dart"
Cohesion: 0.06
Nodes (35): _allModifiers, _attached, _busy, _categoryId, _chipStyle, _controller, createState, _delta (+27 more)

### Community 8 - "sale_models.dart"
Cohesion: 0.06
Nodes (30): allTimeRevenue, allTimeTransactions, changeAmount, createdAt, diningType, discountAmount, fromJson, id (+22 more)

### Community 9 - "Prompt.md"
Cohesion: 0.07
Nodes (28): 1. Urutan Sumber Kebenaran, 2. MASTER PROMPT — SALIN KE CODING AGENT, 3.1 Identitas visual dan token, 3.2 Ikon open-source yang didukung Flutter, 3.3 Layout dan navigasi yang meniru perilaku `index.html`, 3.4 Animasi yang layak untuk produk, 3.5 Standar responsivitas dan UX, 3. Kontrak Desain Flutter: Tidak Generic AI, Tidak Emoji (+20 more)

### Community 10 - "PRD.md"
Cohesion: 0.07
Nodes (26): 10. Persyaratan Non-Fungsional, 11. Uji Penerimaan Utama (UAT), 12. Release Scope dan Rencana Implementasi, 13. Kriteria Rilis, 1.1 Masalah yang diselesaikan, 1.2 Ukuran keberhasilan yang harus diuji, 1. Ringkasan Produk, 2.1 Dalam cakupan (+18 more)

### Community 11 - "catalog_models.dart"
Cohesion: 0.08
Nodes (24): archivedAt, categoryId, categoryName, effectiveAt, fromJson, id, isActive, isArchived (+16 more)

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
Cohesion: 0.07
Nodes (26): Acceptance Criteria, Acceptance Criteria, Alur bukti end-to-end (Chrome, bukan mock), Bukti E2E (Chrome, build web final, tablet 1280×800), Gate S04, Sisa pekerjaan, Sisa pekerjaan, Sisa pekerjaan / risiko (+18 more)

### Community 16 - "theme.dart"
Cohesion: 0.14
Nodes (13): borderColor, brandDark, brandPrimary, brandSoft, buildAppTheme, canvasColor, errorColor, scheme (+5 more)

### Community 17 - "auth_repository.dart"
Cohesion: 0.17
Nodes (11): async, _client, currentUser, isAuthenticatedProvider, maybeWhen, signIn, signOut, supabaseClientProvider (+3 more)

### Community 18 - "login_page_test.dart"
Cohesion: 0.20
Nodes (9): currentUser, lastEmail, lastPassword, main, _pumpLogin, pumpWidget, signIn, signOut (+1 more)

### Community 19 - "manifest.json"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 20 - "@immutable"
Cohesion: 0.20
Nodes (10): @immutable, Modifier, PriceHistoryEntry, Product, ProductCategory, DashboardSummary, Quote, Receipt (+2 more)

### Community 21 - "main.dart"
Cohesion: 0.22
Nodes (8): app/shell.dart, build, initialize, main, MissingConfigApp, PosApp, supabasePublishableKey, supabaseUrl

### Community 22 - "_PosPageState"
Cohesion: 0.25
Nodes (9): _claimDraft, _completeClaimedDrafts, _openCartSheet, _openPayment, _pickProduct, PosPage, _PosPageState, cartControllerProvider (+1 more)

### Community 23 - "shell_test.dart"
Cohesion: 0.15
Nodes (12): AuthRepository, currentUser, _FakeAuthRepository, main, _setSurface, signedOut, signIn, signOut (+4 more)

### Community 24 - "package:flutter_test/flutter_test.dart"
Cohesion: 0.22
Nodes (7): main, main, main, package:flutter_test/flutter_test.dart, package:pos_flutter/app/theme.dart, package:pos_flutter/core/formatters.dart, package:pos_flutter/core/widgets/module_placeholder.dart

### Community 25 - "App.vue"
Cohesion: 0.06
Nodes (24): supabase, cart, cartCount, cartOpen, cartSubtotal, categories, clientKey, confirmation (+16 more)

### Community 26 - "catalogRepositoryProvider"
Cohesion: 0.22
Nodes (9): _addCategory, _CategorySheet, _CategorySheetState, _confirmArchive, _editProduct, _ProductTile, _ProductTileState, _showPriceHistory (+1 more)

### Community 27 - "Smart POS — Waroeng MeJeng Kampoeng"
Cohesion: 0.22
Nodes (8): 1. Supabase, 2. Aplikasi kasir (Flutter), 3. Web QR (Vue), Aturan keamanan, Menjalankan, Smart POS — Waroeng MeJeng Kampoeng, Struktur, Uji

### Community 28 - "Decision Log"
Cohesion: 0.29
Nodes (6): D-01 (2026-10-26) — API bisnis authoritative = fungsi Postgres (bukan FastAPI terpisah), D-02 (2026-10-26) — Penanda satu operator = `business_settings.operator_email`, D-03 (2026-10-26) — Token meja disimpan sebagai hash SHA-256, D-04 (2026-10-26) — WIB dihitung manual (UTC+7), bukan paket zona waktu, D-05 (2026-10-26) — Konfigurasi Flutter via `--dart-define`, layar konfigurasi jujur, Decision Log

### Community 29 - "API Contracts"
Cohesion: 0.33
Nodes (5): API Contracts, Keamanan, Operator (sesi login, via authenticated + RLS), Publik (tanpa sesi, via anon key), `rpc get_public_menu(p_table_token text) -> jsonb`

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
Cohesion: 0.04
Nodes (54): adjustStock, balance, balanceAfter, baseUnit, _client, cost, createdAt, createPurchase (+46 more)

### Community 36 - "package:flutter/material.dart"
Cohesion: 0.18
Nodes (10): build, CashShiftPage, build, EnergyPage, build, ReportsPage, build, SettingsPage (+2 more)

### Community 44 - "purchases_page.dart"
Cohesion: 0.12
Nodes (16): Purchase, purchasesProvider, build, _formatDate, ingredientId, _LineState, onReceive, price (+8 more)

### Community 45 - "qr_page.dart"
Cohesion: 0.14
Nodes (13): onRotate, onToggle, qrUrlFor, qrWebBaseUrl, _rotate, _showTokenDialog, table, _TableCard (+5 more)

### Community 46 - "qr_inbox_sheet_test.dart"
Cohesion: 0.22
Nodes (8): _draft, _harness, main, _open, pumpAndSettle, tap, package:pos_flutter/features/pos/qr_inbox_sheet.dart, package:pos_flutter/features/tables_qr/tables_repository.dart

### Community 47 - "package:supabase_flutter/supabase_flutter.dart"
Cohesion: 0.24
Nodes (8): m, _mapBusinessError, mapErrorToMessage, main, dart:async, dart:io, package:pos_flutter/core/error_mapper.dart, package:supabase_flutter/supabase_flutter.dart

### Community 48 - "categoriesProvider"
Cohesion: 0.33
Nodes (7): build, CatalogPage, _ProductDialog, _ProductDialogState, categoriesProvider, productsProvider, build

### Community 49 - "TablesQrPage"
Cohesion: 0.33
Nodes (6): build, _createTable, TablesQrPage, _toggle, tablesListProvider, tablesRepositoryProvider

### Community 50 - "recipes_page.dart"
Cohesion: 0.15
Nodes (12): RecipeProduct, createState, ingredientId, onBatch, onChanged, onEdit, product, qty (+4 more)

### Community 51 - "test_qr_drafts.py"
Cohesion: 0.80
Nodes (4): check(), main(), req(), rpc()

### Community 53 - "stock_page.dart"
Cohesion: 0.11
Nodes (25): AuthGate, authStateProvider, Ingredient, ingredientSearchProvider, ingredientsProvider, inventoryRepositoryProvider, stockMovementsProvider, _adjust (+17 more)

### Community 54 - "_RecipesHppPageState"
Cohesion: 0.20
Nodes (12): hppProvider, InventoryRepository, RecipeHpp, recipeProductsProvider, RecipeVersion, recipeVersionsProvider, build, _HppDetail (+4 more)

### Community 55 - "package:flutter_riverpod/flutter_riverpod.dart"
Cohesion: 0.25
Nodes (7): _app, main, package:flutter_riverpod/flutter_riverpod.dart, package:pos_flutter/features/inventory/inventory_repository.dart, package:pos_flutter/features/inventory/stock_page.dart, package:pos_flutter/features/purchases/purchases_page.dart, package:pos_flutter/features/recipes_hpp/recipes_page.dart

### Community 56 - "../../core/error_mapper.dart"
Cohesion: 0.33
Nodes (6): build, QrInboxSheet, qrDraftsProvider, ../../core/error_mapper.dart, ../../core/formatters.dart, ../tables_qr/tables_repository.dart

### Community 57 - "test_inventory.py"
Cohesion: 0.57
Nodes (6): check(), main(), make_product(), POST products tidak mengembalikan baris -> query balik by name., req(), rpc()

### Community 58 - "cart_state_test.dart"
Cohesion: 0.50
Nodes (3): line, main, package:pos_flutter/features/pos/pos_repository.dart

## Knowledge Gaps
- **565 isolated node(s):** `label`, `icon`, `group`, `mobileLabel`, `_groupMain` (+560 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Product` connect `@immutable` to `pos_page.dart`, `catalog_models.dart`, `catalog_page.dart`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Why does `Receipt` connect `@immutable` to `sale_models.dart`, `pos_page.dart`, `history_page.dart`?**
  _High betweenness centrality (0.005) - this node is a cross-community bridge._
- **Why does `_RecipesHppPageState` connect `_RecipesHppPageState` to `recipes_page.dart`, `history_page.dart`, `stock_page.dart`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **What connects `label`, `icon`, `group` to the rest of the system?**
  _565 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `StatelessWidget` be split into smaller, more focused modules?**
  _Cohesion score 0.11764705882352941 - nodes in this community are weakly interconnected._
- **Should `pos_page.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.038461538461538464 - nodes in this community are weakly interconnected._
- **Should `catalog_repository.dart` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._