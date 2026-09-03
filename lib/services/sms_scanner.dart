import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/app_database.dart';
import '../models/routing_rule.dart';
import 'sms_source.dart';
import 'transaction_parser.dart';

class ScanResult {
  const ScanResult(
      {required this.scanned,
      required this.imported,
      required this.reviewed,
      required this.duplicates});
  final int scanned;
  final int imported;
  final int reviewed;
  final int duplicates;
}

class SmsScanner {
  SmsScanner(this._database, this._source, this._parser);
  final AppDatabase _database;
  final SmsSource _source;
  final TransactionParser _parser;

  Future<ScanResult> scan() async {
    final rules = await _database.rules();
    var imported = await _applyRulesToReviews(rules);
    final messages = await _source.inbox();
    var reviewed = 0, duplicates = 0;
    for (final sms in messages) {
      final hash = sha256
          .convert(utf8.encode(
              '${sms.id}|${sms.sender}|${sms.date.millisecondsSinceEpoch}|${sms.body}'))
          .toString();
      if (await _database.isIgnored(hash)) {
        continue;
      }
      if (await _database.isProcessed(hash)) {
        await _database.refreshReviewBody(hash: hash, body: sms.body);
        if (await _database.isTransactionImported(hash)) duplicates++;
        continue;
      }
      final parsed = _parser.parseReviewed(sms, rules);
      if (parsed != null) {
        if (await _database.addParsed(parsed, hash)) imported++;
      } else if (_parser.isTransactional(sms.body)) {
        final preview = sms.body.length <= 160
            ? sms.body
            : '${sms.body.substring(0, 160)}…';
        if (await _database.addReview(
            hash: hash,
            sender: sms.sender,
            body: sms.body,
            preview: preview,
            receivedAt: sms.date)) reviewed++;
      }
    }
    return ScanResult(
        scanned: messages.length,
        imported: imported,
        reviewed: reviewed,
        duplicates: duplicates);
  }

  Future<int> applyRulesToReviews() async {
    final rules = await _database.rules();
    return _applyRulesToReviews(rules);
  }

  Future<int> _applyRulesToReviews(List<RoutingRule> rules) async {
    final reviews = await _database.reviewItems();
    var imported = 0;
    for (final item in reviews) {
      final parsed = _parser.parseReviewed(
          DeviceSms(
              id: item.smsHash,
              sender: item.sender,
              body: item.body,
              date: item.receivedAt),
          rules);
      if (parsed != null && await _database.promoteReview(item, parsed))
        imported++;
    }
    return imported;
  }
}
