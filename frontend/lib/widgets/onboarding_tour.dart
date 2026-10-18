import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'staggered_fade_in.dart';

// Design tokens.
const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);

/// Four-step welcome tour shown to first-time users on the dashboard.
///
/// Persists completion via the `onboardingCompleted` boolean on the user's
/// Firestore doc. Call [maybeShow] from the dashboard's initState (after the
/// user-data load completes) — it will only fire if the flag is false.
class OnboardingTour {
  OnboardingTour._();

  /// Reads the user doc and pops the tour if and only if
  /// `onboardingCompleted` is not already true.
  static Future<void> maybeShow(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final done = snap.data()?['onboardingCompleted'] == true;
      if (done) return;
      if (!context.mounted) return;
      await _runTour(context, ref);
    } catch (e) {
      // Never let the tour block the dashboard.
      debugPrint('OnboardingTour skipped: $e');
    }
  }

  static Future<void> _runTour(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.55),
      barrierDismissible: false,
      barrierLabel: 'Tur',
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => _TourSheet(
        onFinish: () async {
          try {
            await userRef.set(
              {'onboardingCompleted': true},
              SetOptions(merge: true),
            );
          } catch (_) {}
        },
      ),
    );
  }
}

class _TourStep {
  final IconData icon;
  final String title;
  final String body;
  final String highlight; // a Turkish keyword to bold
  const _TourStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.highlight,
  });
}

const _kSteps = <_TourStep>[
  _TourStep(
    icon: Icons.menu_book_rounded,
    title: 'Konuları keşfet',
    body:
        "Sol kenardaki 'C Programlama' menüsünden bölümleri açabilir, her "
        "konunun teori sayfasına gidebilirsin.",
    highlight: 'Bu menüden konuları keşfet',
  ),
  _TourStep(
    icon: Icons.code_rounded,
    title: 'Problemleri çöz',
    body:
        "Merkezdeki problem listesinden seçtiğin soruyu açıp editörde C "
        "kodunu yaz. Her doğru cevap puan kazandırır.",
    highlight: 'Problemleri buradan çöz',
  ),
  _TourStep(
    icon: Icons.chat_bubble_outline_rounded,
    title: "Koda'ya sor",
    body:
        "Editörde takılırsan sağdaki Koda asistanına soru sorabilir, "
        "'İpucu Al' butonuyla satır bazında ipucu isteyebilirsin.",
    highlight: "Koda'ya soru sor",
  ),
  _TourStep(
    icon: Icons.local_fire_department_rounded,
    title: 'Serini koru',
    body:
        "Her gün uğradığında günlük seri büyür. Sağ kenardaki ateş simgesi "
        "kaç gün üst üste çalıştığını gösterir.",
    highlight: 'Kazandıkça seri büyür',
  ),
];

class _TourSheet extends StatefulWidget {
  final Future<void> Function() onFinish;
  const _TourSheet({required this.onFinish});

  @override
  State<_TourSheet> createState() => _TourSheetState();
}

class _TourSheetState extends State<_TourSheet> {
  int _index = 0;
  bool _finishing = false;

  bool get _isLast => _index >= _kSteps.length - 1;

  Future<void> _close() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await widget.onFinish();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _next() {
    if (_isLast) {
      _close();
    } else {
      setState(() => _index++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _kSteps[_index];
    return Stack(
      children: [
        // Extra backdrop blur on top of the showGeneralDialog dim.
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: const SizedBox.expand(),
        ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _kAccent.withOpacity(0.18), width: 1.5),
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
                  // AnimatedSwitcher cross-fades the step contents whenever
                  // _index changes so the tour feels alive.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                                begin: const Offset(0.04, 0), end: Offset.zero)
                            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_index),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StaggeredGroup(
                          interval: const Duration(milliseconds: 70),
                          startDelay: const Duration(milliseconds: 60),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StaggeredChild(
                                index: 0,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [_kAccent, _kAccentLight],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _kAccent.withOpacity(0.38),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Icon(step.icon,
                                          color: Colors.white, size: 26),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _kAccent.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        '${_index + 1} / ${_kSteps.length}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: _kAccent,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              StaggeredChild(
                                index: 1,
                                child: Text(
                                  step.title,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: _kText,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              StaggeredChild(
                                index: 2,
                                child: Text(
                                  step.highlight,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: _kAccent.withOpacity(0.85),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              StaggeredChild(
                                index: 3,
                                child: Text(
                                  step.body,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _kSubtitle,
                                    height: 1.55,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Step indicator pills.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_kSteps.length, (i) {
                            final active = i == _index;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 20 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? _kAccent
                                    : _kAccent.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _finishing ? null : _close,
                              style: TextButton.styleFrom(
                                foregroundColor: _kSubtitle,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                              child: const Text(
                                'Atla',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Spacer(),
                            _NextButton(
                              isLast: _isLast,
                              isLoading: _finishing,
                              onTap: _next,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NextButton extends StatefulWidget {
  final bool isLast;
  final bool isLoading;
  final VoidCallback onTap;

  const _NextButton({
    required this.isLast,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kAccent, _kAccentLight],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withOpacity(_hovered ? 0.45 : 0.25),
                blurRadius: _hovered ? 18 : 12,
                offset: Offset(0, _hovered ? 6 : 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Text(
                  widget.isLast ? 'Hadi başlayalım' : 'İleri',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                  ),
                ),
              if (!widget.isLoading) ...[
                const SizedBox(width: 6),
                Icon(
                  widget.isLast
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  size: 15,
                  color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
