import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'auth_cubit.dart';
import '../../core/theme.dart';
import '../../core/router.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with SingleTickerProviderStateMixin {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _showPass = false;
  late final AnimationController _pulse;

  static const _cyan = Color(0xFF00E5FF);
  static const _teal = Color(0xFF00E0B8);
  static const _glassBorder = Color(0x33FFFFFF);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _signUp() {
    final fullName = _fullName.text.trim();
    final phone = _phone.text.trim();
    // إزالة المسافات المخفية وأي علامات اتجاه (RTL/LTR) قد تضاف بواسطة لوحة المفاتيح
    final email = _email.text.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[\u200E\u200F\u202A-\u202E]'), '').toLowerCase();
    final password = _password.text;
    final confirmPassword = _confirmPassword.text;

    if (fullName.isEmpty || phone.isEmpty || email.isEmpty || password.isEmpty) {
      _showError('يرجى ملء جميع الحقول المطلوبة');
      return;
    }

    if (password != confirmPassword) {
      _showError('كلمة المرور غير متطابقة');
      return;
    }

    if (password.length < 6) {
      _showError('كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    context.read<AuthCubit>().signUp(
      fullName: fullName,
      phone: phone,
      email: email,
      password: password,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: const TextStyle(fontFamily: 'Cairo'))),
        ]),
        backgroundColor: Colors.redAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final narrow = screenW < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1A2E),
      body: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthError) _showError(state.message);
          if (state is AuthAuthenticated) {
            context.go(RoutePaths.home);
          }
        },
        child: Stack(
          children: [
            Positioned(top: -200, right: -100, child: _glow(_cyan, 400)),
            Positioned(bottom: -150, left: -200, child: _glow(_teal, 500)),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: _card(narrow, screenW),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(Color c, double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [c.withValues(alpha: 0.15), Colors.transparent], stops: const [0.1, 1.0]),
    ),
  );

  Widget _card(bool narrow, double screenW) {
    final cardW = narrow ? double.infinity : min(screenW * 0.45, 520.0);
    return AnimatedBuilder(animation: _pulse, builder: (_, __) {
      return Container(
        width: cardW,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: _cyan.withValues(alpha: _pulse.value * .15), blurRadius: 70, spreadRadius: -10),
            BoxShadow(color: _teal.withValues(alpha: _pulse.value * .08), blurRadius: 100, spreadRadius: -15),
            BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 40, offset: const Offset(0, 20)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 40, vertical: narrow ? 28 : 40),
              decoration: BoxDecoration(
                color: const Color(0x1E1A2A4A),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: _glassBorder, width: 1),
              ),
              child: Stack(children: [
                Positioned(top: -30, right: -30, child: _glassOrb(80, const Color(0x0D00C2FF))),
                Positioned(bottom: -40, left: -20, child: _glassOrb(100, const Color(0x0A00E0B8))),
                
                BlocBuilder<AuthCubit, AuthState>(
                  builder: (_, state) {
                    final loading = state is AuthLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _titles(),
                        const SizedBox(height: 30),

                        Row(
                          children: [
                            Expanded(child: _fieldLabel('الاسم بالكامل')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _Input(controller: _fullName, hint: 'محمد أحمد', icon: Icons.person_outline_rounded, onSub: (_) => _signUp()),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(child: _fieldLabel('رقم الهاتف')),
                            const SizedBox(width: 16),
                            Expanded(child: _fieldLabel('البريد الإلكتروني')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _Input(controller: _phone, hint: '010...', icon: Icons.phone_outlined, keyboardType: TextInputType.phone, onSub: (_) => _signUp())),
                            const SizedBox(width: 16),
                            Expanded(child: _Input(controller: _email, hint: 'email@example.com', icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress, onSub: (_) => _signUp())),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(child: _fieldLabel('كلمة المرور')),
                            const SizedBox(width: 16),
                            Expanded(child: _fieldLabel('تأكيد كلمة المرور')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _Input(controller: _password, hint: '••••••••', icon: Icons.lock_outline_rounded, obscure: !_showPass, onSub: (_) => _signUp()),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _Input(controller: _confirmPassword, hint: '••••••••', icon: Icons.lock_outline_rounded, obscure: !_showPass, suffix: _eyeToggle(), onSub: (_) => _signUp()),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 30),
                        _signUpBtn(loading),
                        const SizedBox(height: 24),
                        _loginLink(),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _glassOrb(double size, Color c) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, Colors.transparent])),
  );

  Widget _titles() => Column(
    children: [
      const Text('حساب جديد', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      const SizedBox(height: 8),
      Text('أدخل بياناتك لإنشاء حساب', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16, fontFamily: 'Cairo')),
    ],
  );

  Widget _fieldLabel(String t) => Align(
    alignment: Alignment.centerRight,
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
  );

  Widget _eyeToggle() => IconButton(
    icon: AnimatedSwitcher(duration: const Duration(milliseconds: 200),
      child: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, key: ValueKey(_showPass), color: const Color(0xFF00E5FF).withValues(alpha: 0.7), size: 22)),
    onPressed: () => setState(() => _showPass = !_showPass),
  );

  Widget _signUpBtn(bool loading) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: SizedBox(height: 54,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1DA1F2), Color(0xFF00D2A0)]),
          boxShadow: [
            BoxShadow(color: const Color(0xFF1DA1F2).withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 8)),
            BoxShadow(color: const Color(0xFF00D2A0).withValues(alpha: .25), blurRadius: 30),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : _signUp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, foregroundColor: Colors.white, disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0, textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          child: loading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('إنشاء الحساب'),
        ),
      ),
    ),
  );

  Widget _loginLink() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text('لديك حساب بالفعل؟', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, fontFamily: 'Cairo')),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () => context.go(RoutePaths.login),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: const Text('تسجيل الدخول', style: TextStyle(color: _teal, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ),
    ],
  );
}

class _Input extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType keyboardType;
  final void Function(String)? onSub;
  const _Input({required this.controller, required this.hint, required this.icon, this.obscure = false, this.suffix, this.keyboardType = TextInputType.text, this.onSub});
  @override State<_Input> createState() => _InputState();
}
class _InputState extends State<_Input> {
  bool _foc = false;
  @override Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        onFocusChange: (f) => setState(() => _foc = f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _foc ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: .08), width: 1.5),
            boxShadow: _foc ? [BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: .15), blurRadius: 16)] : [],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(
              controller: widget.controller, obscureText: widget.obscure, keyboardType: widget.keyboardType,
              textDirection: (widget.keyboardType == TextInputType.emailAddress || widget.keyboardType == TextInputType.phone || widget.obscure) ? TextDirection.ltr : TextDirection.rtl,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontFamily: 'Cairo'),
              onSubmitted: widget.onSub,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: .3), fontSize: 14, fontFamily: 'Cairo'),
                border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                prefixIcon: Icon(widget.icon, color: _foc ? const Color(0xFF00E5FF) : Colors.white.withValues(alpha: .4), size: 22),
                suffixIcon: widget.suffix,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
