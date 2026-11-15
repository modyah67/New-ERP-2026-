class AccountModel {
  final String? id;
  final String code;
  final String name;
  final String? accountName;
  final String type;
  final String? parentId;
  final double balance;
  final bool isActive;
  final DateTime? deletedAt;
  final int? level;

  /// Per-currency balances: { 'EGP': 100000.0, 'USD': 5000.0, ... }
  /// Populated from account_ledger_entries grouped by currency.
  final Map<String, double> balancesByCurrency;

  AccountModel({
    this.id,
    required this.code,
    required this.name,
    this.accountName,
    required this.type,
    this.parentId,
    this.balance = 0.0,
    this.isActive = true,
    this.deletedAt,
    this.level,
    this.balancesByCurrency = const {},
  });

  bool get isArchived => deletedAt != null;

  /// In the standardized 5-level chart of accounts, level 5 accounts are terminal leaf/posting accounts
  bool get isLeaf => evaluatedLevel >= 5;

  /// Whether this account has credit-normal nature (Liabilities, Equity, Revenues)
  bool get isCreditNormal =>
      type.toLowerCase() == 'liability' ||
      type.toLowerCase() == 'equity' ||
      type.toLowerCase() == 'revenue' ||
      code.startsWith('2') ||
      code.startsWith('4');

  /// Default currency for the account
  String get currency => 'EGP';

  /// Evaluates the account level according to the 5-level hierarchy:
  /// 1. Root / الجذور الرئيسية (e.g. 1, 2, 3, 4, 9)
  /// 2. Groups / المجموعات الرئيسية (e.g. 11, 12, 21, 22, 23, 31, 32, 33, 41, 42, 91)
  /// 3. Sub-groups / الحسابات الفرعية والرقابية (e.g. 111, 121, 122, 123, 124, 125, 126)
  /// 4. Analytical Control Groups / الحسابات التحليلية المجمعة (e.g. 1111, 1211, 1221, 1231, 1241, 1251, 1261)
  /// 5. Leaf & Posting Accounts / حسابات الترحيل والكيانات (e.g. 11111, 12512, 12611..12616)
  int get evaluatedLevel {
    if (level != null && level! > 0) return level!;
    final c = code.trim();
    if (c == '1' || c == '2' || c == '3' || c == '4' || c == '9' || c.length == 1) return 1;
    if (c.length == 2) return 2;
    if (c.length == 3) return 3;
    if (c.length == 4) return 4;
    return 5;
  }

  /// Localized Arabic level label adhering strictly to the 5-level standard.
  /// Any Level 5 sub-ledger posting account (e.g. 12511, 125101) explicitly returns 'مستوى 5 - حساب ترحيل'.
  String get levelLabel {
    switch (evaluatedLevel) {
      case 1:
        return 'مستوى 1 - رئيسي';
      case 2:
        return 'مستوى 2 - مجموعة';
      case 3:
        return 'مستوى 3 - فرعي';
      case 4:
        return 'مستوى 4 - تحليلي';
      case 5:
      default:
        return 'مستوى 5 - حساب ترحيل';
    }
  }

  /// In the standardized 5-level chart of accounts, all dynamic sub-entities (e.g. 125101, 211201)
  /// are terminal Level 5 posting accounts ('مستوى 5 - حساب ترحيل').
  bool get isOperationalSubEntity => false;

  /// Categorizes entity type for statement and dialog header labeling:
  /// - 'المورد' for supplier accounts (211..., 210..., or name with 'مورد')
  /// - 'العميل' for customer accounts (125..., 123..., or name with 'عميل')
  /// - 'الحساب' for all other ledger accounts
  String get entityLabel {
    final cleanCode = code.trim();
    final cleanName = displayName.toLowerCase();

    if (cleanCode.startsWith('12612') ||
        cleanCode.startsWith('12613') ||
        cleanName.contains('عهدة') ||
        cleanName.contains('عهده') ||
        cleanName.contains('custody')) {
      return 'أمين العهدة';
    }

    if (cleanCode.startsWith('211') ||
        cleanCode.startsWith('210') ||
        cleanName.contains('مورد') ||
        cleanName.contains('supplier')) {
      return 'المورد';
    }

    if (cleanCode.startsWith('125') ||
        cleanCode.startsWith('123') ||
        cleanName.contains('عميل') ||
        cleanName.contains('عملاء') ||
        cleanName.contains('customer') ||
        cleanName.contains('client')) {
      return 'العميل';
    }

    return 'الحساب';
  }

  /// Formatted entity header title e.g. "المورد: وليد" or "العميل: شركة الأمل"
  String get entityHeaderTitle => '$entityLabel: $displayName';

  static String? getStandardArabicName(String code) => _standardArabicNames[code.trim()];

  static const Map<String, String> _standardArabicNames = {
    // 5-Level Standard Roots & Groups
    '1': 'الأصول',
    '2': 'الخصوم وحقوق الملكية',
    '3': 'المصروفات والتكاليف',
    '4': 'الإيرادات',
    '9': 'حسابات نظامية ووسيطة',
    '11': 'أصول طويله الأجل',
    '12': 'أصول متداوله',
    '21': 'الخصوم المتداولة',
    '22': 'الإلتزامات طويلة الأجل',
    '23': 'رأس المال وحقوق الملكية',
    '31': 'تكاليف نقدية',
    '32': 'تكاليف محاسبية',
    '33': 'تكاليف مخزنية',
    '34': 'تكاليف المبيعات',
    '41': 'إيرادات النشاط',
    '42': 'إيرادات أخرى',
    '91': 'الحسابات الوسيطة والتسويات',

    // Level 3 Sub-groups (Assets)
    '111': 'أصول ثابته',
    '121': 'النقديه بالبنوك',
    '122': 'النقديه بالصندوق',
    '123': 'النقديه بالطريق',
    '124': 'المخزون',
    '125': 'العملاء',
    '126': 'أرصده مدينه أخرى',

    // Level 4 Analytical Control Groups (Assets)
    '1111': 'أصول ثابته متكامله',
    '1211': 'بنوك مدينه',
    '1212': 'شيكات برسم التحصيل',
    '1221': 'الخزن الاساسيه',
    '1231': 'تحويلات نقديه',
    '1241': 'المخزون',
    '1251': 'العملاء',
    '1261': 'أرصده مدينه أخرى',

    // Level 5 Leaf / Posting Accounts (Assets)
    '11111': 'أصول ثابته أراضى',
    '11112': 'أصول ثابته مباني',
    '11113': 'أصول ثابته أثاث ومعدات مكتبيه',
    '11114': 'أصول ثابته اجهزه كمبيوتر',
    '11115': 'أصول ثابته سيارات ملاكي',
    '11116': 'أصول ثابته وسائل نقل المحاصيل',

    '12111': 'البنك التجاري الدولي CIB - جنيه مصري',
    '12112': 'البنك التجاري الدولي CIB - دولار أمريكي',
    '12113': 'البنك التجاري الدولي CIB - يورو',
    '12114': 'البنك التجاري الدولي CIB - جنيه إسترليني',
    '12121': 'شيكات برسم التحصيل',

    '12211': 'الخزينة الرئيسية - جنيه مصري',
    '12212': 'الخزينة الرئيسية - دولار أمريكي',
    '12213': 'الخزينة الرئيسية - يورو',
    '12214': 'الخزينة الرئيسية - جنيه إسترليني',

    '12311': 'تحويلات نقديه',
    '12312': 'تحويلات شيكات',
    '12313': 'تحويلات بنكيه عملات - خارجيه',
    '12314': 'تحويلات بنكيه بين الفروع - داخليه',

    '12411': 'مخزن التعبئه والتغليف',
    '12412': 'مخزن مشتريات خام',
    '12413': 'مخزن الإنتاج التام',
    '12414': 'مخزن الفرز والتالف القابل للبيع',

    '12511': 'عملاء تصدير',
    '12512': 'عملاء محلي',

    '12611': 'سلف نقديه',
    '12612': 'عهد نقديه مؤقته',
    '12613': 'عهد نقديه مستديمه',
    '12614': 'جاري مصلحه الضرائب - خصم منبع',
    '12615': 'ارصده مدينه اخرى - ارصده تحت التحصيل',
    '12616': 'ارصده مدينه اخرى - مكتب المحاسب القانوني',

    // Fallback analytical / legacy codes
    '1213': 'أوراق قبض وشيكات برسم التحصيل',
    '1214': 'النقدية بالصندوق',

    // ========================================================================
    // CATEGORY 2: LIABILITIES & EQUITY (الخصوم وحقوق الملكية)
    // ========================================================================
    // Level 3 (Category 2)
    '211': 'الموردين وأوراق الدفع',
    '212': 'التزامات لجهات حكومية',
    '213': 'أرصدة دائنة أخرى',
    '221': 'إلتزامات طويلة الأجل',
    '231': 'رأس المال',
    '232': 'جاري مساهمين',
    '233': 'إحتياطي قانوني',
    '234': 'أرباح / خسائر مرحلة',
    '235': 'أرباح / خسائر العام الحالي',

    // Level 4 (Category 2)
    '2111': 'الموردين',
    '2112': 'أوراق الدفع',
    '2121': 'الضرائب',
    '2122': 'هيئة التأمينات الإجتماعية ومكتب العمل',
    '2131': 'أرصدة دائنة أخرى',
    '2211': 'التزامات طويلة الأجل ضرائب',
    '2212': 'مجمع الإهلاك',
    '2311': 'رأس المال',
    '2321': 'جاري مساهمين',
    '2331': 'إحتياطي قانوني',
    '2341': 'أرباح / خسائر مرحلة',
    '2342': 'فروق أرصدة افتتاحية',
    '2351': 'أرباح / خسائر العام الحالي',

    // Level 5 (Category 2)
    '21111': 'موردي النقل والسيارات',
    '21112': 'موردي مواد التعبئة',
    '21113': 'موردي مشتريات محاصيل',
    '21114': 'موردين مشتركين',
    '21115': 'شركات الشحن',
    '21116': 'مخلصي الجمارك',
    '21117': 'موردي المحطات',
    '21118': 'موردي التخصيمات',
    '21121': 'أوراق دفع البنك التجاري الدولي CIB',
    '21211': 'ضريبة كسب العمل',
    '21212': 'ضريبة الخصم من الغير - الخصم والإضافة',
    '21213': 'ضريبة القيمة المضافة - المبيعات',
    '21214': 'ضريبة الدخل',
    '21215': 'ضريبة الدمغة',
    '21216': 'ضريبة سنوات سابقة',
    '21221': 'هيئة التأمينات الإجتماعية',
    '21222': 'مكتب العمل',
    '21311': 'مصروفات مستحقة - مرتبات',
    '21312': 'تأمينات لصالح الغير',
    '22111': 'ضرائب مؤجلة',
    '22121': 'مجمع إهلاك أصول ثابتة أراضي',
    '22122': 'مجمع إهلاك أصول ثابتة مباني',
    '22123': 'مجمع إهلاك أصول ثابتة أثاث ومعدات مكتبية',
    '22124': 'مجمع إهلاك أصول ثابتة أجهزة كمبيوتر',
    '22125': 'مجمع إهلاك أصول ثابتة سيارات ملاكي',
    '22126': 'مجمع إهلاك أصول ثابتة وسائل نقل المحاصيل',
    '23111': 'رأس المال المصدر',
    '23112': 'زيادة رأس المال',
    '23211': 'جاري / عماد',
    '23212': 'جاري / عبد الباطن',
    '23213': 'جاري / إسلام',
    '23311': 'إحتياطي قانوني',
    '23411': 'أرباح / خسائر مرحلة',
    '23421': 'رصيد افتتاحي',
    '23511': 'أرباح / خسائر العام الحالي',

    // ========================================================================
    // CATEGORY 3: EXPENSES & COSTS (التكاليف والمصروفات)
    // ========================================================================
    // Level 3 (Category 3)
    '311': 'مصروفات وأجور عاملين',
    '312': 'مصروفات تشغيل',
    '313': 'مصروفات إدارية',
    '314': 'مصروفات أخرى',
    '321': 'إهلاك أصول ثابتة',
    '322': 'مصروفات محاسبية أخرى',
    '331': 'تكاليف مخزنية',
    '341': 'تكاليف المبيعات',

    // Level 4 (Category 3)
    '3111': 'مرتبات وما في حكمها',
    '3112': 'مصروفات عاملين أخرى',
    '3122': 'مصروفات تشغيل وبيع وتسويق',
    '3124': 'تكاليف ومصروفات تشغيل المحطات',
    '3126': 'رسوم فحص وتخصيمات التشغيل',
    '3131': 'مصروفات البوفيه وخدمات للإدارة',
    '3132': 'استشارات واشتراكات ورسوم',
    '3141': 'الفوائد البنكية',
    '3142': 'المصروفات البنكية',
    '3143': 'المصروفات المتنوعة الأخرى',
    '3211': 'إهلاك أصول ثابتة',
    '3221': 'فروق عملة',
    '3311': 'تكاليف مخزنية',
    '3411': 'تكاليف المبيعات',

    // Level 5 (Category 3)
    '31111': 'مصروفات مرتبات',
    '31112': 'مصروفات تأمينات اجتماعية',
    '31113': 'مصروفات بدلات أخرى - ثابتة',
    '31114': 'مصروفات بدلات أخرى - متغيرة',
    '31115': 'مصروفات مكافآت وحوافز',
    '31116': 'مصروفات مكافأة نهاية الخدمة',
    '31121': 'مصروفات سفر للخارج - بدلات سفر',
    '31122': 'مصروفات علاج العاملين',
    '31123': 'مصروفات انتقالات',
    '31221': 'مصروفات صيانة وتشغيل سيارات',
    '31222': 'مصروفات الدعاية والإعلان',
    '31223': 'مصروفات المعارض',
    '31224': 'مصروفات طباعة كتالوجات',
    // Engineer Expenses (3125)
    '3125': 'مصاريف مهندسين وإشراف موقع',
    '31251': 'مصاريف مهندسين',
    // Station Categories (3124)
    '31241': 'تشغيل',
    '31242': 'تبريد',
    '31243': 'حفظ مبرد',
    '31244': 'تقفيل كرتون',
    '31245': 'تعتيق صادر',
    '31246': 'اعادة تدوير',
    '31247': 'عماله',
    '31248': 'تبخير',
    '31249': 'تدوير خام',
    // Deduction Categories (3126)
    '31261': 'رسوم فحص',
    '31262': 'تخصيم عربي',
    '31263': 'تخصيم اوروبي',
    '31264': 'تحليل خاص',
    '31265': 'تحليل هيئه',
    '31266': 'سحب عينه عربي',
    '31267': 'تعديل وجات',
    '31268': 'دفتر حجر زراعي',
    '31269': 'دفتر حجر سلامه غذاء',
    '31311': 'مصروفات النظافة والبوفيه',
    '31312': 'مصروفات فواتير الكهرباء والمياه والغاز الطبيعي',
    '31313': 'مصروفات الضيافة',
    '31314': 'مصروفات أدوات كتابية وماكينات التصوير وفاكس',
    '31315': 'مصروفات الكمبيوتر والإنترنت وتليفون أرضي',
    '31316': 'مصروفات الإكراميات',
    '31317': 'مصروفات الهدايا',
    '31318': 'مصروفات الصيانة العامة',
    '31319': 'مصروفات إيجار عقارات',
    '31310': 'المصروفات المتنوعة',
    '31321': 'مصروفات أتعاب استشارية',
    '31322': 'مصروفات أتعاب مكتب المراجعة',
    '31323': 'مصروفات رسوم واشتراكات وتراخيص',
    '31324': 'مصروفات شحن مستندات',
    '31411': 'مصروفات فوائد بنكية',
    '31421': 'مصروفات بنكية',
    '31431': 'فروق فحص ضريبي',
    '31432': 'مصروفات سنوات سابقة',
    '32111': 'إهلاك أصول ثابتة أراضي',
    '32112': 'إهلاك أصول ثابتة مباني',
    '32113': 'إهلاك أصول ثابتة أثاث ومعدات مكتبية',
    '32114': 'إهلاك أصول ثابتة أجهزة كمبيوتر',
    '32115': 'إهلاك أصول ثابتة سيارات ملاكي',
    '32116': 'إهلاك أصول ثابتة وسائل نقل المحاصيل',
    '32211': 'فروق تقويم عملة',
    '33111': 'مصروفات مخزنية تعبئة وتغليف',
    '34111': 'تكاليف مشتريات خام - تكلفة بيع',
    '34112': 'مصروفات إكراميات - تكلفة بيع',
    '34113': 'مصروفات عمالة - تكلفة بيع',
    '34114': 'مصروفات نقل ومشال - تكلفة بيع',
    '34115': 'مصروفات رويالتي - تكلفة بيع',
    '34116': 'مصروفات إيجار برادات - تكلفة بيع',
    '34117': 'مصروفات تخليص - تكلفة بيع',
    '34118': 'مصروفات شحن (نولون) - تكلفة بيع',
    '34119': 'مصروفات تحاليل عينات - تكلفة بيع',
    '34110': 'مصروفات متنوعة أخرى - تكلفة بيع',

    // ========================================================================
    // CATEGORY 4: REVENUES (الإيرادات)
    // ========================================================================
    // Level 3 (Category 4)
    '411': 'إيرادات النشاط',
    '421': 'إيرادات أخرى',

    // Level 4 (Category 4)
    '4111': 'مبيعات محاصيل',
    '4112': 'مبيعات أخرى',
    '4211': 'فوائد دائنة',
    '4212': 'عمولات',

    // Level 5 (Category 4)
    '41111': 'مبيعات فراولة',
    '41112': 'مبيعات مانجو',
    '41113': 'مبيعات بلح',
    '41114': 'مبيعات بلوبيري',
    '41121': 'مبيعات فرزة محلي',
    '42111': 'فوائد دائنة - بنك التجاري الدولي CIB',
    '42121': 'عمولات',

    '911': 'حسابات وسيطة للتشغيل والهالك',
    '9111': 'وسيط هالك مواد التعبئة',
    '9112': 'وسيط هالك المحاصيل',
    '912': 'حسابات تسوية الضرائب والمصاريف',
    '9121': 'وسيط ضرائب',
    '9122': 'ضرائب محملة',
    '9123': 'مخصص / وسيط مصروفات إدارية',
    '9124': 'مصروفات إدارية محملة',

    // Legacy Codes compatibility
    '1000': 'الصندوق والنقدية',
    '1010': 'حسابات البنوك',
    '1020': 'العملاء (مدينون)',
    '1030': 'مخزون المحاصيل',
    '1031': 'مخزون الإنتاج التام',
    '1040': 'مخزون مواد التعبئة والتغليف',
    '1050': 'مصروفات التصدير والشحن',
    '11101': 'الخزينة الرئيسية - جنيه',
    '11102': 'الخزينة الرئيسية - دولار',
    '11103': 'الخزينة الرئيسية - يورو',
    '11104': 'الخزينة الرئيسية - جنيه إسترليني',
    '11201': 'حساب بنكي - CIB - جنيه مصري',
    '11202': 'حساب بنكي - CIB - دولار أمريكي',
    '11203': 'حساب بنكي - CIB - يورو',
    '11204': 'حساب بنكي - CIB - جنيه إسترليني',
    '2000': 'الموردون (دائنون)',
    '2100': 'الخصوم المتداولة الأخرى',
    '2101': 'وسيط ضرائب',
    '2102': 'ضرائب محملة',
    '2105': 'مخصص / وسيط مصروفات إدارية',
    '2106': 'وسيط هالك مواد التعبئة',
    '2107': 'وسيط هالك المحاصيل',
    '5210': 'مصروفات إدارية محملة',
    '9000': 'حسابات نظامية ووسيطة',
    '9101': 'وسيط ضرائب',
    '9102': 'ضرائب محملة',
    '9105': 'مخصص / وسيط مصروفات إدارية',
    '9106': 'وسيط هالك مواد التعبئة',
    '9107': 'وسيط هالك المحاصيل',
    '9210': 'مصروفات إدارية محملة',
    '2120': 'دفعات مقدمة للموردين',
    '3000': 'حقوق الملكية / رأس المال',
    '3001': 'رأس مال المالك - ج.م',
    '3002': 'رأس مال المالك - دولار',
    '3003': 'رأس مال المالك - يورو',
    '3004': 'رأس مال المالك - جنيه إسترليني',
    '3100': 'الأرباح المحتجزة',
    '3101': 'رأس مال المساهمين',
    '3200': 'أرباح السنة الجارية',
    '3300': 'احتياطي رأس المال',
    '3900': 'الأرصدة الافتتاحية',
    '3901': 'الأرصدة الافتتاحية - ج.م',
    '3902': 'الأرصدة الافتتاحية - دولار',
    '3903': 'الأرصدة الافتتاحية - يورو',
    '3904': 'الأرصدة الافتتاحية - إسترليني',
    '4000': 'إيرادات المبيعات',
    '4100': 'الإيرادات العامة',
    '4110': 'إيرادات المبيعات المحلية',
    '41101': 'الإيرادات العامة',
    '4200': 'إيرادات التصدير',
    '4300': 'إيرادات أخرى',
    '5000': 'تكلفة البضاعة المباعة',
    '51101': 'مصروفات عامة',
    '51102': 'هالك وفاقد المحاصيل',
    '51103': 'تسوية وفرز المحاصيل',
    '51104': 'هالك وفاقد مواد التعبئة والتغليف',
    '6000': 'المصروفات العمومية والإدارية',
    '6100': 'مصروفات الرواتب والأجور',
    '6200': 'مصروفات الإيجار',
    '6300': 'مصروفات الكهرباء والمياه',
    '6400': 'مصروفات الصيانة والإصلاح',
    '6500': 'مصروفات النقل والانتقالات',
    '6600': 'مصروفات البوفيه والضيافة',
    '6700': 'مصروفات الدعاية والإعلان',
    '6800': 'مصروفات بنكية',
    '6900': 'مصروفات متنوعة',
    '7000': 'حساب المشتريات',
    // English names
    'cash': 'الصندوق والنقدية',
    'bank': 'حسابات البنوك',
    'cib bank account - egp': 'حساب بنكي - CIB - جنيه مصري',
    'cib bank account - usd': 'حساب بنكي - CIB - دولار أمريكي',
    'cib bank account - eur': 'حساب بنكي - CIB - يورو',
    'cib bank account - gbp': 'حساب بنكي - CIB - جنيه إسترليني',
    'main bank - egp': 'حساب بنكي - CIB - جنيه مصري',
    'main bank - usd': 'حساب بنكي - CIB - دولار أمريكي',
    'main bank - eur': 'حساب بنكي - CIB - يورو',
    'main bank - gbp': 'حساب بنكي - CIB - جنيه إسترليني',
    'accounts receivable': 'العملاء (مدينون)',
    'inventory': 'مخزون المحاصيل',
    'produce inventory': 'مخزون المحاصيل',
    'finished goods inventory': 'مخزون الإنتاج التام',
    'packing materials inventory': 'مخزون مواد التعبئة والتغليف',
    'export expenses': 'مصروفات التصدير',
    'accounts payable': 'الموردون (دائنون)',
    'supplier advances': 'دفعات مقدمة للموردين',
    'owner equity': 'حقوق الملكية / رأس المال',
    'equity': 'حقوق الملكية',
    'sales revenue': 'إيرادات المبيعات',
    'general revenue': 'الإيرادات العامة',
    'export revenue': 'إيرادات التصدير',
    'other revenue': 'إيرادات أخرى',
    'other revenues': 'إيرادات أخرى',
    'local revenue': 'الإيرادات المحلية',
    'local sales revenue': 'إيرادات المبيعات المحلية',
    'services revenue': 'إيرادات الخدمات',
    'interest income': 'إيرادات الفوائد',
    'investment income': 'إيرادات الاستثمار',
    'rental income': 'إيرادات الإيجار',
    'gain on asset disposal': 'أرباح بيع أصول',
    'cost of goods sold': 'تكلفة البضاعة المباعة',
    'expenses': 'المصروفات',
    'general expenses': 'مصروفات عمومية',
    'purchase account': 'حساب المشتريات',
    'assets': 'الأصول',
    'liabilities': 'الخصوم',
    'current assets': 'الأصول المتداولة',
    'fixed assets': 'الأصول الثابتة',
    'current liabilities': 'الخصوم المتداولة',
    'non-current liabilities': 'الخصوم غير المتداولة',
    'revenues': 'الإيرادات',
    'operating expenses': 'المصروفات التشغيلية',
    'administrative expenses': 'المصروفات الإدارية',
    'tax': 'الضرائب',
    'vat': 'ضريبة القيمة المضافة',
    'retained earnings': 'الأرباح المبقاة / المرحلة',
    'capital': 'رأس المال',
    'salaries': 'الرواتب والأجور',
    'rent': 'الإيجار',
    'utilities': 'المنافع والخدمات',
    'electricity': 'الكهرباء والمياه',
    'water': 'المياه',
    'maintenance': 'الصيانة والإصلاح',
    'transportation': 'النقل والانتقالات',
    'freight': 'الشحن والنولون',
    'customs': 'الجمارك والتخليص',
    'hospitality': 'الضيافة والبوفيه',
    'advertising': 'الدعاية والإعلان',
    'marketing': 'التسويق والإعلان',
    'bank charges': 'مصروفات ورسوم بنكية',
    'bank fees': 'رسوم بنكية',
    'interest expense': 'مصروفات الفوائد',
    'office supplies': 'أدوات مكتبية ومطبوعات',
    'legal and professional': 'أتعاب قانونية ومهنية',
    'depreciation': 'مصروف الإهلاك',
    'miscellaneous': 'مصروفات نثرية ومتنوعة',
  };

  static bool _hasArabicChars(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  /// Localized Arabic name for the account.
  String get displayName {
    // 1. Strict priority to official 5-level Master Chart of Accounts mapping by code
    final cleanCode = code.trim();
    if (_standardArabicNames.containsKey(cleanCode)) {
      return _standardArabicNames[cleanCode]!;
    }
    // 2. If accountName has Arabic characters, use it
    if (accountName != null && accountName!.trim().isNotEmpty) {
      if (_hasArabicChars(accountName!)) {
        return accountName!.trim();
      }
    }
    // 3. If name has Arabic characters, use it
    if (name.trim().isNotEmpty && _hasArabicChars(name)) {
      return name.trim();
    }
    // 4. Match standard mapping by English name (lowercased)
    final lowerName = name.trim().toLowerCase();
    if (_standardArabicNames.containsKey(lowerName)) {
      return _standardArabicNames[lowerName]!;
    }
    final lowerAccName = (accountName ?? '').trim().toLowerCase();
    if (_standardArabicNames.containsKey(lowerAccName)) {
      return _standardArabicNames[lowerAccName]!;
    }
    // 5. Fallback to accountName or name or code
    if (accountName != null && accountName!.trim().isNotEmpty) {
      return accountName!.trim();
    }
    return name.trim().isNotEmpty ? name.trim() : code;
  }

  factory AccountModel.fromMap(Map<String, dynamic> map) {
    final rawAccountName = (map['account_name'] ?? map['arabic_name'])?.toString();
    final rawName = (map['name'] ?? '').toString();

    return AccountModel(
      id: map['id']?.toString(),
      code: (map['account_code'] ?? map['code'] ?? '').toString(),
      name: rawName.isNotEmpty ? rawName : (rawAccountName ?? ''),
      accountName: rawAccountName,
      type: (map['account_type'] ?? map['type'] ?? 'asset').toString(),
      parentId: map['parent_id']?.toString(),
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      isActive: (map['is_active'] as bool?) ?? true,
      level: (map['level'] as num?)?.toInt(),
      deletedAt: map['deleted_at'] != null
          ? DateTime.tryParse(map['deleted_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'account_code': code,
      'name': name,
      'account_name': (accountName != null && accountName!.isNotEmpty) ? accountName : displayName,
      'account_type': type,
      'parent_id': parentId,
      'balance': balance,
      'is_active': isActive,
      if (level != null) 'level': level,
    };
  }

  AccountModel copyWith({
    String? id,
    String? code,
    String? name,
    String? accountName,
    String? type,
    String? parentId,
    double? balance,
    bool? isActive,
    DateTime? deletedAt,
    int? level,
    Map<String, double>? balancesByCurrency,
  }) {
    return AccountModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      accountName: accountName ?? this.accountName,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      deletedAt: deletedAt ?? this.deletedAt,
      level: level ?? this.level,
      balancesByCurrency: balancesByCurrency ?? this.balancesByCurrency,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
