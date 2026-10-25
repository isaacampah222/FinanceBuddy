import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ledger_transaction.dart';
import '../models/review_item.dart';
import '../state/app_state.dart';
import 'account_dialog.dart';
import 'formatters.dart';

Future<void> showTransactionDialog(BuildContext context,
    {ReviewItem? review, int? accountId}) async {
  if (context.read<AppState>().accounts.isEmpty) {
    await showAccountDialog(context);
    if (!context.mounted || context.read<AppState>().accounts.isEmpty) return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransactionDialog(review: review, accountId: accountId));
}

class _TransactionDialog extends StatefulWidget {
  const _TransactionDialog({this.review, this.accountId});
  final ReviewItem? review;
  final int? accountId;
  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  int? _accountId, _categoryId;
  TransactionDirection? _direction;
  late DateTime _date;
  bool _saving = false;
  String? _error, _foreignCurrency;

  @override
  void initState() {
    super.initState();
    final item = widget.review;
    final parsed =
        item == null ? null : context.read<AppState>().suggestion(item);
    _accountId = widget.accountId ?? parsed?.accountId;
    _categoryId = parsed?.categoryId;
    _direction = parsed?.direction;
    _date = item?.receivedAt ?? DateTime.now();
    if (parsed != null) {
      if (parsed.currency == 'GHS') {
        _amount.text = parsed.amount.toStringAsFixed(2);
      } else {
        _foreignCurrency = parsed.currency;
      }
    }
    _note.text = parsed?.counterparty ?? item?.sender ?? '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save({bool dismiss = false}) async {
    if (_saving) return;
    if (!dismiss && !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      final item = widget.review;
      if (dismiss && item != null) {
        await state.dismissReview(item.id);
      } else {
        final note =
            _note.text.trim().isEmpty ? 'Transaction' : _note.text.trim();
        if (item == null) {
          await state.addManual(
              accountId: _accountId!,
              categoryId: _categoryId,
              amount: double.parse(_amount.text.trim()),
              direction: _direction!,
              note: note,
              occurredAt: _date);
        } else {
          await state.confirmReview(item,
              accountId: _accountId!,
              categoryId: _categoryId,
              amount: double.parse(_amount.text.trim()),
              direction: _direction!,
              note: note,
              occurredAt: _date);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Check the details and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final item = widget.review;
    return PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(item == null ? 'Add transaction' : 'Confirm transaction'),
          content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (item != null) ...[
                              Text('From ${item.sender}',
                                  style:
                                      Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 8),
                              SelectableText(item.body),
                              const SizedBox(height: 12),
                              const Text(
                                  'Check the amount and account before saving. Your balance changes only after you confirm.'),
                              const SizedBox(height: 16),
                            ],
                            DropdownButtonFormField<int>(
                                initialValue: _accountId,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Account'),
                                items: state.accounts
                                    .map((a) => DropdownMenuItem(
                                        value: a.id, child: Text(a.name)))
                                    .toList(),
                                validator: (value) =>
                                    value == null ? 'Choose an account.' : null,
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _accountId = value)),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<TransactionDirection>(
                                initialValue: _direction,
                                decoration: const InputDecoration(
                                    labelText: 'Transaction type'),
                                items: const [
                                  DropdownMenuItem(
                                      value: TransactionDirection.credit,
                                      child: Text('Income')),
                                  DropdownMenuItem(
                                      value: TransactionDirection.debit,
                                      child: Text('Expense'))
                                ],
                                validator: (value) => value == null
                                    ? 'Choose income or expense.'
                                    : null,
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _direction = value)),
                            const SizedBox(height: 14),
                            if (_foreignCurrency != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                      'This message uses $_foreignCurrency. Enter the equivalent GHS amount yourself; no exchange rate is applied.')),
                            TextFormField(
                                controller: _amount,
                                enabled: !_saving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Amount (GHS)'),
                                validator: (value) {
                                  final amount =
                                      double.tryParse(value?.trim() ?? '');
                                  return amount != null &&
                                          amount.isFinite &&
                                          amount > 0
                                      ? null
                                      : 'Enter a positive amount.';
                                }),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<int>(
                                initialValue: _categoryId,
                                decoration: const InputDecoration(
                                    labelText: 'Category (optional)'),
                                items: state.categories
                                    .map((c) => DropdownMenuItem(
                                        value: c.id, child: Text(c.name)))
                                    .toList(),
                                onChanged: _saving
                                    ? null
                                    : (value) =>
                                        setState(() => _categoryId = value)),
                            const SizedBox(height: 14),
                            TextFormField(
                                controller: _note,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                    labelText: 'Note / counterparty')),
                            TextButton.icon(
                                icon: const Icon(Icons.calendar_today_outlined),
                                label: Text(dayFormat.format(_date)),
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _date,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime.now()
                                                .add(const Duration(days: 1)));
                                        if (picked != null && mounted) {
                                          setState(() => _date = DateTime(
                                              picked.year,
                                              picked.month,
                                              picked.day,
                                              _date.hour,
                                              _date.minute));
                                        }
                                      }),
                            if (_error != null)
                              Text(_error!,
                                  style: TextStyle(
                                      color:
                                          Theme.of(context).colorScheme.error)),
                          ])))),
          actions: [
            if (item != null)
              TextButton(
                  onPressed: _saving ? null : () => _save(dismiss: true),
                  child: const Text('Ignore')),
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(item == null ? 'Cancel' : 'Later')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save transaction')),
          ],
        ));
  }
}
