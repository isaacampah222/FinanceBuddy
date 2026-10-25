import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import 'account_dialog.dart';
import 'transaction_dialog.dart';
import '../state/app_state.dart';
import 'account_transactions_page.dart';
import 'formatters.dart';
import 'review_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Your money',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Every account. Every income. Every expense.'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xff176b4d), Color(0xff2c8a66)]),
                borderRadius: BorderRadius.circular(24)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TOTAL BALANCE',
                  style: TextStyle(color: Colors.white70, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(moneyFormat.format(state.totalBalance),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          if (state.permissionPermanentlyDenied) ...[
            const SizedBox(height: 16),
            MaterialBanner(
              content: const Text(
                  'SMS access is disabled. Enable it in system settings to sync transactions.'),
              leading: const Icon(Icons.sms_failed_outlined),
              actions: [
                TextButton(
                    onPressed: openAppSettings,
                    child: const Text('OPEN SETTINGS'))
              ],
            ),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Accounts',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            TextButton.icon(
                onPressed: () => showTransactionDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add transaction')),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => showAccountDialog(context),
              icon: const Icon(Icons.add_card),
              label: const Text('Create account')),
          const SizedBox(height: 12),
          ...state.accounts.map((account) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountCard(account: account))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.scanning ? null : () => _sync(context, state),
            icon: state.scanning
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(state.scanning
                    ? 'Checking messages…'
                    : 'Find transactions in SMS')),
          ),
          if (state.lastScan != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                    '${state.lastScan!.reviewed} new suggestion(s) to review',
                    textAlign: TextAlign.center)),
          if (state.error != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(state.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (state.reviewItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.rate_review_outlined),
                    title: Text(
                        '${state.reviewItems.length} message(s) need review'),
                    subtitle: const Text(
                        'Confirm the account and details before saving'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReviewPage())))),
          ],
        ],
      ),
    );
  }

  Future<void> _sync(BuildContext context, AppState state) async {
    var status = await Permission.sms.status;
    if (!status.isGranted) {
      if (!context.mounted) return;
      final proceed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                      title: const Text('Read transaction messages?'),
                      content: const Text(
                          'This optional scan reads up to 1,000 inbox messages and adds possible transactions for you to review. Nothing is saved to your balances automatically. Avoid recording a payment twice if you already received a notification suggestion.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('NOT NOW')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('CONTINUE'))
                      ])) ??
          false;
      if (!proceed) return;
      status = await state.requestSmsPermission();
    }
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status.isPermanentlyDenied
                ? 'SMS permission is disabled in Settings.'
                : 'SMS permission is required to sync.')));
      }
      return;
    }
    final result = await state.scan();
    if (context.mounted && result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Found ${result.reviewed} new transaction suggestion(s).')));
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) => Card(
          child: ListTile(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => AccountTransactionsPage(account: account))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
            child: Icon(switch (account.kind) {
          'bank' => Icons.account_balance,
          'momo' => Icons.phone_android,
          _ => Icons.payments_outlined
        })),
        title: Text(account.name),
        subtitle: Text(account.kind == 'momo' ? 'Mobile wallet' : account.kind),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(moneyFormat.format(account.balance),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
              tooltip: 'Edit balance',
              onPressed: () => _edit(context),
              icon: const Icon(Icons.edit_outlined, size: 19)),
        ]),
      ));
  Future<void> _edit(BuildContext context) async {
    final controller =
        TextEditingController(text: account.balance.toStringAsFixed(2));
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Edit ${account.name} balance'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration:
                        const InputDecoration(labelText: 'Current balance')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL')),
                  FilledButton(
                      onPressed: () async {
                        final value = double.tryParse(controller.text);
                        if (value == null || !value.isFinite) return;
                        await context
                            .read<AppState>()
                            .setBalance(account.id, value);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('UPDATE'))
                ]));
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
  }
}
