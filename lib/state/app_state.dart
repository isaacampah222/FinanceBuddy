import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:permission_handler/permission_handler.dart';

import '../data/app_database.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/ledger_transaction.dart';
import '../models/review_item.dart';
import '../models/routing_rule.dart';
import '../services/sms_scanner.dart';

class AppState extends ChangeNotifier {
  AppState(this._database, this._scanner);
  final AppDatabase _database;
  final SmsScanner _scanner;

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

  double get netWorth =>
      accounts.fold(0, (sum, account) => sum + account.balance);

  Future<void> initialize() async {
    try {
      await refresh();
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

  Future<void> addManual(
      {required int accountId,
      int? categoryId,
      required double amount,
      required TransactionDirection direction,
      required String note}) async {
    await _database.addManual(
        accountId: accountId,
        categoryId: categoryId,
        amount: amount,
        direction: direction,
        note: note,
        occurredAt: DateTime.now());
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
    await _scanner.applyRulesToReviews();
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
