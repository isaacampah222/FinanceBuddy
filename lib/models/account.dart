class Account {
  const Account(
      {required this.id,
      required this.name,
      required this.kind,
      required this.balance,
      required this.currency});

  final int id;
  final String name;
  final String kind;
  final double balance;
  final String currency;

  factory Account.fromMap(Map<String, Object?> map) => Account(
        id: map['id']! as int,
        name: map['name']! as String,
        kind: map['kind']! as String,
        balance: (map['balance']! as num).toDouble(),
        currency: map['currency']! as String,
      );
}
