import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../dao/dashboard_dao.dart';

class DashboardRepository {
  final _dao = DashboardDao();

  Future<Map<String, dynamic>> getKpiData() async {
    return _dao.getKpiData();
  }

  Future<List<Map<String, dynamic>>> globalSearch(String query) async {
    return _dao.globalSearch(query);
  }

  Future<Map<String, dynamic>> getBadgeCounts() async {
    return _dao.getBadgeCounts();
  }
}
