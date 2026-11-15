import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/features/suppliers/master_codes_directory_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MasterCodesDirectoryPdfService 9-Categories Tests', () {
    test('compileDirectory returns exactly 9 official financial categories in required order', () async {
      final groups = await MasterCodesDirectoryPdfService.compileDirectory();

      expect(groups.length, equals(9));

      // 1. موردين المحاصيل
      expect(groups[0].groupId, equals(50));
      expect(groups[0].groupName, contains('موردين المحاصيل'));
      expect(groups[0].groupName, contains('50000 - 59999'));

      // 2. موردين النقل ومقاولي الشحن
      expect(groups[1].groupId, equals(60));
      expect(groups[1].groupName, contains('موردين النقل'));
      expect(groups[1].groupName, contains('60000 - 69999'));

      // 3. موردين مواد التعبئة والتغليف
      expect(groups[2].groupId, equals(70));
      expect(groups[2].groupName, contains('موردين مواد التعبئة'));
      expect(groups[2].groupName, contains('70000 - 74999'));

      // 4. الموردين المشتركين (محاصيل وتعبئة)
      expect(groups[3].groupId, equals(75));
      expect(groups[3].groupName, contains('الموردين المشتركين'));
      expect(groups[3].groupName, contains('75000 - 79999'));

      // 5. المحطات
      expect(groups[4].groupId, equals(80));
      expect(groups[4].groupName, contains('المحطات'));
      expect(groups[4].groupName, contains('80000 - 89999'));

      // 6. موردي المحطات
      expect(groups[5].groupId, equals(85));
      expect(groups[5].groupName, contains('موردي المحطات'));
      expect(groups[5].groupName, contains('85000 - 89999'));

      // 7. موردي التخصيمات
      expect(groups[6].groupId, equals(40));
      expect(groups[6].groupName, contains('موردي التخصيمات'));
      expect(groups[6].groupName, contains('40000 - 49999'));

      // 8. المخلصين (بحري / جوي)
      expect(groups[7].groupId, equals(20));
      expect(groups[7].groupName, contains('المخلصين'));
      expect(groups[7].groupName, contains('بحري / جوي'));

      // 9. شركات الشحن
      expect(groups[8].groupId, equals(90));
      expect(groups[8].groupName, contains('شركات الشحن'));
      expect(groups[8].groupName, contains('90000+'));
    });

    test('generatePdfBytes produces valid PDF bytes from dynamic 9 groups', () async {
      final mockLiveGroups = [
        const MasterCodeGroup(
          groupId: 50,
          groupName: 'موردين المحاصيل\n(50000 - 59999)',
          entries: [
            MasterCodeEntry(code: '50001', name: 'مزرعة السلام'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 60,
          groupName: 'موردين النقل ومقاولي الشحن\n(60000 - 69999)',
          entries: [
            MasterCodeEntry(code: '60001', name: 'شركة الفرسان للنقل المبرد'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 70,
          groupName: 'موردين مواد التعبئة والتغليف\n(70000 - 74999)',
          entries: [
            MasterCodeEntry(code: '70001', name: 'إيجيبت باك للكرتون'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 75,
          groupName: 'الموردين المشتركين (محاصيل وتعبئة)\n(75000 - 79999)',
          entries: [
            MasterCodeEntry(code: '75001', name: 'الواحة للتنمية الزراعية'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 80,
          groupName: 'المحطات\n(80000 - 89999)',
          entries: [
            MasterCodeEntry(code: '80001', name: 'محطة الأمل المركزية للتعبئة'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 85,
          groupName: 'موردي المحطات\n(85000 - 89999)',
          entries: [
            MasterCodeEntry(code: '85001', name: 'محطة الأمل للفرز'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 40,
          groupName: 'موردي التخصيمات\n(40000 - 49999)',
          entries: [
            MasterCodeEntry(code: '40001', name: 'مكتب الحجر الزراعي'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 20,
          groupName: 'المخلصين\n(بحري / جوي)',
          entries: [
            MasterCodeEntry(code: '20001', name: 'مكتب البدر (بحري)'),
          ],
        ),
        const MasterCodeGroup(
          groupId: 90,
          groupName: 'شركات الشحن\n(90000+)',
          entries: [
            MasterCodeEntry(code: '90001', name: 'خط ميرسك الملاحي'),
          ],
        ),
      ];

      final bytes = await MasterCodesDirectoryPdfService.generatePdfBytes(
        groups: mockLiveGroups,
        settings: {
          'company_name': 'Fruity Farms Egypt',
        },
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // PDF signature "%PDF"
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });

    test('generatePdfBytes handles all 9 empty groups gracefully without errors and shows empty placeholder', () async {
      final emptyGroups = [
        const MasterCodeGroup(groupId: 50, groupName: 'موردين المحاصيل\n(50000 - 59999)', entries: []),
        const MasterCodeGroup(groupId: 60, groupName: 'موردين النقل ومقاولي الشحن\n(60000 - 69999)', entries: []),
        const MasterCodeGroup(groupId: 70, groupName: 'موردين مواد التعبئة والتغليف\n(70000 - 74999)', entries: []),
        const MasterCodeGroup(groupId: 75, groupName: 'الموردين المشتركين (محاصيل وتعبئة)\n(75000 - 79999)', entries: []),
        const MasterCodeGroup(groupId: 80, groupName: 'المحطات\n(80000 - 89999)', entries: []),
        const MasterCodeGroup(groupId: 85, groupName: 'موردي المحطات\n(85000 - 89999)', entries: []),
        const MasterCodeGroup(groupId: 40, groupName: 'موردي التخصيمات\n(40000 - 49999)', entries: []),
        const MasterCodeGroup(groupId: 20, groupName: 'المخلصين\n(بحري / جوي)', entries: []),
        const MasterCodeGroup(groupId: 90, groupName: 'شركات الشحن\n(90000+)', entries: []),
      ];

      final bytes = await MasterCodesDirectoryPdfService.generatePdfBytes(
        groups: emptyGroups,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(String.fromCharCodes(bytes.take(4)), equals('%PDF'));
    });
  });
}
