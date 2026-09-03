import '../models/ledger_transaction.dart';
import '../models/parsed_sms.dart';
import '../models/routing_rule.dart';
import 'sms_source.dart';

class TransactionParser {
  static final RegExp _nonTransactionPattern = RegExp(
    r'\b(?:eligible|offer|promo|promotion|win|bonus|download (?:the )?app|unsuccessful|failed|declined|pending|kindly wait|request (?:has been )?received|scheduled|maintenance|limit (?:is|has)|low balance)\b',
    caseSensitive: false,
  );
  static final RegExp _authorizationPattern = RegExp(
    r'\b(?:enter|use|provide)\s+(?:the\s+)?(?:code|otp)\b|\bverification code\b|\botp\s+(?:to|for)\s+(?:pay|authorize|complete)\b',
    caseSensitive: false,
  );
  // Supports GHS/GHC/GH₵, common ISO codes, and currency symbols, before or
  // after an amount. Word boundaries prevent data balances such as "10 GB".
  static final RegExp _amountPattern = RegExp(
    r'(?:(GHS|GHC|GH₵|USD|UGX|EUR|GBP|KES|NGN|\$|€|£|₵)\s*)?'
    r'([0-9]+(?:[ ,][0-9]{3})*(?:\.[0-9]{1,2})?)'
    r'(?:\s*(GHS|GHC|GH₵|USD|UGX|EUR|GBP|KES|NGN|€|£|₵))?',
    caseSensitive: false,
  );
  static final RegExp _referencePattern = RegExp(
    r'(?:transaction|txn|trx|reference|ref)(?:\s+(?:id|number|no\.?))?\s*(?:is|[:#-])?\s*([a-z0-9][a-z0-9._/-]{2,})',
    caseSensitive: false,
  );
  static final RegExp _leadingIdPattern = RegExp(
      r'^\s*([0-9]{10,})\s+(?:confirmed|completed)\b',
      caseSensitive: false);
  static final RegExp _counterpartyPattern = RegExp(
    r'(?:sent\s+to|paid\s+to|transferred\s+to|withdrawn\s+from|received(?:\s+[^.]{0,30}?)?\s+from|purchase(?:d)?\s+(?:at|from)|merchant)\s+(.{2,80}?)(?=\s+(?:on|at\s+\d|with\s+transaction|ref|your\s+(?:new\s+)?(?:account\s+)?balance|you\s+were\s+charged)\b|[.;]|$)',
    caseSensitive: false,
  );

  static final RegExp _debitPattern = RegExp(
    r'\b(?:debited|deducted|spent|purchase(?:d)?|bought|paid(?:\s+off)?|payment|withdrawn|sent|charged|transferred\s+to|cash withdrawal)\b',
    caseSensitive: false,
  );
  static final RegExp _creditPattern = RegExp(
    r'\b(?:credited|received|deposit(?:ed)?|refund(?:ed)?|salary|cashback|reversal|transferred\s+from)\b',
    caseSensitive: false,
  );
  static final RegExp _nonMoneyCredit = RegExp(
      r'\bcredited\s+with\s+[0-9.,]+\s*(?:gb|mb|minutes?|points?)\b',
      caseSensitive: false);

  ParsedSms? parse(DeviceSms sms, List<RoutingRule> rules,
      {TransactionDirection? directionHint}) {
    final inferredDirection = _direction(sms.body);
    final direction = inferredDirection ?? directionHint;
    if (direction == null || _nonMoneyCredit.hasMatch(sms.body)) return null;
    final amountMatch = _transactionAmount(sms.body, direction);
    if (amountMatch == null) return null;
    final amount =
        double.tryParse(amountMatch.amount.replaceAll(RegExp(r'[ ,]'), ''));
    if (amount == null || amount <= 0) return null;
    final currency = _currency(amountMatch.currency);
    final route = _route(sms, rules,
        direction: direction,
        amount: amount,
        currency: currency,
        requireExplicitDirection:
            inferredDirection == null && directionHint != null);
    if (route == null) return null;

    return ParsedSms(
      amount: amount,
      currency: currency,
      direction: direction,
      counterparty: _counterpartyPattern
              .firstMatch(sms.body)
              ?.group(1)
              ?.replaceAll(RegExp(r'\s+'), ' ')
              .trim() ??
          sms.sender,
      reference: _leadingIdPattern.firstMatch(sms.body)?.group(1) ??
          _referencePattern.firstMatch(sms.body)?.group(1),
      occurredAt: sms.date,
      accountId: route.accountId,
      categoryId: route.categoryId,
    );
  }

  ParsedSms? parseReviewed(DeviceSms sms, List<RoutingRule> rules) {
    final parsed = parse(sms, rules);
    if (parsed != null) return parsed;

    final candidates = <ParsedSms>[];
    for (final direction in TransactionDirection.values) {
      final candidate = parse(sms, rules, directionHint: direction);
      if (candidate != null) {
        candidates.add(candidate);
      }
    }
    return candidates.length == 1 ? candidates.single : null;
  }

  bool isTransactional(String body) {
    if (_nonTransactionPattern.hasMatch(body) ||
        _authorizationPattern.hasMatch(body) ||
        _nonMoneyCredit.hasMatch(body)) {
      return false;
    }
    final direction = _direction(body);
    if (direction != null) return _transactionAmount(body, direction) != null;
    if (!_debitPattern.hasMatch(body) || !_creditPattern.hasMatch(body)) {
      return false;
    }
    return _transactionAmount(body, TransactionDirection.debit) != null ||
        _transactionAmount(body, TransactionDirection.credit) != null;
  }

  _AmountMatch? _transactionAmount(
      String body, TransactionDirection direction) {
    _AmountMatch? best;
    var bestScore = -999;
    for (final match in _amountPattern.allMatches(body)) {
      final currency = match.group(1) ?? match.group(3);
      if (currency == null) continue;
      final start = match.start;
      final context = body
          .substring(start > 45 ? start - 45 : 0,
              (match.end + 30).clamp(0, body.length).toInt())
          .toLowerCase();
      var score = 0;
      if ((direction == TransactionDirection.debit
              ? _debitPattern
              : _creditPattern)
          .hasMatch(context)) score += 8;
      if (RegExp(r'\b(?:balance|fee|charge|levy|limit|eligible|bonus)\b',
              caseSensitive: false)
          .hasMatch(context)) score -= 5;
      if (RegExp(
              r'\b(?:sent|received|withdrawn|debited|credited|paid|bought|purchased|deducted)\b',
              caseSensitive: false)
          .hasMatch(context)) score += 4;
      if (score > bestScore) {
        bestScore = score;
        best = _AmountMatch(match.group(2)!, currency);
      }
    }
    return best;
  }

  RoutingRule? _route(DeviceSms sms, List<RoutingRule> rules,
      {required TransactionDirection direction,
      required double amount,
      required String currency,
      bool requireExplicitDirection = false}) {
    final sender = sms.sender.toLowerCase();
    final body = sms.body.toLowerCase();
    final ordered = [...rules]
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (final rule in ordered) {
      if (requireExplicitDirection && rule.direction == null) continue;
      if (!_matchesAny(sender, rule.effectiveSenderPattern)) continue;
      if (!_matchesAll(body, rule.effectiveRequiredKeywords)) continue;
      if (_matchesAny(body, rule.excludedKeywords, emptyMatches: false))
        continue;
      if (rule.direction != null && rule.direction != direction) continue;
      if (rule.currency?.isNotEmpty == true &&
          rule.currency!.toUpperCase() != currency) continue;
      if (rule.minAmount != null && amount < rule.minAmount!) continue;
      if (rule.maxAmount != null && amount > rule.maxAmount!) continue;
      return rule;
    }
    return null;
  }

  bool _matchesAll(String target, String patterns) {
    final values = _terms(patterns);
    return values.isEmpty || values.every((term) => target.contains(term));
  }

  bool _matchesAny(String target, String patterns, {bool emptyMatches = true}) {
    final values = _terms(patterns);
    return values.isEmpty
        ? emptyMatches
        : values.any((term) => target.contains(term));
  }

  List<String> _terms(String value) => value
      .toLowerCase()
      .split(RegExp(r'[,|]'))
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();

  TransactionDirection? _direction(String body) {
    final debit = _debitPattern.hasMatch(body);
    final credit = _creditPattern.hasMatch(body);
    if (debit == credit)
      return null; // Ambiguous messages go to review instead of being misclassified.
    return debit ? TransactionDirection.debit : TransactionDirection.credit;
  }

  String _currency(String raw) => switch (raw.toUpperCase()) {
        r'$' => 'USD',
        '€' => 'EUR',
        '£' => 'GBP',
        '₵' || 'GH₵' || 'GHC' => 'GHS',
        _ => raw.toUpperCase()
      };
}

class _AmountMatch {
  const _AmountMatch(this.amount, this.currency);
  final String amount;
  final String currency;
}
