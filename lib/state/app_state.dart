import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:permission_handler/permission_handler.dart';

import '../data/app_database.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/ledger_transaction.dart';
import '../models/review_item.dart';
import '../models/routing_rule.dart';
import '../models/parsed_sms.dart';
import '../services/notification_source.dart';
import '../services/sms_source.dart';
import '../services/transaction_parser.dart';
import '../services/sms_scanner.dart';

class AppState extends ChangeNotifier {
  AppState(this._database, this._scanner);
  final AppDatabase _database;
  final SmsScanner _scanner;
  final notifications = NotificationSource();
  bool notificationsEnabled = false;
  bool _readingNotifications = false;

  List<Account> accounts = const [];
  List<Category> categories = const [];
  List<RoutingRule> rules = const [];
  List<LedgerTransaction> transactions = const [];
  List<ReviewItem> reviewItems = const [];
  bool loading = true;
  bool scanning = false;
  bool permissionPermanentlyDenied = false;
  String? error;
  ScanResult? lastScan;

  double get totalBalance =>
      accounts.fold(0, (sum, account) => sum + account.balance);

  Future<void> initialize() async {
    try {
      await refresh();
      notificationsEnabled = await notifications.enabled();
      permissionPermanentlyDenied = await Permission.sms.isPermanentlyDenied;
    } catch (e) {
      error = 'Could not open local storage: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final values = await Future.wait([
      _database.accounts(),
      _database.categories(),
      _database.rules(),
      _database.transactions(),
      _database.reviewItems()
    ]);
    accounts = values[0] as List<Account>;
    categories = values[1] as List<Category>;
    rules = values[2] as List<RoutingRule>;
    transactions = values[3] as List<LedgerTransaction>;
    reviewItems = values[4] as List<ReviewItem>;
    notifyListeners();
  }

  Future<PermissionStatus> requestSmsPermission() async {
    final status = await Permission.sms.request();
    permissionPermanentlyDenied = status.isPermanentlyDenied;
    notifyListeners();
    return status;
  }

  Future<ScanResult?> scan() async {
    scanning = true;
    error = null;
    notifyListeners();
    try {
      lastScan = await _scanner.scan();
      await refresh();
      return lastScan;
    } catch (e) {
      error = 'SMS scan failed: $e';
      return null;
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> setBalance(int id, double value) async {
    await _database.setBalance(id, value);
    await refresh();
  }

  Future<void> addAccount(
      {required String name,
      required String kind,
      required double openingBalance}) async {
    await _database.addAccount(
        name: name, kind: kind, openingBalance: openingBalance);
    await refresh();
  }

  ParsedSms? suggestion(ReviewItem item) => TransactionParser().parse(
      DeviceSms(
          id: item.smsHash,
          sender: item.sender,
          body: item.body,
          date: item.receivedAt),
      rules,
      requireRoute: false);

  Future<void> confirmReview(ReviewItem item,
      {required int accountId,
      int? categoryId,
      required double amount,
      required TransactionDirection direction,
      required String note,
      required DateTime occurredAt}) async {
    await _database.promoteReview(
        item,
        ParsedSms(
            amount: amount,
            currency: 'GHS',
            direction: direction,
            counterparty: note,
            occurredAt: occurredAt,
            accountId: accountId,
            categoryId: categoryId,
            reference: suggestion(item)?.reference));
    await refresh();
  }

  Future<void> setNotificationDetection(bool enabled) async {
    await notifications.setEnabled(enabled);
    notificationsEnabled = await notifications.enabled();
    notifyListeners();
  }

  Future<void> readNotifications() async {
    if (_readingNotifications || loading) return;
    _readingNotifications = true;
    try {
      notificationsEnabled = await notifications.enabled();
      final pending = await notifications.pending();
      for (final message in pending) {
        await _scanner.queueMessage(message);
        await notifications.acknowledge(message.id);
      }
      if (pending.isNotEmpty) await refresh();
    } catch (_) {
      error = 'Could not read transaction alerts. They will be retried.';
    } finally {
      _readingNotifications = false;
      notifyListeners();
    }
  }

  Future<void> addManual(
      {required int accountId,
      int? categoryId,
      required double amount,
      required TransactionDirection direction,
      required String note,
      DateTime? occurredAt}) async {
    await _database.addManual(
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        direction: direction,
        note: note,
        occurredAt: occurredAt ?? DateTime.now());
    await refresh();
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
    final created = await _database.addRule(
        accountId: accountId,
        categoryId: categoryId,
        senderPattern: senderPattern,
        requiredKeywords: requiredKeywords,
        excludedKeywords: excludedKeywords,
        direction: direction,
        currency: currency,
        minAmount: minAmount,
        maxAmount: maxAmount,
        priority: priority);
    await refresh();
    return created;
  }

  Future<void> dismissReview(int id) async {
    await _database.dismissReview(id);
    await refresh();
  }

  Future<void> deleteRule(int id) async {
    await _database.deleteRule(id);
    await refresh();
  }

  Future<void> addCategory(String name) async {
    await _database.addCategory(name);
    await refresh();
  }
}
