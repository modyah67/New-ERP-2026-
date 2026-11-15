class StationModel {
  // ── Scalable 5-Digit Category Range Constants ──
  static const int minCode = 80000;
  static const int maxCode = 84999;
  static const int capacity = 5000;
  static const String codeHint = 'مثال: 80000 (نطاق 80000 - 84999)';

  static String? validateStationCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return 'كود المحطة مطلوب';
    }
    final cleanCode = code.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(cleanCode);
    if (num == null) {
      return 'يجب أن يحتوي الكود على أرقام فقط';
    }
    if (num < minCode || num > maxCode) {
      return 'كود المحطة يجب أن يكون بين $minCode و $maxCode (السعة: $capacity محطة)';
    }
    return null;
  }

  final String? id;
  final String code;
  final String name;
  final String? description;
  final bool isActive;
  final String type;
  final String createdAt;

  const StationModel({
    this.id,
    required this.code,
    required this.name,
    this.description,
    this.isActive = true,
    this.type = 'sub',
    required this.createdAt,
  });

  bool get isMain => type == 'main';
  bool get isSub => type == 'sub';

  factory StationModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();

    return StationModel(
      id: map['id']?.toString(),
      code: str(map['code']) ?? '',
      name: str(map['name']) ?? '',
      description: str(map['description']),
      isActive: map['is_active'] == true || map['is_active'] == 1,
      type: str(map['type']) ?? 'sub',
      createdAt: str(map['created_at']) ?? '',
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'code': code,
      'name': name,
      'description': description,
      'is_active': isActive,
      'type': type,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'code': code,
      'name': name,
      'description': description,
      'is_active': isActive,
      'type': type,
    };
  }

  StationModel copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    bool? isActive,
    String? type,
    String? createdAt,
  }) {
    return StationModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StationModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
