import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sheets/transaction_editor_sheet.dart';
import '../theme.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'transactions_screen.dart';

/// The four top-level destinations, with the one action that matters on top.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.pie_chart_outline),
      selectedIcon: Icon(Icons.pie_chart),
      label: 'Dashboard',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Transactions',
    ),
    NavigationDestination(
      icon: Icon(Icons.savings_outlined),
      selectedIcon: Icon(Icons.savings),
      label: 'Budgets',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: Motion.of(context, Motion.quick),
        // A short cross-fade with a touch of vertical travel: enough to signal
        // a change of place without making the user wait for it.
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: switch (_index) {
            0 => const DashboardScreen(),
            1 => const TransactionsScreen(),
            2 => const BudgetsScreen(),
            _ => const SettingsScreen(),
          },
        ),
      ),
      floatingActionButton: _index == 3
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-transaction',
              onPressed: () => showTransactionEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }
}
