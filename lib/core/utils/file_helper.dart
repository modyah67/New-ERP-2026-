import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FileHelper {
  static Future<Directory> getExportDirectory() async {
    Directory dir;
    if (Platform.isAndroid) {
      final docDir = Directory('/storage/emulated/0/Documents');
      if (await docDir.exists()) {
        dir = docDir;
      } else {
        try {
          await docDir.create(recursive: true);
          dir = docDir;
        } catch (_) {
          dir = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
        }
      }
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        dir = Directory('$home/Documents');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    return dir;
  }
}
