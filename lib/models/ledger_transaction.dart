enum TransactionDirection { credit, debit }

class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.counterparty,
    required this.occurredAt,
    required this.isManual,
    this.categoryName,
    this.reference,
  });
  final int id;
  final int accountId;
  final String accountName;
  final double amount;
  final String currency;
  final TransactionDirection direction;
  final String counterparty;
  final DateTime occurredAt;
  final bool isManual;
  final String? categoryName;
  final String? reference;

  factory LedgerTransaction.fromMap(Map<String, Object?> map) =>
      LedgerTransaction(
        id: map['id']! as int,
        accountId: map['account_id']! as int,
        accountName: map['account_name']! as String,
        amount: (map['amount']! as num).toDouble(),
        currency: map['currency']! as String,
        direction: map['direction'] == 'credit'
            ? TransactionDirection.credit
            : TransactionDirection.debit,
        counterparty: (map['counterparty'] as String?) ?? 'Unknown',
        occurredAt:
            DateTime.fromMillisecondsSinceEpoch(map['occurred_at']! as int),
        isManual: map['is_manual'] == 1,
        categoryName: map['category_name'] as String?,
        reference: map['reference'] as String?,
      );
}
