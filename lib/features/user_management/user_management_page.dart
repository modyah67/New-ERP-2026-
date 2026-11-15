import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../data/models/user_model.dart';
import 'user_management_cubit.dart';
import 'user_management_state.dart';
import 'user_form_dialog.dart';
import 'permissions_dialog.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  late final UserManagementCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = UserManagementCubit()..init();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = AppTheme.getBackgroundColor(context);
    final cardBg = AppTheme.getCardBg(context);

    return BlocProvider<UserManagementCubit>.value(
      value: _cubit,
      child: BlocListener<UserManagementCubit, UserManagementState>(
        listener: (context, state) {
          if (state is UserManagementLoaded && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!, style: const TextStyle(fontFamily: 'Cairo')),
                backgroundColor: AppTheme.danger,
              ),
            );
            // Clear the error message so it doesn't show again on rebuild
            _cubit.emit(state.copyWith(errorMessage: null));
          }
        },
        child: Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            title: const Text('إدارة المستخدمين',
                style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: cardBg,
            actions: [
              BlocBuilder<UserManagementCubit, UserManagementState>(
                builder: (context, state) {
                  if (state is UserManagementLoaded && state.isAdmin) {
                    return IconButton(
                      icon: const Icon(Icons.person_add),
                      tooltip: 'إضافة مستخدم',
                      onPressed: () => _showCreateUserDialog(context),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          body: BlocBuilder<UserManagementCubit, UserManagementState>(
            builder: (context, state) {
              if (state is UserManagementLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is UserManagementError) {
                final textSecondary = AppTheme.getTextSecondary(context);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
                      const SizedBox(height: 16),
                      Text(state.message,
                          style: TextStyle(
                              color: textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _cubit.loadAll(),
                        child: const Text('إعادة المحاولة',
                            style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ],
                  ),
                );
              }
              if (state is UserManagementLoaded) {
                return _buildUserList(context, state);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUserList(BuildContext context, UserManagementLoaded state) {
    final textSecondary = AppTheme.getTextSecondary(context);

    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 80, color: textSecondary),
            const SizedBox(height: 16),
            Text('لا يوجد مستخدمون بعد',
                style: TextStyle(
                    color: textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 18)),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showCreateUserDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('إضافة أول مستخدم',
                  style: TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        ),
      );
    }

    if (state.isSaving) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.users.length,
      itemBuilder: (context, index) => _buildUserCard(
        context,
        state.users[index],
        state.userRoles[state.users[index].id],
        state.isAdmin,
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    UserModel user,
    Map<String, dynamic>? role,
    bool isAdmin,
  ) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final cardBg = AppTheme.getCardBg(context);
    final borderColor = AppTheme.getBorderColor(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final textMuted = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF94A3B8);

    final roleName = role?['role']?.toString() ?? 'بدون صلاحية';
    final roleLabel = _translateRole(roleName);

    return Card(
      color: cardBg,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: user.isAdmin
                  ? primary.withValues(alpha: 0.2)
                  : AppTheme.accent.withValues(alpha: 0.2),
              child: Text(
                (user.fullName ?? user.email ?? '?').substring(0, 1),
                style: TextStyle(
                  color: user.isAdmin ? primary : AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName ?? 'بدون اسم',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (user.email != null &&
                          !user.email!.contains('@fruityfarms.com') &&
                          !user.email!.contains('@fruityfarms.local')) ...[
                        Flexible(
                          child: Text(
                            'البريد: ${user.email}',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        Flexible(
                          child: Text(
                            'البريد: ${user.email ?? ""}',
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (user.isAdmin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('مالك',
                              style: TextStyle(
                                  color: primary,
                                  fontSize: 11,
                                  fontFamily: 'Cairo')),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    roleLabel,
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
            if (isAdmin && !user.isAdmin)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: textSecondary),
                color: cardBg,
                onSelected: (value) async {
                  if (value == 'role') {
                    _showPermissionsDialog(context, user, role);
                  } else if (value == 'edit') {
                    _showEditUserDialog(context, user);
                  } else if (value == 'toggle_admin') {
                    await _cubit.updateUser(
                      userId: user.id!,
                      isAdmin: !user.isAdmin,
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'role',
                    child: Row(
                      children: [
                        Icon(Icons.security, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text('الصلاحيات', style: TextStyle(fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: AppTheme.warning),
                        SizedBox(width: 8),
                        Text('تعديل', style: TextStyle(fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle_admin',
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(user.isAdmin ? 'إزالة المالك' : 'تعيين كمالك',
                            style: const TextStyle(fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showCreateUserDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider<UserManagementCubit>.value(
        value: _cubit,
        child: const UserFormDialog(),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider<UserManagementCubit>.value(
        value: _cubit,
        child: UserFormDialog(user: user),
      ),
    );
  }

  void _showPermissionsDialog(
      BuildContext context, UserModel user, Map<String, dynamic>? role) {
    showDialog(
      context: context,
      builder: (_) => BlocProvider<UserManagementCubit>.value(
        value: _cubit,
        child: PermissionsDialog(userId: user.id!, currentRole: role),
      ),
    );
  }

  String _translateRole(String role) {
    switch (role) {
      case 'owner':
        return 'مالك';
      case 'manager':
        return 'مدير';
      case 'accountant':
        return 'محاسب';
      case 'warehouse':
        return 'أمين مخزن';
      case 'sales':
        return 'مبيعات';
      case 'cashier':
        return 'كاشير';
      case 'employee':
        return 'موظف';
      default:
        return role;
    }
  }
}
