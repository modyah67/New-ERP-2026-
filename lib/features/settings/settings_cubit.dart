import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/dao/settings_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/invoice_dao.dart';
import '../../data/services/full_excel_export_service.dart';
import '../../core/data_management_service.dart';
import '../../core/constants.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final SettingsDao _dao = SettingsDao();
  final DataManagementService _dataService = DataManagementService();

  final companyNameController = TextEditingController();
  final companyAddressController = TextEditingController();
  final companyPhoneController = TextEditingController();
  final chequeNotificationDaysCtrl = TextEditingController();

  SettingsCubit() : super(const SettingsInitial()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    emit(const SettingsLoading());
    try {
      final map = await _dao.getAllSettings();
      companyNameController.text = map['company_name'] ?? 'اسم الشركة';
      companyAddressController.text = map['company_address'] ?? 'العنوان';
      companyPhoneController.text = map['company_phone'] ?? 'رقم الهاتف';
      final notifDays = int.tryParse(map['cheque_notification_days'] ?? '') ?? 3;
      chequeNotificationDaysCtrl.text = notifDays.toString();
      emit(SettingsLoaded(
        companyName: companyNameController.text,
        companyAddress: companyAddressController.text,
        companyPhone: companyPhoneController.text,
        chequeNotificationDays: notifDays,
      ));
    } catch (e) {
      emit(SettingsError(message: 'حدث خطأ: $e'));
    }
  }

  Future<void> saveSettings() async {
    final newName = companyNameController.text.trim();
    final newAddress = companyAddressController.text.trim();
    final newPhone = companyPhoneController.text.trim();
    final notifDays = int.tryParse(chequeNotificationDaysCtrl.text.trim()) ?? 3;

    await _dao.saveSetting('company_name', newName);
    await _dao.saveSetting('company_address', newAddress);
    await _dao.saveSetting('company_phone', newPhone);
    await _dao.saveSetting('cheque_notification_days', notifDays.toString());

    AppConstants.companyName = newName;
    AppConstants.companyAddress = newAddress;
    AppConstants.companyPhone = newPhone;

    emit(SettingsLoaded(
      companyName: newName,
      companyAddress: newAddress,
      companyPhone: newPhone,
      chequeNotificationDays: notifDays,
    ));
  }

  Future<void> backupDatabase(BuildContext context) async {
    await _dataService.backupDatabase(context);
  }

  Future<void> restoreDatabase(BuildContext context) async {
    await _dataService.restoreDatabase(context);
  }

  Future<void> exportCustomers(BuildContext context) async {
    final dao = CustomerDao();
    final rows = <List<dynamic>>[];
    rows.add(['الرقم', 'الاسم', 'الموبايل', 'العنوان', 'الرصيد']);

    int limit = 5000;
    int offset = 0;
    while (true) {
      final customers = await dao.getAll(limit: limit, offset: offset);
      if (customers.isEmpty) break;
      for (final c in customers) {
        rows.add([c.id, c.name, c.phone, c.addresses.isNotEmpty ? (c.addresses.first['address_line_1'] ?? '').toString() : '', c.balance]);
      }
      if (customers.length < limit) break;
      offset += limit;
    }
    await _dataService.exportToCsv(context, 'العملاء', rows);
  }

  Future<void> exportSuppliers(BuildContext context) async {
    final dao = SupplierDao();
    final rows = <List<dynamic>>[];
    rows.add(['الكود', 'الاسم', 'الموبايل', 'العنوان']);

    int limit = 5000;
    int offset = 0;
    while (true) {
      final suppliers = await dao.getAll(limit: limit, offset: offset);
      if (suppliers.isEmpty) break;
      for (final s in suppliers) {
        rows.add([s.supplierCode, s.name, s.phone, s.address]);
      }
      if (suppliers.length < limit) break;
      offset += limit;
    }
    await _dataService.exportToCsv(context, 'الموردين', rows);
  }

  Future<void> exportInvoices(BuildContext context) async {
    final dao = InvoiceDao();
    final rows = <List<dynamic>>[];
    rows.add([
      'رقم الفاتورة', 'التاريخ', 'اسم العميل', 'الإجمالي',
      'المدفوع', 'المتبقي', 'النوع'
    ]);

    int limit = 5000;
    int offset = 0;
    while (true) {
      final invoices = await dao.getAll(limit: limit, offset: offset);
      if (invoices.isEmpty) break;
      for (final inv in invoices) {
        rows.add([
          inv.invoiceNumber,
          inv.invoiceDate,
          inv.customerName ?? '',
          inv.netAmount,
          inv.paidAmount,
          inv.remainingAmount,
          inv.type == 'sale' ? 'فاتورة بيع' : 'مرتجع'
        ]);
      }
      if (invoices.length < limit) break;
      offset += limit;
    }
    await _dataService.exportToCsv(context, 'الفواتير', rows);
  }

  Future<void> exportAllToExcel(BuildContext context) async {
    final service = FullExcelExportService();
    try {
      final filePath = await service.exportAll(
        onProgress: (section, current, total) {
          emit(ExportProgressState(section: section, current: current, total: total));
        },
      );
      emit(ExportSuccess(filePath: filePath));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('تم التصدير بنجاح إلى:\n$filePath')),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      emit(ExportError(message: 'حدث خطأ أثناء التصدير: $e'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('حدث خطأ: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      loadSettings();
    }
  }

  @override
  void onChange(Change<SettingsState> change) {
    super.onChange(change);
  }

  @override
  Future<void> close() {
    companyNameController.dispose();
    companyAddressController.dispose();
    companyPhoneController.dispose();
    chequeNotificationDaysCtrl.dispose();
    return super.close();
  }
}
