import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../widgets/staggered_fade_in.dart';
import '../widgets/verify_email_modal.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design tokens — kept in sync with profile_page.dart / dashboard_page.dart
// ─────────────────────────────────────────────────────────────────────────────
const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kBg          = Color(0xFFE3E2E2);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);
const _kDanger      = Color(0xFFEF4444);
const _kSuccess     = Color(0xFF10B981);

/// What the right-side panel is currently rendering. Switching values
/// triggers a stagger replay (via [StaggeredGroup.replayKey]) so the new
/// fields slide in instead of just popping.
enum _LoginPanelMode { login, register, forgotEntry, forgotSent }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();

  bool _isLoading = false;
  _LoginPanelMode _mode = _LoginPanelMode.login;
  String _errorMessage = '';

  // When true, the verify-email card floats over the page behind a blurred,
  // dimmed backdrop. Driven by initState (signed-in unverified user landing
  // on / ) and by _submit after a successful registration.
  bool _showVerifyOverlay = false;

  @override
  void initState() {
    super.initState();
    // The router redirects unverified signed-in users to / — surface the
    // modal immediately rather than dropping them onto an empty form.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.emailVerified) {
      _showVerifyOverlay = true;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Mode switching
  // ───────────────────────────────────────────────────────────────────────────

  void _switchMode(_LoginPanelMode next) {
    setState(() {
      _mode = next;
      _errorMessage = '';
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Submit (login / register)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final isRegister = _mode == _LoginPanelMode.register;
    if (isRegister) {
      if (_nameController.text.trim().isEmpty ||
          _surnameController.text.trim().isEmpty ||
          _emailController.text.trim().isEmpty ||
          _passwordController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Lütfen tüm alanları doldurun.');
        return;
      }
    } else {
      if (_emailController.text.trim().isEmpty ||
          _passwordController.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Email ve şifre boş olamaz.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (isRegister) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
          'email': _emailController.text.trim(),
          'name': _nameController.text.trim(),
          'surname': _surnameController.text.trim(),
          'joinDate': FieldValue.serverTimestamp(),
          'level': 'beginner',
          'totalScore': 0,
          'completedProblems': [],
        });
        try {
          await cred.user?.sendEmailVerification();
        } catch (e) {
          debugPrint('sendEmailVerification failed: $e');
        }
        // Don't navigate — keep the user here and float the verify modal.
        if (mounted) setState(() => _showVerifyOverlay = true);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (mounted) {
          final user = FirebaseAuth.instance.currentUser;
          if (user?.emailVerified ?? false) {
            context.go('/dashboard');
          } else {
            // Signed in but the address still isn't verified — overlay.
            setState(() => _showVerifyOverlay = true);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Bir hata oluştu');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Password reset — embedded panel state machine
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'E-posta adresi gir.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _mode = _LoginPanelMode.forgotSent);
    } on FirebaseAuthException catch (e) {
      // We deliberately do NOT leak whether the address has a registered
      // account — that would let attackers enumerate users. For
      // user-not-found we still show the success state.
      if (e.code == 'user-not-found') {
        if (mounted) setState(() => _mode = _LoginPanelMode.forgotSent);
      } else if (e.code == 'invalid-email') {
        setState(() => _errorMessage = 'Geçersiz e-posta adresi.');
      } else if (e.code == 'too-many-requests') {
        setState(() => _errorMessage = 'Çok sık deneme yapıldı. Birazdan tekrar dene.');
      } else {
        setState(() => _errorMessage = e.message ?? 'Bir hata oluştu.');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Bağlantı hatası.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Verify overlay callbacks
  // ───────────────────────────────────────────────────────────────────────────

  void _onEmailVerified() {
    if (!mounted) return;
    setState(() => _showVerifyOverlay = false);
    context.go('/dashboard');
  }

  Future<void> _onLogoutFromOverlay() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _showVerifyOverlay = false;
      _mode = _LoginPanelMode.login;
      _passwordController.clear();
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared visual pieces
  // ───────────────────────────────────────────────────────────────────────────

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kAccent.withOpacity(0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: _kAccent.withOpacity(0.12),
            blurRadius: 60,
            spreadRadius: 4,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildLogo({double size = 44, double iconSize = 26, double radius = 14}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.black, _kAccent, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: _kAccent.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Icon(Icons.code_rounded, color: Colors.white, size: iconSize),
    );
  }

  Widget _buildInput(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: _kText, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _kText.withOpacity(0.5), fontSize: 14),
        prefixIcon: Icon(icon, color: _kAccent.withOpacity(0.8), size: 20),
        filled: true,
        fillColor: _kAccent.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.18), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.18), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _kDanger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kDanger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: _kDanger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                color: _kDanger,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Per-mode panel children — same outer card, different inner contents.
  // Indices on the StaggeredChild widgets are stable across modes so the
  // sequence reads naturally each time.
  // ───────────────────────────────────────────────────────────────────────────

  List<Widget> _loginRegisterChildren() {
    final isRegister = _mode == _LoginPanelMode.register;
    return [
      StaggeredChild(
        index: 0,
        child: Text(
          isRegister ? 'Aramıza Katıl' : 'Tekrar Hoş Geldin',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.5,
          ),
        ),
      ),
      const SizedBox(height: 6),
      StaggeredChild(
        index: 1,
        child: Text(
          isRegister ? "KodLearn'de yeni bir hesap oluştur" : "KodLearn'e giriş yap",
          style: const TextStyle(
            fontSize: 14,
            color: _kSubtitle,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(height: 28),
      if (isRegister) ...[
        StaggeredChild(
          index: 2,
          child: Row(
            children: [
              Expanded(child: _buildInput(_nameController, 'Ad', Icons.person_outline_rounded)),
              const SizedBox(width: 12),
              Expanded(child: _buildInput(_surnameController, 'Soyad', Icons.person_outline_rounded)),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      StaggeredChild(
        index: 3,
        child: _buildInput(_emailController, 'Email', Icons.alternate_email_rounded),
      ),
      const SizedBox(height: 12),
      StaggeredChild(
        index: 4,
        child: _PasswordField(
          controller: _passwordController,
          hint: 'Şifre',
        ),
      ),
      // "Şifremi unuttum?" — login mode only. Now it swaps the panel
      // in-place instead of popping a dialog.
      if (!isRegister) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : () => _switchMode(_LoginPanelMode.forgotEntry),
            style: TextButton.styleFrom(
              foregroundColor: _kAccent,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Şifremi unuttum?',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _kAccent,
              ),
            ),
          ),
        ),
      ],
      if (_errorMessage.isNotEmpty) ...[
        const SizedBox(height: 14),
        _buildErrorBox(),
      ],
      const SizedBox(height: 24),
      StaggeredChild(
        index: 5,
        child: _SubmitButton(
          label: isRegister ? 'Kayıt Ol' : 'Giriş Yap',
          isLoading: _isLoading,
          onTap: _isLoading ? null : _submit,
        ),
      ),
      const SizedBox(height: 18),
      StaggeredChild(
        index: 6,
        child: Center(
          child: GestureDetector(
            onTap: () => _switchMode(
              isRegister ? _LoginPanelMode.login : _LoginPanelMode.register,
            ),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  color: _kSubtitle,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(text: isRegister ? 'Zaten hesabın var mı? ' : 'Hesabın yok mu? '),
                  TextSpan(
                    text: isRegister ? 'Giriş Yap' : 'Kayıt Ol',
                    style: const TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _forgotEntryChildren() {
    return [
      StaggeredChild(
        index: 0,
        child: Row(
          children: [
            _BackChip(onTap: () => _switchMode(_LoginPanelMode.login)),
            const Spacer(),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const StaggeredChild(
        index: 1,
        child: Text(
          'Şifreni mi Unuttun?',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.5,
          ),
        ),
      ),
      const SizedBox(height: 6),
      const StaggeredChild(
        index: 2,
        child: Text(
          'Hesabına bağlı e-posta adresini gir; sıfırlama bağlantısını oraya göndereceğiz.',
          style: TextStyle(
            fontSize: 13,
            color: _kSubtitle,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ),
      const SizedBox(height: 24),
      StaggeredChild(
        index: 3,
        child: _buildInput(_emailController, 'Email', Icons.alternate_email_rounded),
      ),
      if (_errorMessage.isNotEmpty) ...[
        const SizedBox(height: 14),
        _buildErrorBox(),
      ],
      const SizedBox(height: 24),
      StaggeredChild(
        index: 4,
        child: _SubmitButton(
          label: 'Bağlantı Gönder',
          isLoading: _isLoading,
          onTap: _isLoading ? null : _sendPasswordReset,
        ),
      ),
      const SizedBox(height: 14),
      StaggeredChild(
        index: 5,
        child: Center(
          child: GestureDetector(
            onTap: () => _switchMode(_LoginPanelMode.login),
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  color: _kSubtitle,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(text: 'Hatırladın mı? '),
                  TextSpan(
                    text: 'Giriş Yap',
                    style: TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _forgotSentChildren() {
    final email = _emailController.text.trim();
    return [
      StaggeredChild(
        index: 0,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _kSuccess.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kSuccess.withOpacity(0.35), width: 1.5),
          ),
          child: const Icon(Icons.mark_email_read_rounded,
              color: _kSuccess, size: 32),
        ),
      ),
      const SizedBox(height: 18),
      const StaggeredChild(
        index: 1,
        child: Text(
          'Bağlantıyı Gönderdik',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _kText,
            letterSpacing: -0.5,
          ),
        ),
      ),
      const SizedBox(height: 10),
      StaggeredChild(
        index: 2,
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13.5,
              color: _kSubtitle,
              fontWeight: FontWeight.w500,
              height: 1.55,
            ),
            children: [
              const TextSpan(text: 'Şifre sıfırlama bağlantısını '),
              TextSpan(
                text: email.isEmpty ? 'e-posta adresine' : email,
                style: const TextStyle(
                  color: _kAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const TextSpan(
                text: ' gönderdik. Mailini kontrol ederek yeni bir şifre belirleyebilirsin.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      StaggeredChild(
        index: 3,
        child: _SubmitButton(
          label: 'Giriş Ekranına Dön',
          isLoading: false,
          onTap: () => _switchMode(_LoginPanelMode.login),
        ),
      ),
    ];
  }

  List<Widget> _panelChildrenFor(_LoginPanelMode mode) {
    switch (mode) {
      case _LoginPanelMode.login:
      case _LoginPanelMode.register:
        return _loginRegisterChildren();
      case _LoginPanelMode.forgotEntry:
        return _forgotEntryChildren();
      case _LoginPanelMode.forgotSent:
        return _forgotSentChildren();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final leftPanel = Padding(
      padding: const EdgeInsets.fromLTRB(48, 40, 32, 48),
      child: StaggeredGroup(
        interval: const Duration(milliseconds: 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StaggeredChild(
              index: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLogo(),
                  const SizedBox(width: 14),
                  const Text(
                    'KodLearn',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(color: Colors.black38, offset: Offset(0, 4), blurRadius: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            StaggeredChild(
              index: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'C ile sıfırdan ileri seviyeye',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            StaggeredChild(
              index: 2,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -1.5,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.35), offset: const Offset(0, 4), blurRadius: 18),
                    ],
                  ),
                  children: const [
                    TextSpan(text: 'Kodlama dünyasını\n'),
                    TextSpan(text: 'keşfet, geleceğini\n'),
                    TextSpan(text: 'şekillendir.', style: TextStyle(color: _kAccentLight)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            StaggeredChild(
              index: 3,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  'Adım adım problemler, anlık geri bildirim ve seninle birlikte büyüyen bir yolculuk.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.4), offset: const Offset(0, 2), blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );

    final rightPanel = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: SizedBox(
          width: 440,
          child: _buildCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 36),
              // replayKey: any mode change re-runs the stagger so the new
              // panel slides in. This is what gives the login ↔ forgot ↔
              // sent transitions their seamless, animated feel.
              child: StaggeredGroup(
                replayKey: ValueKey(_mode),
                interval: const Duration(milliseconds: 65),
                itemDuration: const Duration(milliseconds: 460),
                slideOffset: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _panelChildrenFor(_mode),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background video, fully isolated.
          const _LoginVideoBackground(),

          // Static darkening overlay so the hero text reads against the
          // brighter parts of the video.
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withOpacity(0.45),
                    Colors.black.withOpacity(0.15),
                  ],
                ),
              ),
            ),
          ),

          // Main login content.
          if (isDesktop)
            Row(
              children: [
                Expanded(flex: 5, child: leftPanel),
                Expanded(flex: 4, child: rightPanel),
              ],
            )
          else
            rightPanel,

          // Verify-email overlay — sits on top of the rest of the page,
          // blurs everything behind it, centres the modal. We use
          // AnimatedSwitcher so it fades in/out smoothly without leaving
          // the BackdropFilter around when dismissed.
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_showVerifyOverlay,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                child: _showVerifyOverlay
                    ? _VerifyOverlayBackdrop(
                        key: const ValueKey('verify-overlay-on'),
                        child: VerifyEmailModal(
                          onVerified: _onEmailVerified,
                          onClose: _onLogoutFromOverlay,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('verify-overlay-off')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small "← geri" chip used in the forgot-password panel header so the user
// has an obvious way back to login without scrolling to the bottom.
// ─────────────────────────────────────────────────────────────────────────────
class _BackChip extends StatefulWidget {
  final VoidCallback onTap;
  const _BackChip({required this.onTap});

  @override
  State<_BackChip> createState() => _BackChipState();
}

class _BackChipState extends State<_BackChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(_hovered ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kAccent.withOpacity(_hovered ? 0.4 : 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.arrow_back_rounded, size: 14, color: _kAccent),
              SizedBox(width: 6),
              Text(
                'Geri',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _kAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen verify-email backdrop. Blurs everything behind it, dims with a
// translucent black, centres a [VerifyEmailModal]. Tapping outside the modal
// is a no-op — closing the modal happens via Çıkış yap.
// ─────────────────────────────────────────────────────────────────────────────
class _VerifyOverlayBackdrop extends StatelessWidget {
  final Widget child;
  const _VerifyOverlayBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.black.withOpacity(0.45)),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submit button with subtle hover state — same family as the dashboard's
// _HoverNavButton, just shaped for a primary CTA.
// ─────────────────────────────────────────────────────────────────────────────
class _SubmitButton extends StatefulWidget {
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  const _SubmitButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) { if (enabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kAccent, _kAccentLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withOpacity(_hovered ? 0.45 : 0.25),
                blurRadius: _hovered ? 22 : 14,
                offset: Offset(0, _hovered ? 8 : 5),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Password input with a visibility toggle. Internally tracks `obscureText`
// state so the parent doesn't have to. Styled identically to _buildInput so
// it lines up with the email field above it.
// ─────────────────────────────────────────────────────────────────────────────
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;

  const _PasswordField({required this.controller, required this.hint});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      style: const TextStyle(fontSize: 14, color: _kText, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(color: _kText.withOpacity(0.5), fontSize: 14),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: _kAccent.withOpacity(0.8),
          size: 20,
        ),
        suffixIcon: IconButton(
          tooltip: _obscured ? 'Şifreyi göster' : 'Şifreyi gizle',
          splashRadius: 18,
          icon: Icon(
            _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: _kSubtitle,
            size: 20,
          ),
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
        filled: true,
        fillColor: _kAccent.withOpacity(0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.18), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.18), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background video, fully isolated (same pattern as dashboard).
// Owns its own State + controller; the parent's setState() can never reach
// it because the call site is `const _LoginVideoBackground()`.
// ─────────────────────────────────────────────────────────────────────────────
class _LoginVideoBackground extends StatefulWidget {
  const _LoginVideoBackground();

  @override
  State<_LoginVideoBackground> createState() => _LoginVideoBackgroundState();
}

class _LoginVideoBackgroundState extends State<_LoginVideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.asset('assets/1030.OrangeInk-375w-812h.mp4');
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c
        ..setVolume(0.0)
        ..setLooping(true)
        ..play();
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (!_ready || c == null) {
      return Container(color: const Color(0xFF1A0F08));
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}
