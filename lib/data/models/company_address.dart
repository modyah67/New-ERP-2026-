class CompanyAddress {
  final int? id;
  final int? companyId;
  final String label;
  final String fullAddress;
  final String country;

  const CompanyAddress({
    this.id,
    this.companyId,
    required this.label,
    required this.fullAddress,
    required this.country,
  });

  factory CompanyAddress.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

    return CompanyAddress(
      id: intVal(map['id']),
      companyId: intVal(map['customer_id']) ?? intVal(map['company_id']),
      label: str(map['label']) ?? '',
      fullAddress: str(map['address_line_1']) ?? str(map['full_address']) ?? '',
      country: str(map['country']) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (companyId != null) 'customer_id': companyId,
      'label': label,
      'address_line_1': fullAddress,
      'country': country,
    };
  }

  CompanyAddress copyWith({
    int? id,
    int? companyId,
    String? label,
    String? fullAddress,
    String? country,
  }) {
    return CompanyAddress(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      label: label ?? this.label,
      fullAddress: fullAddress ?? this.fullAddress,
      country: country ?? this.country,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyAddress && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
