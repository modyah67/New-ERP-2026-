class InvoiceEditModel {
  final int? id;
  final int invoiceId;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String? editedBy;
  final String? editedByName;
  final DateTime? editedAt;
  final String? reason;

  InvoiceEditModel({
    this.id,
    required this.invoiceId,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    this.editedBy,
    this.editedByName,
    this.editedAt,
    this.reason,
  });

  factory InvoiceEditModel.fromMap(Map<String, dynamic> map) {
    return InvoiceEditModel(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] as int,
      fieldName: map['field_name'] as String,
      oldValue: map['old_value'] as String?,
      newValue: map['new_value'] as String?,
      editedBy: map['edited_by'] as String?,
      editedByName: map['edited_by_name'] as String?,
      editedAt: map['edited_at'] != null ? DateTime.parse(map['edited_at'] as String) : null,
      reason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'edited_by': editedBy,
      'edited_at': editedAt?.toIso8601String(),
      'reason': reason,
    };
  }

  InvoiceEditModel copyWith({
    int? id,
    int? invoiceId,
    String? fieldName,
    String? oldValue,
    String? newValue,
    String? editedBy,
    String? editedByName,
    DateTime? editedAt,
    String? reason,
  }) {
    return InvoiceEditModel(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      fieldName: fieldName ?? this.fieldName,
      oldValue: oldValue ?? this.oldValue,
      newValue: newValue ?? this.newValue,
      editedBy: editedBy ?? this.editedBy,
      editedByName: editedByName ?? this.editedByName,
      editedAt: editedAt ?? this.editedAt,
      reason: reason ?? this.reason,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceEditModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
