enum FiscalYearStatus {
  draft,
  active,
  closing,
  closed,
  archived,
}

extension FiscalYearStatusExtension on FiscalYearStatus {
  String get value {
    switch (this) {
      case FiscalYearStatus.draft:
        return 'DRAFT';
      case FiscalYearStatus.active:
        return 'ACTIVE';
      case FiscalYearStatus.closing:
        return 'CLOSING';
      case FiscalYearStatus.closed:
        return 'CLOSED';
      case FiscalYearStatus.archived:
        return 'ARCHIVED';
    }
  }

  String get displayNameAr {
    switch (this) {
      case FiscalYearStatus.draft:
        return 'مسودة';
      case FiscalYearStatus.active:
        return 'نشطة';
      case FiscalYearStatus.closing:
        return 'جاري الإغلاق';
      case FiscalYearStatus.closed:
        return 'مغلقة';
      case FiscalYearStatus.archived:
        return 'مؤرشفة';
    }
  }

  static FiscalYearStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'DRAFT':
        return FiscalYearStatus.draft;
      case 'ACTIVE':
        return FiscalYearStatus.active;
      case 'OPEN':
        return FiscalYearStatus.active;
      case 'CLOSING':
        return FiscalYearStatus.closing;
      case 'CLOSED':
        return FiscalYearStatus.closed;
      case 'ARCHIVED':
        return FiscalYearStatus.archived;
      case 'REOPENED':
        return FiscalYearStatus.active;
      default:
        return FiscalYearStatus.active;
    }
  }

  bool get canTransitionToClosing =>
      this == FiscalYearStatus.active || this == FiscalYearStatus.closing;
  bool get canTransitionToClosed => this == FiscalYearStatus.closing;
  bool get canTransitionToActive => this == FiscalYearStatus.draft ||
      this == FiscalYearStatus.closing ||
      this == FiscalYearStatus.closed;
  bool get canTransitionToArchived => this == FiscalYearStatus.closed;
  bool get canCreateDocuments => this == FiscalYearStatus.active;
  bool get isClosedOrArchived => this == FiscalYearStatus.closed ||
      this == FiscalYearStatus.archived;
}
