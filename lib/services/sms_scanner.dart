import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/app_database.dart';
import 'sms_source.dart';
import 'transaction_parser.dart';

class ScanResult {
  const ScanResult(
      {required this.scanned,
      required this.imported,
      required this.reviewed,
      required this.duplicates});
  final int scanned, imported, reviewed, duplicates;
}

class SmsScanner {
  SmsScanner(this._database, this._source, this._parser);
  final AppDatabase _database;
  final SmsSource _source;
  final TransactionParser _parser;

  Future<bool> queueMessage(DeviceSms sms) async {
    if (!_parser.isTransactional(sms.body)) return false;
    final hash = sha256
        .convert(utf8.encode(
            '${sms.id}|${sms.sender}|${sms.date.millisecondsSinceEpoch}|${sms.body}'))
        .toString();
    if (await _database.isIgnored(hash) || await _database.isProcessed(hash)) {
      return false;
    }
    return _database.addReview(
        hash: hash,
        sender: sms.sender,
        body: sms.body,
        preview: sms.body.length <= 160
            ? sms.body
            : '${sms.body.substring(0, 160)}…',
        receivedAt: sms.date);
  }

  Future<ScanResult> scan() async {
    final messages = await _source.inbox();
    var reviewed = 0;
    for (final sms in messages) {
      if (await queueMessage(sms)) reviewed++;
    }
    return ScanResult(
        scanned: messages.length,
        imported: 0,
        reviewed: reviewed,
        duplicates: 0);
  }
}
