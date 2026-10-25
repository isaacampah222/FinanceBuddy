import 'dart:io';
import 'package:finance_buddy/data/app_database.dart';
import 'package:finance_buddy/models/ledger_transaction.dart';
import 'package:finance_buddy/models/parsed_sms.dart';
import 'package:finance_buddy/services/sms_scanner.dart';
import 'package:finance_buddy/services/sms_source.dart';
import 'package:finance_buddy/services/transaction_parser.dart';
import 'package:finance_buddy/state/app_state.dart';
import 'package:finance_buddy/ui/account_dialog.dart';
import 'package:finance_buddy/ui/transaction_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Inbox extends SmsSource {
  final messages = <DeviceSms>[];
  @override
  Future<List<DeviceSms>> inbox() async => messages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  late Directory directory;
  late AppDatabase db;
  late Inbox inbox;
  late SmsScanner scanner;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('finance_buddy_test_');
    await databaseFactory.setDatabasesPath(directory.path);
    db = AppDatabase();
    await db.database;
    inbox = Inbox();
    scanner = SmsScanner(db, inbox, TransactionParser());
  });
  tearDown(() async {
    await (await db.database).close();
    await directory.delete(recursive: true);
  });

  test('custom accounts keep independent balances for income and expenses',
      () async {
    await db.addAccount(name: 'GCB salary', kind: 'bank', openingBalance: 500);
    await db.addAccount(name: 'Travel cash', kind: 'cash', openingBalance: 100);
    final accounts = await db.accounts();
    final bank = accounts.firstWhere((a) => a.name == 'GCB salary');
    final cash = accounts.firstWhere((a) => a.name == 'Travel cash');
    await db.addManual(
        accountId: bank.id,
        amount: 200,
        direction: TransactionDirection.credit,
        note: 'Salary',
        occurredAt: DateTime(2026, 10, 1));
    await db.addManual(
        accountId: cash.id,
        amount: 25,
        direction: TransactionDirection.debit,
        note: 'Transport',
        occurredAt: DateTime(2026, 10, 2));
    final updated = await db.accounts();
    expect(updated.firstWhere((a) => a.id == bank.id).balance, 700);
    expect(updated.firstWhere((a) => a.id == cash.id).balance, 75);
    expect((await db.transactions()).length, 2);
    await expectLater(
        db.addManual(
            accountId: bank.id,
            amount: double.nan,
            direction: TransactionDirection.debit,
            note: '',
            occurredAt: DateTime.now()),
        throwsArgumentError);
    expect((await db.transactions()).length, 2);
  });

  test(
      'matching SMS queues for confirmation without changing balance; repeat scan is idempotent',
      () async {
    final account = (await db.accounts()).first;
    await db.addRule(accountId: account.id, senderPattern: 'BANK');
    inbox.messages.add(DeviceSms(
        id: '1',
        sender: 'BANK',
        body: 'You have been debited GHS 50.00. Ref: AB123',
        date: DateTime(2026, 10, 25)));
    expect((await scanner.scan()).reviewed, 1);
    expect((await db.transactions()), isEmpty);
    expect((await db.accounts()).first.balance, 0);
    expect((await scanner.scan()).reviewed, 0);
    final item = (await db.reviewItems()).single;
    final parsed = ParsedSms(
        amount: 45,
        currency: 'GHS',
        direction: TransactionDirection.debit,
        counterparty: 'Corrected amount',
        occurredAt: item.receivedAt,
        accountId: account.id);
    expect(await db.promoteReview(item, parsed), isTrue);
    expect(await db.promoteReview(item, parsed), isFalse);
    expect((await db.accounts()).first.balance, -45);
    expect((await db.transactions()).length, 1);
    expect(await db.reviewItems(), isEmpty);
  });

  test(
      'invalid account rolls confirmation back and leaves suggestion available',
      () async {
    await scanner.queueMessage(DeviceSms(
        id: '1',
        sender: 'BANK',
        body: 'Received GHS 20 from Ama',
        date: DateTime(2026)));
    final item = (await db.reviewItems()).single;
    await expectLater(
        db.promoteReview(
            item,
            ParsedSms(
                amount: 20,
                currency: 'GHS',
                direction: TransactionDirection.credit,
                counterparty: 'Ama',
                occurredAt: item.receivedAt,
                accountId: 999)),
        throwsArgumentError);
    expect((await db.reviewItems()).length, 1);
    expect(await db.transactions(), isEmpty);
  });

  test('ignored suggestions and failed payments never change balances',
      () async {
    final sms = DeviceSms(
        id: '1',
        sender: 'BANK',
        body: 'Paid GHS 20 to Ama',
        date: DateTime(2026));
    await scanner.queueMessage(sms);
    await db.dismissReview((await db.reviewItems()).single.id);
    expect(await scanner.queueMessage(sms), isFalse);
    expect(
        await scanner.queueMessage(DeviceSms(
            id: '2',
            sender: 'BANK',
            body: 'Failed payment of GHS 200',
            date: DateTime(2026))),
        isFalse);
    expect(await db.transactions(), isEmpty);
    expect(await db.reviewItems(), isEmpty);
  });

  test(
      'suggestion parser works without rules and rejects authorization messages',
      () {
    final parser = TransactionParser();
    final parsed = parser.parse(
        DeviceSms(
            id: '1',
            sender: 'BANK',
            body: 'You received GHS 150 from Ama',
            date: DateTime(2026)),
        [],
        requireRoute: false);
    expect(parsed?.amount, 150);
    expect(parsed?.accountId, isNull);
    expect(parsed?.direction, TransactionDirection.credit);
    expect(
        parser.parse(
            DeviceSms(
                id: '2',
                sender: 'BANK',
                body: 'Use code 1234 for payment of GHS 200',
                date: DateTime(2026)),
            [],
            requireRoute: false),
        isNull);
  });

  testWidgets('account form validates name and creates named account',
      (tester) async {
    final state = AppState(db, scanner);
    await state.refresh();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showAccountDialog(context),
                        child: const Text('Create')))))));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter an account name.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'My savings');
    await tester.enterText(find.byType(TextFormField).last, '350.50');
    await tester.tap(find.text('Create account').last);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    final accounts = await tester.runAsync(() => db.accounts());
    expect(accounts!.last.name, 'My savings');
    expect(accounts.last.balance, 350.50);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('Later keeps suggestion without recording a transaction',
      (tester) async {
    await scanner.queueMessage(DeviceSms(
        id: '1',
        sender: 'BANK',
        body: 'Received GHS 20 from Ama',
        date: DateTime(2026)));
    final state = AppState(db, scanner);
    await state.refresh();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showTransactionDialog(context,
                            review: state.reviewItems.single),
                        child: const Text('Review')))))));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm transaction'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    final reviews = await tester.runAsync(() => db.reviewItems());
    final transactions = await tester.runAsync(() => db.transactions());
    expect(reviews!.length, 1);
    expect(transactions, isEmpty);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
