import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'dashboard_page.dart';
import 'ledger_page.dart';
import 'settings_page.dart';
import 'review_page.dart';
import 'transaction_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int index = 0;
  Timer? _timer;
  bool _active = true, _polling = false;
  final _shown = <int>{};
  static const pages = [DashboardPage(), LedgerPage(), SettingsPage()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) _poll();
  }

  Future<void> _poll() async {
    if (!mounted || !_active || _polling) return;
    final state = context.read<AppState>();
    if (state.loading) return;
    _polling = true;
    try {
      await state.readNotifications();
      if (!mounted || !_active || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      final item = state.reviewItems
          .where((item) => !_shown.contains(item.id))
          .firstOrNull;
      if (item != null && state.accounts.isNotEmpty) {
        _shown.add(item.id);
        await showTransactionDialog(context, review: item);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AppState>().reviewItems.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Finance Buddy'), actions: [
        IconButton(
            tooltip: 'Transaction suggestions',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const ReviewPage())),
            icon: Badge(
                isLabelVisible: pending > 0,
                label: Text('$pending'),
                child: const Icon(Icons.inbox_outlined))),
      ]),
      body: SafeArea(child: IndexedStack(index: index, children: pages)),
      floatingActionButton: index == 1
          ? FloatingActionButton.extended(
              onPressed: () => showTransactionDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add transaction'))
          : null,
      bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Accounts'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Transactions'),
            NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Settings'),
          ]),
    );
  }
}
