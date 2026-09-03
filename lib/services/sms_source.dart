import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

class DeviceSms {
  const DeviceSms(
      {required this.id,
      required this.sender,
      required this.body,
      required this.date});
  final String id;
  final String sender;
  final String body;
  final DateTime date;
}

abstract class SmsSource {
  Future<List<DeviceSms>> inbox();
}

class AndroidSmsSource implements SmsSource {
  final SmsQuery _query = SmsQuery();

  @override
  Future<List<DeviceSms>> inbox() async {
    final messages =
        await _query.querySms(kinds: [SmsQueryKind.inbox], count: 1000);
    return messages
        .where((sms) => sms.body != null)
        .map((sms) => DeviceSms(
              id: sms.id?.toString() ?? '',
              sender: sms.address ?? 'Unknown',
              body: sms.body!,
              date: sms.date ?? DateTime.now(),
            ))
        .toList();
  }
}
