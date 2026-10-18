import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'staggered_fade_in.dart';

// Design tokens — matched to the rest of the app.
const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);
const _kDanger      = Color(0xFFEF4444);
const _kSuccess     = Color(0xFF10B981);

/// Card-only verify-email surface. Lives inside an overlay on top of the
/// login page (no Scaffold — that's the parent's job).
///
/// Polls `currentUser.reload()` every 5 seconds. When the user clicks the
/// verification link in their mail and the flag flips, the modal calls
/// [onVerified] so the parent can dismiss the overlay and navigate on.
/// [onClose] is invoked when the user hits "Çıkış yap" — the parent should
/// sign out and dismiss.
class VerifyEmailModal extends StatefulWidget {
  final VoidCallback onVerified;
  final VoidCallback onClose;

  const VerifyEmailModal({
    super.key,
    required this.onVerified,
    required this.onClose,
  });

  @override
  State<VerifyEmailModal> createState() => _VerifyEmailModalState();
}

class _VerifyEmailModalState extends State<VerifyEmailModal> {
  Timer? _pollTimer;
  bool _isChecking = false;
  bool _isResending = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _silentCheck());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<bool> _refreshAndCheck() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await user.reload();
      return FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _silentCheck() async {
    final verified = await _refreshAndCheck();
    if (verified && mounted) {
      _pollTimer?.cancel();
      widget.onVerified();
    }
  }

  Future<void> _manualCheck() async {
    setState(() {
      _isChecking = true;
      _errorMessage = '';
    });
    final verified = await _refreshAndCheck();
    if (!mounted) return;
    setState(() => _isChecking = false);

    if (verified) {
      _pollTimer?.cancel();
      widget.onVerified();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Henüz doğrulanmamış görünüyor — mailindeki linke tıkladığından emin ol.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: _kDanger,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _errorMessage = '';
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Doğrulama maili tekrar gönderildi.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: _kSuccess,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.code == 'too-many-requests'
          ? 'Çok sık deneme yapıldı. Birkaç dakika sonra tekrar dene.'
          : (e.message ?? 'Bir hata oluştu'));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _kAccent.withOpacity(0.20), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: _kAccent.withOpacity(0.12),
              blurRadius: 60,
              spreadRadius: 4,
            ),
          ],
        ),
        child: StaggeredGroup(
          interval: const Duration(milliseconds: 65),
          startDelay: const Duration(milliseconds: 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              StaggeredChild(
                index: 0,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_kAccent, _kAccentLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withOpacity(0.42),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mark_email_read_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              StaggeredChild(
                index: 1,
                child: const Text(
                  'E-postanı Doğrula',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _kText,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              StaggeredChild(
                index: 2,
                child: const Text(
                  'Doğrulama bağlantısını şu adrese gönderdik:',
                  style: TextStyle(fontSize: 12, color: _kSubtitle),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              StaggeredChild(
                index: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _kAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kAccent.withOpacity(0.25)),
                  ),
                  child: Text(
                    email,
                    style: const TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              StaggeredChild(
                index: 4,
                child: const Text(
                  'Mailindeki linke tıkladıktan sonra "Doğruladım" butonuna bas — '
                  'doğrulamayı algıladığımızda otomatik devam edeceğiz.',
                  style: TextStyle(fontSize: 12, color: _kSubtitle, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _kDanger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kDanger.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 16, color: _kDanger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: _kDanger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              StaggeredChild(
                index: 5,
                child: _PrimaryButton(
                  label: _isChecking ? 'Kontrol ediliyor…' : 'Doğruladım, kontrol et',
                  icon: Icons.refresh_rounded,
                  isLoading: _isChecking,
                  onTap: _isChecking ? null : _manualCheck,
                ),
              ),
              const SizedBox(height: 10),
              StaggeredChild(
                index: 6,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isResending ? null : _resend,
                        icon: _isResending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _kAccent,
                                ),
                              )
                            : const Icon(Icons.outgoing_mail, size: 16, color: _kAccent),
                        label: const Text(
                          'Tekrar gönder',
                          style: TextStyle(
                            color: _kAccent,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          side: BorderSide(color: _kAccent.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onClose,
                        icon: const Icon(
                          Icons.logout_rounded,
                          size: 16,
                          color: _kSubtitle,
                        ),
                        label: const Text(
                          'Çıkış yap',
                          style: TextStyle(
                            color: _kSubtitle,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          side: BorderSide(color: Colors.black.withOpacity(0.12)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onTap;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
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
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kAccent, _kAccentLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withOpacity(_hovered ? 0.45 : 0.28),
                blurRadius: _hovered ? 20 : 14,
                offset: Offset(0, _hovered ? 8 : 5),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
