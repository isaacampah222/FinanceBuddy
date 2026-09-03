import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ledger_transaction.dart';
import '../state/app_state.dart';
import 'formatters.dart';

class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});
  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppState>().transactions;
    return CustomScrollView(slivers: [
      SliverAppBar.large(title: const Text('Transactions')),
      if (items.isEmpty)
        const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                        'No transactions yet. Add one manually or sync your SMS inbox.',
                        textAlign: TextAlign.center))))
      else
        SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final showHeader = index == 0 ||
                      !_sameDay(item.occurredAt, items[index - 1].occurredAt);
                  final credit = item.direction == TransactionDirection.credit;
                  final color = credit
                      ? const Color(0xff138a58)
                      : const Color(0xffc43d3d);
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Padding(
                              padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                              child: Text(dayFormat.format(item.occurredAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold))),
                        Card(
                            child: ListTile(
                          leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: .12),
                              child: Icon(
                                  credit ? Icons.south_west : Icons.north_east,
                                  color: color)),
                          title: Text(item.counterparty,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${item.accountName}${item.categoryName == null ? '' : ' • ${item.categoryName}'} • ${timeFormat.format(item.occurredAt)}'),
                          trailing: Text(
                              '${credit ? '+' : '−'}${item.currency} ${item.amount.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.bold)),
                        )),
                        const SizedBox(height: 8),
                      ]);
                })),
    ]);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
