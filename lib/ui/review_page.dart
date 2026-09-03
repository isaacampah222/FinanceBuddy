import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger_transaction.dart';
import '../models/review_item.dart';
import '../state/app_state.dart';
import 'formatters.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Review transactions')),
      body: state.reviewItems.isEmpty
          ? const Center(child: Text('Nothing needs review.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.reviewItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = state.reviewItems[index];
                return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                        onTap: () => _showMessage(context, state, item),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.sms_outlined),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(item.sender,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium)),
                                    Text(dayFormat.format(item.receivedAt),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)
                                  ]),
                                  const SizedBox(height: 12),
                                  Text(item.preview,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text('Tap to review',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.chevron_right,
                                            size: 18)
                                      ]),
                                ]))));
              },
            ),
    );
  }

  Future<void> _showMessage(
      BuildContext pageContext, AppState state, ReviewItem item) async {
    final action = await showModalBottomSheet<_ReviewAction>(
        context: pageContext,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => FractionallySizedBox(
            heightFactor: .95,
            child: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.sender,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Text(
                              '${dayFormat.format(item.receivedAt)} ${timeFormat.format(item.receivedAt)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          const Divider(height: 28),
                          Expanded(
                              child: SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SelectableText(item.body,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(height: 1.5)))),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 12),
                                        visualDensity: VisualDensity.compact,
                                        textStyle:
                                            const TextStyle(fontSize: 11)),
                                    onPressed: () => Navigator.pop(
                                        context, _ReviewAction.notTransaction),
                                    icon: const Icon(Icons.not_interested,
                                        size: 17),
                                    label: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('NOT A TRANSACTION')))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 12),
                                        visualDensity: VisualDensity.compact,
                                        textStyle:
                                            const TextStyle(fontSize: 11)),
                                    onPressed: () => Navigator.pop(
                                        context, _ReviewAction.createRule),
                                    icon: const Icon(Icons.auto_awesome,
                                        size: 17),
                                    label: const FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text('CREATE RULE')))),
                          ])
                        ])))));
    if (action == _ReviewAction.notTransaction) {
      await state.dismissReview(item.id);
    } else if (action == _ReviewAction.createRule && pageContext.mounted) {
      await _generateRule(pageContext, state, item);
    }
  }

  Future<void> _generateRule(
      BuildContext context, AppState state, ReviewItem item) async {
    final sender = TextEditingController(text: item.sender);
    final keywords = TextEditingController(text: _suggestKeywords(item.body));
    final excluded = TextEditingController(
        text: 'otp | verification code | unsuccessful | failed | pending');
    var direction = _suggestDirection(item.body);
    var accountId = _suggestAccount(state, item.sender);
    int? categoryId;
    final draft = await showDialog<_GeneratedRule>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
                  title: const Text('Generated routing rule'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'Review the suggested fields. Saving applies this rule to every message currently waiting for review.'),
                    const SizedBox(height: 12),
                    TextField(
                        controller: sender,
                        decoration: const InputDecoration(
                            labelText: 'Sender contains')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: keywords,
                        decoration: const InputDecoration(
                            labelText: 'Required keywords',
                            helperText:
                                'Every comma-separated keyword must match')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: excluded,
                        decoration: const InputDecoration(
                            labelText: 'Excluded keywords')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<TransactionDirection>(
                        initialValue: direction,
                        decoration: const InputDecoration(
                            labelText: 'Transaction type'),
                        items: const [
                          DropdownMenuItem(
                              value: TransactionDirection.debit,
                              child: Text('Expense')),
                          DropdownMenuItem(
                              value: TransactionDirection.credit,
                              child: Text('Income'))
                        ],
                        onChanged: (v) => setModalState(() => direction = v!)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                        initialValue: accountId,
                        decoration: const InputDecoration(
                            labelText: 'Route to account'),
                        items: state.accounts
                            .map((a) => DropdownMenuItem(
                                value: a.id, child: Text(a.name)))
                            .toList(),
                        onChanged: (v) => setModalState(() => accountId = v!)),
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
                        onChanged: (v) => setModalState(() => categoryId = v)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('CANCEL')),
                    FilledButton(
                        onPressed: () => Navigator.pop(
                            context,
                            _GeneratedRule(
                                accountId: accountId,
                                categoryId: categoryId,
                                senderPattern: sender.text,
                                requiredKeywords: keywords.text,
                                excludedKeywords: excluded.text,
                                direction: direction)),
                        child: const Text('SAVE & APPLY')),
                  ],
                )));
    await WidgetsBinding.instance.endOfFrame;
    sender.dispose();
    keywords.dispose();
    excluded.dispose();
    if (draft == null) return;
    final created = await state.addRule(
        accountId: draft.accountId,
        categoryId: draft.categoryId,
        senderPattern: draft.senderPattern,
        requiredKeywords: draft.requiredKeywords,
        excludedKeywords: draft.excludedKeywords,
        direction: draft.direction,
        currency: 'GHS',
        priority: 50);
    if (!created && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'That rule already exists. The existing rule was applied.')));
    }
  }

  int _suggestAccount(AppState state, String sender) {
    final value = sender.toLowerCase();
    final kind = RegExp(r'momo|mobilemoney|mtn|t-cash|telecel|airteltigo')
            .hasMatch(value)
        ? 'momo'
        : 'bank';
    return state.accounts
            .where((account) => account.kind == kind)
            .firstOrNull
            ?.id ??
        state.accounts.first.id;
  }

  TransactionDirection _suggestDirection(String body) =>
      RegExp(r'\b(?:received|credited|deposited|refund|salary|cashback)\b',
                  caseSensitive: false)
              .hasMatch(body)
          ? TransactionDirection.credit
          : TransactionDirection.debit;

  String _suggestKeywords(String body) {
    const phrases = [
      'paid off',
      'cash withdrawal',
      'bundle purchase',
      'airtime'
    ];
    const words = [
      'received',
      'credited',
      'deposited',
      'withdrawn',
      'debited',
      'deducted',
      'sent',
      'paid',
      'bought',
      'purchased',
      'refund',
      'salary'
    ];
    final lower = body.toLowerCase();
    for (final phrase in phrases) {
      if (lower.contains(phrase)) return phrase;
    }
    for (final word in words) {
      if (RegExp('\\b$word\\b').hasMatch(lower)) return word;
    }
    return '';
  }
}

class _GeneratedRule {
  const _GeneratedRule(
      {required this.accountId,
      required this.categoryId,
      required this.senderPattern,
      required this.requiredKeywords,
      required this.excludedKeywords,
      required this.direction});
  final int accountId;
  final int? categoryId;
  final String senderPattern;
  final String requiredKeywords;
  final String excludedKeywords;
  final TransactionDirection direction;
}

enum _ReviewAction { notTransaction, createRule }
