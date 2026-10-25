import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

Future<void> showAccountDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AccountDialog());

class _AccountDialog extends StatefulWidget {
  const _AccountDialog();
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0.00');
  String _kind = 'bank';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().addAccount(
          name: _name.text,
          kind: _kind,
          openingBalance: double.parse(_balance.text.trim()));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the account. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Create an account'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Give each bank account, wallet, or cash stash its own place.'),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _name,
                      maxLength: 60,
                      decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'e.g. GCB salary account'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter an account name.'
                              : null),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                            value: 'bank', child: Text('Bank account')),
                        DropdownMenuItem(
                            value: 'momo', child: Text('Mobile money')),
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(
                            value: 'savings', child: Text('Savings')),
                        DropdownMenuItem(value: 'other', child: Text('Other'))
                      ],
                      onChanged: (value) => setState(() => _kind = value!)),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _balance,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                          labelText: 'Opening balance (GHS)',
                          helperText:
                              'Your balance before the transactions you will add.'),
                      validator: (value) =>
                          double.tryParse(value?.trim() ?? '')?.isFinite == true
                              ? null
                              : 'Enter a valid balance.'),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!)),
                ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Create account'))
        ],
      ));
}
