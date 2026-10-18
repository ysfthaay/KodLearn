import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../data/course_content.dart';
import '../data/problems.dart';

const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);

/// Wrap the app body in [GlobalShortcuts] for Cmd+K / Ctrl+K. Opens
/// the command palette modal from anywhere in the app.
class GlobalShortcuts extends StatelessWidget {
  final Widget child;
  const GlobalShortcuts({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        // Cmd on macOS, Ctrl on Windows/Linux/web. Both bind to the same
        // intent so the shortcut feels native everywhere.
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): const _OpenPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true): const _OpenPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
            onInvoke: (_) {
              // The context captured by `Actions` is above the Navigator (we
              // live at the MaterialApp.router builder level), so it can't
              // be used directly with `showGeneralDialog`. The currently-
              // focused widget's context is always below the Navigator
              // (Navigator's FocusScope, a focused TextField, etc.), so it's
              // a safe lookup. Falls back to the outer context only if no
              // widget claims focus — unusual, but safer than crashing.
              final ctx = FocusManager.instance.primaryFocus?.context ?? context;
              _openPalette(ctx);
              return null;
            },
          ),
        },
        // No explicit Focus(autofocus: true) here — the Navigator inside
        // MaterialApp.router already establishes its own FocusScope, so
        // unhandled keystrokes bubble up through this Shortcuts ancestor
        // naturally. Calling autofocus at this level would request focus
        // before the routed page has been laid out, which trips the
        // RenderBox-size assertion in focus_traversal during the first frame.
        child: child,
      ),
    );
  }
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}

void _openPalette(BuildContext context) {
  // Fizzle if a palette is already open.
  if (ModalRoute.of(context)?.settings.name == '_command_palette') return;
  showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.35),
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    transitionDuration: const Duration(milliseconds: 180),
    routeSettings: const RouteSettings(name: '_command_palette'),
    pageBuilder: (ctx, _, __) => const _CommandPalette(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.05), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// The palette itself.
// ─────────────────────────────────────────────────────────────────────────────

enum _ItemKind { page, topic, problem }

class _PaletteItem {
  final _ItemKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final String path;
  const _PaletteItem({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.path,
  });
}

List<_PaletteItem> _allItems() {
  final out = <_PaletteItem>[
    const _PaletteItem(
      kind: _ItemKind.page,
      title: 'Dashboard',
      subtitle: 'Ana ekran',
      icon: Icons.dashboard_rounded,
      path: '/dashboard',
    ),
    const _PaletteItem(
      kind: _ItemKind.page,
      title: 'Profil',
      subtitle: 'İstatistikler ve ilerleme',
      icon: Icons.person_outline_rounded,
      path: '/profile',
    ),
  ];
  for (final ch in kCourseContent) {
    for (final t in ch.topics) {
      out.add(_PaletteItem(
        kind: _ItemKind.topic,
        title: t.title,
        subtitle: ch.title,
        icon: Icons.menu_book_rounded,
        path: '/context/${t.id}',
      ));
    }
  }
  for (final p in kProblems) {
    out.add(_PaletteItem(
      kind: _ItemKind.problem,
      title: p.title,
      subtitle: '${p.topic} · ${p.difficulty}',
      icon: Icons.code_rounded,
      path: '/editor',
      // problem-objects-as-extra are passed at navigation time; see _open
    ));
  }
  return out;
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Returns matched items ordered by:
///  1. title startsWith query (highest)
///  2. title contains query
///  3. subtitle contains query
List<_PaletteItem> _filterAndRank(List<_PaletteItem> all, String rawQuery) {
  final q = _norm(rawQuery);
  if (q.isEmpty) return all.take(12).toList();
  final scored = <(int, _PaletteItem)>[];
  for (final it in all) {
    final title = _norm(it.title);
    final sub = _norm(it.subtitle);
    int score;
    if (title.startsWith(q)) {
      score = 3;
    } else if (title.contains(q)) {
      score = 2;
    } else if (sub.contains(q)) {
      score = 1;
    } else {
      continue;
    }
    scored.add((score, it));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return scored.take(20).map((e) => e.$2).toList();
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette();

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  late final FocusNode _focus;
  final _controller = TextEditingController();
  late List<_PaletteItem> _all;
  late List<_PaletteItem> _results;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _all = _allItems();
    _results = _filterAndRank(_all, '');
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() {
      _results = _filterAndRank(_all, q);
      _activeIndex = 0;
    });
  }

  void _select(_PaletteItem it) {
    Navigator.of(context).pop();
    if (it.kind == _ItemKind.problem) {
      // Find the raw problem map so the editor can read .extra as before.
      final p = kProblems.firstWhere((p) => p.title == it.title);
      context.go('/editor', extra: {
        'id': p.id,
        'title': p.title,
        'difficulty': p.difficulty,
        'topic': p.topic,
        'chapterIndex': p.chapterIndex,
      });
    } else {
      context.go(it.path);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _activeIndex = (_activeIndex + 1).clamp(0, _results.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _activeIndex = (_activeIndex - 1).clamp(0, _results.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_results.isNotEmpty) _select(_results[_activeIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        // Blurred backdrop so the palette feels like it floats over the page.
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: const SizedBox.expand(),
        ),
        // Anchor near the top of the viewport, like Spotlight.
        Padding(
          padding: EdgeInsets.only(top: mq.padding.top + 120),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _kAccent.withOpacity(0.18), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.20),
                          blurRadius: 40,
                          offset: const Offset(0, 18),
                        ),
                        BoxShadow(
                          color: _kAccent.withOpacity(0.10),
                          blurRadius: 60,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Search row.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
                          child: Row(
                            children: [
                              const Icon(Icons.search_rounded,
                                  color: _kAccent, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Focus(
                                  onKeyEvent: _handleKey,
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focus,
                                    autofocus: true,
                                    onChanged: _onChanged,
                                    onSubmitted: (_) {
                                      if (_results.isNotEmpty) _select(_results[_activeIndex]);
                                    },
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: _kText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Konu, problem veya sayfa ara…',
                                      hintStyle: TextStyle(color: _kSubtitle, fontSize: 15),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'esc',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _kSubtitle,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0x14000000)),
                        // Results.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 380),
                          child: _results.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 28),
                                  child: Text(
                                    'Sonuç bulunamadı.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _kSubtitle,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _results.length,
                                  itemBuilder: (ctx, i) {
                                    final it = _results[i];
                                    final active = i == _activeIndex;
                                    return InkWell(
                                      onTap: () => _select(it),
                                      onHover: (h) {
                                        if (h) setState(() => _activeIndex = i);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 11),
                                        color: active
                                            ? _kAccent.withOpacity(0.08)
                                            : Colors.transparent,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 30,
                                              height: 30,
                                              decoration: BoxDecoration(
                                                color: _kAccent.withOpacity(0.10),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(it.icon, size: 16, color: _kAccent),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    it.title,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: active
                                                          ? FontWeight.w700
                                                          : FontWeight.w600,
                                                      color: _kText,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    it.subtitle,
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: _kSubtitle,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            _KindBadge(kind: it.kind),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        // Footer hints.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          color: Colors.black.withOpacity(0.025),
                          child: Row(
                            children: [
                              const _KbdHint(label: '↑↓', desc: 'gez'),
                              const SizedBox(width: 16),
                              const _KbdHint(label: '↵', desc: 'aç'),
                              const Spacer(),
                              Text(
                                '${_results.length} sonuç',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kSubtitle,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
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

class _KindBadge extends StatelessWidget {
  final _ItemKind kind;
  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (String label, Color bg, Color fg) = switch (kind) {
      _ItemKind.page    => ('Sayfa',    _kSubtitle.withOpacity(0.10), _kSubtitle),
      _ItemKind.topic   => ('Konu',     _kAccent.withOpacity(0.10),   _kAccent),
      _ItemKind.problem => ('Problem',  _kAccentLight.withOpacity(0.12), _kAccentLight),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _KbdHint extends StatelessWidget {
  final String label;
  final String desc;
  const _KbdHint({required this.label, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _kSubtitle,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          desc,
          style: const TextStyle(
            fontSize: 11,
            color: _kSubtitle,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
