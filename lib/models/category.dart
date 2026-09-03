class Category {
  const Category({required this.id, required this.name});
  final int id;
  final String name;
  factory Category.fromMap(Map<String, Object?> map) =>
      Category(id: map['id']! as int, name: map['name']! as String);
}
