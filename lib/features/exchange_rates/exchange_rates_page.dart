import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../../core/theme.dart';
import '../../data/dao/exchange_rate_dao.dart';

class ExchangeRatesPage extends StatefulWidget {
  const ExchangeRatesPage({super.key});

  @override
  State<ExchangeRatesPage> createState() => _ExchangeRatesPageState();
}

class _ExchangeRatesPageState extends State<ExchangeRatesPage> {
  final ExchangeRateDao _dao = ExchangeRateDao();
  List<ExchangeRateModel> _rates = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  Future<void> _loadRates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _dao.fetchAllRates();
      if (mounted) {
        setState(() {
          _rates = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'فشل في تحميل أسعار الصرف: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showEditRateDialog(ExchangeRateModel item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller =
        TextEditingController(text: item.rateToEgp.toStringAsFixed(4));
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppTheme.surface : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                      .withValues(alpha: isDark ? 0.1 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.currency_exchange,
                    color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                    size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'تعديل سعر الصرف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Text(
                      item.displayName,
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textSecondary
                            : const Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.navy : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color:
                            isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: isDark
                              ? AppTheme.primary
                              : const Color(0xFF0284C7),
                          size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '1 ${item.currencyCode} = ؟ جنيه مصري (EGP)',
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                isDark ? AppTheme.textPrimary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.left,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      color: isDark ? AppTheme.textPrimary : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: 'سعر الصرف مقابل الجنيه المصري',
                    labelStyle: TextStyle(
                        color: isDark
                            ? AppTheme.textSecondary
                            : const Color(0xFF64748B),
                        fontFamily: 'Cairo'),
                    suffixText: 'EGP',
                    suffixStyle: TextStyle(
                        color:
                            isDark ? AppTheme.primary : const Color(0xFF0284C7),
                        fontWeight: FontWeight.bold),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.border
                              : const Color(0xFFCBD5E1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.border
                              : const Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark
                              ? AppTheme.primary
                              : const Color(0xFF0284C7),
                          width: 1.5),
                    ),
                    filled: true,
                    fillColor: isDark ? AppTheme.navy : const Color(0xFFF8FAFC),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'يرجى إدخال السعر';
                    }
                    final num = double.tryParse(val.trim());
                    if (num == null || num <= 0) {
                      return 'يرجى إدخال رقم موجب صحيح';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
              child: Text('إلغاء',
                  style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondary
                          : const Color(0xFF64748B),
                      fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isDark ? AppTheme.primary : const Color(0xFF0284C7),
                foregroundColor: isDark ? AppTheme.navy : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final newRate = double.parse(controller.text.trim());
                      setDialogState(() => isSaving = true);

                      try {
                        await _dao.updateRate(item.currencyCode, newRate);
                        if (!mounted) return;
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'تم تحديث سعر صرف ${item.currencyCode} بنجاح',
                                style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: AppTheme.success,
                          ),
                        );
                        _loadRates();
                      } catch (e) {
                        if (dialogCtx.mounted) {
                          setDialogState(() => isSaving = false);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('خطأ أثناء التحديث: $e',
                                style: const TextStyle(fontFamily: 'Cairo')),
                            backgroundColor: AppTheme.danger,
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDark ? AppTheme.navy : Colors.white),
                    )
                  : const Text('حفظ التعديل',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = intl.DateFormat('yyyy/MM/dd hh:mm a', 'ar');

    return Scaffold(
      backgroundColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.currency_exchange,
                size: 24,
                color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
            const SizedBox(width: 10),
            Text(
              'أسعار الصرف الرسمية',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontFamily: 'Cairo'),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: isDark ? AppTheme.surface : Colors.white,
        foregroundColor: isDark ? AppTheme.textPrimary : Colors.black,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh,
                color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
            tooltip: 'تحديث البيانات',
            onPressed: _loadRates,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                  color: isDark ? AppTheme.primary : const Color(0xFF0284C7)))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: AppTheme.danger),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: 16,
                              color:
                                  isDark ? AppTheme.textPrimary : Colors.black,
                              fontFamily: 'Cairo')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? AppTheme.primary
                                : const Color(0xFF0284C7),
                            foregroundColor:
                                isDark ? AppTheme.navy : Colors.white),
                        onPressed: _loadRates,
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Card Info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surface : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isDark
                                  ? AppTheme.border
                                  : const Color(0xFFCBD5E1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                  alpha: isDark ? 0.26 : 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: (isDark
                                        ? AppTheme.primary
                                        : const Color(0xFF0284C7))
                                    .withValues(alpha: isDark ? 0.1 : 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.account_balance,
                                  color: isDark
                                      ? AppTheme.primary
                                      : const Color(0xFF0284C7),
                                  size: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'العملة الأساسية للنظام: الجنيه المصري (EGP = 1.0000)',
                                    style: TextStyle(
                                      color: isDark
                                          ? AppTheme.textPrimary
                                          : Colors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'تُستخدم هذه الأسعار كمرجع رسمي لحساب القيمة بالعملة الأساسية في الخزينة، البنوك، والشيكات.',
                                    style: TextStyle(
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : const Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Rates Table
                      Expanded(
                        child: Card(
                          color: isDark ? AppTheme.surface : Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: isDark
                                    ? AppTheme.border
                                    : const Color(0xFFCBD5E1)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _rates.isEmpty
                              ? Center(
                                  child: Text('لا توجد أسعار صرف مسجلة',
                                      style: TextStyle(
                                          color: isDark
                                              ? AppTheme.textSecondary
                                              : const Color(0xFF64748B),
                                          fontFamily: 'Cairo')),
                                )
                              : ListView.separated(
                                  itemCount: _rates.length,
                                  separatorBuilder: (context, index) => Divider(
                                      height: 1,
                                      color: isDark
                                          ? AppTheme.border
                                          : const Color(0xFFE2E8F0)),
                                  itemBuilder: (context, index) {
                                    final rate = _rates[index];
                                    final formattedDate = rate.updatedAt != null
                                        ? dateFormat
                                            .format(rate.updatedAt!.toLocal())
                                        : 'غير محدد';

                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 12),
                                      leading: CircleAvatar(
                                        radius: 22,
                                        backgroundColor: (isDark
                                                ? AppTheme.primary
                                                : const Color(0xFF0284C7))
                                            .withValues(
                                                alpha: isDark ? 0.1 : 0.12),
                                        child: Text(
                                          rate.currencyCode,
                                          style: TextStyle(
                                            color: isDark
                                                ? AppTheme.primary
                                                : const Color(0xFF0284C7),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Text(
                                            rate.displayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isDark
                                                  ? AppTheme.textPrimary
                                                  : Colors.black,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? AppTheme.navy
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: isDark
                                                      ? AppTheme.border
                                                      : const Color(0xFFCBD5E1)),
                                            ),
                                            child: Text(
                                              rate.currencyCode,
                                              style: TextStyle(
                                                color: isDark
                                                    ? AppTheme.primary
                                                    : const Color(0xFF0284C7),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            Icon(Icons.schedule,
                                                size: 14,
                                                color: isDark
                                                    ? AppTheme.textSecondary
                                                    : const Color(0xFF64748B)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'آخر تحديث: $formattedDate',
                                              style: TextStyle(
                                                  color: isDark
                                                      ? AppTheme.textSecondary
                                                      : const Color(0xFF64748B),
                                                  fontSize: 12,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? AppTheme.navy
                                                  : const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: isDark
                                                      ? AppTheme.border
                                                      : const Color(0xFFCBD5E1)),
                                            ),
                                            child: Text(
                                              '${rate.rateToEgp.toStringAsFixed(4)} ج.م',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isDark
                                                    ? AppTheme.primary
                                                    : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: (isDark
                                                      ? AppTheme.primary
                                                      : const Color(0xFF0284C7))
                                                  .withValues(
                                                      alpha:
                                                          isDark ? 0.15 : 0.12),
                                              foregroundColor: isDark
                                                  ? AppTheme.primary
                                                  : const Color(0xFF0284C7),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                            ),
                                            onPressed: () =>
                                                _showEditRateDialog(rate),
                                            icon:
                                                const Icon(Icons.edit, size: 16),
                                            label: const Text('تعديل السعر',
                                                style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
