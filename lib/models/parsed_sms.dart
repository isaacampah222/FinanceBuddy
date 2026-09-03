import 'ledger_transaction.dart';

class ParsedSms {
  const ParsedSms({
    required this.amount,
    required this.currency,
    required this.direction,
    required this.counterparty,
    required this.occurredAt,
    this.reference,
    this.accountId,
    this.categoryId,
  });
  final double amount;
  final String currency;
  final TransactionDirection direction;
  final String counterparty;
  final DateTime occurredAt;
  final String? reference;
  final int? accountId;
  final int? categoryId;
}
