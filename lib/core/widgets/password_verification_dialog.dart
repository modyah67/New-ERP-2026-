import 'package:flutter/material.dart';
import '../theme.dart';

/// Displays a secure administrative password verification dialog.
///
/// Returns `true` if the entered password matches [expectedPassword] (default: `eslam2026`).
/// Returns `false` if cancelled or dismissed.
Future<bool> showPasswordVerificationDialog(
  BuildContext context, {
  String title = 'تأكيد كلمة المرور للمتابعة',
  String subtitle = 'يرجى إدخال كلمة المرور لتعديل البيانات',
  String expectedPassword = 'eslam2026',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PasswordVerificationDialog(
      title: title,
      subtitle: subtitle,
      expectedPassword: expectedPassword,
    ),
  );
  return result ?? false;
}

class PasswordVerificationDialog extends StatefulWidget {
  final String title;
  final String subtitle;
  final String expectedPassword;

  const PasswordVerificationDialog({
    super.key,
    this.title = 'تأكيد كلمة المرور للمتابعة',
    this.subtitle = 'يرجى إدخال كلمة المرور لتعديل البيانات',
    this.expectedPassword = 'eslam2026',
  });

  @override
  State<PasswordVerificationDialog> createState() => _PasswordVerificationDialogState();
}

class _PasswordVerificationDialogState extends State<PasswordVerificationDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _obscure = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _verify() {
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'يرجى إدخال كلمة المرور';
      });
      _focusNode.requestFocus();
      return;
    }

    if (input == widget.expectedPassword) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _errorMessage = 'كلمة المرور غير صحيحة';
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF05192D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.glassBorder),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_outline, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.subtitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              obscureText: _obscure,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              onSubmitted: (_) => _verify(),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              decoration: InputDecoration(
                hintText: 'كلمة المرور',
                hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                prefixIcon: const Icon(Icons.password_outlined, color: AppTheme.textSecondary, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscure = !_obscure);
                  },
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.glassBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _errorMessage != null ? AppTheme.danger : AppTheme.glassBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _errorMessage != null ? AppTheme.danger : AppTheme.primary,
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'إلغاء',
            style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: const Color(0xFF041E42),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _verify,
          child: const Text(
            'تأكيد',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
