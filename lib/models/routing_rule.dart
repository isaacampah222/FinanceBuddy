import 'ledger_transaction.dart';

class RoutingRule {
  const RoutingRule({
    required this.id,
    required this.pattern,
    required this.matchSender,
    required this.accountId,
    this.categoryId,
    this.senderPattern = '',
    this.requiredKeywords = '',
    this.excludedKeywords = '',
    this.direction,
    this.currency,
    this.minAmount,
    this.maxAmount,
    this.priority = 0,
  });

  final int id;
  final String pattern;
  final bool matchSender;
  final int accountId;
  final int? categoryId;
  final String senderPattern;
  final String requiredKeywords;
  final String excludedKeywords;
  final TransactionDirection? direction;
  final String? currency;
  final double? minAmount;
  final double? maxAmount;
  final int priority;

  String get effectiveSenderPattern =>
      senderPattern.isNotEmpty ? senderPattern : (matchSender ? pattern : '');
  String get effectiveRequiredKeywords => requiredKeywords.isNotEmpty
      ? requiredKeywords
      : (matchSender ? '' : pattern);

  factory RoutingRule.fromMap(Map<String, Object?> map) => RoutingRule(
        id: map['id']! as int,
        pattern: map['pattern']! as String,
        matchSender: map['match_sender'] == 1,
        accountId: map['account_id']! as int,
        categoryId: map['category_id'] as int?,
        senderPattern: (map['sender_pattern'] as String?) ?? '',
        requiredKeywords: (map['required_keywords'] as String?) ?? '',
        excludedKeywords: (map['excluded_keywords'] as String?) ?? '',
        direction: switch (map['direction']) {
          'credit' => TransactionDirection.credit,
          'debit' => TransactionDirection.debit,
          _ => null
        },
        currency: map['currency'] as String?,
        minAmount: (map['min_amount'] as num?)?.toDouble(),
        maxAmount: (map['max_amount'] as num?)?.toDouble(),
        priority: (map['priority'] as int?) ?? 0,
      );
}
