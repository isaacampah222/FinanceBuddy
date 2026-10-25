import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'sms_source.dart';

class NotificationSource {
  static const _channel = MethodChannel('finance_buddy/notifications');
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> enabled() async =>
      supported && (await _channel.invokeMethod<bool>('enabled') ?? false);

  Future<void> setEnabled(bool enabled) async {
    if (supported) await _channel.invokeMethod<void>('setEnabled', enabled);
  }

  Future<List<DeviceSms>> pending() async {
    if (!supported) return [];
    final rows = await _channel.invokeListMethod<dynamic>('pending') ?? [];
    return rows
        .map((row) => DeviceSms(
            id: row['id'] as String,
            sender: row['sender'] as String,
            body: row['body'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int)))
        .toList();
  }

  Future<void> acknowledge(String id) async {
    if (supported) await _channel.invokeMethod<void>('acknowledge', id);
  }
}
