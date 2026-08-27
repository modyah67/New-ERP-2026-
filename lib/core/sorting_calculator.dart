class SortingCalculator {
  final double grossWeight;
  final double netWeight;
  final Map<String, double> grades;

  SortingCalculator({
    this.grossWeight = 0,
    this.netWeight = 0,
    Map<String, double>? grades,
  }) : grades = grades ?? {};

  double get wasteWeight => grossWeight - netWeight;

  double get wastePercentage =>
      grossWeight > 0 ? (wasteWeight / grossWeight) * 100 : 0;

  double get classifiedWeight =>
      grades.values.fold(0.0, (sum, w) => sum + w);

  double get remainingWeight => netWeight - classifiedWeight;

  bool get isValid => (classifiedWeight - netWeight).abs() <= 0.01;

  ValidationState get validationState {
    if (classifiedWeight > netWeight + 0.01) return ValidationState.exceeds;
    if (remainingWeight > 0.01) return ValidationState.unclassified;
    return ValidationState.balanced;
  }

  String get validationMessage {
    switch (validationState) {
      case ValidationState.balanced:
        return 'مجموع الدرجات يساوي الوزن الصافي';
      case ValidationState.unclassified:
        return 'يوجد وزن صافٍ غير مصنف ⚠';
      case ValidationState.exceeds:
        return 'الوزن المصنف يتجاوز الوزن الصافي ✗';
    }
  }
}

enum ValidationState {
  balanced,
  unclassified,
  exceeds;

  bool get validate => this != ValidationState.exceeds;
}
