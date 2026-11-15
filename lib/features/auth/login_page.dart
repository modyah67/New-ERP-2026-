import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_cubit.dart';
import '../../ui/widgets/safe_image.dart';
import '../../ui/widgets/theme_switcher_button.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? _navy : const Color(0xFFF8FAFC),
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
            _bg(isDark),
            if (isDark) _vignette(),
            if (isDark) Positioned.fill(child: CustomPaint(painter: _ParticlesPainter(_ac.value))),
            const Positioned(
              top: 16,
              left: 16,
              child: SafeArea(child: ThemeSwitcherButton()),
            ),
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
                          _novaBranding(isDark),
                          const SizedBox(height: 28),
                          _card(narrow, w, isDark),
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
  Widget _bg(bool isDark) => isDark
      ? Container(
          decoration: const BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [_navy, _navyLight, Color(0xFF0D1F3C), _navy],
          )),
          child: SafeImage('assets/images/login_bg.png', fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(.28)),
        )
      : Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFF8FAFC), Color(0xFFEDF2F7), Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
            ),
          ),
        );

  Widget _vignette() => Container(
    decoration: BoxDecoration(gradient: RadialGradient(
      center: Alignment.center, radius: 1.4,
      colors: [Colors.transparent, const Color(0xE00A1630)],
      stops: const [.2, 1],
    )),
  );

  // ── GLASS CARD ────────────────────────────────────────────
  Widget _card(bool narrow, double screenW, bool isDark) {
    final cardW = narrow ? double.infinity : min(screenW * 0.42, 480.0);
    return AnimatedBuilder(animation: _pulse, builder: (_, __) {
      return Container(
        width: cardW,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: isDark ? [
            BoxShadow(color: _cyan.withValues(alpha: _pulse.value * .18), blurRadius: 70, spreadRadius: -10),
            BoxShadow(color: _teal.withValues(alpha: _pulse.value * .1), blurRadius: 100, spreadRadius: -15),
            BoxShadow(color: Colors.black.withValues(alpha: .4), blurRadius: 40, offset: const Offset(0, 20)),
          ] : [
            BoxShadow(color: const Color(0x140F172A), blurRadius: 30, offset: const Offset(0, 10)),
            BoxShadow(color: const Color(0x0A0F172A), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: narrow ? 24 : 40, vertical: narrow ? 28 : 40),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x1E1A2A4A) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: isDark ? _glassBorder : const Color(0xFFCBD5E1), width: 1.5),
              ),
              child: Stack(children: [
                if (isDark) ...[
                  Positioned(top: -30, right: -30,
                      child: _glassOrb(80, const Color(0x0D00C2FF))),
                  Positioned(bottom: -40, left: -20,
                      child: _glassOrb(100, const Color(0x0A00E0B8))),
                  Positioned(top: 60, left: -20,
                      child: _glassOrb(50, const Color(0x08FFFFFF))),
                ],

                // ── Content ──
                BlocBuilder<AuthCubit, AuthState>(
                  builder: (_, state) {
                    final loading = state is AuthLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _logoRow(isDark),
                        const SizedBox(height: 20),
                        _titles(isDark),
                        const SizedBox(height: 30),
                        _fieldLabel('البريد الإلكتروني أو اسم المستخدم', isDark),
                        const SizedBox(height: 10),
                        _Input(controller: _identifier, 
                            hint: 'example@novasoft.com',
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            isDark: isDark,
                            onSub: (_) => _login()),
                        const SizedBox(height: 20),
                        _fieldLabel('كلمة المرور', isDark),
                        const SizedBox(height: 10),
                        _Input(controller: _password, hint: '••••••••',
                            icon: Icons.lock_outline_rounded, obscure: !_showPass,
                            suffix: _eyeToggle(isDark),
                            isDark: isDark,
                            onSub: (_) => _login()),
                        const SizedBox(height: 24),
                        _loginBtn(loading),
                        const SizedBox(height: 24),
                        _divider(isDark),
                        const SizedBox(height: 20),
                        _supportSection(isDark),
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
  Widget _novaBranding(bool isDark) => Column(
    children: [
      ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          colors: isDark
              ? const [Color(0xFF00C2FF), Color(0xFF00E0B8)]
              : const [Color(0xFF0284C7), Color(0xFF0D9488)],
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
          color: isDark ? Colors.white.withValues(alpha: .45) : Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 8,
          fontFamily: 'Cairo',
        ),
      ),
    ],
  );

  // ── LOGO ROW (image + FRUITY FARMS side by side) ────────
  Widget _logoRow(bool isDark) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SafeImage(
          'assets/images/preview.png',
          width: 72,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: isDark ? Colors.white.withValues(alpha: .08) : const Color(0x140F172A),
            ),
            child: const Icon(Icons.spa, color: _teal, size: 30),
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
              child: isDark
                  ? ShaderMask(
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
                    )
                  : const Text(
                      'FRUITY FARMS',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        fontFamily: 'Cairo',
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
  Widget _titles(bool isDark) => Column(children: [
    if (isDark)
      ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
        ).createShader(rect),
        child: const Text('تسجيل الدخول', style: TextStyle(
            color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold,
            fontFamily: 'Cairo')),
      )
    else
      const Text('تسجيل الدخول', style: TextStyle(
          color: Colors.black, fontSize: 26, fontWeight: FontWeight.bold,
          fontFamily: 'Cairo')),
    const SizedBox(height: 6),
    if (isDark)
      ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [Color(0xFF00C2FF), Color(0xFF00E0B8)],
        ).createShader(rect),
        child: Text('أدخل بريدك الإلكتروني أو اسم المستخدم', style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7), fontSize: 14,
            fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
      )
    else
      const Text('أدخل بريدك الإلكتروني أو اسم المستخدم', style: TextStyle(
          color: Colors.black, fontSize: 14,
          fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
  ]);

  Widget _fieldLabel(String t, bool isDark) => Align(
    alignment: Alignment.centerRight,
    child: Text(t, style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        fontFamily: 'Cairo')),
  );

  // ── EYE TOGGLE ────────────────────────────────────────────
  Widget _eyeToggle(bool isDark) => IconButton(
    icon: AnimatedSwitcher(duration: const Duration(milliseconds: 200),
      child: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          key: ValueKey(_showPass),
          color: isDark ? const Color(0xFF00E5FF).withValues(alpha: 0.7) : Colors.black87, size: 22)),
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

  // ── DIVIDER ───────────────────────────────────────────────
  Widget _divider(bool isDark) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    color: isDark ? Colors.white.withValues(alpha: .08) : const Color(0xFFE2E8F0),
  );

  // ── SUPPORT ───────────────────────────────────────────────
  Widget _supportSection(bool isDark) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Center(
        child: Text('الدعم الفني', style: TextStyle(
            color: isDark ? _textFaint : Colors.black,
            fontSize: 12,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 14),
      _SupCard(
        name: 'Mahmoud',
        phone: '01105263199',
        intl: '+201105263199',
        isDark: isDark,
        onOpen: _wa,
      ),
    ],
  );

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
  final bool isDark;

  const _Input({required this.controller, required this.hint, required this.icon,
      this.obscure = false, this.suffix, this.keyboardType, this.onSub, this.isDark = true});

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFF8FAFC),
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x0000E5FF).withValues(alpha: 0.05) : const Color(0x0A0F172A),
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
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.35) : const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            filled: true,
            fillColor: Colors.transparent,
            prefixIcon: Icon(widget.icon, color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7), size: 22),
            prefixIconConstraints: const BoxConstraints(minWidth: 50, minHeight: 50),
            suffixIcon: widget.suffix,
            suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF00E5FF).withValues(alpha: 0.3) : const Color(0xFFCBD5E1), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF00E5FF).withValues(alpha: 0.3) : const Color(0xFFCBD5E1), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7), width: 2.2),
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
  final bool isDark;
  const _SupCard({required this.name, required this.phone,
      required this.intl, required this.onOpen, this.isDark = true});

  @override
  State<_SupCard> createState() => _SupCardState();
}

class _SupCardState extends State<_SupCard> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onOpen(widget.intl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _h
                ? const Color(0xFF25D366).withValues(alpha: .12)
                : (isDark ? Colors.white.withValues(alpha: .04) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _h
                ? const Color(0xFF25D366).withValues(alpha: .45)
                : (isDark ? Colors.white.withValues(alpha: .08) : const Color(0xFFCBD5E1))),
            boxShadow: _h ? [BoxShadow(
                color: const Color(0xFF25D366).withValues(alpha: .14), blurRadius: 14)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(FontAwesomeIcons.whatsapp, size: 24,
                  color: _h ? const Color(0xFF25D366) : const Color(0xFF25D366).withValues(alpha: .9)),
              const SizedBox(width: 14),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.name, style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold)),
                  Text(widget.phone, style: TextStyle(
                      color: isDark ? Colors.white.withValues(alpha: .5) : const Color(0xFF475569),
                      fontSize: 12,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
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
