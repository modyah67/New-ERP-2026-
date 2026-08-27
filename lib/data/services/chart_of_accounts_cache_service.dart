import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cache service for Chart of Accounts.
/// Loads accounts once, refreshes on add/edit/archive/delete.
class ChartOfAccountsCacheService {
  final _client = Supabase.instance.client;
  static final ChartOfAccountsCacheService _instance =
      ChartOfAccountsCacheService._();
  factory ChartOfAccountsCacheService() => _instance;
  ChartOfAccountsCacheService._();

  // Cache
  List<Map<String, dynamic>> _allAccounts = [];
  List<Map<String, dynamic>> _expenseAccounts = [];
  List<Map<String, dynamic>> _revenueAccounts = [];
  List<Map<String, dynamic>> _leafAccounts = [];
  DateTime? _lastLoaded;
  static const _cacheDuration = Duration(minutes: 5);

  // Stream for reactive updates
  final _accountsController = StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get accountsStream => _accountsController.stream;

  /// Get all accounts (cached).
  Future<List<Map<String, dynamic>>> getAllAccounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _allAccounts.isNotEmpty && _isCacheValid()) {
      return _allAccounts;
    }
    await _loadAll();
    return _allAccounts;
  }

  /// Get expense accounts (leaf, active).
  Future<List<Map<String, dynamic>>> getExpenseAccounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _expenseAccounts.isNotEmpty && _isCacheValid()) {
      return _expenseAccounts;
    }
    await _loadAll();
    return _expenseAccounts;
  }

  /// Get revenue accounts (leaf, active).
  Future<List<Map<String, dynamic>>> getRevenueAccounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _revenueAccounts.isNotEmpty && _isCacheValid()) {
      return _revenueAccounts;
    }
    await _loadAll();
    return _revenueAccounts;
  }

  /// Get all leaf accounts (active).
  Future<List<Map<String, dynamic>>> getLeafAccounts({bool forceRefresh = false}) async {
    if (!forceRefresh && _leafAccounts.isNotEmpty && _isCacheValid()) {
      return _leafAccounts;
    }
    await _loadAll();
    return _leafAccounts;
  }

  /// Get account by ID (from cache).
  Map<String, dynamic>? getAccountById(String id) {
    try {
      return _allAccounts.firstWhere((a) => a['id'].toString() == id);
    } catch (_) {
      return null;
    }
  }

  /// Get account by code (from cache).
  Map<String, dynamic>? getAccountByCode(String code) {
    try {
      return _allAccounts.firstWhere((a) => a['account_code'] == code);
    } catch (_) {
      return null;
    }
  }

  /// Force refresh the cache.
  Future<void> refresh() async {
    await _loadAll();
  }

  /// Invalidate cache (call after any mutation).
  void invalidate() {
    _allAccounts = [];
    _expenseAccounts = [];
    _revenueAccounts = [];
    _leafAccounts = [];
    _lastLoaded = null;
  }

  bool _isCacheValid() {
    if (_lastLoaded == null) return false;
    return DateTime.now().difference(_lastLoaded!) < _cacheDuration;
  }

  Future<void> _loadAll() async {
    try {
      final data = await _client
          .from('accounts')
          .select('id, account_code, name, account_name, account_type, parent_id, balance, is_active, is_leaf, is_system')
          .order('account_code', ascending: true);

      _allAccounts = (data as List).cast<Map<String, dynamic>>();
      _expenseAccounts = _allAccounts
          .where((a) => a['account_type'] == 'expense' && a['is_leaf'] == true && a['is_active'] == true)
          .toList();
      _revenueAccounts = _allAccounts
          .where((a) => a['account_type'] == 'revenue' && a['is_leaf'] == true && a['is_active'] == true)
          .toList();
      _leafAccounts = _allAccounts
          .where((a) => a['is_leaf'] == true && a['is_active'] == true)
          .toList();
      _lastLoaded = DateTime.now();

      _accountsController.add(_allAccounts);
      debugPrint('ChartOfAccountsCache: loaded ${_allAccounts.length} accounts');
    } catch (e) {
      debugPrint('ChartOfAccountsCache: load error: $e');
    }
  }
}
