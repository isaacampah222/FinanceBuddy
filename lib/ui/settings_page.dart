import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger_transaction.dart';
import '../state/app_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return CustomScrollView(slivers: [
      SliverAppBar.large(title: const Text('Routing rules')),
      SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(children: [
            const Text(
                'Combine sender, required and excluded keywords, transaction type, currency, and amount range. Higher priority rules win.'),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: state.accounts.isEmpty
                    ? null
                    : () => _addRule(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Add routing rule')),
            const SizedBox(height: 24),
            if (state.rules.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                          'No rules yet. Add one such as sender “T-CASH” → Mobile Money.'))),
            ...state.rules.map((rule) {
              final account = state.accounts
                  .where((a) => a.id == rule.accountId)
                  .firstOrNull;
              final category = state.categories
                  .where((c) => c.id == rule.categoryId)
                  .firstOrNull;
              final details = <String>[
                if (rule.effectiveRequiredKeywords.isNotEmpty)
                  'needs: ${rule.effectiveRequiredKeywords}',
                if (rule.excludedKeywords.isNotEmpty)
                  'excludes: ${rule.excludedKeywords}',
                if (rule.direction != null)
                  rule.direction == TransactionDirection.debit
                      ? 'expense'
                      : 'income',
                if (rule.currency?.isNotEmpty == true) rule.currency!,
                if (category != null) category.name,
                'priority ${rule.priority}',
              ];
              return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                      child: ListTile(
                    leading: const Icon(Icons.rule_outlined),
                    title: Text(
                        '${rule.effectiveSenderPattern.isEmpty ? 'Any sender' : rule.effectiveSenderPattern} → ${account?.name ?? 'Account'}'),
                    subtitle: Text(details.join(' • ')),
                    trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => state.deleteRule(rule.id)),
                  )));
            }),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Categories',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                  onPressed: () => _addCategory(context, state),
                  icon: const Icon(Icons.add_circle_outline))
            ]),
            Wrap(
                spacing: 8,
                children: state.categories
                    .map((category) => Chip(label: Text(category.name)))
                    .toList()),
            const SizedBox(height: 24),
            const Card(
                child: ListTile(
                    leading: Icon(Icons.lock_outline),
                    title: Text('Local-only privacy'),
                    subtitle: Text(
                        'SMS bodies and financial records remain in the app’s on-device SQLite database.'))),
          ])),
    ]);
  }

  Future<void> _addRule(BuildContext context, AppState state) async {
    final sender = TextEditingController(),
        required = TextEditingController(),
        excluded = TextEditingController();
    final minimum = TextEditingController(),
        maximum = TextEditingController(),
        priority = TextEditingController(text: '0');
    var accountId = state.accounts.first.id;
    int? categoryId;
    TransactionDirection? direction;
    String? currency;
    final draft = await showDialog<
            ({
              String sender,
              String requiredKeywords,
              String excludedKeywords,
              int accountId,
              int? categoryId,
              TransactionDirection? direction,
              String? currency,
              double? minAmount,
              double? maxAmount,
              int priority
            })>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
                  title: const Text('New routing rule'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: sender,
                        autofocus: true,
                        decoration: const InputDecoration(
                            labelText: 'Sender contains (optional)',
                            hintText: 'T-CASH | MobileMoney | GCB')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: required,
                        decoration: const InputDecoration(
                            labelText: 'All required keywords',
                            hintText: 'paid, airtime')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: excluded,
                        decoration: const InputDecoration(
                            labelText: 'Any excluded keywords',
                            hintText: 'promo | otp | unsuccessful')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<TransactionDirection?>(
                        initialValue: direction,
                        decoration: const InputDecoration(
                            labelText: 'Transaction type'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Any')),
                          DropdownMenuItem(
                              value: TransactionDirection.debit,
                              child: Text('Expense')),
                          DropdownMenuItem(
                              value: TransactionDirection.credit,
                              child: Text('Income'))
                        ],
                        onChanged: (v) => setState(() => direction = v)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                        initialValue: currency,
                        decoration:
                            const InputDecoration(labelText: 'Currency'),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Any')),
                          DropdownMenuItem(value: 'GHS', child: Text('GHS')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP'))
                        ],
                        onChanged: (v) => setState(() => currency = v)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextField(
                              controller: minimum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Minimum'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextField(
                              controller: maximum,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Maximum')))
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                        controller: priority,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Priority',
                            helperText: 'Higher numbers are checked first')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                        initialValue: accountId,
                        decoration: const InputDecoration(
                            labelText: 'Route to account'),
                        items: state.accounts
                            .map((a) => DropdownMenuItem(
                                value: a.id, child: Text(a.name)))
                            .toList(),
                        onChanged: (v) => setState(() => accountId = v!)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                        initialValue: categoryId,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          ...state.categories.map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                        ],
                        onChanged: (v) => setState(() => categoryId = v)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('CANCEL')),
                    FilledButton(
                        onPressed: () {
                          if (sender.text.trim().isEmpty &&
                              required.text.trim().isEmpty &&
                              direction == null) return;
                          Navigator.pop(context, (
                            sender: sender.text,
                            requiredKeywords: required.text,
                            excludedKeywords: excluded.text,
                            accountId: accountId,
                            categoryId: categoryId,
                            direction: direction,
                            currency: currency,
                            minAmount: double.tryParse(minimum.text),
                            maxAmount: double.tryParse(maximum.text),
                            priority: int.tryParse(priority.text) ?? 0,
                          ));
                        },
                        child: const Text('ADD'))
                  ],
                )));
    await WidgetsBinding.instance.endOfFrame;
    sender.dispose();
    required.dispose();
    excluded.dispose();
    minimum.dispose();
    maximum.dispose();
    priority.dispose();
    if (draft == null) return;
    final created = await state.addRule(
        accountId: draft.accountId,
        categoryId: draft.categoryId,
        senderPattern: draft.sender,
        requiredKeywords: draft.requiredKeywords,
        excludedKeywords: draft.excludedKeywords,
        direction: draft.direction,
        currency: draft.currency,
        minAmount: draft.minAmount,
        maxAmount: draft.maxAmount,
        priority: draft.priority);
    if (!created && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That routing rule already exists.')));
    }
  }

  Future<void> _addCategory(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('New category'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Name')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL')),
                  FilledButton(
                      onPressed: () async {
                        if (controller.text.trim().isEmpty) return;
                        await state.addCategory(controller.text);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('ADD'))
                ]));
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
  }
}
