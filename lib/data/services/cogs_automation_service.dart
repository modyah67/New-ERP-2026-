import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CogsAutomationService {
  final _client = Supabase.instance.client;

  /// COGS flag column (cogs_posted) does not exist in production schema.
  /// This method is a safe no-op that returns false.
  Future<bool> postCogsForShipment(int shipmentId) async {
    try {
      debugPrint('CogsAutomation.postCogsForShipment: no-op for $shipmentId (cogs_posted column absent)');
      return false;
    } catch (e, st) {
      debugPrint('CogsAutomation.postCogsForShipment error: $e\n$st');
      return false;
    }
  }

  /// COGS flag column (cogs_posted) does not exist in production schema.
  /// This method is a safe no-op that returns false.
  Future<bool> isCogsPosted(int shipmentId) async {
    try {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// COGS flag column (cogs_posted) does not exist in production schema.
  /// This method is a safe no-op.
  Future<void> reverseCogsForShipment(int shipmentId) async {
    try {
      debugPrint('CogsAutomation.reverseCogsForShipment: no-op for $shipmentId (cogs_posted column absent)');
    } catch (e, st) {
      debugPrint('CogsAutomation.reverseCogsForShipment error: $e\n$st');
    }
  }
}
