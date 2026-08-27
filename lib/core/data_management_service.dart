import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';

class DataManagementService {
  final _client = Supabase.instance.client;

  // ── Database Backup ──────────────────────────
  Future<void> backupDatabase(BuildContext context) async {
    _ok(context, 'النسخ الاحتياطي مُدار عبر Supabase cloud. لا حاجة للنسخ اليدوي.');
  }

  // ── Database Restore ─────────────────────────
  Future<void> restoreDatabase(BuildContext context) async {
    _ok(context, 'استعادة البيانات مُدارة عبر Supabase cloud. لا حاجة للاستعادة اليدوية.');
  }

  // ── Export to CSV ────────────────────────────
  Future<void> exportToCsv(BuildContext context, String title, List<List<dynamic>> rows) async {
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath();

      if (selectedDirectory == null) {
        return;
      }

      final String fileName = '${title}_${DateTime.now().millisecondsSinceEpoch}.csv';
      final String savePath = p.join(selectedDirectory, fileName);

      // Convert rows to CSV string
      // Adding BOM (Byte Order Mark) for UTF-8 to display Arabic correctly in Excel
      final String csvData = csv.encode(rows);
      final List<int> bom = [0xEF, 0xBB, 0xBF]; 
      
      final File file = File(savePath);
      final raf = file.openSync(mode: FileMode.write);
      raf.writeFromSync(bom);
      raf.writeStringSync(csvData);
      raf.closeSync();

      _ok(context, 'تم تصدير البيانات بنجاح إلى:\n$savePath');
    } catch (e) {
      _err(context, 'حدث خطأ أثناء التصدير: $e');
    }
  }

  void _ok(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _err(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: AppTheme.danger,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
