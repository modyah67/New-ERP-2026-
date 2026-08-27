import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_cubit.dart';
import '../../core/router.dart';

// ══════════════════════════════════════════════════════════
// CONSTANTS
// ══════════════════════════════════════════════════════════
const _cyan = Color(0xFF00C2FF);
const _teal = Color(0xFF00E0B8);
const _navy = Color(0xFF0A1630);
const _navyLight = Color(0xFF112240);
const _glassBorder = Color(0x33FFFFFF);
const _textFaint = Color(0x66FFFFFF);

// ══════════════════════════════════════════════════════════
// LOGIN PAGE
// ══════════════════════════════════════════════════════════
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _showPass = false;

  late final AnimationController _ac;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, .1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOutCubic));
    _pulse = Tween(begin: .3, end: .8)
        .animate(CurvedAnimation(parent: _ac, curve: Curves.easeInOut));
    _ac.forward();
  }

  @override
  void dispose() {
    _ac.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  void _login() {
    final ident = _identifier.text.trim();
    final p = _password.text.trim();
    if (ident.isEmpty) { _bar('يرجى إدخال البريد أو اسم المستخدم'); return; }
    if (p.isEmpty) { _bar('يرجى إدخال كلمة المرور'); return; }
    debugPrint('🔐 LoginPage: attempting login for $ident');

    if (ident.contains('@')) {
      context.read<AuthCubit>().signInWithEmail(email: ident, password: p);
    } else {
      context.read<AuthCubit>().signInAsEmployee(username: ident, password: p);
    }
  }

  void _bar(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: _teal,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  Future<void> _wa(String phone) async {
    if (!await launchUrl(Uri.parse('https://wa.me/$phone'),
        mode: LaunchMode.externalApplication)) _bar('تعذر فتح الواتساب');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      body: BlocListener<AuthCubit, AuthState>(
        listener: (_, s) {
          if (s is AuthError) {
            _bar(s.message);
          } else if (s is AuthAuthenticated) {
            context.go('/home');
          }
        },
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          final narrow = w < 600;
          return Stack(fit: StackFit.expand, children: [
            _bg(),
            _vignette(),
            Positioned.fill(child: CustomPaint(painter: _ParticlesPainter(_ac.value))),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 24, vertical: 20),
                  child: FadeTransition(
                    opacity: _fade,
                    child: SlideTransition(
                      position: _slide,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _novaBranding(),
                          const SizedBox(height: 28),
                          _card(narrow, w),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  // ── BACKGROUND ────────────────────────────────────────────
  Widget _bg() => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [_navy, _navyLight, Color(0xFF0D1F3C), _navy],
    )),
    child: Image.asset('assets/images/login_bg.png', fit: BoxFit.cover,
        opacity: const AlwaysStoppedAnimation(.28)),
  );

  Widget _vignette() => Container(
    decoration: BoxDecoration(gradient: RadialGradient(
      center: Alignment.center, radius: 1.4,
      colors: [Colors.transparent, const Color(0xE00A1630)],
      stops: const [.2, 1],
    )),
  );

  // ── GLASS CARD ────────────────────────────────────────────
  Widget _card(bool narrow, double screenW) {
    final cardW = narrow ? double.infinity : min(screenW * 0.42, 480.0);
    return AnimatedBuilder(animation: _pulse, builder: (_, __) {
      return Container(
        width: cardW,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(color: _cyan.withValues(alpha: _pulse.value * .18), blurRadius: 70, spreadRadius: -10),
            BoxShadow(color: _teal.withValues(alpha: _pulse.value * .1), blurRadius: 100, spreadRadius: -15),
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
                // ── Inner corner decorations ──
                Positioned(top: -30, right: -30,
                    child: _glassOrb(80, const Color(0x0D00C2FF))),
                Positioned(bottom: -40, left: -20,
                    child: _glassOrb(100, const Color(0x0A00E0B8))),
                Positioned(top: 60, left: -20,
                    child: _glassOrb(50, const Color(0x08FFFFFF))),

                // ── Content ──
                BlocBuilder<AuthCubit, AuthState>(
                  builder: (_, state) {
                    final loading = state is AuthLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logoRow(),
                        const SizedBox(height: 20),
                        _titles(),
                        const SizedBox(height: 30),
                        _fieldLabel('البريد الإلكتروني أو اسم المستخدم'),
                        const SizedBox(height: 10),
                        _Input(controller: _identifier, 
                            hint: 'example@novasoft.com',
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            onSub: (_) => _login()),
                        const SizedBox(height: 20),
                        _fieldLabel('كلمة المرور'),
                        const SizedBox(height: 10),
                        _Input(controller: _password, hint: '••••••••',
                            icon: Icons.lock_outline_rounded, obscure: !_showPass,
                            suffix: _eyeToggle(), onSub: (_) => _login()),
                        const SizedBox(height: 8),
                        //_forgotLink(),
                        const SizedBox(height: 24),
                        _loginBtn(loading),
                        const SizedBox(height: 16),
                       // _signUpLink(),
                        const SizedBox(height: 22),
                        _orDivider(),
                        const SizedBox(height: 22),
                        _supportSection(),
                        const SizedBox(height: 4),
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

  // ── DECORATIVE GLASS ORB ──────────────────────────────────
  Widget _glassOrb(double size, Color c) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c, Colors.transparent])),
  );

  // ── NOVA SOFT BRANDING (above form) ─────────────────────
  Widget _novaBranding() => Column(
    children: [
      ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
        ).createShader(rect),
        child: const Text(
          'NOVA SOFT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: 6,
            fontFamily: 'Cairo',
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'SOFTWARE DEVELOPMENT',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .45),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 8,
          fontFamily: 'Cairo',
        ),
      ),
    ],
  );

  // ── LOGO ROW (image + FRUITY FARMS side by side) ────────
  Widget _logoRow() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/images/preview.png',
          width: 72,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: .08),
            ),
            child: Icon(Icons.spa, color: _teal, size: 30),
          ),
        ),
      ),
      const SizedBox(width: 14),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
                ).createShader(rect),
                child: const Text(
                  'FRUITY FARMS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // ── LOCK ICON ─────────────────────────────────────────────
  Widget _lockIcon() => Center(
    child: Container(
      width: 64, height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [_cyan, _teal]),
        boxShadow: [
          BoxShadow(color: _cyan.withValues(alpha: .5), blurRadius: 28, offset: const Offset(0, 6)),
          BoxShadow(color: _teal.withValues(alpha: .25), blurRadius: 40),
        ],
      ),
      child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 30),
    ),
  );

  // ── TITLES ────────────────────────────────────────────────
  Widget _titles() => Column(children: [
    ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
      ).createShader(rect),
      child: const Text('تسجيل الدخول', style: TextStyle(
          color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold,
          fontFamily: 'Cairo')),
    ),
    const SizedBox(height: 6),
    ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
      ).createShader(rect),
      child: Text('أدخل بريدك الإلكتروني أو اسم المستخدم', style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7), fontSize: 14,
          fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
    ),
  ]);

  Widget _fieldLabel(String t) => Align(
    alignment: Alignment.centerRight,
    child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 14,
        fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
  );

  // Widget _forgotLink() => Align(
  //   alignment: Alignment.centerRight,
  //   child: TextButton(
  //     onPressed: () {},
  //     style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4),
  //         minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
  //     child: Text('نسيت كلمة المرور؟', style: TextStyle(
  //         color: _cyan.withValues(alpha: .9), fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
  //   ),
  // );

  // ── EYE TOGGLE ────────────────────────────────────────────
  Widget _eyeToggle() => IconButton(
    icon: AnimatedSwitcher(duration: const Duration(milliseconds: 200),
      child: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          key: ValueKey(_showPass),
          color: const Color(0xFF00E5FF).withValues(alpha: 0.7), size: 22)),
    onPressed: () => setState(() => _showPass = !_showPass),
  );

  // ── LOGIN BUTTON ──────────────────────────────────────────
  Widget _loginBtn(bool loading) => _HoverScale(
    child: SizedBox(height: 54,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1DA1F2), Color(0xFF00D2A0)]),
          boxShadow: [
            BoxShadow(color: const Color(0xFF1DA1F2).withValues(alpha: .45),
                blurRadius: 22, offset: const Offset(0, 8)),
            BoxShadow(color: const Color(0xFF00D2A0).withValues(alpha: .25),
                blurRadius: 30),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent, foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0, textStyle: const TextStyle(fontSize: 18,
              fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          child: loading
              ? const SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('دخول'),
        ),
      ),
    ),
  );

  // ── SIGN UP LINK ──────────────────────────────────────────
  Widget _signUpLink() => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      Text('ليس لديك حساب؟', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, fontFamily: 'Cairo')),
      TextButton(
        onPressed: () => context.go(RoutePaths.signUp),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        child: const Text('إنشاء حساب جديد', style: TextStyle(color: _teal, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
      ),
    ],
  );

  // ── DIVIDER ───────────────────────────────────────────────
  Widget _orDivider() => Row(children: [
    Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: .08))),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('أو', style: TextStyle(color: _textFaint, fontSize: 13, fontFamily: 'Cairo'))),
    Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: .08))),
  ]);

  // ── SUPPORT ───────────────────────────────────────────────
  Widget _supportSection() => Column(children: [
    Text('الدعم الفني', style: TextStyle(
        color: _textFaint, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
    const SizedBox(height: 14),
    Row(children: [
      Expanded(child: _SupCard(name: 'Mahmoud', phone: '01105263199',
          intl: '+201105263199', onOpen: _wa)),
      const SizedBox(width: 12),
      Expanded(child: _SupCard(name: 'Mazen', phone: '01022731089',
          intl: '+201022731089', onOpen: _wa)),
    ]),
  ]);

}

// ══════════════════════════════════════════════════════════
// CYBERPUNK GLASS INPUT
// ══════════════════════════════════════════════════════════
class _Input extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSub;

  const _Input({required this.controller, required this.hint, required this.icon,
      this.obscure = false, this.suffix, this.keyboardType, this.onSub});

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0x1A00E5FF),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0000E5FF).withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: TextField(
          controller: widget.controller,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
            filled: true,
            fillColor: Colors.transparent,
            prefixIcon: Icon(widget.icon, color: const Color(0xFF00E5FF), size: 22),
            prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 50),
            suffixIcon: widget.suffix,
            suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF00E5FF).withValues(alpha: 0.3), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 2.2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          ),
          onSubmitted: widget.onSub,
        ),
      );
  }
}

// ══════════════════════════════════════════════════════════
// SUPPORT CARD
// ══════════════════════════════════════════════════════════
class _SupCard extends StatefulWidget {
  final String name, phone, intl;
  final Future<void> Function(String) onOpen;
  const _SupCard({required this.name, required this.phone,
      required this.intl, required this.onOpen});

  @override
  State<_SupCard> createState() => _SupCardState();
}

class _SupCardState extends State<_SupCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onOpen(widget.intl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _h ? const Color(0xFF25D366).withValues(alpha: .1) : Colors.white.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _h
                ? const Color(0xFF25D366).withValues(alpha: .4)
                : Colors.white.withValues(alpha: .08)),
            boxShadow: _h ? [BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: .12), blurRadius: 14)] : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FaIcon(FontAwesomeIcons.whatsapp, size: 18,
                color: _h ? const Color(0xFF25D366) : const Color(0xFF25D366).withValues(alpha: .6)),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.name, style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                Text(widget.phone, style: TextStyle(
                    color: Colors.white.withValues(alpha: .45), fontSize: 11, fontFamily: 'Cairo')),
              ],
            )),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// HOVER SCALE WRAPPER
// ══════════════════════════════════════════════════════════
class _HoverScale extends StatefulWidget {
  final Widget child;
  const _HoverScale({required this.child});

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _h ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// FLOATING PARTICLES
// ══════════════════════════════════════════════════════════
class _ParticlesPainter extends CustomPainter {
  final double t;
  _ParticlesPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..style = PaintingStyle.fill;
    final rng = Random(42);

    for (int i = 0; i < 35; i++) {
      final x = rng.nextDouble() * s.width;
      final by = rng.nextDouble() * s.height;
      final y = (by + t * 60 * (i % 3 + 1)) % s.height;
      final r = rng.nextDouble() * 1.5 + .4;
      final a = rng.nextDouble() * .1 + .03;
      p.color = i % 3 == 0
          ? _cyan.withValues(alpha: a)
          : i % 3 == 1
              ? _teal.withValues(alpha: a)
              : Colors.white.withValues(alpha: a * .6);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter o) => o.t != t;
}
