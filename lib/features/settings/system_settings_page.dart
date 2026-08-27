import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../data/services/notification_service.dart';

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final _client = Supabase.instance.client;
  final _notifService = NotificationService();
  bool _loading = true;
  bool _saving = false;

  // Company profile
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _commercialCtrl = TextEditingController();

  // Currency
  String _baseCurrency = 'EGP';

  // Fiscal year
  int _fyStartMonth = 1;
  List<Map<String, dynamic>> _fiscalYears = [];

  // Invoice numbering
  final Map<String, Map<String, dynamic>> _numbering = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _taxCtrl.dispose();
    _commercialCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Company profile
      final profile = await _client.from('company_profile').select().limit(1).maybeSingle();
      if (profile != null) {
        _nameCtrl.text = profile['company_name'] ?? '';
        _addressCtrl.text = profile['address'] ?? '';
        _phoneCtrl.text = profile['phone'] ?? '';
        _emailCtrl.text = profile['email'] ?? '';
        _taxCtrl.text = profile['tax_number'] ?? '';
        _commercialCtrl.text = profile['commercial_register'] ?? '';
        _baseCurrency = profile['base_currency'] ?? 'EGP';
        _fyStartMonth = profile['fiscal_year_start_month'] ?? 1;
      }

      // Fiscal years
      final fy = await _client.from('fiscal_years').select().order('start_date', ascending: false);
      _fiscalYears = (fy as List).cast<Map<String, dynamic>>();

      // Invoice numbering
      final numbering = await _client.from('invoice_numbering').select();
      for (final n in numbering) {
        _numbering[n['entity_type'] as String] = {
          'prefix': n['prefix'] ?? '',
          'suffix': n['suffix'] ?? '',
          'next_number': n['next_number'] ?? 1,
          'pad_length': n['pad_length'] ?? 4,
          'year_format': n['year_format'] ?? 'YY',
          'id': n['id'],
        };
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _saveCompany() async {
    setState(() => _saving = true);
    try {
      final exists = await _client.from('company_profile').select('id').limit(1).maybeSingle();
      final data = {
        'company_name': _nameCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'tax_number': _taxCtrl.text.trim(),
        'commercial_register': _commercialCtrl.text.trim(),
        'base_currency': _baseCurrency,
        'fiscal_year_start_month': _fyStartMonth,
      };
      if (exists != null) {
        data['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await _client.from('company_profile').update(data).eq('id', exists['id']);
      } else {
        await _client.from('company_profile').insert(data);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات الشركة', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.primary),
      );
      await _notifService.createNotification(
        type: 'settings_update',
        title: 'تحديث الإعدادات',
        body: 'تم تحديث بيانات الشركة',
        severity: 'info',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الحفظ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.danger),
      );
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
            ),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                        children: [
                          _buildCompanySection(),
                          const SizedBox(height: 16),
                          _buildFiscalYearSection(),
                          const SizedBox(height: 16),
                          _buildNumberingSection(),
                          const SizedBox(height: 16),
                          _buildCurrenciesSection(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 20, right: 20, bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 50))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.settings_outlined, color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إعدادات النظام', style: TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  Text('System Settings', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassContainer(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x1A00E5FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.glassBorder.withValues(alpha: 30)),
          ),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildCompanySection() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('بيانات الشركة', Icons.business_outlined),
          const SizedBox(height: 16),
          _field('اسم الشركة', _nameCtrl),
          const SizedBox(height: 12),
          _field('العنوان', _addressCtrl, maxLines: 2),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field('الهاتف', _phoneCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _field('البريد الإلكتروني', _emailCtrl)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field('الرقم الضريبي', _taxCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _field('السجل التجاري', _commercialCtrl)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dropdownField('العملة الأساسية', _baseCurrency, ['EGP', 'USD', 'EUR', 'GBP'], (v) {
                  setState(() => _baseCurrency = v!);
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdownField('بداية السنة المالية (شهر)', '$_fyStartMonth',
                  List.generate(12, (i) => '${i + 1}'),
                  (v) => setState(() => _fyStartMonth = int.parse(v!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _saveCompany,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('حفظ بيانات الشركة', style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiscalYearSection() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('السنوات المالية', Icons.calendar_month_outlined),
          const SizedBox(height: 12),
          ..._fiscalYears.map((fy) {
            final active = fy['is_active'] == true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: (active ? AppTheme.primary : AppTheme.textSecondary).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      active ? Icons.check_circle : Icons.circle_outlined,
                      color: active ? AppTheme.primary : AppTheme.textSecondary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${fy['name'] ?? ''}', style: TextStyle(color: active ? Colors.white : AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                  ),
                  Text(
                    '${(fy['start_date']?.toString() ?? '').substring(0, 10).padRight(10, '—')} → ${(fy['end_date']?.toString() ?? '').substring(0, 10).padRight(10, '—')}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontFamily: 'Cairo'),
                  ),
                ],
              ),
            );
          }),
          if (_fiscalYears.isEmpty) const Text('لا توجد سنوات مالية', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildNumberingSection() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('ترقيم الفواتير', Icons.numbers_outlined),
          const SizedBox(height: 12),
          ..._numbering.entries.map((e) {
            final n = e.value;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.description_outlined, color: AppTheme.info, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo')),
                        Text('${n['prefix']}${n['next_number'].toString().padLeft(n['pad_length'] as int, '0')}${n['suffix']}', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCurrenciesSection() {
    return _glassContainer(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('العملات', Icons.currency_exchange_outlined),
          const SizedBox(height: 12),
          FutureBuilder(
            future: _client.from('currencies').select().order('code'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final currencies = snapshot.data as List;
              return Column(
                children: currencies.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: (c['is_base'] == true ? AppTheme.primary : AppTheme.textSecondary).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(c['symbol'] ?? c['code'], style: TextStyle(color: c['is_base'] == true ? AppTheme.primary : AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('${c['name_ar'] ?? c['name']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Cairo')),
                      ),
                      Text('${c['code']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                      if (c['is_base'] == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('أساسية', style: TextStyle(color: AppTheme.primary, fontSize: 10, fontFamily: 'Cairo')),
                        ),
                      ],
                    ],
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
        filled: true,
        fillColor: const Color(0x1A00E5FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 30)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _dropdownField(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
        filled: true,
        fillColor: const Color(0x1A00E5FF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.glassBorder.withValues(alpha: 30)),
        ),
      ),
      dropdownColor: const Color(0xFF0D2137),
      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
      onChanged: onChanged,
    );
  }
}
