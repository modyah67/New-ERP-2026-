import 'dart:convert';
import 'package:flutter/material.dart';

/// Type of Cost Center: Product Variety line vs. Operational Support line
enum CostCenterType {
  variety,
  operational,
}

/// Domain Model for Cost Centers in Fruity Farms ERP
class CostCenter {
  final String id;
  final String nameAr;
  final String nameEn;
  final CostCenterType type;
  final Color color;
  final IconData icon;
  final String? code;
  final dynamic productId;
  final dynamic dbId;

  // ── Agricultural Accounting & Seasonal Extensions ──
  final String? cropName;
  final String? cropCode;
  final String? season;
  final String seasonStatus; // 'active', 'closed', or 'permanently_closed'
  final String status; // 'active', 'closed', or 'permanently_closed'
  final double openingBalance;
  final double currentBalance;
  final dynamic branchId;
  final dynamic rolloverCostCenterId;
  final bool isActive;

  // ── Two-Stage Seasonal Closure Tracking ──
  final int closureCount;   // Max 2 per agricultural year
  final int seasonNumber;   // 1 = Period 1, 2 = Period 2

  const CostCenter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.type,
    required this.color,
    required this.icon,
    this.code,
    this.productId,
    this.dbId,
    this.cropName,
    this.cropCode,
    this.season = '2026-2027',
    this.seasonStatus = 'active',
    this.status = 'active',
    this.openingBalance = 0.0,
    this.currentBalance = 0.0,
    this.branchId,
    this.rolloverCostCenterId,
    this.isActive = true,
    this.closureCount = 0,
    this.seasonNumber = 1,
  });

  String get typeLabelAr =>
      type == CostCenterType.variety ? 'خط إنتاجي' : 'مركز تشغيلي';

  String get typeLabelEn =>
      type == CostCenterType.variety ? 'Variety Line' : 'Operational Line';

  bool get isClosed =>
      seasonStatus == 'closed' || seasonStatus == 'permanently_closed' ||
      status == 'closed' || status == 'permanently_closed' || !isActive;
  bool get isActiveSeason => !isClosed;

  /// Whether this cost center has been permanently closed (both seasons exhausted)
  bool get isPermanentlyClosed =>
      seasonStatus == 'permanently_closed' || status == 'permanently_closed' ||
      closureCount >= 2;

  /// Whether this cost center can still be closed/rolled over
  bool get canClose => !isClosed && closureCount < 2;

  /// Arabic label indicating the current closure stage
  String get closureStageLabel {
    if (isPermanentlyClosed) return 'السنة مقفلة نهائياً';
    if (isClosed) return 'الموسم مقفل';
    if (seasonNumber == 2) return 'الموسم الثاني (الأخير)';
    if (seasonNumber == 1) return 'الموسم الأول';
    return 'نشط';
  }

  /// Whether this is the final season (closing will permanently close the year)
  bool get isFinalSeason => seasonNumber == 2 || closureCount >= 1;

  String get displayTitle {
    if (type != CostCenterType.variety || season == null || season!.isEmpty) {
      return nameAr;
    }
    if (nameAr.contains(season!)) {
      return nameAr;
    }
    final cleanCrop = canonicalCropName(nameAr);
    return '$cleanCrop (موسم $season)';
  }

  /// Strips purchasing method variants and seasonal suffixes to unify
  /// any fruit purchase into its canonical single crop cost center.
  static String canonicalCropName(String rawName) {
    var clean = rawName.trim();
    if (clean.isEmpty) return 'محصول';

    // 0. Remove seasonal tags e.g. " (موسم 2026-2027)", " [موسم 2027]", " (Season 2026-2027)"
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[\{]?(موسم|season)\s*[^)\]\}]*[\)\]\}]?', caseSensitive: false),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[\{]?\d{4}\s*[-/–]\s*\d{4}[\)\]\}]?'),
      '',
    );

    // 1. Remove suffixes with dashes/slashes like " - وزن", " - كرتون", " / بالوزن"
    clean = clean.replaceAll(
      RegExp(r'\s*[-–/\\:]\s*(وزن|كرتون|كرتونة|كراتين|طرد|طرود|صندوق|صناديق|شوال|شوالات|بالوزن|بالكرتون|بالطرد|قطاعي|جملة|خام).*$',
          caseSensitive: false),
      '',
    );

    // 2. Remove suffixes enclosed in brackets like " (وزن)", " [كرتون]"
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[\{](وزن|كرتون|كرتونة|كراتين|طرد|طرود|صندوق|صناديق|شوال|شوالات|بالوزن|بالكرتون|بالطرد|قطاعي|جملة|خام)[\)\]\}].*$',
          caseSensitive: false),
      '',
    );

    // 2b. Remove trailing standalone trading keywords like " قطاعي", " جملة", " فريش"
    clean = clean.replaceAll(
      RegExp(r'\s+(قطاعي|جملة|فريش|خام|بالوزن|بالكرتون)\s*$', caseSensitive: false),
      '',
    );

    // 3. Remove English purchasing mode tokens
    clean = clean.replaceAll(
      RegExp(r'\s*[-–/\\:]\s*(weight|carton|cartons|box|boxes|crate|crates|pkg|package|bulk).*$',
          caseSensitive: false),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r'\s*[\(\[\{](weight|carton|cartons|box|boxes|crate|crates|pkg|package|bulk)[\)\]\}].*$',
          caseSensitive: false),
      '',
    );

    // 4. Strip redundant leading line keywords
    clean = clean.replaceFirst(
      RegExp(r'^(خط\s+محصول|خط\s+إنتاج|خط)\s+', caseSensitive: false),
      '',
    );

    clean = clean.trim();
    return clean.isEmpty ? rawName.trim() : clean;
  }

  /// Resolves the canonical slug identifier for a crop (e.g. "مانجو - وزن" -> "mango")
  static String resolveCropSlug(String cropName) => CostCenterHelper.resolveCropSlug(cropName);

  /// Creates a dynamic Cost Center from a database record (`cost_centers` table)
  factory CostCenter.fromMap(Map<String, dynamic> map) {
    final nameAr = map['name_ar']?.toString() ??
        map['name']?.toString() ??
        'مركز تكلفة';
    final nameEn = map['name_en']?.toString() ??
        CostCenterHelper.resolveEnglishName(nameAr);
    final typeStr = map['cost_center_type']?.toString() ?? 'variety';
    final type = typeStr == 'operational'
        ? CostCenterType.operational
        : CostCenterType.variety;
    final colorStr = map['color']?.toString();
    final iconStr = map['icon']?.toString();

    final rawCode = map['code']?.toString() ?? '';
    final rawId = map['id']?.toString() ?? '';
    final code = rawCode.isNotEmpty ? rawCode : rawId;

    // Only map exact standard predefined codes to their canonical IDs, preserving distinct IDs for all other centers
    final canonicalId = (code == 'CC-PACKING' || code == 'packing_station')
        ? 'packing_station'
        : (code == 'CC-LOGISTICS' || code == 'freight_logistics')
            ? 'freight_logistics'
            : (code == 'CC-CUSTOMS' || code == 'customs_clearance')
                ? 'customs_clearance'
                : (code == 'CC-ADMIN' || code == 'general_admin')
                    ? 'general_admin'
                    : code;

    final rawCropName = map['crop_name']?.toString();
    final effectiveCropName = (rawCropName != null && rawCropName.isNotEmpty)
        ? rawCropName
        : (type == CostCenterType.variety ? canonicalCropName(nameAr) : null);

    final seasonStatus = map['season_status']?.toString() ?? 'active';
    final status = map['status']?.toString() ?? seasonStatus;

    return CostCenter(
      id: canonicalId,
      nameAr: nameAr,
      nameEn: nameEn,
      type: type,
      color: CostCenterHelper.resolveColor(colorStr, code),
      icon: CostCenterHelper.resolveIcon(iconStr, nameAr),
      code: code,
      productId: map['product_id'],
      dbId: map['id'],
      cropName: effectiveCropName,
      cropCode: map['crop_code']?.toString() ??
          (effectiveCropName != null ? CostCenterHelper.resolveCropSlug(effectiveCropName) : null),
      season: map['season']?.toString() ?? '2026-2027',
      seasonStatus: seasonStatus,
      status: status,
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
      branchId: map['branch_id'],
      rolloverCostCenterId: map['rollover_cost_center_id'],
      isActive: map['is_active'] != false && map['is_active'] != 0,
      closureCount: (map['closure_count'] as num?)?.toInt() ?? 0,
      seasonNumber: (map['season_number'] as num?)?.toInt() ?? 1,
    );
  }

  /// Creates a dynamic Cost Center directly from an active product inventory record (`fruit_types`)
  factory CostCenter.fromProduct(Map<String, dynamic> product) {
    final rawName = product['name']?.toString() ?? 'محصول';
    final canonName = canonicalCropName(rawName);
    final slug = CostCenterHelper.resolveCropSlug(canonName);
    final boundCcId = product['cost_center_id']?.toString();
    final id = (boundCcId != null && boundCcId.isNotEmpty) ? boundCcId : 'CC-$slug';
    final nameEn = CostCenterHelper.resolveEnglishName(canonName);
    final colorStr = product['color']?.toString();
    final iconStr = product['icon']?.toString();
    final nameAr = (boundCcId != null && boundCcId.contains('2026-2027'))
        ? '$canonName (موسم 2026-2027)'
        : canonName;

    return CostCenter(
      id: id,
      nameAr: nameAr,
      nameEn: nameEn,
      type: CostCenterType.variety,
      color: CostCenterHelper.resolveColor(colorStr, id),
      icon: CostCenterHelper.resolveIcon(iconStr, canonName),
      code: id,
      productId: product['id'],
      dbId: product['id'],
      cropName: canonName,
      cropCode: slug,
      season: '2026-2027',
      seasonStatus: 'active',
      openingBalance: 0.0,
      currentBalance: 0.0,
      isActive: true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code ?? id,
      'name': nameAr,
      'name_ar': nameAr,
      'name_en': nameEn,
      'cost_center_type': type == CostCenterType.variety ? 'variety' : 'operational',
      if (productId != null) 'product_id': productId,
      if (cropName != null) 'crop_name': cropName,
      if (cropCode != null) 'crop_code': cropCode,
      if (season != null) 'season': season,
      'season_status': seasonStatus,
      'opening_balance': openingBalance,
      'current_balance': currentBalance,
      if (branchId != null) 'branch_id': branchId,
      if (rolloverCostCenterId != null) 'rollover_cost_center_id': rolloverCostCenterId,
      'is_active': isActive,
      'closure_count': closureCount,
      'season_number': seasonNumber,
    };
  }

  CostCenter copyWith({
    String? id,
    String? nameAr,
    String? nameEn,
    CostCenterType? type,
    Color? color,
    IconData? icon,
    String? code,
    dynamic productId,
    dynamic dbId,
    String? cropName,
    String? cropCode,
    String? season,
    String? seasonStatus,
    double? openingBalance,
    double? currentBalance,
    dynamic branchId,
    dynamic rolloverCostCenterId,
    bool? isActive,
    int? closureCount,
    int? seasonNumber,
  }) {
    return CostCenter(
      id: id ?? this.id,
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      type: type ?? this.type,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      code: code ?? this.code,
      productId: productId ?? this.productId,
      dbId: dbId ?? this.dbId,
      cropName: cropName ?? this.cropName,
      cropCode: cropCode ?? this.cropCode,
      season: season ?? this.season,
      seasonStatus: seasonStatus ?? this.seasonStatus,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      branchId: branchId ?? this.branchId,
      rolloverCostCenterId: rolloverCostCenterId ?? this.rolloverCostCenterId,
      isActive: isActive ?? this.isActive,
      closureCount: closureCount ?? this.closureCount,
      seasonNumber: seasonNumber ?? this.seasonNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CostCenter &&
          runtimeType == other.runtimeType &&
          id.toLowerCase() == other.id.toLowerCase();

  @override
  int get hashCode => id.toLowerCase().hashCode;
}

/// Helper and Resolution Engine for Cost Centers
class CostCenterHelper {
  // ── Predefined Standard Operational & Logistics Cost Centers ──
  static const CostCenter packingStation = CostCenter(
    id: 'packing_station',
    nameAr: 'محطة التعبئة والتجهيز',
    nameEn: 'Packing & Processing Station',
    type: CostCenterType.operational,
    color: Color(0xFF06B6D4), // Cyan
    icon: Icons.inventory_2_rounded,
    code: 'CC-PACKING',
  );

  static const CostCenter freightLogistics = CostCenter(
    id: 'freight_logistics',
    nameAr: 'الشحن والنقل اللوجستي',
    nameEn: 'Freight & Logistics',
    type: CostCenterType.operational,
    color: Color(0xFF3B82F6), // Blue
    icon: Icons.local_shipping_rounded,
    code: 'CC-LOGISTICS',
  );

  static const CostCenter customsClearance = CostCenter(
    id: 'customs_clearance',
    nameAr: 'التخليص والخدمات الجمركية',
    nameEn: 'Customs Clearance',
    type: CostCenterType.operational,
    color: Color(0xFF6366F1), // Indigo
    icon: Icons.assignment_turned_in_rounded,
    code: 'CC-CUSTOMS',
  );

  static const CostCenter logisticsTransport = CostCenter(
    id: 'CC-CAT-6',
    nameAr: 'لوجستيك ونقل',
    nameEn: 'Logistics & Transport',
    type: CostCenterType.operational,
    color: Color(0xFF14B8A6), // Teal
    icon: Icons.local_shipping_outlined,
    code: 'CC-CAT-6',
  );

  static const CostCenter generalAdmin = CostCenter(
    id: 'general_admin',
    nameAr: 'المصروفات العمومية والإدارية',
    nameEn: 'General & Administrative',
    type: CostCenterType.operational,
    color: Color(0xFF94A3B8), // Slate
    icon: Icons.business_rounded,
    code: 'CC-ADMIN',
  );

  static const List<CostCenter> operationalCenters = [
    packingStation,
    freightLogistics,
    customsClearance,
    logisticsTransport,
    generalAdmin,
  ];

  // Static compatibility getters for standard varieties & tests
  static const CostCenter strawberryLine = CostCenter(
    id: 'strawberry_line',
    nameAr: 'خط الفراولة',
    nameEn: 'Strawberry Line',
    type: CostCenterType.variety,
    color: Color(0xFFF43F5E),
    icon: Icons.local_florist_rounded,
    code: 'CC-STRAWBERRY',
  );

  static const CostCenter mangoLine = CostCenter(
    id: 'mango_line',
    nameAr: 'خط المانجو',
    nameEn: 'Mango Line',
    type: CostCenterType.variety,
    color: Color(0xFFF59E0B),
    icon: Icons.eco_rounded,
    code: 'CC-MANGO',
  );

  static const CostCenter grapesLine = CostCenter(
    id: 'grapes_line',
    nameAr: 'خط العنب',
    nameEn: 'Grapes Line',
    type: CostCenterType.variety,
    color: Color(0xFF8B5CF6),
    icon: Icons.grain_rounded,
    code: 'CC-GRAPES',
  );

  static const CostCenter citrusLine = CostCenter(
    id: 'citrus_line',
    nameAr: 'خط الموالح والحمضيات',
    nameEn: 'Citrus Line',
    type: CostCenterType.variety,
    color: Color(0xFF10B981),
    icon: Icons.brightness_5_rounded,
    code: 'CC-CITRUS',
  );

  static const CostCenter bananaLine = CostCenter(
    id: 'banana_line',
    nameAr: 'موز',
    nameEn: 'Banana Line',
    type: CostCenterType.variety,
    color: Color(0xFFEAB308),
    icon: Icons.eco_rounded,
    code: 'CC-BANANA',
  );

  static const CostCenter sharedProducts = CostCenter(
    id: 'ALL',
    nameAr: 'توزيع بالتساوي على كل المنتجات',
    nameEn: 'Equal Distribution Across Products',
    type: CostCenterType.variety,
    color: Color(0xFF10B981), // Emerald
    icon: Icons.pie_chart_rounded,
    code: 'CC-ALL',
  );

  static List<CostCenter> get allCenters => [
        ...operationalCenters,
        sharedProducts,
      ];

  static const List<Color> _palette = [
    Color(0xFFF43F5E), // Rose
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
    Color(0xFFEC4899), // Pink
    Color(0xFFEAB308), // Yellow
    Color(0xFF14B8A6), // Teal
    Color(0xFF6366F1), // Indigo
  ];

  static const List<IconData> _varietyIcons = [
    Icons.eco_rounded,
    Icons.local_florist_rounded,
    Icons.grain_rounded,
    Icons.brightness_5_rounded,
    Icons.nature_rounded,
    Icons.park_rounded,
    Icons.yard_rounded,
    Icons.spa_rounded,
  ];

  /// Resolves an appropriate accent color for a Cost Center code / name
  static Color resolveColor(String? colorStr, String seed) {
    if (colorStr != null && colorStr.isNotEmpty) {
      try {
        final clean = colorStr.replaceAll('#', '').trim();
        if (clean.length == 6) {
          return Color(int.parse('FF$clean', radix: 16));
        } else if (clean.length == 8) {
          return Color(int.parse(clean, radix: 16));
        }
      } catch (_) {}
    }

    final hash = seed.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _palette[hash % _palette.length];
  }

  /// Resolves an appropriate Icon for a Cost Center name
  static IconData resolveIcon(String? iconStr, String arabicName) {
    final lower = arabicName.toLowerCase();
    if (lower.contains('فراول') || lower.contains('strawberry')) {
      return Icons.local_florist_rounded;
    }
    if (lower.contains('مانج') || lower.contains('mango')) {
      return Icons.eco_rounded;
    }
    if (lower.contains('عنب') || lower.contains('grape')) {
      return Icons.grain_rounded;
    }
    if (lower.contains('برتقال') ||
        lower.contains('orange') ||
        lower.contains('ليمون') ||
        lower.contains('موالح') ||
        lower.contains('حمضيات') ||
        lower.contains('citrus')) {
      return Icons.brightness_5_rounded;
    }
    if (lower.contains('رمان') || lower.contains('pomegranate')) {
      return Icons.spa_rounded;
    }
    if (lower.contains('تعبئة') || lower.contains('packing')) {
      return Icons.inventory_2_rounded;
    }
    if (lower.contains('شحن') || lower.contains('freight') || lower.contains('shipping')) {
      return Icons.local_shipping_rounded;
    }
    if (lower.contains('تخليص') || lower.contains('customs')) {
      return Icons.assignment_turned_in_rounded;
    }
    if (lower.contains('توزيع') || lower.contains('مشترك') || lower.contains('بالتساوي')) {
      return Icons.pie_chart_rounded;
    }

    final hash = arabicName.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _varietyIcons[hash % _varietyIcons.length];
  }

  /// Helper to guess English line name from Arabic product name
  static String resolveEnglishName(String arabicName) {
    final lower = arabicName.toLowerCase();
    if (lower.contains('فراول') || lower.contains('strawberry')) {
      return 'Strawberry Line';
    }
    if (lower.contains('مانج') || lower.contains('mango')) {
      return 'Mango Line';
    }
    if (lower.contains('عنب') || lower.contains('grape')) {
      return 'Grapes Line';
    }
    if (lower.contains('برتقال') || lower.contains('orange')) {
      return 'Orange Line';
    }
    if (lower.contains('ليمون') || lower.contains('lemon')) {
      return 'Lemon Line';
    }
    if (lower.contains('يوسفي') || lower.contains('mandarin')) {
      return 'Mandarin Line';
    }
    if (lower.contains('رمان') || lower.contains('pomegranate')) {
      return 'Pomegranate Line';
    }
    if (lower.contains('خوخ') || lower.contains('peach')) {
      return 'Peach Line';
    }
    if (lower.contains('مشمش') || lower.contains('apricot')) {
      return 'Apricot Line';
    }
    if (lower.contains('بلح') ||
        lower.contains('تمر') ||
        lower.contains('dates')) {
      return 'Dates Line';
    }
    if (lower.contains('موز') || lower.contains('banana')) {
      return 'Banana Line';
    }
    if (lower.contains('تين') || lower.contains('fig')) {
      return 'Fig Line';
    }
    return '$arabicName Line';
  }

  /// Resolves the standardized uppercase slug for an agricultural crop name
  static String resolveCropSlug(String arabicCropName) {
    final lower = arabicCropName.toLowerCase();
    if (lower.contains('مانج') || lower.contains('مانق') || lower.contains('mango')) return 'MANGO';
    if (lower.contains('فراول') || lower.contains('strawberry')) return 'STRAWBERRY';
    if (lower.contains('عنب') || lower.contains('grape')) return 'GRAPES';
    if (lower.contains('برتقال') || lower.contains('orange')) return 'ORANGE';
    if (lower.contains('ليمون') || lower.contains('lemon')) return 'LEMON';
    if (lower.contains('يوسفي') || lower.contains('mandarin')) return 'MANDARIN';
    if (lower.contains('رمان') || lower.contains('pomegranate')) return 'POMEGRANATE';
    if (lower.contains('موز') || lower.contains('banana')) return 'BANANA';
    if (lower.contains('خوخ') || lower.contains('peach')) return 'PEACH';
    if (lower.contains('مشمش') || lower.contains('apricot')) return 'APRICOT';
    if (lower.contains('بلح') || lower.contains('تمر') || lower.contains('dates')) return 'DATES';
    if (lower.contains('تين') || lower.contains('fig')) return 'FIG';
    return 'CROP';
  }

  /// Normalizes Arabic text for flexible matching across variations (ة/ه, أ/إ/آ/ا, فرولة/فراولة, etc.)
  static String normalizeArabic(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('فرول', 'فراول')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'^خط\s+'), '');
  }

  /// Lookup CostCenter by id, name, code, or product from active centers list
  static CostCenter fromId(String? id, [List<CostCenter>? activeCenters]) {
    if (id == null || id.isEmpty) return generalAdmin;

    final cleanId = id.trim();
    final lowerId = cleanId.toLowerCase();

    // 1. Equal distribution across all products
    if (lowerId == 'all' ||
        cleanId == 'ALL' ||
        cleanId == 'CC-ALL' ||
        cleanId == 'توزيع بالتساوي على كل المنتجات') {
      return sharedProducts;
    }

    final canonCropName = CostCenter.canonicalCropName(cleanId);
    final cropSlug = resolveCropSlug(canonCropName);

    // 2. Search active product-linked cost centers first
    if (activeCenters != null && activeCenters.isNotEmpty) {
      // 2a. Direct exact identifier match
      for (final c in activeCenters) {
        if (c.id == cleanId ||
            c.code == cleanId ||
            (c.dbId != null && c.dbId.toString() == cleanId)) {
          return c;
        }
      }

      // Check numeric fruit_type_id or CC-<id> (e.g. CC-1, 1) mapping to active crop centers
      final numPart = cleanId.startsWith('CC-') ? cleanId.substring(3) : cleanId;
      if (int.tryParse(numPart) != null) {
        for (final c in activeCenters) {
          if (c.productId != null && c.productId.toString() == numPart) {
            return c;
          }
        }
        if (numPart == '1' || numPart == '2') {
          for (final c in activeCenters) {
            if (c.cropCode == 'MANGO' || normalizeArabic(c.nameAr).contains('مانج')) {
              return c;
            }
          }
        }
      }

      // 2b. Prioritize active seasonal centers matching crop slug or canonical crop name (excluding lines)
      for (final c in activeCenters) {
        if (!c.isActiveSeason) continue;
        if (c.nameAr.startsWith('خط ')) continue;
        if (cropSlug != 'CROP' && c.cropCode == cropSlug) {
          return c;
        }
        if (c.cropName != null && c.cropName == canonCropName) {
          return c;
        }
      }

      // 2c. Match other fields or inactive centers matching crop slug / name
      for (final c in activeCenters) {
        if (c.nameAr == cleanId ||
            c.nameEn.toLowerCase() == lowerId ||
            (c.code != null && ('CC-${c.code}' == cleanId || c.code == 'CC-$cleanId')) ||
            (c.id.startsWith('CC-') && c.id.substring(3) == cleanId) ||
            cleanId == 'CC-${c.id}') {
          return c;
        }

        if (c.nameAr.startsWith('خط ')) continue;
        if (cropSlug != 'CROP' && c.cropCode == cropSlug) {
          return c;
        }
        if (c.cropName != null && c.cropName == canonCropName) {
          return c;
        }
      }

      // Normalized Arabic name match (prioritizing active seasons first, excluding lines)
      final normClean = normalizeArabic(canonCropName);
      for (final c in activeCenters) {
        if (!c.isActiveSeason) continue;
        if (c.nameAr.startsWith('خط ')) continue;
        final normC = normalizeArabic(c.cropName ?? c.nameAr);
        if (normC == normClean ||
            (normClean.length >= 3 && normC.contains(normClean)) ||
            (normC.length >= 3 && normClean.contains(normC))) {
          return c;
        }
      }
      for (final c in activeCenters) {
        if (c.nameAr.startsWith('خط ')) continue;
        final normC = normalizeArabic(c.cropName ?? c.nameAr);
        if (normC == normClean ||
            (normClean.length >= 3 && normC.contains(normClean)) ||
            (normC.length >= 3 && normClean.contains(normC))) {
          return c;
        }
      }
    }

    // 3. Operational centers
    for (final c in operationalCenters) {
      if (c.id == cleanId ||
          c.code == cleanId ||
          c.nameAr == cleanId ||
          c.nameEn.toLowerCase() == lowerId) {
        return c;
      }
    }
    if (cleanId == 'CC-CAT-3' || cleanId.contains('تعبئة') || cleanId.contains('تغليف')) {
      return packingStation;
    }
    if (cleanId == 'CC-CAT-4' || cleanId.contains('شحن')) {
      return freightLogistics;
    }
    if (cleanId == 'CC-CAT-5' || cleanId.contains('تخليص') || cleanId.contains('مخلص')) {
      return customsClearance;
    }
    if (cleanId == 'CC-CAT-6' || cleanId.contains('لوجستيك') || cleanId.contains('نقل')) {
      return logisticsTransport;
    }
    if (cleanId == 'CC-CAT-7' || cleanId.contains('عمومية') || cleanId.contains('إدارية')) {
      return generalAdmin;
    }

    // 4. Dynamic evaluation for CC- identifiers: NEVER produce generic line names like 'خط $sub'
    if (cleanId.startsWith('CC-')) {
      final sub = cleanId.substring(3);
      final canon = CostCenter.canonicalCropName(sub);
      final hasSeason = cleanId.contains('2026') || cleanId.contains('2027');
      final label = (canon.isNotEmpty && canon != 'محصول عام')
          ? (hasSeason ? '$canon (موسم 2026-2027)' : '$canon (موسم 2026-2027)')
          : cleanId;
      return CostCenter(
        id: cleanId,
        nameAr: label,
        nameEn: '$sub Center',
        type: CostCenterType.variety,
        color: resolveColor(null, cleanId),
        icon: resolveIcon(null, sub),
        code: cleanId,
        season: hasSeason ? '2026-2027' : '2026-2027',
        seasonStatus: 'active',
      );
    }

    // 5. Standard variety lines compatibility (exact legacy codes)
    if (cleanId == strawberryLine.id || cleanId == strawberryLine.code) {
      return strawberryLine;
    }
    if (cleanId == mangoLine.id || cleanId == mangoLine.code) {
      return mangoLine;
    }
    if (cleanId == grapesLine.id || cleanId == grapesLine.code) {
      return grapesLine;
    }
    if (cleanId == citrusLine.id || cleanId == citrusLine.code) {
      return citrusLine;
    }
    if (cleanId == bananaLine.id || cleanId == bananaLine.code || cleanId == 'CC-03' || cleanId == 'CC-3') {
      return bananaLine;
    }

    // 6. Generic agricultural crop fallback: resolve as seasonal variety center
    if (cropSlug != 'CROP') {
      final code = 'CC-$cropSlug-2026-2027';
      return CostCenter(
        id: code,
        nameAr: '$canonCropName (موسم 2026-2027)',
        nameEn: '${resolveEnglishName(canonCropName)} (2026-2027)',
        type: CostCenterType.variety,
        color: resolveColor(null, canonCropName),
        icon: resolveIcon(null, canonCropName),
        code: code,
        cropName: canonCropName,
        cropCode: cropSlug,
        season: '2026-2027',
        seasonStatus: 'active',
      );
    }

    return generalAdmin;
  }

  /// Dynamically resolves any transaction row into its real Cost Center based on active inventory products
  static CostCenter resolve(
    Map<String, dynamic> row, [
    List<CostCenter>? activeCenters,
  ]) {
    // 0. Pre-resolved or explicit cost center info
    final explicitId = row['cost_center_id']?.toString();
    if (explicitId != null && explicitId.isNotEmpty) {
      if (explicitId == 'ALL' ||
          explicitId.toLowerCase() == 'all' ||
          explicitId == 'CC-ALL') {
        return sharedProducts;
      }
      final resolved = fromId(explicitId, activeCenters);
      if (resolved.id != generalAdmin.id) {
        return resolved;
      }
    }

    // If cost_center_name is already present and not generic admin
    final ccName = row['cost_center_name']?.toString();
    if (ccName != null &&
        ccName.isNotEmpty &&
        ccName != generalAdmin.nameAr &&
        ccName != 'المصروفات العمومية والإدارية') {
      if (ccName == 'توزيع بالتساوي على كل المنتجات') {
        return sharedProducts;
      }
      final resolvedFromName = fromId(ccName, activeCenters);
      if (resolvedFromName.id != generalAdmin.id) {
        return resolvedFromName;
      }
    }

    final targetProd = (row['target_product_name'] as String? ?? '').trim();
    if (targetProd.isNotEmpty && activeCenters != null) {
      for (final center in activeCenters) {
        final strippedCenter = center.nameAr.replaceFirst('خط ', '').trim();
        final strippedTarget = targetProd.replaceFirst('خط ', '').trim();
        if (center.nameAr == targetProd ||
            strippedCenter == strippedTarget ||
            center.nameAr.contains(targetProd) ||
            targetProd.contains(center.nameAr) ||
            (strippedTarget.length >= 3 && strippedCenter.contains(strippedTarget)) ||
            (strippedCenter.length >= 3 && strippedTarget.contains(strippedCenter)) ||
            center.nameEn.toLowerCase().contains(targetProd.toLowerCase())) {
          return center;
        }
      }
    }

    final itemName = (row['item_name'] as String? ?? '').toLowerCase();
    final cat = (row['category'] as String? ?? '').toLowerCase();

    // Check if notes is JSON string (from packing orders) and safely extract item metadata
    String specificNotes = '';
    final rawNotes = row['notes']?.toString() ?? '';
    if (rawNotes.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(rawNotes);
        if (decoded is Map && decoded['cost_items'] is List) {
          for (final ci in decoded['cost_items']) {
            if (ci is Map &&
                (ci['name']?.toString().trim().toLowerCase() == itemName.trim())) {
              final ciCcId = ci['cost_center_id']?.toString();
              if (ciCcId != null &&
                  ciCcId.isNotEmpty &&
                  ciCcId != 'all' &&
                  ciCcId != 'ALL') {
                return fromId(ciCcId, activeCenters);
              }
              final ciTarget = ci['target_product_name']?.toString() ?? '';
              if (ciTarget.isNotEmpty && activeCenters != null) {
                for (final center in activeCenters) {
                  if (center.nameAr.contains(ciTarget) ||
                      ciTarget.contains(center.nameAr)) {
                    return center;
                  }
                }
              }
            }
          }
        }

        // Check if item corresponds to packaging materials in packing order notes
        if (decoded is Map && decoded['materials'] is List) {
          for (final mat in decoded['materials']) {
            if (mat is Map &&
                (mat['product_name']?.toString().trim().toLowerCase() == itemName.trim() ||
                 mat['name']?.toString().trim().toLowerCase() == itemName.trim())) {
              final matCcId = mat['cost_center_id']?.toString();
              if (matCcId != null &&
                  matCcId.isNotEmpty &&
                  matCcId != 'all' &&
                  matCcId != 'ALL') {
                return fromId(matCcId, activeCenters);
              }
              final matTarget = mat['target_product_name']?.toString() ?? '';
              if (matTarget.isNotEmpty && activeCenters != null) {
                for (final center in activeCenters) {
                  if (center.nameAr.contains(matTarget) ||
                      matTarget.contains(center.nameAr) ||
                      center.nameEn.toLowerCase().contains(matTarget.toLowerCase())) {
                    return center;
                  }
                }
              }

              // Check apply_to (e.g. 'line:0')
              final applyTo = mat['apply_to']?.toString() ?? '';
              if (applyTo.startsWith('line:') && decoded['lot_entries'] is List) {
                final idx = int.tryParse(applyTo.substring(5));
                if (idx != null &&
                    idx >= 0 &&
                    idx < (decoded['lot_entries'] as List).length) {
                  final entry = decoded['lot_entries'][idx];
                  if (entry is Map) {
                    final pName = entry['product_name']?.toString() ?? '';
                    if (pName.isNotEmpty && activeCenters != null) {
                      for (final center in activeCenters) {
                        if (center.nameAr.contains(pName) ||
                            pName.contains(center.nameAr) ||
                            center.nameEn.toLowerCase().contains(pName.toLowerCase())) {
                          return center;
                        }
                      }
                    }
                    if (pName.isNotEmpty) {
                      final resolved = resolve({'item_name': pName}, activeCenters);
                      if (resolved.id != packingStation.id && resolved.id != generalAdmin.id) {
                        return resolved;
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // If the order has only 1 product variety, any packaging materials belong to that variety
        if (decoded is Map && decoded['lot_entries'] is List) {
          final entries = decoded['lot_entries'] as List;
          final prodNames = <String>{};
          for (final e in entries) {
            if (e is Map) {
              final pName = e['product_name']?.toString().trim() ?? '';
              if (pName.isNotEmpty) prodNames.add(pName);
            }
          }
          if (prodNames.length == 1) {
            final singleProd = prodNames.first;
            if (activeCenters != null) {
              for (final center in activeCenters) {
                if (center.nameAr.contains(singleProd) ||
                    singleProd.contains(center.nameAr) ||
                    center.nameEn.toLowerCase().contains(singleProd.toLowerCase())) {
                  return center;
                }
              }
            }
            final resolved = resolve({'item_name': singleProd}, activeCenters);
            if (resolved.id != packingStation.id && resolved.id != generalAdmin.id) {
              return resolved;
            }
          }
        }
      } catch (_) {
        specificNotes = rawNotes.toLowerCase();
      }
    } else {
      specificNotes = rawNotes.toLowerCase();
    }

    // 1. Direct match against active product inventory centers
    if (activeCenters != null && activeCenters.isNotEmpty) {
      final normItem = normalizeArabic(itemName);
      // First pass: match strictly against item_name
      for (final center in activeCenters) {
        final normAr = normalizeArabic(center.nameAr);
        final en = center.nameEn.toLowerCase();
        final code = (center.code ?? '').toLowerCase();

        if (normAr.isNotEmpty &&
            (normItem == normAr ||
             (normItem.length >= 3 && normAr.contains(normItem)) ||
             (normAr.length >= 3 && normItem.contains(normAr)))) {
          return center;
        }
        if (en.isNotEmpty && (itemName.toLowerCase().contains(en) || en.contains(itemName.toLowerCase()))) {
          return center;
        }
        if (code.isNotEmpty && (itemName.toLowerCase().contains(code) || code.contains(itemName.toLowerCase()))) {
          return center;
        }
      }

      // Second pass: match combined text (itemName + category + specificNotes)
      final normCombined = normalizeArabic('$itemName $cat $specificNotes');
      for (final center in activeCenters) {
        final normAr = normalizeArabic(center.nameAr);
        final en = center.nameEn.toLowerCase();
        final code = (center.code ?? '').toLowerCase();

        if (normAr.isNotEmpty &&
            (normCombined.contains(normAr) ||
             (normAr.length >= 3 && normAr.contains(normCombined)))) {
          return center;
        }
        if (en.isNotEmpty && (normCombined.contains(en) || en.contains(normCombined))) {
          return center;
        }
        if (code.isNotEmpty && normCombined.contains(code)) {
          return center;
        }
      }
    }

    final combined = '$itemName $cat $specificNotes';

    // 1.5 Crop category MUST resolve to a crop product variety
    if (cat.contains('محاصيل') || cat.contains('crop') || cat.contains('fruit')) {
      if (combined.contains('فراول') || combined.contains('strawberry') || combined.contains('فرول')) {
        if (activeCenters != null) {
          final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('فراول') || c.nameEn.toLowerCase().contains('strawberry')).firstOrNull;
          if (m != null) return m;
        }
        return strawberryLine;
      }
      if (combined.contains('مانج') || combined.contains('mango')) {
        if (activeCenters != null) {
          final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('مانج') || c.nameEn.toLowerCase().contains('mango')).firstOrNull;
          if (m != null) return m;
        }
        return mangoLine;
      }
      if (combined.contains('عنب') || combined.contains('grape')) {
        if (activeCenters != null) {
          final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('عنب') || c.nameEn.toLowerCase().contains('grape')).firstOrNull;
          if (m != null) return m;
        }
        return grapesLine;
      }
      if (combined.contains('برتقال') || combined.contains('orange') || combined.contains('ليمون') || combined.contains('يوسفي') || combined.contains('citrus')) {
        if (activeCenters != null) {
          final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('برتقال') || normalizeArabic(c.nameAr).contains('موالح')).firstOrNull;
          if (m != null) return m;
        }
        return citrusLine;
      }
      if (combined.contains('موز') || combined.contains('banana')) {
        if (activeCenters != null) {
          final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('موز') || c.nameEn.toLowerCase().contains('banana')).firstOrNull;
          if (m != null) return m;
        }
        return bananaLine;
      }
      if (activeCenters != null) {
        final varietyCenters = activeCenters.where((c) => c.type == CostCenterType.variety).toList();
        if (varietyCenters.length == 1) return varietyCenters.first;
      }
    }

    // 2. Check Specific Product Crop Varieties (whether fruit receipts, crop costs, or packaging for that fruit)
    if (combined.contains('فراول') || combined.contains('strawberry') || combined.contains('فرول')) {
      if (activeCenters != null) {
        final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('فراول') || c.nameEn.toLowerCase().contains('strawberry')).firstOrNull;
        if (m != null) return m;
      }
      return strawberryLine;
    }
    if (combined.contains('مانج') || combined.contains('mango')) {
      if (activeCenters != null) {
        final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('مانج') || c.nameEn.toLowerCase().contains('mango')).firstOrNull;
        if (m != null) return m;
      }
      return mangoLine;
    }
    if (combined.contains('عنب') ||
        combined.contains('grape') ||
        combined.contains('فليم') ||
        combined.contains('كرمسون') ||
        combined.contains('سوبيريور')) {
      if (activeCenters != null) {
        final m = activeCenters.where((c) => normalizeArabic(c.nameAr).contains('عنب') || c.nameEn.toLowerCase().contains('grape')).firstOrNull;
        if (m != null) return m;
      }
      return grapesLine;
    }
    if (combined.contains('برتقال') ||
        combined.contains('orange') ||
        combined.contains('ليمون') ||
        combined.contains('lemon') ||
        combined.contains('يوسفي') ||
        combined.contains('mandarin')) {
      return citrusLine;
    }
    if (combined.contains('موز') || combined.contains('banana')) {
      return bananaLine;
    }

    // 3. Check General Operational & Logistics
    if (cat.contains('شحن') ||
        cat.contains('shipping') ||
        cat.contains('freight') ||
        combined.contains('نولون') ||
        combined.contains('خط ملاحي') ||
        combined.contains('شحن جوي') ||
        combined.contains('شحن بحري') ||
        combined.contains('نقل لوجستي')) {
      return freightLogistics;
    }

    if (cat.contains('تخليص') ||
        cat.contains('مخلص') ||
        cat.contains('clearance') ||
        cat.contains('clearing') ||
        combined.contains('جمارك') ||
        combined.contains('رسوم موانئ') ||
        combined.contains('أتعاب تخليص')) {
      return customsClearance;
    }

    if (cat.contains('مواد التعبئة') ||
        cat.contains('تعبئة') ||
        cat.contains('تغليف') ||
        cat.contains('packing') ||
        cat.contains('packaging') ||
        combined.contains('كراتين') ||
        combined.contains('كرتون') ||
        combined.contains('ورق') ||
        combined.contains('بلاستيك') ||
        combined.contains('أكياس') ||
        combined.contains('بالتة') ||
        combined.contains('بالتات') ||
        combined.contains('عمالة') ||
        combined.contains('فرز') ||
        combined.contains('استيكر') ||
        combined.contains('ليبل') ||
        combined.contains('تبريد') ||
        combined.contains('شريط لاصق')) {
      return packingStation;
    }

    // 4. Administrative & General
    if (cat.contains('إدارية') ||
        cat.contains('admin') ||
        combined.contains('مصاريف إدارية') ||
        combined.contains('بوفيه') ||
        combined.contains('مكتب') ||
        combined.contains('إيجار') ||
        combined.contains('كهرباء') ||
        combined.contains('انترنت') ||
        combined.contains('هاتف') ||
        combined.contains('صيانة')) {
      return generalAdmin;
    }

    return generalAdmin;
  }
}
