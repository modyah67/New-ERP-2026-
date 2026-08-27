import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/utils.dart';
import '../exports/shipment_constants.dart';
import 'proforma_invoice_model.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class ProformaInvoiceWordService {
  static Future<void> exportWord({
    required BuildContext context,
    required ProformaInvoiceModel invoice,
    required List<ProformaInvoiceItem> items,
    CustomerModel? customer,
    ClearingAgentModel? clearingAgent,
  }) async {
    try {
      final bank = BankDetails.forCurrency(invoice.currency ?? 'EUR');
      
      final String dateStr = AppUtils.formatDate(invoice.invoiceDate ?? DateTime.now());
      final String invoiceNo = invoice.invoiceNo ?? 'Draft';
      
      final int totalQty = items.fold<int>(0, (s, i) => s + i.quantity.toInt());
      final double totalNet = items.fold<double>(0, (s, i) => s + i.netWeight);
      final double totalGross = items.fold<double>(0, (s, i) => s + i.grossWeight);
      final double totalAmount = items.fold<double>(0, (s, i) => s + i.computedTotal);
      final int totalPallets = items.fold<int>(0, (s, i) => s + i.palletsCount);
      final String symbol = invoice.currency == 'USD' ? '\$' : (invoice.currency == 'GBP' ? '£' : (invoice.currency == 'EGP' ? 'ج.م' : '€'));
      
      String? bgBase64;
      String? logoBase64;
      try {
        final bgBytes = await rootBundle.load('assets/images/invoice_bg.png');
        bgBase64 = base64Encode(bgBytes.buffer.asUint8List());
      } catch (_) {}
      try {
        final logoBytes = await rootBundle.load('assets/images/logo.png');
        logoBase64 = base64Encode(logoBytes.buffer.asUint8List());
      } catch (_) {}

      final String bgHtml = bgBase64 != null ? '''
  <!--[if gte vml 1]>
  <v:background id="_x0000_s1025" o:bwmode="white" fillcolor="white">
    <v:fill src="data:image/png;base64,$bgBase64" o:title="bg" type="frame"/>
  </v:background>
  <![endif]-->
''' : '';

      final String bodyBackground = bgBase64 != null ? 'background="data:image/png;base64,$bgBase64"' : '';

      String spacer(double h) => '<table style="width: 100%; border: none; border-collapse: collapse;"><tr><td style="height: ${h}pt; border: none; padding: 0; font-size: 1pt; line-height: ${h}pt;"></td></tr></table>';


      final String itemsHtml = items.map((item) {
        final netWt = item.quantity > 0 ? (item.netWeight / item.quantity).toStringAsFixed(1) : item.netWeight.toStringAsFixed(1);
        return '''
      <tr>
        <td style="text-align: left; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">
          <div style="font-size: 8pt; font-weight: bold; text-align: center;">${item.productName}</div>
          <div style="font-size: 8pt; text-align: center;">Net Weight: $netWt KG</div>
        </td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">${item.quantity.toInt()}</td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">$symbol ${item.pricePerCarton.toStringAsFixed(2)}</td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">${item.netWeight.toStringAsFixed(1)}</td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">${item.grossWeight.toStringAsFixed(1)}</td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; font-weight: bold; border-bottom: 0.5pt solid black;">$symbol ${item.computedTotal.toStringAsFixed(2)}</td>
      </tr>
        ''';
      }).join('');

      final emptyItemsHtml = items.isEmpty ? '''
      <tr>
        <td style="padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;"></td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">0</td>
        <td style="padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;"></td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">0</td>
        <td style="font-size: 8pt; text-align: center; padding: 5pt 3pt; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">0</td>
        <td style="padding: 5pt 3pt; border-bottom: 0.5pt solid black;"></td>
      </tr>
      ''' : '';

      final String palletsHtml = totalPallets > 0 ? '''
      <tr>
        <td colspan="6" style="font-size: 8pt; text-align: center; padding: 3pt; border-bottom: 0.5pt solid black;">$totalPallets Pallets</td>
      </tr>
      ''' : '';

      String consigneeHtml = '';
      if (customer != null) {
        consigneeHtml += '<div style="font-size: 9pt; font-weight: bold;">${customer.name}</div>';
        String address = invoice.destinationAddress ?? '';
        if (address.trim().isEmpty && customer.addresses.isNotEmpty) {
           final a = customer.addresses.first;
           address = (a['full_address'] ?? a['address_line_1'] ?? a['address'] ?? '').toString();
        }
        if (address.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">$address</div>';
        if (customer.city.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">${customer.city}</div>';
        if (invoice.country != null && invoice.country!.isNotEmpty) {
          consigneeHtml += '<div style="font-size: 8pt;">${invoice.country}</div>';
        } else if (customer.country.isNotEmpty) {
          consigneeHtml += '<div style="font-size: 8pt;">${customer.country}</div>';
        }
        if (customer.contactPersonName.isNotEmpty) {
          consigneeHtml += '<div style="font-size: 8pt;"><span style="font-weight: bold;">Contact Person :</span> ${customer.contactPersonName}</div>';
        }
        final displayPhone = customer.contactPersonPhone.isNotEmpty ? customer.contactPersonPhone : customer.phone;
        if (displayPhone.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">Tel: $displayPhone</div>';
        final displayEmail = customer.contactPersonEmail.isNotEmpty ? customer.contactPersonEmail : customer.gmail;
        if (displayEmail.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">E-Mail: $displayEmail</div>';
        if (customer.vatNumber.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">VAT NO: ${customer.vatNumber}</div>';
        if (customer.eoriNo.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">EORI NO: ${customer.eoriNo}</div>';
      } else {
        consigneeHtml += '<div style="font-size: 9pt; font-weight: bold;">${invoice.customerName ?? '—'}</div>';
        if (invoice.country != null && invoice.country!.isNotEmpty) consigneeHtml += '<div style="font-size: 8pt;">${invoice.country}</div>';
        if (invoice.destinationAddress != null && invoice.destinationAddress!.trim().isNotEmpty) {
          consigneeHtml += '<div style="font-size: 8pt;">${invoice.destinationAddress}</div>';
        }
      }

      String notifyHtml = '';
      if (clearingAgent == null || clearingAgent.name.isEmpty) {
        if (invoice.clearingAgentName != null && invoice.clearingAgentName!.isNotEmpty) {
            notifyHtml += '<div style="font-size: 9pt; font-weight: bold;">${invoice.clearingAgentName}</div>';
        } else {
            notifyHtml += '<div style="font-size: 9pt; font-weight: bold;">Air Agent</div>';
            notifyHtml += '<div style="font-size: 8pt;">Clearer</div>';
            notifyHtml += '<div style="font-size: 8pt;">Giza</div>';
            notifyHtml += '<div style="font-size: 8pt;">Egypt</div>';
        }
      } else {
        notifyHtml += '<div style="font-size: 9pt; font-weight: bold;">${clearingAgent.name}</div>';
        for (final a in clearingAgent.addresses) {
          final addr = a['full_address']?.toString() ?? a['address_line_1']?.toString() ?? a['address']?.toString() ?? '';
          if (addr.isNotEmpty) notifyHtml += '<div style="font-size: 8pt;">$addr</div>';
        }
        if (clearingAgent.city.isNotEmpty) notifyHtml += '<div style="font-size: 8pt;">${clearingAgent.city}</div>';
        if (clearingAgent.country.isNotEmpty) notifyHtml += '<div style="font-size: 8pt;">${clearingAgent.country}</div>';
        if (clearingAgent.contactPersonName.isNotEmpty) {
          notifyHtml += '<div style="font-size: 8pt;"><span style="font-weight: bold;">Contact Person :</span> ${clearingAgent.contactPersonName}</div>';
        }
        if (clearingAgent.phone.isNotEmpty) notifyHtml += '<div style="font-size: 8pt;">Tel: ${clearingAgent.phone}</div>';
        if (clearingAgent.gmail.isNotEmpty) notifyHtml += '<div style="font-size: 8pt;">E-Mail: ${clearingAgent.gmail}</div>';
      }

      String shippingHtml = '';
      if (invoice.transportMode == 'sea') {
        shippingHtml = '''
        <table style="width: 100%; border-collapse: collapse;">
          <tr><td style="border-bottom: 0.5pt solid black; padding: 3pt 6pt; font-size: 9pt; height: 18pt;"><span style="font-weight: bold;">BL No.: </span>${invoice.blNumber ?? 'TBA'}</td></tr>
          <tr><td style="border-bottom: 0.5pt solid black; padding: 3pt 6pt; font-size: 9pt; height: 18pt;"><span style="font-weight: bold;">Vessel Name: </span>${invoice.vesselName ?? 'TBA'}</td></tr>
          <tr><td style="border-bottom: 0.5pt solid black; padding: 3pt 6pt; font-size: 9pt; height: 18pt;"><span style="font-weight: bold;">Cntr. No.: </span>${invoice.containerNo ?? 'TBA'}</td></tr>
          <tr><td style="padding: 3pt 6pt; font-size: 9pt; height: 18pt;"><span style="font-weight: bold;">Data Logger No.: </span>${invoice.dataLoggerNo ?? 'TBA'}</td></tr>
        </table>
        ''';
      } else {
        shippingHtml = '''
        <table style="width: 100%; border-collapse: collapse;">
          <tr><td style="padding: 3pt 6pt; font-size: 9pt; font-weight: bold;">AWB: ${invoice.blNumber ?? 'TBA'}</td></tr>
        </table>
        ''';
      }

      final bankHtml = bank != null ? '''
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">Bank Name: </span>${bank.bankName}</div>
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">Bank Address: </span>${bank.bankAddress}, El Nozha, Cairo Governorate, Egypt</div>
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">Account Name: </span>${bank.accountName}</div>
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">Account Number: </span>${bank.accountNumber}</div>
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">IBAN no.: </span>${bank.iban}</div>
        <div style="font-size: 5pt; line-height: 1.4;"><span style="font-weight: bold;">Swift Code: </span>${bank.swiftCode}</div>
      ''' : '';

      final paymentTermsHtml = invoice.paymentTerms != null && invoice.paymentTerms!.isNotEmpty 
          ? '<div style="font-size: 6pt; font-weight: bold; padding-bottom: 1pt;">Terms of Payment  : <span style="font-size: 5pt; font-weight: normal; border-bottom: 0.5pt solid black;">${invoice.paymentTerms}</span></div>' 
          : '';

      final tl = invoice.transportMode == 'sea' ? "By Sea" : 'By Air';

      final String htmlContent = """
<html xmlns:v="urn:schemas-microsoft-com:vml"
      xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word"
      xmlns="http://www.w3.org/TR/REC-html40">
<head>
  <meta charset="utf-8">
  <title>invoice</title>
  <style>
    @page {
      size: 595pt 841pt;
      margin: 0pt 0pt 0pt 0pt;
    }
    body, html { margin: 0; padding: 0; font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; font-size: 12px; color: black; }
    table { border-collapse: collapse; border-spacing: 0; }
    td, th { padding: 0; vertical-align: top; margin: 0; }
    div, p { margin: 0; padding: 0; line-height: normal; }
    * { margin: 0; padding: 0; }
  </style>
</head>
<body $bodyBackground>

  $bgHtml

  <table style="width: 595pt; height: 841pt; border: none; border-collapse: collapse;">
    <tr>
      <td style="width: 28pt; border: none;"></td>
      <td style="width: 539pt; border: none; vertical-align: top; padding-top: 147pt; padding-bottom: 71pt; padding-left: 0pt;">

        <div style="text-align: center; border-bottom: 1pt solid black; margin-bottom: 3pt; padding-bottom: 1pt; width: 100%;">
          <span style="font-size: 11pt; font-weight: bold; text-transform: lowercase;">invoice</span>
        </div>

        <table style="width: 262pt; border-collapse: collapse; border: 0.5pt solid black; margin-bottom: 3pt;">
          <tr>
            <td style="width: 131pt; text-align: center; font-size: 8pt; padding: 4pt 5pt; border-right: 0.5pt solid black; border-bottom: 0.5pt solid black;">Date</td>
            <td style="width: 131pt; text-align: center; font-size: 8pt; padding: 4pt 5pt; border-bottom: 0.5pt solid black;">Invoice No</td>
          </tr>
          <tr>
            <td style="text-align: center; font-size: 9pt; font-weight: bold; padding: 4pt 5pt; border-right: 0.5pt solid black;">$dateStr</td>
            <td style="text-align: center; font-size: 9pt; font-weight: bold; padding: 4pt 5pt;">$invoiceNo</td>
          </tr>
        </table>

        <table style="width: 523pt; border-collapse: collapse; margin-top: 3pt;">
          <tr>
            <td style="width: 240pt; border: 0.5pt solid black; padding: 0;">
              <div style="font-size: 8pt; font-weight: bold; text-align: center; border-bottom: 0.5pt solid black; padding: 3pt 6pt; height: 16pt;">Consignee</div>
              <div style="padding: 4pt 6pt;">
                $consigneeHtml
              </div>
            </td>
            <td style="width: 283pt; border: 0.5pt solid black; padding: 0; border-left: none;">
              <div style="font-size: 8pt; font-weight: bold; text-align: center; border-bottom: 0.5pt solid black; padding: 3pt 6pt; height: 16pt;">Shipper</div>
              <div style="padding: 4pt 6pt;">
                <div style="font-size: 9pt; font-weight: bold; padding-bottom: 3pt;">Fruity Farms</div>
                <div style="font-size: 8pt; padding-bottom: 3pt;">Al Musheer Ahmed Ismail St., Building No.1</div>
                <div style="font-size: 8pt;">Sheraton District, Heliopolis, Cairo, Egypt.</div>
                <div style="font-size: 8pt;">Tel : 01111034064</div>
                <div style="font-size: 8pt;">E-mail : export@fruityfarms.co</div>
              </div>
            </td>
          </tr>
        </table>

        <table style="width: 523pt; border-collapse: collapse;">
          <tr>
            <td style="width: 240pt; border: 0.5pt solid black; border-top: none; padding: 0;">
              <div style="font-size: 8pt; font-weight: bold; text-align: center; border-bottom: 0.5pt solid black; padding: 3pt 6pt; height: 16pt;">Notify</div>
              <div style="padding: 4pt 6pt;">
                $notifyHtml
              </div>
            </td>
            <td style="width: 283pt; border: 0.5pt solid black; border-top: none; padding: 0; border-left: none;">
              $shippingHtml
            </td>
          </tr>
        </table>

        <table style="width: 523pt; border-collapse: collapse; border: 0.5pt solid black; border-bottom: none; margin-top: 3pt;">
          <tr>
            <th style="width: 190pt; text-align: left; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">Product Description</th>
            <th style="width: 50pt; text-align: center; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">Qty-Crtn</th>
            <th style="width: 62pt; text-align: center; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">Price/Crtn</th>
            <th style="width: 56pt; text-align: center; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">Total<br>Net WT</th>
            <th style="width: 62pt; text-align: center; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black; border-right: 0.5pt solid black;">Total Gross<br>WT</th>
            <th style="width: 103pt; text-align: center; padding: 4pt 3pt; font-size: 8pt; font-style: italic; border-bottom: 0.5pt solid black;">Amount</th>
          </tr>
          $itemsHtml
          $emptyItemsHtml
          $palletsHtml
        </table>

        <table style="width: 523pt; border-collapse: collapse; border: 0.5pt solid black; border-top: 1pt solid black;">
          <tr>
            <td style="width: 190pt; text-align: left; padding: 4pt 3pt; font-size: 9pt; font-weight: bold; padding-left: 6pt;">Total</td>
            <td style="width: 50pt; text-align: center; padding: 4pt 3pt; font-size: 9pt; font-weight: bold;"><span style="border-bottom: 0.6pt solid black;">$totalQty</span></td>
            <td style="width: 62pt; text-align: center; padding: 4pt 3pt; font-size: 9pt; font-weight: bold;"></td>
            <td style="width: 56pt; text-align: center; padding: 4pt 3pt; font-size: 9pt; font-weight: bold;"><span style="border-bottom: 0.6pt solid black;">${totalNet.toStringAsFixed(0)}</span></td>
            <td style="width: 62pt; text-align: center; padding: 4pt 3pt; font-size: 9pt; font-weight: bold;"><span style="border-bottom: 0.6pt solid black;">${totalGross.toStringAsFixed(0)}</span></td>
            <td style="width: 103pt; text-align: center; padding: 4pt 3pt; font-size: 10pt; font-weight: bold;"><span style="border-bottom: 0.6pt solid black;">$symbol ${totalAmount.toStringAsFixed(2)}</span></td>
          </tr>
        </table>

        <div style="width: 140pt; border: 0.5pt solid black; padding: 0.3pt; text-align: center; font-size: 7pt; font-weight: bold; margin-bottom: 1pt; margin-top: 4pt;">
          TERMS OF SALE AND OTHER COMMENTS
        </div>
        <div style="width: 280pt; border: 0.5pt solid black; padding: 5pt 8pt;">
          <div style="font-size: 7pt; font-weight: bold; padding-bottom: 1pt;">TERMS AND CONDITIONS</div>
          <div style="font-size: 5pt; font-weight: bold; padding-bottom: 1pt;">Fruity Farms</div>
          <div style="font-size: 6pt; font-weight: bold; padding-bottom: 1pt;">Port Of Loading  : <span style="font-size: 5pt; font-weight: normal; border-bottom: 0.5pt solid black;">${invoice.portOfLoading ?? 'TBA'}</span></div>
          <div style="font-size: 6pt; font-weight: bold; padding-bottom: 1pt;">Port Of Destination  : <span style="font-size: 5pt; font-weight: normal; border-bottom: 0.5pt solid black;">${invoice.portOfDestination ?? 'TBA'}</span></div>
          $paymentTermsHtml
          <div style="font-size: 6pt; font-weight: bold; padding-bottom: 1pt;">Mode Of Transport  : <span style="font-size: 5pt; font-weight: normal; border-bottom: 0.5pt solid black;">$tl</span></div>
          <div style="font-size: 5pt;">All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account</div>
        </div>

        <div style="font-size: 5pt; margin-top: 2pt;">I Certify The Above To Be True And Correct To The Best Of My Knowledge</div>

        <div style="width: 250pt; border: 0.5pt solid black; margin-top: 2pt;">
          <div style="width: 100pt; border-bottom: 0.5pt solid black; padding: 3pt 6pt; font-size: 7pt; font-weight: bold;">
            Bank Details
          </div>
          <div style="padding: 3pt 6pt 4pt 6pt;">
            $bankHtml
          </div>
        </div>

      </td>
      <td style="width: 36pt; border: none;"></td>
    </tr>
  </table>

</body>
</html>
""";

      // Save to documents
      final directory = await FileHelper.getExportDirectory();
      final String dirPath = '${directory.path}\\FruityFarms\\WordFiles';
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final fileName = 'ProformaInvoice_${invoice.invoiceNo?.replaceAll('/', '_') ?? 'Draft'}_${DateTime.now().millisecondsSinceEpoch}.doc';
      final file = File('$dirPath\\$fileName');
      
      await file.writeAsString(htmlContent);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم حفظ ملف الوورد بنجاح في مجلد المستندات'), backgroundColor: Colors.green),
        );
      }

      // Open the file
      await OpenFilex.open(file.path);

    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ حدث خطأ أثناء تصدير ملف الوورد: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
