import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import 'formatters.dart';
import 'transaction_dialog.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction suggestions')),
      body: state.reviewItems.isEmpty
          ? const Center(
              child: Text('All caught up. No transactions to confirm.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.reviewItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = state.reviewItems[index];
                return Card(
                    child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.mark_chat_unread_outlined),
                  title: Text(item.sender),
                  subtitle: Text(
                      '${dayFormat.format(item.receivedAt)}\n${item.preview}',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showTransactionDialog(context, review: item),
                ));
              }),
    );
  }
}
