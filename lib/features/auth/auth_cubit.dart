import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_state_notifier.dart';
import '../../core/services/admin_service.dart';
import '../../core/services/tenant_service.dart';
import '../../data/repositories/auth_repository.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final User user;
  final bool isAdmin;
  final List<String> allowedPages;

  const AuthAuthenticated({required this.user, this.isAdmin = false, this.allowedPages = const []});

  String? get fullName => user.userMetadata?['full_name'] as String?;
  String? get email => user.email;

  @override
  List<Object?> get props => [user.id, isAdmin, allowedPages];
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository _repository;
  StreamSubscription<dynamic>? _authSubscription;
  bool _initialCheckDone = false;

  // ✅ منع الـ double emit — لو في emit جاري متبدأش تاني
  bool _isEmittingAuth = false;
  String? _lastEmittedUserId;

  AuthCubit({required AuthRepository repository})
      : _repository = repository,
        super(const AuthInitial()) {
    _listenToAuthChanges();
  }

  void _log(String msg) {
    final user = _repository.currentUser;
    debugPrint('🔐 AuthCubit: $msg');
    debugPrint('   currentUser: ${user?.id ?? 'null'}');
    debugPrint('   state:       ${state.runtimeType}');
  }

  void _listenToAuthChanges() {
    _authSubscription = _repository.authStateChanges.listen(
      (authState) {
        final event = authState.event;
        final session = authState.session;

        debugPrint('🔐 AuthChangeEvent: $event');
        debugPrint('   session.user: ${authState.session?.user.id ?? 'null'}');

        switch (event) {
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
          case AuthChangeEvent.userUpdated:
            if (session?.user != null) {
              _log('Session restored / logged in');
              _emitAuthenticated(session!.user);
            } else {
              _log('Session event but no user');
              if (_initialCheckDone) {
                emit(const AuthUnauthenticated());
              }
            }
            break;
          case AuthChangeEvent.signedOut:
            _log('Signed out');
            emit(const AuthUnauthenticated());
            break;
          case AuthChangeEvent.passwordRecovery:
            break;
          default:
            break;
        }

        _initialCheckDone = true;
      },
      onError: (error) {
        debugPrint('❌ Auth stream error: $error');
        emit(const AuthError(message: 'خطأ في جلسة الدخول'));
      },
    );
  }

  Future<void> _emitAuthenticated(User user) async {
    if (_isEmittingAuth) {
      debugPrint('🔐 _emitAuthenticated: skipped (already in progress)');
      return;
    }
    if (state is AuthAuthenticated && _lastEmittedUserId == user.id) {
      debugPrint('🔐 _emitAuthenticated: skipped (already emitted for this user)');
      return;
    }
    _isEmittingAuth = true;

    try {
      final data = await Supabase.instance.client
          .from('users')
          .select('is_admin')
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) {
        _log('User ${user.id} not found in public.users — signing out');
        emit(const AuthError(message: 'المستخدم غير موجود في قاعدة البيانات'));
        await _repository.signOut();
        return;
      }

      final isAdmin = data['is_admin'] == true;
      final allowedPages = await _queryAllowedPages(user.id);

      await TenantService().loadTenant();

      // Non-admin users inherit the admin's block/read-only/subscription status
      if (!isAdmin) {
        await _applyAdminStatusOverrides();
      }

      _log('Emitting authenticated (isAdmin=$isAdmin, allowedPages=${allowedPages.length})');
      _lastEmittedUserId = user.id;
      emit(AuthAuthenticated(user: user, isAdmin: isAdmin, allowedPages: allowedPages));
    } catch (e) {
      debugPrint('❌ _emitAuthenticated error: $e');
      emit(AuthError(message: 'خطأ في التحقق من المستخدم: $e'));
    } finally {
      _isEmittingAuth = false;
    }
  }

  Future<void> _applyAdminStatusOverrides() async {
    try {
      // Find the admin (owner) user's ID from local users table
      final adminData = await Supabase.instance.client
          .from('users')
          .select('id')
          .eq('is_admin', true)
          .limit(1);

      if (adminData.isEmpty) return;

      final adminId = adminData.first['id'].toString();

      // Use the ADMIN's user ID to validate subscription from the admin Supabase
      // This way non-admin users inherit the admin's subscription status
      final adminTenantData = await AdminService().validateSubscription(adminId);
      if (adminTenantData != null) {
        // Apply the admin's subscription status to TenantService
        // so ReadOnlyGuard picks it up
        TenantService().setLocalAdminOverrides(
          isBlocked: !(adminTenantData['is_active'] ?? true),
          readOnlyMode: adminTenantData['is_read_only'] ?? false,
          subscriptionActive: !(adminTenantData['is_expired'] ?? false),
        );
        debugPrint('🔐 Applied admin subscription status to non-admin user '
            '(active=${adminTenantData['is_active']}, '
            'readOnly=${adminTenantData['is_read_only']}, '
            'expired=${adminTenantData['is_expired']})');
      }
    } catch (e) {
      debugPrint('⚠️ _applyAdminStatusOverrides error: $e');
    }
  }

  Future<List<String>> _queryAllowedPages(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('user_roles')
          .select('allowed_pages')
          .eq('user_id', userId)
          .maybeSingle();
      if (data != null && data['allowed_pages'] != null) {
        return (data['allowed_pages'] as List).map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('⚠️ _queryAllowedPages error: $e');
    }
    return [];
  }



  Future<void> checkInitialAuth() async {
    final user = _repository.currentUser;
    final session = _repository.currentSession;

    debugPrint('🔐 checkInitialAuth()');
    debugPrint('   currentUser:  ${user?.id ?? 'null'}');
    debugPrint(
        '   currentSession: ${session?.accessToken != null ? 'present' : 'null'}');

    if (user != null) {
      // ✅ لو الـ stream اشتغل بالفعل (initialSession جه) متعملش emit تاني
      if (_initialCheckDone) {
        debugPrint('   -> stream already handled initialSession, skipping');
        return;
      }
      _emitAuthenticated(user);
      _initialCheckDone = true;
    } else {
      debugPrint('   -> awaiting stream event (no user yet)');
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _log('signInWithEmail($email)');
    emit(const AuthLoading());

    try {
      final response = await _repository.signInWithEmail(
        email: email,
        password: password,
      );

      debugPrint('   response.user: ${response.user?.id ?? 'null'}');
      debugPrint(
          '   response.session: ${response.session?.accessToken != null ? 'present' : 'null'}');

      if (response.user != null) {
        await _emitAuthenticated(response.user!);
      } else {
        emit(const AuthUnauthenticated());
      }
    } on AuthException catch (e) {
      debugPrint('❌ AuthException signInWithEmail: ${e.message}');
      emit(AuthError(message: _translateAuthError(e.message)));
    } catch (e) {
      debugPrint('❌ Unexpected error signInWithEmail: $e');
      emit(AuthError(message: 'حدث خطأ غير متوقع: ${e.toString()}'));
    }
  }

  Future<void> signInAsEmployee({
    required String username,
    required String password,
  }) async {
    // Generate the internal fake email for the employee
    final fakeEmail = '$username@fruityfarms.com';
    _log('signInAsEmployee($username) -> $fakeEmail');
    await signInWithEmail(email: fakeEmail, password: password);
  }

  Future<void> signUp({
    required String fullName,
    required String phone,
    required String email,
    required String password,
    bool isOwner = true,
  }) async {
    _log('signUp($email)');
    emit(const AuthLoading());

    try {
      // 1. Create user in auth.users
      final response = await _repository.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'phone': phone,
        },
      );

      final user = response.user;
      if (user == null) {
        emit(const AuthError(message: 'فشل إنشاء الحساب، برجاء المحاولة مرة أخرى'));
        return;
      }

      if (isOwner) {
        // 2. Call local RPC to setup tenant (resilient to clock skew)
        try {
          final rpcRes = await Supabase.instance.client.rpc(
            'sign_up_new_tenant',
            params: {
              'p_user_id': user.id,
              'p_full_name': fullName,
              'p_phone': phone,
              'p_email': email,
            },
          );

          if (rpcRes != null && (rpcRes as Map)['success'] == false) {
            debugPrint('⚠️ sign_up_new_tenant note: ${rpcRes['warning'] ?? rpcRes['error']}');
          }
        } catch (rpcErr) {
          debugPrint('⚠️ sign_up_new_tenant RPC note: $rpcErr');
          if (rpcErr.toString().contains('PGRST303') || rpcErr.toString().contains('JWT issued at future')) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
        }

        // 3. Register to admin database (non-blocking)
        try {
          final adminRes = await AdminService().registerTenant(
            userId: user.id,
            fullName: fullName,
            email: email,
            phone: phone,
          );

          if (adminRes == null) {
            debugPrint('⚠️ فشل مزامنة الحساب مع خادم الإدارة (Admin DB)');
          }
        } catch (adminErr) {
          debugPrint('⚠️ AdminService error: $adminErr');
        }
      } else {
        // If employee, just insert into local users table without admin privileges
        try {
          await Supabase.instance.client.from('users').upsert({
            'id': user.id,
            'full_name': fullName,
            'email': email.trim().toLowerCase(),
            'is_admin': false,
          });
        } catch (empErr) {
          debugPrint('⚠️ Employee upsert error: $empErr');
        }
      }

      // 4. Emit authenticated
      await _emitAuthenticated(user);

    } on AuthException catch (e) {
      debugPrint('❌ AuthException signUp: ${e.message}');
      emit(AuthError(message: _translateAuthError(e.message)));
    } catch (e) {
      debugPrint('❌ Unexpected error signUp: $e');
      emit(const AuthError(message: 'حدث خطأ غير متوقع أثناء إنشاء الحساب'));
    }
  }

  Future<void> signOut() async {
    _log('signOut()');
    try {
      await _repository.signOut();
    } catch (e) {
      debugPrint('❌ signOut error: $e');
    } finally {
      // Always emit unauthenticated to ensure local logout even if network fails
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> resetPassword(String email) async {
    _log('resetPassword($email)');
    emit(const AuthLoading());
    try {
      await _repository.resetPassword(email);
      emit(const AuthUnauthenticated());
    } on AuthException catch (e) {
      debugPrint('❌ AuthException resetPassword: ${e.message}');
      emit(AuthError(message: _translateAuthError(e.message)));
    } catch (e) {
      emit(const AuthError(message: 'حدث خطأ غير متوقع'));
    }
  }

  String? get userFullName => _repository.getUserFullName();
  String? get userEmail => _repository.getUserEmail();

  @override
  void onChange(Change<AuthState> change) {
    super.onChange(change);
    authNotifier.value = change.nextState;
  }

  String _translateAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
    }
    if (message.contains('User already registered')) {
      return 'هذا البريد الإلكتروني مسجل بالفعل';
    }
    if (message.contains('Password should be at least')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }
    if (message.contains('Unable to validate email address')) {
      return 'البريد الإلكتروني غير صالح';
    }
    if (message.contains('Email not confirmed')) {
      return 'يرجى تأكيد البريد الإلكتروني أولاً';
    }
    if (message.contains('Refresh Token Not Found') ||
        message.contains('Invalid Refresh Token')) {
      return 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مرة أخرى';
    }
    return message;
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
