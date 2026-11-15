import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/router.dart';

/// Service for navigating directly to a specific journal entry.
///
/// RULE: Every navigation MUST use journal_entry_id (the primary key of
/// journal_entries). NEVER search by description, amount, purchase_id,
/// invoice_id, or any other field. If journal_entry_id is missing, show
/// an error — never guess.
class JournalEntryNavigationService {
  static final _client = Supabase.instance.client;

  /// Navigate directly to a journal entry by its journal_entry_id.
  static void openById(BuildContext context, {required dynamic journalEntryId}) {
    final navContext = rootNavigatorKey.currentContext ?? context;
    final rawId = journalEntryId?.toString().trim() ?? '';
    final id = rawId.replaceAll('#', '').trim();
    if (id.isEmpty || id == '0') {
      if (navContext.mounted) {
        ScaffoldMessenger.of(navContext).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد قيد محاسبي مرتبط بهذه العملية.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
      return;
    }
    navContext.go(
      Uri(
        path: RoutePaths.journalEntry,
        queryParameters: {'journalEntryId': id},
      ).toString(),
    );
  }

  /// Open journal entry for a warehouse stock transfer.
  static Future<void> openForWarehouseTransfer(
    BuildContext context, {
    required dynamic transferId,
    dynamic journalEntryId,
  }) async {
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim();
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    try {
      final tId = transferId?.toString().trim() ?? '';
      if (tId.isNotEmpty) {
        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', 'stock_transfer')
            .eq('source_id', tId)
            .isFilter('deleted_at', null)
            .maybeSingle();

        if (res != null) {
          final id = res['id'] ?? res['entry_number'];
          if (id != null) {
            openById(context, journalEntryId: id);
            return;
          }
        }
      }
    } catch (_) {}

    openById(context, journalEntryId: journalEntryId);
  }

  /// Open journal entry for a purchase invoice.
  /// Priority: direct entry_number/id → v_journal_entry_lines search → purchase_invoices table → error.
  static Future<void> openForPurchase(
    BuildContext context, {
    required dynamic purchaseId,
    required dynamic purchaseNumber,
    dynamic journalEntryId,
  }) async {
    // 1. Direct navigation by journalEntryId if provided and starts with prefix
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim();
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    // 2. Look up exact entry from v_journal_entry_lines
    try {
      final pNum = purchaseNumber?.toString().trim() ?? '';
      final pId = purchaseId?.toString().trim() ?? '';

      if (pNum.isNotEmpty) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('entry_number')
            .ilike('description', '%فاتورة مشتريات%$pNum%')
            .limit(1)
            .maybeSingle();
        if (resView != null && resView['entry_number'] != null) {
          openById(context, journalEntryId: resView['entry_number']);
          return;
        }
      }

      if (pId.isNotEmpty) {
        final resViewId = await _client
            .from('v_journal_entry_lines')
            .select('entry_number')
            .or('source_id.eq.$pId,description.ilike.%$pId%')
            .limit(1)
            .maybeSingle();
        if (resViewId != null && resViewId['entry_number'] != null) {
          openById(context, journalEntryId: resViewId['entry_number']);
          return;
        }
      }
    } catch (_) {}

    // 3. Look up journal_entry_id from purchase_invoices table
    try {
      final pid = purchaseId?.toString().trim() ?? '';
      if (pid.isNotEmpty) {
        final res = await _client
            .from('purchase_invoices')
            .select('journal_entry_id')
            .eq('id', pid)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'].toString();
          if (jeId.isNotEmpty && jeId != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      }
    } catch (_) {}

    // 4. No journal entry found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لهذه الفاتورة بعد (تأكد من تأكيد الفاتورة).'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for a treasury/bank transaction.
  /// Priority: direct entryNumber/id → v_journal_entry_lines search → journal_entries table → error.
  static Future<void> openForTransaction(
    BuildContext context, {
    dynamic journalEntryId,
    dynamic entryNumber,
    dynamic txId,
    String? description,
    String? sourceType,
    String? sourceId,
  }) async {
    // 1. Direct navigation by journalEntryId (the actual FK — most reliable)
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim().replaceAll('#', '');
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    // 2. Direct navigation by entryNumber (whether numeric ID or formatted entry code like JE-00001, LOT-00001)
    if (entryNumber != null) {
      final numStr = entryNumber.toString().trim().replaceAll('#', '');
      if (numStr.isNotEmpty) {
        try {
          final res = await _client
              .from('journal_entries')
              .select('id')
              .eq('entry_number', numStr)
              .isFilter('deleted_at', null)
              .limit(1)
              .maybeSingle();
          if (res != null && res['id'] != null) {
            openById(context, journalEntryId: res['id']);
            return;
          }
        } catch (_) {}
        openById(context, journalEntryId: numStr);
        return;
      }
    }

    // 3. Direct lookup from treasury_transactions if txId is provided
    if (txId != null && txId.toString().trim().isNotEmpty) {
      try {
        final res = await _client
            .from('treasury_transactions')
            .select('journal_entry_id')
            .eq('id', txId)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      } catch (_) {}

      // 3b. Direct lookup from bank_transactions if txId is provided
      try {
        final res = await _client
            .from('bank_transactions')
            .select('journal_entry_id')
            .eq('id', txId)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      } catch (_) {}
    }

    // 4. Look up in v_journal_entry_lines ONLY if explicit sourceId is provided AND we are not coming from a txId.
    // (We DO NOT use sourceId here if txId is present, to prevent false matches where txId happens to equal a supplier ID in Opening Balances)
    try {
      final sid = sourceId?.toString().trim() ?? '';
      final tId = txId?.toString().trim() ?? '';
      if (sid.isNotEmpty && tId.isEmpty) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .eq('source_id', sid)
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resView != null) {
          final jeId = resView['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resView['entry_number'] != null) {
            openById(context, journalEntryId: resView['entry_number']);
            return;
          }
        }
      }

      // 4b. Try description search
      if (description != null && description.trim().length > 5) {
        final cleanDesc = description.trim();
        final resDesc = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .ilike('description', '%$cleanDesc%')
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resDesc != null) {
          final jeId = resDesc['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resDesc['entry_number'] != null) {
            openById(context, journalEntryId: resDesc['entry_number']);
            return;
          }
        }
      }
    } catch (_) {}

    // 5. Fallback: look up journal_entries by source_type + source_id
    try {
      if (sourceType != null && sourceId != null && sourceId.isNotEmpty) {
        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', sourceType)
            .eq('source_id', sourceId)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          final target = res['id'] ?? res['entry_number'];
          if (target != null) {
            openById(context, journalEntryId: target);
            return;
          }
        }
      }
    } catch (_) {}

    // 5. No journal entry found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يوجد قيد محاسبي مرتبط بهذه الحركة. [txId: $txId] [jeId: $journalEntryId] [desc: $description]'),
          backgroundColor: AppTheme.warning,
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  /// Open journal entry for a sales or return invoice.
  /// Priority: direct entryNumber/id → v_journal_entry_lines → error.
  static Future<void> openForInvoice(
    BuildContext context, {
    required dynamic invoiceNumber,
    dynamic invoiceId,
    dynamic journalEntryId,
  }) async {
    // Direct navigation by journalEntryId if provided
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim();
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    try {
      final invNum = invoiceNumber?.toString().trim() ?? '';
      if (invNum.isNotEmpty) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('entry_number')
            .ilike('description', '%$invNum%')
            .limit(1)
            .maybeSingle();
        if (resView != null && resView['entry_number'] != null) {
          openById(context, journalEntryId: resView['entry_number']);
          return;
        }
      }
    } catch (_) {}

    // No journal entry found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لهذه الفاتورة بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for a lot purchase receipt.
  /// Priority: journalEntryId (FK) → v_journal_entry_lines → lot_receipts.journal_entry_id → source_type+source_id lookup → error.
  static Future<void> openForLotReceipt(
    BuildContext context, {
    required dynamic lotId,
    dynamic lotNumber,
    dynamic journalEntryId,
  }) async {
    final lNum = lotNumber?.toString().trim() ?? lotId?.toString().trim() ?? '';
    final lid = lotId?.toString().trim() ?? '';

    // 1. Direct navigation by journalEntryId (FK — most reliable)
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim().replaceAll('#', '');
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    // 2. Look up exact entry in v_journal_entry_lines by lot number description
    try {
      if (lNum.isNotEmpty) {
        final resDesc = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .ilike('description', '%شراء محصول رقم $lNum%')
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resDesc != null) {
          final jeId = resDesc['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resDesc['entry_number'] != null) {
            openById(context, journalEntryId: resDesc['entry_number']);
            return;
          }
        }
      }

      if (lid.isNotEmpty) {
        final resSource = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .eq('source_id', lid)
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resSource != null) {
          final jeId = resSource['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resSource['entry_number'] != null) {
            openById(context, journalEntryId: resSource['entry_number']);
            return;
          }
        }
      }
    } catch (_) {}

    // 3. Look up journal_entry_id from lot_receipts table
    try {
      if (lid.isNotEmpty) {
        final res = await _client
            .from('lot_receipts')
            .select('journal_entry_id')
            .eq('id', lid)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'].toString();
          if (jeId.isNotEmpty && jeId != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      }
    } catch (_) {}

    // 4. Fallback: look up by source_type + source_id in journal_entries
    try {
      if (lid.isNotEmpty) {
        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', 'lot_receipt')
            .eq('source_id', lid)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          final target = res['id'] ?? res['entry_number'];
          if (target != null) {
            openById(context, journalEntryId: target);
            return;
          }
        }
      }
    } catch (_) {}

    // 5. Not found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لعملية شراء هذا المحصول بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for a lot return.
  /// Priority: journalEntryId (FK) → v_journal_entry_lines → lot_returns.journal_entry_id → source_type+source_id lookup → error.
  static Future<void> openForLotReturn(
    BuildContext context, {
    required dynamic returnId,
    dynamic lotNumber,
    dynamic journalEntryId,
  }) async {
    final rid = returnId?.toString().trim() ?? '';
    final lNum = lotNumber?.toString().trim() ?? '';

    // 1. Direct navigation by journalEntryId (FK — most reliable)
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim().replaceAll('#', '');
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    // 2. Look up exact entry in v_journal_entry_lines
    try {
      if (lNum.isNotEmpty) {
        final resDesc = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .ilike('description', '%مرتجع%رقم $lNum%')
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resDesc != null) {
          final jeId = resDesc['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resDesc['entry_number'] != null) {
            openById(context, journalEntryId: resDesc['entry_number']);
            return;
          }
        }
      }

      if (rid.isNotEmpty) {
        final resSource = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .eq('source_id', rid)
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resSource != null) {
          final jeId = resSource['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resSource['entry_number'] != null) {
            openById(context, journalEntryId: resSource['entry_number']);
            return;
          }
        }
      }
    } catch (_) {}

    // 3. Look up journal_entry_id from lot_returns table
    try {
      if (rid.isNotEmpty) {
        final res = await _client
            .from('lot_returns')
            .select('journal_entry_id')
            .eq('id', rid)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'].toString();
          if (jeId.isNotEmpty && jeId != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      }
    } catch (_) {}

    // 4. Fallback: look up by source_type + source_id
    try {
      if (rid.isNotEmpty) {
        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', 'lot_return')
            .eq('source_id', rid)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          final target = res['id'] ?? res['entry_number'];
          if (target != null) {
            openById(context, journalEntryId: target);
            return;
          }
        }
      }
    } catch (_) {}

    // 5. Not found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لعملية مرتجع هذا المحصول بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for an export shipment.
  /// Searches by: journalEntryId (FK) → source_type=export_shipment → v_journal_entry_lines by shipment_no → description search.
  static Future<void> openForExportShipment(
    BuildContext context, {
    required dynamic shipmentId,
    dynamic journalEntryId,
    String? shipmentNo,
  }) async {
    // 1. Direct navigation by journalEntryId (FK — most reliable)
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim().replaceAll('#', '');
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    final sid = shipmentId?.toString().trim() ?? '';

    try {
      if (sid.isNotEmpty) {
        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', 'export_shipment')
            .eq('source_id', sid)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          final target = res['id'] ?? res['entry_number'];
          if (target != null) {
            openById(context, journalEntryId: target);
            return;
          }
        }
      }
    } catch (_) {}

    try {
      if (sid.isNotEmpty) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .eq('source_type', 'export_shipment')
            .eq('source_id', sid)
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resView != null) {
          final jeId = resView['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resView['entry_number'] != null) {
            openById(context, journalEntryId: resView['entry_number']);
            return;
          }
        }
      }
    } catch (_) {}

    try {
      if (shipmentNo != null && shipmentNo.trim().isNotEmpty) {
        final resDesc = await _client
            .from('v_journal_entry_lines')
            .select('journal_entry_id, entry_number')
            .ilike('description', '%$shipmentNo%')
            .order('journal_entry_id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (resDesc != null) {
          final jeId = resDesc['journal_entry_id'];
          if (jeId != null && jeId.toString() != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
          if (resDesc['entry_number'] != null) {
            openById(context, journalEntryId: resDesc['entry_number']);
            return;
          }
        }
      }
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لهذه الشحنة بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for a shipment cost item (expense).
  /// Uses the stored journal_entry_id directly from shipment_cost_items.
  static Future<void> openForShipmentCostItem(
    BuildContext context, {
    required dynamic costItemId,
    dynamic journalEntryId,
    String? description,
  }) async {
    // 1. Direct navigation by journalEntryId if provided
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim();
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    // 2. Look up journal_entry_id from shipment_cost_items table
    try {
      final cid = costItemId?.toString().trim() ?? '';
      if (cid.isNotEmpty) {
        final res = await _client
            .from('shipment_cost_items')
            .select('journal_entry_id')
            .eq('id', cid)
            .maybeSingle();
        if (res != null && res['journal_entry_id'] != null) {
          final jeId = res['journal_entry_id'].toString();
          if (jeId.isNotEmpty && jeId != '0') {
            openById(context, journalEntryId: jeId);
            return;
          }
        }
      }
    } catch (_) {}

    // 3. Fallback: search by description in v_journal_entry_lines
    try {
      if (description != null && description.trim().length > 3) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('entry_number')
            .ilike('description', '%${description.trim()}%')
            .limit(1)
            .maybeSingle();
        if (resView != null && resView['entry_number'] != null) {
          openById(context, journalEntryId: resView['entry_number']);
          return;
        }
      }
    } catch (_) {}

    // 4. Not found
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لهذه التكلفة بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  /// Open journal entry for any document type & ID
  static Future<void> openForDocument(
    BuildContext context, {
    required String sourceType,
    required dynamic sourceId,
    dynamic journalEntryId,
  }) async {
    if (journalEntryId != null) {
      final id = journalEntryId.toString().trim();
      if (id.isNotEmpty && id != '0') {
        openById(context, journalEntryId: id);
        return;
      }
    }

    try {
      final sid = sourceId?.toString().trim() ?? '';
      if (sid.isNotEmpty) {
        final resView = await _client
            .from('v_journal_entry_lines')
            .select('entry_number')
            .eq('source_type', sourceType)
            .eq('source_id', sid)
            .limit(1)
            .maybeSingle();
        if (resView != null && resView['entry_number'] != null) {
          openById(context, journalEntryId: resView['entry_number']);
          return;
        }

        final res = await _client
            .from('journal_entries')
            .select('id, entry_number')
            .eq('source_type', sourceType)
            .eq('source_id', sid)
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();
        if (res != null) {
          final target = res['entry_number'] ?? res['id'];
          if (target != null) {
            openById(context, journalEntryId: target);
            return;
          }
        }
      }
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد قيد محاسبي مسجل لهذه العملية بعد.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }
}
