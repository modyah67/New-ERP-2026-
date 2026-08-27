// lib/data/models/governorate_model.dart

class GovernorateModel {
  final int? id;
  final String name;
  final String? code;

  GovernorateModel({this.id, required this.name, this.code});

  factory GovernorateModel.fromMap(Map<String, dynamic> map) {
    return GovernorateModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      code: map['code'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {if (id != null) 'id': id, 'name': name, 'code': code};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GovernorateModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}