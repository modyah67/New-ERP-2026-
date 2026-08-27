import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/ui_utils.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import 'invoice_pdf_service.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class InvoicePreviewPage extends StatelessWidget {
  final ExportShipmentModel shipment;
  final List<Map<String, dynamic>> itemsData;
  final CustomerModel? customer;
  final ClearingAgentModel? clearingAgent;
  const InvoicePreviewPage({
    super.key,
    required this.shipment,
    this.itemsData = const [],
    this.customer,
    this.clearingAgent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('معاينة الفاتورة — ${shipment.shipmentNo}',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_alt, color: Colors.black, size: 20),
            label: const Text('حفظ PDF', style: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: () => _savePdf(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        pageFormats: const {'A4': PdfPageFormat.a4},
        initialPageFormat: PdfPageFormat.a4,
        pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
        onError: (context, error) => Center(
          child: Text('خطأ: $error', style: const TextStyle(color: Colors.red, fontFamily: 'Cairo')),
        ),
        build: (format) => _generatePdf(format),
        loadingWidget: const Center(child: CircularProgressIndicator(color: Colors.blue)),
        actions: const [],
      ),
    );
  }

  Future<void> _savePdf(BuildContext context) async {
    try {
      final doc = await InvoicePdfService.generate(
        shipment,
        itemsData: itemsData,
        customer: customer,
        clearingAgent: clearingAgent,
      );
      final bytes = await doc.save();
      final fileName = 'invoice_${shipment.shipmentNo.replaceAll('/', '-')}.pdf';

      final dir = await FileHelper.getExportDirectory();
      final filePath = '${dir.path}\\$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('تم حفظ الفاتورة بنجاح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(filePath, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white70)),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'فتح',
            textColor: Colors.white,
            onPressed: () async {
              await Process.run('explorer', [filePath]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ الملف: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format) async {
    final doc = await InvoicePdfService.generate(
      shipment,
      itemsData: itemsData,
      customer: customer,
      clearingAgent: clearingAgent,
    );
    return doc.save();
  }
}
