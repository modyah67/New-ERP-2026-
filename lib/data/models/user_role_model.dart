class UserRoleModel {
  final int? id;
  final int userId;
  final String role;
  final bool canEditInvoicePrices;
  final bool canEditAfterSave;
  final bool canEditQuantity;
  final bool canEditDiscounts;
  final int editTimeLimitHours;
  final DateTime? createdAt;

  UserRoleModel({
    this.id,
    required this.userId,
    required this.role,
    this.canEditInvoicePrices = false,
    this.canEditAfterSave = false,
    this.canEditQuantity = true,
    this.canEditDiscounts = false,
    this.editTimeLimitHours = 24,
    this.createdAt,
  });

  factory UserRoleModel.fromMap(Map<String, dynamic> map) {
    return UserRoleModel(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      role: map['role'] as String,
      canEditInvoicePrices: map['can_edit_invoice_prices'] as bool? ?? false,
      canEditAfterSave: map['can_edit_after_save'] as bool? ?? false,
      canEditQuantity: map['can_edit_quantity'] as bool? ?? true,
      canEditDiscounts: map['can_edit_discounts'] as bool? ?? false,
      editTimeLimitHours: map['edit_time_limit_hours'] as int? ?? 24,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'role': role,
      'can_edit_invoice_prices': canEditInvoicePrices,
      'can_edit_after_save': canEditAfterSave,
      'can_edit_quantity': canEditQuantity,
      'can_edit_discounts': canEditDiscounts,
      'edit_time_limit_hours': editTimeLimitHours,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UserRoleModel copyWith({
    int? id,
    int? userId,
    String? role,
    bool? canEditInvoicePrices,
    bool? canEditAfterSave,
    bool? canEditQuantity,
    bool? canEditDiscounts,
    int? editTimeLimitHours,
    DateTime? createdAt,
  }) {
    return UserRoleModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      canEditInvoicePrices: canEditInvoicePrices ?? this.canEditInvoicePrices,
      canEditAfterSave: canEditAfterSave ?? this.canEditAfterSave,
      canEditQuantity: canEditQuantity ?? this.canEditQuantity,
      canEditDiscounts: canEditDiscounts ?? this.canEditDiscounts,
      editTimeLimitHours: editTimeLimitHours ?? this.editTimeLimitHours,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRoleModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
