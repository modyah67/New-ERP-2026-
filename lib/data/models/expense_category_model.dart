import 'package:equatable/equatable.dart';

class ExpenseCategoryModel extends Equatable {
  final String id;
  final String name;
  final String color;
  final bool isActive;
  final String currency;

  const ExpenseCategoryModel({
    required this.id,
    required this.name,
    required this.color,
    this.isActive = true,
    this.currency = 'EGP',
  });

  factory ExpenseCategoryModel.fromMap(Map<String, dynamic> map) {
    return ExpenseCategoryModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      color: map['color']?.toString() ?? '#10B981',
      isActive: map['is_active'] == true,
      currency: map['currency']?.toString() ?? 'EGP',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'is_active': isActive,
        'currency': currency,
      };

  ExpenseCategoryModel copyWith({
    String? id,
    String? name,
    String? color,
    bool? isActive,
    String? currency,
  }) {
    return ExpenseCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
      currency: currency ?? this.currency,
    );
  }

  @override
  List<Object?> get props => [id, name, color, isActive, currency];
}
