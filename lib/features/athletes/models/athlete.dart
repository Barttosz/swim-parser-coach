import 'package:uuid/uuid.dart';

/// Model zawodnika
class Athlete {
  final String id;
  final String name;
  final bool isInGroup;

  Athlete({
    String? id,
    required this.name,
    this.isInGroup = true,
  }) : id = id ?? const Uuid().v4();

  Athlete copyWith({String? name, bool? isInGroup}) {
    return Athlete(id: id, name: name ?? this.name, isInGroup: isInGroup ?? this.isInGroup);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'isInGroup': isInGroup ? 1 : 0,
  };

  factory Athlete.fromMap(Map<String, dynamic> map) => Athlete(
    id: map['id'] as String,
    name: map['name'] as String,
    isInGroup: (map['isInGroup'] as int? ?? 1) == 1,
  );

  @override
  String toString() => 'Athlete($name, group=$isInGroup)';
}
