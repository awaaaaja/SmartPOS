import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_repository.dart';
import '../features/auth/login_page.dart';
import '../features/cash_shift/cash_page.dart';
import '../features/catalog/catalog_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/energy/energy_page.dart';
import '../features/expenses/expenses_page.dart';
import '../features/inventory/stock_page.dart';
import '../features/pos/pos_page.dart';
import '../features/purchases/purchases_page.dart';
import '../features/recipes_hpp/recipes_page.dart';
import '../features/reports/reports_page.dart';
import '../features/sales_history/history_page.dart';
import '../features/settings/settings_page.dart';
import '../features/tables_qr/qr_page.dart';
import 'destinations.dart';
import 'theme.dart';

/// Gate sesi: belum masuk = LoginPage, sudah masuk = shell aplikasi.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    return authState.when(
      loading: () => const _SplashScreen(),
      error: (e, _) => _SessionErrorScreen(
        onRetry: () => ref.invalidate(authStateProvider),
      ),
      data: (state) =>
          state.session == null ? const LoginPage() : const AppShell(),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _SessionErrorScreen extends StatelessWidget {
  const _SessionErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: warningColor),
            const SizedBox(height: 12),
            const Text('Gagal memeriksa sesi operator.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppDestination _current = AppDestination.dashboard;

  static const double _sidebarWidth = 248;
  static const double _wideBreakpoint = 840;

  Widget _pageFor(AppDestination destination) {
    switch (destination) {
      case AppDestination.dashboard:
        return const DashboardPage();
      case AppDestination.pos:
        return const PosPage();
      case AppDestination.tablesQr:
        return const TablesQrPage();
      case AppDestination.catalog:
        return const CatalogPage();
      case AppDestination.inventory:
        return const InventoryPage();
      case AppDestination.recipesHpp:
        return const RecipesHppPage();
      case AppDestination.purchases:
        return const PurchasesPage();
      case AppDestination.expenses:
        return const ExpensesPage();
      case AppDestination.energy:
        return const EnergyPage();
      case AppDestination.cashShift:
        return const CashShiftPage();
      case AppDestination.salesHistory:
        return const SalesHistoryPage();
      case AppDestination.reports:
        return const ReportsPage();
      case AppDestination.settings:
        return const SettingsPage();
    }
  }

  Future<void> _openOthers() async {
    final others = AppDestination.values
        .where((d) => !mobileNavDestinations.contains(d))
        .toList();
    final selected = await showModalBottomSheet<AppDestination>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in others)
              ListTile(
                leading: Icon(d.icon, color: brandPrimary),
                title: Text(d.label),
                onTap: () => Navigator.of(context).pop(d),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _current = selected);
  }

  @override
  Widget build(BuildContext context) {
    final email =
        ref.watch(authRepositoryProvider).currentUser?.email ?? 'Operator';
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            titleSpacing: wide ? 16 : 12,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/logo-mark.png',
                    width: 40,
                    height: 40,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Waroeng MeJeng Kampoeng',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        email,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Keluar',
                icon: const Icon(Icons.logout_rounded),
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                SizedBox(
                  width: _sidebarWidth,
                  child: _Sidebar(
                    current: _current,
                    onSelected: (d) => setState(() => _current = d),
                  ),
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(child: _pageFor(_current)),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: () {
                    final idx = mobileNavDestinations.indexOf(_current);
                    return idx >= 0 ? idx : mobileNavDestinations.length;
                  }(),
                  onDestinationSelected: (index) {
                    if (index >= mobileNavDestinations.length) {
                      _openOthers();
                    } else {
                      setState(() => _current = mobileNavDestinations[index]);
                    }
                  },
                  destinations: [
                    for (final d in mobileNavDestinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        label: d.mobileLabel ?? d.label,
                      ),
                    const NavigationDestination(
                      icon: Icon(Icons.menu_rounded),
                      label: 'Lainnya',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelected});

  final AppDestination current;
  final ValueChanged<AppDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      children: [
        for (final group in AppDestination.groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              group.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: textSecondary,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final d in AppDestination.byGroup(group))
            _SidebarTile(
              destination: d,
              selected: d == current,
              onTap: () => onSelected(d),
            ),
        ],
      ],
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? brandSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                destination.icon,
                size: 21,
                color: selected ? brandPrimary : textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  style: TextStyle(
                    color: selected ? brandPrimary : textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
