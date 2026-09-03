class ReviewItem {
  const ReviewItem(
      {required this.id,
      required this.smsHash,
      required this.sender,
      required this.body,
      required this.preview,
      required this.receivedAt});
  final int id;
  final String smsHash;
  final String sender;
  final String body;
  final String preview;
  final DateTime receivedAt;
  factory ReviewItem.fromMap(Map<String, Object?> map) => ReviewItem(
        id: map['id']! as int,
        smsHash: map['sms_hash']! as String,
        sender: (map['sender'] as String?) ?? 'Unknown',
        body: (map['body_full'] as String?) ?? map['body_preview']! as String,
        preview: map['body_preview']! as String,
        receivedAt:
            DateTime.fromMillisecondsSinceEpoch(map['received_at']! as int),
      );
}
