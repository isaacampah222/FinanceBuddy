import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/category.dart';
import '../models/ledger_transaction.dart';
import '../models/parsed_sms.dart';
import '../models/review_item.dart';
import '../models/routing_rule.dart';

class AppDatabase {
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(
      p.join(root, 'finance_buddy.db'),
      version: 5,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE accounts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kind TEXT NOT NULL, balance REAL NOT NULL DEFAULT 0, currency TEXT NOT NULL DEFAULT \'GHS\')');
        await db.execute(
            'CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
        await db.execute(
            'CREATE TABLE routing_rules(id INTEGER PRIMARY KEY AUTOINCREMENT, pattern TEXT NOT NULL DEFAULT \'\', match_sender INTEGER NOT NULL DEFAULT 0, account_id INTEGER NOT NULL REFERENCES accounts(id), category_id INTEGER REFERENCES categories(id), sender_pattern TEXT NOT NULL DEFAULT \'\', required_keywords TEXT NOT NULL DEFAULT \'\', excluded_keywords TEXT NOT NULL DEFAULT \'\', direction TEXT, currency TEXT, min_amount REAL, max_amount REAL, priority INTEGER NOT NULL DEFAULT 0)');
        await db.execute(
            'CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT, account_id INTEGER NOT NULL REFERENCES accounts(id), category_id INTEGER REFERENCES categories(id), amount REAL NOT NULL CHECK(amount > 0), currency TEXT NOT NULL, direction TEXT NOT NULL CHECK(direction IN (\'credit\', \'debit\')), counterparty TEXT, reference TEXT, occurred_at INTEGER NOT NULL, sms_hash TEXT UNIQUE, is_manual INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
        await db.execute(
            'CREATE TABLE processed_sms(hash TEXT PRIMARY KEY, processed_at INTEGER NOT NULL)');
        await db.execute(
            'CREATE TABLE ignored_sms(hash TEXT PRIMARY KEY, ignored_at INTEGER NOT NULL)');
        await db.execute(
            'CREATE TABLE review_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sms_hash TEXT NOT NULL UNIQUE, sender TEXT, body_preview TEXT NOT NULL, body_full TEXT NOT NULL, received_at INTEGER NOT NULL, created_at INTEGER NOT NULL)');
        final batch = db.batch();
        for (final item in [
          ('Bank', 'bank'),
          ('Mobile Money', 'momo'),
          ('Cash', 'cash')
        ]) {
          batch.insert('accounts', {
            'name': item.$1,
            'kind': item.$2,
            'balance': 0.0,
            'currency': 'GHS'
          });
        }
        for (final name in [
          'Groceries',
          'Utilities',
          'Salary',
          'Transfers',
          'Transport',
          'Other'
        ]) {
          batch.insert('categories', {'name': name});
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final statement in [
            'ALTER TABLE routing_rules ADD COLUMN sender_pattern TEXT NOT NULL DEFAULT \'\'',
            'ALTER TABLE routing_rules ADD COLUMN required_keywords TEXT NOT NULL DEFAULT \'\'',
            'ALTER TABLE routing_rules ADD COLUMN excluded_keywords TEXT NOT NULL DEFAULT \'\'',
            'ALTER TABLE routing_rules ADD COLUMN direction TEXT',
            'ALTER TABLE routing_rules ADD COLUMN currency TEXT',
            'ALTER TABLE routing_rules ADD COLUMN min_amount REAL',
            'ALTER TABLE routing_rules ADD COLUMN max_amount REAL',
            'ALTER TABLE routing_rules ADD COLUMN priority INTEGER NOT NULL DEFAULT 0',
          ]) {
            await db.execute(statement);
          }
        }
        if (oldVersion < 3) {
          await db
              .execute('ALTER TABLE review_items ADD COLUMN body_full TEXT');
          await db.execute(
              'UPDATE review_items SET body_full=body_preview WHERE body_full IS NULL');
        }
        if (oldVersion < 4) {
          await db.execute(
              'CREATE TABLE ignored_sms(hash TEXT PRIMARY KEY, ignored_at INTEGER NOT NULL)');
        }
        if (oldVersion < 5) {
          await db.execute('''
            DELETE FROM processed_sms
            WHERE hash NOT IN (
              SELECT sms_hash FROM transactions WHERE sms_hash IS NOT NULL
              UNION SELECT sms_hash FROM review_items
              UNION SELECT hash FROM ignored_sms
            )
          ''');
        }
      },
    );
  }

  Future<List<Account>> accounts() async =>
      (await (await database).query('accounts', orderBy: 'id'))
          .map(Account.fromMap)
          .toList();
  Future<List<Category>> categories() async =>
      (await (await database).query('categories', orderBy: 'name'))
          .map(Category.fromMap)
          .toList();
  Future<List<RoutingRule>> rules() async => (await (await database)
          .query('routing_rules', orderBy: 'priority DESC, id DESC'))
      .map(RoutingRule.fromMap)
      .toList();

  Future<List<LedgerTransaction>> transactions() async {
    final rows = await (await database).rawQuery(
        'SELECT t.*, a.name account_name, c.name category_name FROM transactions t JOIN accounts a ON a.id=t.account_id LEFT JOIN categories c ON c.id=t.category_id ORDER BY t.occurred_at DESC');
    return rows.map(LedgerTransaction.fromMap).toList();
  }

  Future<List<ReviewItem>> reviewItems() async => (await (await database)
          .query('review_items', orderBy: 'received_at DESC'))
      .map(ReviewItem.fromMap)
      .toList();
  Future<bool> isProcessed(String hash) async =>
      (await (await database).query('processed_sms',
              columns: ['hash'], where: 'hash=?', whereArgs: [hash], limit: 1))
          .isNotEmpty;

  Future<bool> isIgnored(String hash) async =>
      (await (await database).query('ignored_sms',
              columns: ['hash'], where: 'hash=?', whereArgs: [hash], limit: 1))
          .isNotEmpty;

  Future<bool> isTransactionImported(String hash) async =>
      (await (await database).query('transactions',
              columns: ['id'],
              where: 'sms_hash=?',
              whereArgs: [hash],
              limit: 1))
          .isNotEmpty;

  Future<void> markProcessed(String hash) async => (await database).insert(
      'processed_sms',
      {'hash': hash, 'processed_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore);

  Future<void> refreshReviewBody(
          {required String hash, required String body}) async =>
      (await database).update(
          'review_items',
          {
            'body_full': body,
            'body_preview':
                body.length <= 160 ? body : '${body.substring(0, 160)}…',
          },
          where: 'sms_hash=?',
          whereArgs: [hash]);

  Future<bool> addParsed(ParsedSms parsed, String hash) async {
    final db = await database;
    return db.transaction((txn) async {
      final claimed = await txn.insert('processed_sms',
          {'hash': hash, 'processed_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (claimed == 0) return false;
      final accountId = parsed.accountId!;
      await txn.insert('transactions', {
        'account_id': accountId,
        'category_id': parsed.categoryId,
        'amount': parsed.amount,
        'currency': parsed.currency,
        'direction': parsed.direction.name,
        'counterparty': parsed.counterparty,
        'reference': parsed.reference,
        'occurred_at': parsed.occurredAt.millisecondsSinceEpoch,
        'sms_hash': hash,
        'is_manual': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      final signed = parsed.direction == TransactionDirection.credit
          ? parsed.amount
          : -parsed.amount;
      await txn.rawUpdate('UPDATE accounts SET balance=balance+? WHERE id=?',
          [signed, accountId]);
      return true;
    });
  }

  Future<bool> addReview(
      {required String hash,
      required String sender,
      required String body,
      required String preview,
      required DateTime receivedAt}) async {
    final db = await database;
    return db.transaction((txn) async {
      final claimed = await txn.insert('processed_sms',
          {'hash': hash, 'processed_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (claimed == 0) return false;
      await txn.insert('review_items', {
        'sms_hash': hash,
        'sender': sender,
        'body_preview': preview,
        'body_full': body,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'created_at': DateTime.now().millisecondsSinceEpoch
      });
      return true;
    });
  }

  Future<bool> promoteReview(ReviewItem item, ParsedSms parsed) async {
    final db = await database;
    return db.transaction((txn) async {
      final exists = await txn.query('review_items',
          columns: ['id'], where: 'id=?', whereArgs: [item.id], limit: 1);
      if (exists.isEmpty) return false;
      final accountId = parsed.accountId!;
      final rowId = await txn.insert(
          'transactions',
          {
            'account_id': accountId,
            'category_id': parsed.categoryId,
            'amount': parsed.amount,
            'currency': parsed.currency,
            'direction': parsed.direction.name,
            'counterparty': parsed.counterparty,
            'reference': parsed.reference,
            'occurred_at': parsed.occurredAt.millisecondsSinceEpoch,
            'sms_hash': item.smsHash,
            'is_manual': 0,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      if (rowId != 0) {
        final signed = parsed.direction == TransactionDirection.credit
            ? parsed.amount
            : -parsed.amount;
        await txn.rawUpdate('UPDATE accounts SET balance=balance+? WHERE id=?',
            [signed, accountId]);
      }
      await txn.delete('review_items', where: 'id=?', whereArgs: [item.id]);
      return rowId != 0;
    });
  }

  Future<void> dismissReview(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query('review_items',
          columns: ['sms_hash'], where: 'id=?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return;
      await txn.insert(
          'ignored_sms',
          {
            'hash': rows.first['sms_hash'],
            'ignored_at': DateTime.now().millisecondsSinceEpoch
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.delete('review_items', where: 'id=?', whereArgs: [id]);
    });
  }

  Future<void> setBalance(int accountId, double balance) async =>
      (await database).update('accounts', {'balance': balance},
          where: 'id=?', whereArgs: [accountId]);

  Future<void> addManual(
      {required int accountId,
      int? categoryId,
      required double amount,
      required TransactionDirection direction,
      required String note,
      required DateTime occurredAt}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('transactions', {
        'account_id': accountId,
        'category_id': categoryId,
        'amount': amount,
        'currency': 'GHS',
        'direction': direction.name,
        'counterparty': note,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'is_manual': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch
      });
      final signed =
          direction == TransactionDirection.credit ? amount : -amount;
      await txn.rawUpdate('UPDATE accounts SET balance=balance+? WHERE id=?',
          [signed, accountId]);
    });
  }

  Future<bool> addRule(
      {required int accountId,
      int? categoryId,
      String senderPattern = '',
      String requiredKeywords = '',
      String excludedKeywords = '',
      TransactionDirection? direction,
      String? currency,
      double? minAmount,
      double? maxAmount,
      int priority = 0}) async {
    final candidateSender = _canonicalTerms(senderPattern);
    final candidateRequired = _canonicalTerms(requiredKeywords);
    final candidateExcluded = _canonicalTerms(excludedKeywords);
    final candidateCurrency = currency?.trim().toUpperCase();
    final existing = await rules();
    final duplicate = existing.any((rule) =>
        rule.accountId == accountId &&
        rule.categoryId == categoryId &&
        _canonicalTerms(rule.effectiveSenderPattern) == candidateSender &&
        _canonicalTerms(rule.effectiveRequiredKeywords) == candidateRequired &&
        _canonicalTerms(rule.excludedKeywords) == candidateExcluded &&
        rule.direction == direction &&
        (rule.currency?.toUpperCase()) == candidateCurrency &&
        rule.minAmount == minAmount &&
        rule.maxAmount == maxAmount);
    if (duplicate) return false;
    await (await database).insert('routing_rules', {
      'pattern': '',
      'match_sender': 0,
      'account_id': accountId,
      'category_id': categoryId,
      'sender_pattern': candidateSender,
      'required_keywords': candidateRequired,
      'excluded_keywords': candidateExcluded,
      'direction': direction?.name,
      'currency': currency?.trim().toUpperCase(),
      'min_amount': minAmount,
      'max_amount': maxAmount,
      'priority': priority,
    });
    return true;
  }

  String _canonicalTerms(String value) {
    final terms = value
        .toLowerCase()
        .split(RegExp(r'[,|]'))
        .map((term) => term.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return terms.join(' | ');
  }

  Future<void> deleteRule(int id) async =>
      (await database).delete('routing_rules', where: 'id=?', whereArgs: [id]);
  Future<void> addCategory(String name) async =>
      (await database).insert('categories', {'name': name.trim()},
          conflictAlgorithm: ConflictAlgorithm.ignore);
}
