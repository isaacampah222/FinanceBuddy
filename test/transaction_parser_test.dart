import 'package:finance_buddy/models/ledger_transaction.dart';
import 'package:finance_buddy/models/routing_rule.dart';
import 'package:finance_buddy/services/sms_source.dart';
import 'package:finance_buddy/services/transaction_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const momo = RoutingRule(
      id: 1, pattern: 'MTN', matchSender: true, accountId: 2, categoryId: null);
  final parser = TransactionParser();

  test('parses comma separated debit and reference', () {
    final parsed = parser.parse(
        DeviceSms(
            id: '1',
            sender: 'MTN',
            body: 'You have sent GHS 5,000.50 to Ama. Ref: AB-123',
            date: DateTime(2026)),
        [momo]);
    expect(parsed?.amount, 5000.50);
    expect(parsed?.currency, 'GHS');
    expect(parsed?.direction, TransactionDirection.debit);
    expect(parsed?.accountId, 2);
    expect(parsed?.reference, 'AB-123');
  });

  test('parses symbol-based credit', () {
    final parsed = parser.parse(
        DeviceSms(
            id: '2',
            sender: 'MTN',
            body: r'You received $45.20 from Alex',
            date: DateTime(2026)),
        [momo]);
    expect(parsed?.amount, 45.20);
    expect(parsed?.currency, 'USD');
    expect(parsed?.direction, TransactionDirection.credit);
  });

  test('does not parse without a routing rule', () {
    final parsed = parser.parse(
        DeviceSms(
            id: '3',
            sender: 'Other',
            body: 'Debited GHS 10.00',
            date: DateTime(2026)),
        [momo]);
    expect(parsed, isNull);
  });

  test('parses Telecel Cash send and ignores balance and fee amounts', () {
    const rule = RoutingRule(
        id: 2,
        pattern: '',
        matchSender: false,
        senderPattern: 'T-CASH|Telecel',
        requiredKeywords: 'sent',
        direction: TransactionDirection.debit,
        accountId: 2,
        categoryId: 4,
        priority: 10);
    final parsed = parser.parse(
        DeviceSms(
            id: '4',
            sender: 'T-CASH',
            body:
                '0000013375645675 Confirmed. GHS125.00 sent to 0543273403 WINIFRED on MTN MOBILE MONEY. Your Telecel Cash balance is GHS576.52. You were charged GHS0.94.',
            date: DateTime(2026)),
        [rule]);
    expect(parsed?.amount, 125);
    expect(parsed?.direction, TransactionDirection.debit);
    expect(parsed?.reference, '0000013375645675');
    expect(parsed?.categoryId, 4);
  });

  test('parses Telecel Cash receipt as income', () {
    const rule = RoutingRule(
        id: 3,
        pattern: '',
        matchSender: false,
        senderPattern: 'T-CASH',
        requiredKeywords: 'received',
        direction: TransactionDirection.credit,
        accountId: 2,
        categoryId: 3);
    final parsed = parser.parse(
        DeviceSms(
            id: '5',
            sender: 'T-CASH',
            body:
                '0000013309283289 Confirmed. You have received GHS21.00 from MTN MOBILE MONEY. Your Telecel Cash balance is GHS21.07.',
            date: DateTime(2026)),
        [rule]);
    expect(parsed?.amount, 21);
    expect(parsed?.direction, TransactionDirection.credit);
  });

  test('supports Ghana cedi variants and postfixed currency', () {
    const rule = RoutingRule(
        id: 4,
        pattern: '',
        matchSender: false,
        senderPattern: 'GCB|BANK',
        requiredKeywords: 'debited',
        accountId: 1,
        categoryId: null);
    final parsed = parser.parse(
        DeviceSms(
            id: '6',
            sender: 'GCB',
            body:
                'Your account has been debited 1,250.50 GHS for POS purchase at ACCRA MALL. Ref ABC12345.',
            date: DateTime(2026)),
        [rule]);
    expect(parsed?.amount, 1250.50);
    expect(parsed?.currency, 'GHS');
  });

  test('exclusion keywords stop OTP and unsuccessful messages', () {
    const rule = RoutingRule(
        id: 5,
        pattern: '',
        matchSender: false,
        senderPattern: 'PaystackGH',
        requiredKeywords: 'pay',
        excludedKeywords: 'code|otp|unsuccessful',
        accountId: 1,
        categoryId: null);
    final parsed = parser.parse(
        DeviceSms(
            id: '7',
            sender: 'PaystackGH',
            body:
                'Enter code 114001 to pay GHS 5.61 to BRYTELINK. DO NOT SHARE.',
            date: DateTime(2026)),
        [rule]);
    expect(parsed, isNull);
  });

  test('does not treat a data credit as income', () {
    final parsed = parser.parse(
        DeviceSms(
            id: '8',
            sender: 'MTN',
            body: 'Your Account has been credited with 10 GB valid for 90 days',
            date: DateTime(2026)),
        [momo]);
    expect(parsed, isNull);
  });

  test('only identifies completed monetary transactions for review', () {
    expect(
        parser.isTransactional(
            'GHS125.00 sent to 0543273403 AMA. Your balance is GHS20.00.'),
        isTrue);
    expect(
        parser.isTransactional(
            'You have received GHS700.00 from MTN MOBILE MONEY.'),
        isTrue);
    expect(
        parser
            .isTransactional('Enter code 114001 to pay GHS5.61. DO NOT SHARE.'),
        isFalse);
    expect(
        parser.isTransactional('Get an offer of GHS10 bonus. Dial *170# now.'),
        isFalse);
    expect(parser.isTransactional('Your GHS20.00 payment was unsuccessful.'),
        isFalse);
    expect(parser.isTransactional('Your Account has been credited with 10 GB.'),
        isFalse);
    expect(
        parser.isTransactional(
            'You have received GHS700.00 from AMA. Never share your PIN or OTP with anyone.'),
        isTrue);
  });

  test('review rule resolves received messages that also mention a charge', () {
    const incomeRule = RoutingRule(
        id: 6,
        pattern: '',
        matchSender: false,
        senderPattern: 'T-CASH',
        requiredKeywords: 'received',
        direction: TransactionDirection.credit,
        accountId: 2,
        categoryId: 4);
    final sms = DeviceSms(
        id: '9',
        sender: 'T-CASH',
        body:
            'You have received GHS100.00 from KOFI. You were charged GHS1.00. Your balance is GHS200.00.',
        date: DateTime(2026));
    expect(parser.isTransactional(sms.body), isTrue);
    final parsed = parser.parseReviewed(sms, [incomeRule]);
    expect(parsed?.amount, 100);
    expect(parsed?.direction, TransactionDirection.credit);
  });
}
