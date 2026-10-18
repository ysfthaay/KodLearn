import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/course_content.dart';
import '../widgets/staggered_fade_in.dart';

// Design tokens — kept in sync with the rest of the app.
const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kBg          = Color(0xFFE3E2E2);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);

/// Per-topic theory / tutorial page reachable at `/context/:topicId`.
///
/// The catalog of topics lives in [kCourseContent]. The detailed content
/// (theory text, examples, diagrams, tutorial steps) is intentionally left
/// as placeholder sections — they'll be filled in later. The page is built
/// so that swapping a placeholder for real content is a localized edit.
class ContextPage extends StatelessWidget {
  final String topicId;

  const ContextPage({super.key, required this.topicId});

  @override
  Widget build(BuildContext context) {
    final hit = findTopicById(topicId);

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: hit == null
            ? _NotFound(topicId: topicId)
            : _TopicView(topic: hit.topic, chapter: hit.chapter),
      ),
    );
  }
}

class _TopicView extends StatelessWidget {
  final CourseTopic topic;
  final CourseChapter chapter;
  const _TopicView({required this.topic, required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: StaggeredGroup(
            interval: const Duration(milliseconds: 75),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Top nav row ──
                StaggeredChild(
                  index: 0,
                  child: Row(
                    children: [
                      _BackTile(onTap: () => context.go('/dashboard')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          chapter.title,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _kAccent.withOpacity(0.85),
                            letterSpacing: 0.4,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Hero card with topic title ──
                StaggeredChild(
                  index: 1,
                  child: _HeroCard(topic: topic, chapter: chapter),
                ),
                const SizedBox(height: 22),

                // ── Theory / explanation placeholder ──
                StaggeredChild(
                  index: 2,
                  child: _Section(
                    icon: Icons.menu_book_rounded,
                    title: 'Konu Açıklaması',
                    body: const _PlaceholderText(
                      'Bu konunun ayrıntılı açıklaması yakında burada olacak. '
                      'Temel kavramlar, sentaks ve C dilindeki kullanımı '
                      'adım adım anlatılacak.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Code example placeholder ──
                StaggeredChild(
                  index: 3,
                  child: _Section(
                    icon: Icons.code_rounded,
                    title: 'Örnek Kod',
                    body: const _CodePlaceholder(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Detailed walkthrough placeholder ──
                StaggeredChild(
                  index: 4,
                  child: _Section(
                    icon: Icons.school_rounded,
                    title: 'Detaylı Anlatım',
                    body: const _PlaceholderText(
                      'Bu bölüme yakında çoklu adımlı, görsel destekli '
                      'bir anlatım eklenecek. Şimdilik bir yer tutucu.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── CTA: jump to practice ──
                StaggeredChild(
                  index: 5,
                  child: _PracticeCta(onTap: () => context.go('/dashboard')),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────────────────────

class _BackTile extends StatefulWidget {
  final VoidCallback onTap;
  const _BackTile({required this.onTap});

  @override
  State<_BackTile> createState() => _BackTileState();
}

class _BackTileState extends State<_BackTile> {
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
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(_hovered ? -2 : 0, 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kAccent.withOpacity(0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_hovered ? 0.10 : 0.06),
                blurRadius: _hovered ? 18 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: _kAccent, size: 15),
              ),
              const SizedBox(width: 10),
              const Text(
                "Dashboard'a Dön",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final CourseTopic topic;
  final CourseChapter chapter;
  const _HeroCard({required this.topic, required this.chapter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kAccent, _kAccentLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _kAccent.withOpacity(0.36),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: _kAccent.withOpacity(0.18),
            blurRadius: 60,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: const Icon(Icons.code_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapter.title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  topic.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.tag_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        // Visible to the user, also matches the route segment.
                        // Useful while content is sparse.
                        'Konu Kimliği',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  topic.id,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget body;
  const _Section({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kAccent.withOpacity(0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: _kAccent.withOpacity(0.04),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _kAccent, size: 17),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kText,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

class _PlaceholderText extends StatelessWidget {
  final String text;
  const _PlaceholderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _kAccent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _kAccent.withOpacity(0.18),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.construction_rounded, size: 16, color: _kAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: _kSubtitle,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodePlaceholder extends StatelessWidget {
  const _CodePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '// Örnek kod bloğu yakında buraya eklenecek.\n'
        '// printf("Hello, KodLearn!\\n");',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFF98C379),
          height: 1.55,
        ),
      ),
    );
  }
}

class _PracticeCta extends StatefulWidget {
  final VoidCallback onTap;
  const _PracticeCta({required this.onTap});

  @override
  State<_PracticeCta> createState() => _PracticeCtaState();
}

class _PracticeCtaState extends State<_PracticeCta> {
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
          duration: const Duration(milliseconds: 160),
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kAccent.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _kAccent.withOpacity(_hovered ? 0.22 : 0.12),
                blurRadius: _hovered ? 24 : 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_kAccent, _kAccentLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.fitness_center_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pratik yapmaya hazır mısın?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _kText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Dashboard'daki problemlerle bu konuyu pekiştir.",
                      style: TextStyle(fontSize: 12, color: _kSubtitle),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: _kAccent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  final String topicId;
  const _NotFound({required this.topicId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _kAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.search_off_rounded, color: _kAccent, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Konu bulunamadı',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Bu kimlikte bir konu yok: \"$topicId\".",
                style: const TextStyle(color: _kSubtitle, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              _BackTile(onTap: () => context.go('/dashboard')),
            ],
          ),
        ),
      ),
    );
  }
}
