import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../data/course_content.dart';
import '../data/problems.dart';
import '../widgets/onboarding_tour.dart';
import '../widgets/staggered_fade_in.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // ── YÜKLEME DURUMU EKLENDİ ──
  bool _isLoading = true;

  String _userName = '';
  String _userLevel = 'beginner';
  List<String> _unlockedDifficulties = ['Kolay'];
  // New authoritative gate: list of problem ids the backend says are
  // currently reachable. Computed per-chapter sequentially. The legacy
  // `_unlockedDifficulties` field is still read for backward-compat with
  // older backend responses.
  List<String> _unlockedProblems = [];
  List<String> _completedProblems = [];

  bool _filterKolay = false;
  bool _filterOrta = false;
  bool _filterZor = false;
  bool _filterCompleted = false;
  bool _filterLocked = false;

  int _currentStreak = 0;
  DateTime? _lastLoginDate;
  // Indices 0..6 (Mon..Sun) of the *current* calendar week on which the user
  // has logged in. Populated from /api/code/streak; falls back to the
  // inference-from-streak path if the field is missing.
  List<int> _weekActiveDays = const [];

  List<Map<String, dynamic>> _leaders = [];
  bool _leadersLoading = true;

  int _quickTipIndex = 0;
  Timer? _quickTipTimer;
  static const List<String> _quickTips = [
    'C programlamada pointerlar bellek yönetiminin temelidir. Verinin adresini tutarlar.',
    '`scanf` kullanırken değişkenin adresini (&) vermeyi unutma.',
    '`malloc` ile aldığın belleği `free` ile mutlaka geri ver.',
    'Dizi adı, dizinin ilk elemanına işaret eden bir pointer gibi davranır.',
    'String\'lerin sonunda \'\\0\' (null terminator) karakteri vardır.',
    'Fonksiyona pointer geçerek değişkeni doğrudan değiştirebilirsin.',
    '`const` ile pointer\'ın işaret ettiği değeri salt-okunur yapabilirsin.',
    '`printf`\'te yanlış format tutucusu kullanmak (örn. %d yerine %f) tanımsız davranıştır.',
    '`switch-case`\'de her case sonuna `break` koymayı unutma, yoksa fall-through olur.',
    'Struct\'lar ilişkili verileri tek bir tip altında toplamak için kullanılır.',
  ];

  int _currentTopicIndex = 0;

  // Shared with the profile page and the command palette via
  // lib/data/problems.dart. Returns Map<String, dynamic> for backward-compat
  // with the existing dashboard call sites that index with ['id'] etc.
  final List<Map<String, dynamic>> problems = kProblemsAsLegacyMap();

  // Imported from lib/data/course_content.dart — same catalog as the
  // Context page so topic ids stay consistent across both surfaces.
  final List<CourseChapter> _courseContent = kCourseContent;

  // True when the backend has explicitly listed this problem as reachable,
  // OR (legacy fallback for older /level responses) when the difficulty
  // tier is unlocked.
  bool _isProblemUnlocked(Map<String, dynamic> problem) {
    if (_unlockedProblems.isNotEmpty) {
      return _unlockedProblems.contains(problem['id']);
    }
    return _unlockedDifficulties.contains(problem['difficulty']);
  }

  List<Map<String, dynamic>> get _filteredProblems {
    return problems.where((problem) {
      if (problem['chapterIndex'] != _currentTopicIndex) return false;

      final isUnlocked = _isProblemUnlocked(problem);
      final isCompleted = _completedProblems.contains(problem['id']);
      final diff = problem['difficulty'];

      final diffFiltersActive = _filterKolay || _filterOrta || _filterZor;
      bool matchesDiff = true;
      if (diffFiltersActive) {
        matchesDiff = (_filterKolay && diff == 'Kolay') ||
                      (_filterOrta && diff == 'Orta') ||
                      (_filterZor && diff == 'Zor');
      }

      bool matchesCompleted = _filterCompleted ? isCompleted : true;
      bool matchesLocked = _filterLocked ? !isUnlocked : true;

      return matchesDiff && matchesCompleted && matchesLocked;
    }).toList();
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _saveUserProfile();
    _loadUserLevel();
    _loadLeaderboard();

    _quickTipTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _quickTipIndex = (_quickTipIndex + 1) % _quickTips.length;
      });
    });
  }

  @override
  void dispose() {
    _quickTipTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveUserProfile() async {
    final user = _user;
    if (user == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();
    if (!doc.exists) {
      await docRef.set({
        'email': user.email,
        'joinDate': FieldValue.serverTimestamp(),
        'level': 'beginner',
        'totalScore': 0,
        'completedProblems': [],
      });
    }
  }

  Future<void> _loadUserLevel() async {
    final user = _user;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final results = await Future.wait([
        http.get(Uri.parse('http://localhost:3000/api/code/level/${user.uid}')),
        FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        http.post(
          Uri.parse('http://localhost:3000/api/code/streak'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'uid': user.uid}),
        ),
      ]);

      final response = results[0] as http.Response;
      final doc = results[1] as DocumentSnapshot;
      final streakResponse = results[2] as http.Response;

      final data = jsonDecode(response.body);
      final userData = doc.data() as Map<String, dynamic>?;
      final streakData = jsonDecode(streakResponse.body);

      if (mounted) {
        setState(() {
          _userLevel = data['level'] ?? 'beginner';
          _unlockedDifficulties = List<String>.from(data['unlockedDifficulties'] ?? ['Kolay']);
          _unlockedProblems = List<String>.from(data['unlockedProblems'] ?? const []);
          _completedProblems = List<String>.from(data['completedProblems'] ?? []);
          _userName = '${userData?['name'] ?? ''} ${userData?['surname'] ?? ''}'.trim();
          _currentStreak = streakData['streak'] ?? 0;
          final lastLoginMs = streakData['lastLoginDate'];
          _lastLoginDate = (lastLoginMs is int)
              ? DateTime.fromMillisecondsSinceEpoch(lastLoginMs)
              : DateTime.now();
          // New: backend now returns the exact weekday indices that were
          // active *this* calendar week (Mon=0..Sun=6). Used directly by
          // the streak dot row.
          final waw = streakData['weekActiveDays'];
          _weekActiveDays = (waw is List)
              ? waw.map((e) => (e as num).toInt()).toList()
              : const [];
              
          // ── YÜKLEME TAMAMLANDI ──
          _isLoading = false;
        });
        // Fire the onboarding tour exactly once for new users. The tour
        // itself reads onboardingCompleted from Firestore and self-skips
        // if it's already true, so calling unconditionally is fine.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) OnboardingTour.maybeShow(context);
        });
      }
    } catch (e) {
      debugPrint('Level yüklenemedi: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLeaderboard() async {
    try {
      final response = await http.get(
        Uri.parse('http://localhost:3000/api/code/leaderboard?limit=10'),
      );
      if (response.statusCode != 200) {
        if (mounted) setState(() => _leadersLoading = false);
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final leaders = (data['leaders'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          _leaders = leaders;
          _leadersLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Leaderboard yüklenemedi: $e');
      if (mounted) setState(() => _leadersLoading = false);
    }
  }

  // Returns a 7-element list (Mon..Sun) marking which days of the *current*
  // calendar week the user logged in on.
  //
  // Source of truth: backend's `weekActiveDays`. The visual resets every
  // Monday automatically because the backend wipes that array when crossing
  // into a new ISO week (see /api/code/streak).
  //
  // Fallback (older backend response without the field): infer from streak
  // count + lastLoginDate, the way we used to.
  List<bool> _activeDaysThisWeek() {
    if (_weekActiveDays.isNotEmpty) {
      final flags = List<bool>.filled(7, false);
      for (final i in _weekActiveDays) {
        if (i >= 0 && i < 7) flags[i] = true;
      }
      return flags;
    }

    final lastLogin = _lastLoginDate;
    if (lastLogin == null || _currentStreak <= 0) {
      return List<bool>.filled(7, false);
    }
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    final monday = todayMidnight.subtract(Duration(days: todayMidnight.weekday - 1));
    final lastLoginDay = DateTime(lastLogin.year, lastLogin.month, lastLogin.day);
    final earliestActive = lastLoginDay.subtract(Duration(days: _currentStreak - 1));

    return List<bool>.generate(7, (i) {
      final d = monday.add(Duration(days: i));
      return !d.isAfter(lastLoginDay) && !d.isBefore(earliestActive);
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/');
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Kolay': return const Color(0xFF10B981);
      case 'Orta': return const Color(0xFFF59E0B);
      case 'Zor': return const Color(0xFFEF4444);
      default: return Colors.grey;
    }
  }

  String _levelText() {
    switch (_userLevel) {
      case 'beginner': return 'Başlangıç';
      case 'intermediate': return 'Orta Seviye';
      case 'advanced': return 'İleri Seviye';
      default: return 'Başlangıç';
    }
  }

  Widget _buildGlassCard({
    required Widget child,
    bool isLocked = false,
    Color? borderColor,
    bool enableBlur = true,
  }) {
    final baseColor = Colors.white;
    final opacity = isLocked ? 0.5 : (enableBlur ? 0.88 : 0.94);
    final finalColor = baseColor.withOpacity(opacity);

    // Border opacity bumped from 30/255 → 55/255. Still gentle, but now
    // actually visible against the light-gray background.
    final defaultBorder = const Color.fromARGB(55, 175, 76, 0);

    final cardBody = Container(
      decoration: BoxDecoration(
        color: finalColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: borderColor ?? defaultBorder,
          width: 1.5,
        ),
      ),
      child: child,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        // Two-layer shadow: a darker, focused one for depth + a soft accent
        // glow underneath. Together they give a clear sense of elevation
        // without looking heavy.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: const Color(0xFFAF4C00).withOpacity(0.05),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: cardBody,
              )
            : cardBody,
      ),
    );
  }

  Widget _buildFilterChip(String title, bool active, Color activeColor, VoidCallback onTap) {
    return _HoverFilterChip(
      title: title,
      isActive: active,
      activeColor: activeColor,
      onTap: onTap,
    );
  }

  Widget _buildChapterItem(CourseChapter chapter, int index, Color textColor,
      Color subtitleColor, Color accentColor) {
    // RepaintBoundary isolates this tile's paint from the surrounding glass
    // card so the height animation during expand/collapse doesn't dirty the
    // whole subject-menu panel. Combined with enableBlur:false on the card,
    // the accordion now expands at 60fps instead of stalling.
    return RepaintBoundary(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: index == 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 0),
          iconColor: accentColor,
          collapsedIconColor: subtitleColor,
          // Default ExpansionTile uses a fairly long ease-in-out which
          // amplifies any per-frame cost. A shorter, snappier curve makes
          // the same animation feel responsive.
          // (No public API for this on ExpansionTile, so we lean on
          //  RepaintBoundary + cheap children to keep frames cheap.)
          title: Text(
            chapter.title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
          ),
          children: [
            // Build all children once and wrap in a second RepaintBoundary
            // so hover state changes on a single _TopicRow don't trigger
            // repaints in the rest of the column.
            RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: chapter.topics.map((topic) {
                  return _TopicRow(
                    key: ValueKey(topic.id),
                    topic: topic,
                    accentColor: accentColor,
                    subtitleColor: subtitleColor,
                    textColor: textColor,
                    onTap: () => context.go('/context/${topic.id}'),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderItem(String rank, String name, int score, Color rankColor, Color textColor, Color subtitleColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: rankColor.withOpacity(0.5), width: 1.5),
            ),
            child: Text(rank, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: rankColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
          ),
          Text('$score p', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subtitleColor)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color.fromARGB(255, 227, 226, 226);
    const textColor = Color.fromARGB(255, 0, 0, 0);
    final subtitleColor = const Color.fromARGB(170, 0, 0, 0);
    const accentColor = Color.fromARGB(255, 175, 76, 0);
    
    final filteredList = _filteredProblems; 

    return Scaffold(
      backgroundColor: bg,
      // ── YÜKLEME KONTROLÜ EKLENDİ ──
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch, 
                children: [
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40, left: 24, bottom: 24),
                      child: StaggeredGroup(
                        interval: const Duration(milliseconds: 90),
                        child: Column(
                        children: [
                          Expanded(
                            child: StaggeredChild(
                              index: 0,
                              // enableBlur:false — the subject menu sits on
                              // a static light-gray background where the
                              // BackdropFilter blur barely visible, and the
                              // ExpansionTile's height animation made the
                              // blur re-execute every frame (GPU stall).
                              child: _buildGlassCard(
                              enableBlur: false,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                                    child: Row(
                                      children: [
                                        Icon(Icons.menu_book_rounded, color: subtitleColor, size: 18),
                                        const SizedBox(width: 8),
                                        Text('C Programlama', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: subtitleColor)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      itemCount: _courseContent.length,
                                      itemBuilder: (context, index) {
                                        return _buildChapterItem(_courseContent[index], index, textColor, subtitleColor, accentColor);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          StaggeredChild(
                            index: 1,
                            child: _buildGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header — matches the other dashboard cards
                                  // (icon + label, left-aligned, no right-side
                                  // pill that visually splits the row in two).
                                  Row(
                                    children: [
                                      Icon(Icons.filter_alt_rounded, color: textColor, size: 14),
                                      const SizedBox(width: 6),
                                      Text('Filtreler',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: textColor)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildFilterChip('Kolay', _filterKolay,
                                            const Color(0xFF10B981),
                                            () => setState(() => _filterKolay = !_filterKolay)),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildFilterChip('Orta', _filterOrta,
                                            const Color(0xFFF59E0B),
                                            () => setState(() => _filterOrta = !_filterOrta)),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildFilterChip('Zor', _filterZor,
                                            const Color(0xFFEF4444),
                                            () => setState(() => _filterZor = !_filterZor)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildFilterChip('Tamamlandı', _filterCompleted,
                                            accentColor,
                                            () => setState(() {
                                                  _filterCompleted = !_filterCompleted;
                                                  if (_filterCompleted) _filterLocked = false;
                                                })),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _buildFilterChip('Kilitli', _filterLocked,
                                            Colors.grey.shade700,
                                            () => setState(() {
                                                  _filterLocked = !_filterLocked;
                                                  if (_filterLocked) _filterCompleted = false;
                                                })),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(24, 40, 24, 0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFAF4C00).withOpacity(0.55),
                                blurRadius: 28,
                                offset: Offset.zero,
                              ),
                              BoxShadow(
                                color: const Color(0xFFAF4C00).withOpacity(0.25),
                                blurRadius: 60,
                                spreadRadius: 4,
                                offset: Offset.zero,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF111111),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFFAF4C00).withOpacity(0.7),
                                  width: 1.5,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  const Positioned.fill(child: _HeaderVideoBackground()),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), 
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min, 
                                              children: [
                                                Container(
                                                  width: 48, 
                                                  height: 48, 
                                                  decoration: BoxDecoration(
                                                    gradient: const LinearGradient(
                                                      colors: [Colors.black, Color.fromARGB(255, 175, 76, 0), Colors.white], 
                                                      begin: Alignment.topLeft, 
                                                      end: Alignment.bottomRight
                                                    ), 
                                                    borderRadius: BorderRadius.circular(16)
                                                  ), 
                                                  child: const Icon(Icons.code_rounded, color: Colors.white, size: 28)
                                                ), 
                                                const SizedBox(width: 12), 
                                                const Text(
                                                  'KodLearn', 
                                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)
                                                )
                                              ]
                                            )
                                          ),
                                          const Spacer(),
                                          _HoverNavButton(
                                            onTap: () => context.go('/profile'),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), 
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 24, 
                                                    height: 24, 
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(colors: [Colors.black, Color.fromARGB(255, 175, 76, 0), Colors.white]), 
                                                      borderRadius: BorderRadius.circular(6)
                                                    ), 
                                                    child: const Icon(Icons.person, size: 14, color: Colors.white)
                                                  ), 
                                                  const SizedBox(width: 8), 
                                                  Text(
                                                    _userName.isNotEmpty ? _userName : _user?.email ?? '', 
                                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)
                                                  )
                                                ]
                                              )
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          _HoverNavButton(
                                            onTap: _logout,
                                            child: const Padding(
                                              padding: EdgeInsets.all(10), 
                                              child: Icon(Icons.logout_rounded, color: Colors.white70, size: 20)
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      _buildGlassCard(enableBlur: false, child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.black, Colors.white]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22)), const SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Mevcut Seviye', style: TextStyle(fontSize: 12, color: subtitleColor)), Text(_levelText(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor))]), const Spacer(), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Tamamlanan', style: TextStyle(fontSize: 12, color: subtitleColor)), Text('${_completedProblems.length}/${problems.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor))])]))),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                        // The header above contains the video and is left
                        // un-animated to avoid wrapping the video subtree in
                        // Opacity/Transform. The problem-list area below
                        // staggers in solo.
                        Expanded(
                          child: StaggeredGroup(
                            child: StaggeredChild(
                              index: 0,
                              child: Container(
                            margin: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.94),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFAF4C00).withOpacity(0.22),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                                BoxShadow(
                                  color: const Color(0xFFAF4C00).withOpacity(0.06),
                                  blurRadius: 40,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start, 
                                            children: [
                                              const Text('Problemler', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF111111))), 
                                              const SizedBox(height: 4), 
                                              Text(_courseContent[_currentTopicIndex].title, style: const TextStyle(fontSize: 13, color: Color(0xFFAF4C00), fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: _currentTopicIndex > 0 ? () => setState(() => _currentTopicIndex--) : null,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.arrow_back_ios_new_rounded,
                                                    size: 18,
                                                    color: _currentTopicIndex > 0 ? const Color(0xFF111111) : Colors.black26,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: _currentTopicIndex < _courseContent.length - 1 ? () => setState(() => _currentTopicIndex++) : null,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Icon(
                                                    Icons.arrow_forward_ios_rounded,
                                                    size: 18,
                                                    color: _currentTopicIndex < _courseContent.length - 1 ? const Color(0xFF111111) : Colors.black26,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    if (filteredList.isEmpty) 
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(20.0),
                                          child: Text('Bu bölüme ait problem bulunamadı.', style: TextStyle(color: Colors.black.withOpacity(0.4))),
                                        )
                                      )
                                    else ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: filteredList.length,
                                      itemBuilder: (context, index) {
                                        final problem = filteredList[index];
                                        final unlocked = _isProblemUnlocked(problem);
                                        return HoverableProblemCard(
                                          key: ValueKey(problem['id']),
                                          problem: problem,
                                          isUnlocked: unlocked,
                                          isCompleted: _completedProblems.contains(problem['id']),
                                          diffColor: _difficultyColor(problem['difficulty']),
                                          borderColor: _completedProblems.contains(problem['id'])
                                              ? const Color(0xFFAF4C00).withOpacity(0.35)
                                              : (unlocked
                                                  ? const Color(0xFFAF4C00).withOpacity(0.15)
                                                  : Colors.black.withOpacity(0.08)),
                                          defaultTextColor: const Color(0xFF111111),
                                          defaultSubtitleColor: Colors.black54,
                                          buildGlassCard: _buildGlassCard,
                                        );
                                      },
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
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 40, right: 24, bottom: 24),
                      child: StaggeredGroup(
                        interval: const Duration(milliseconds: 90),
                        child: Column(
                        children: [
                          StaggeredChild(
                            index: 0,
                            child: Builder(builder: (_) {
                            final activeDays = _activeDaysThisWeek();
                            final todayIdx = DateTime.now().weekday - 1;
                            return _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('🔥 $_currentStreak Günlük Seri',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: textColor)),
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children:
                                          ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'].asMap().entries.map((e) {
                                        final bool active = activeDays[e.key];
                                        final bool isToday = e.key == todayIdx;
                                        return Column(children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              color: active ? accentColor : textColor.withOpacity(0.05),
                                              shape: BoxShape.circle,
                                              border: isToday && !active
                                                  ? Border.all(color: accentColor.withOpacity(0.6), width: 1.5)
                                                  : null,
                                            ),
                                            child: active
                                                ? const Icon(Icons.check, size: 12, color: Colors.white)
                                                : null,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(e.value,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: subtitleColor,
                                                  fontWeight:
                                                      isToday ? FontWeight.bold : FontWeight.normal))
                                        ]);
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          ),
                          const SizedBox(height: 20),
                          StaggeredChild(
                            index: 1,
                            child: _buildGlassCard(
                            borderColor: accentColor.withOpacity(0.3),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Icon(Icons.lightbulb_outline_rounded, color: accentColor, size: 18),
                                    const SizedBox(width: 8),
                                    Text("Koda'dan İpucu",
                                        style: TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                                  ]),
                                  const SizedBox(height: 12),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    transitionBuilder: (child, anim) => FadeTransition(
                                      opacity: anim,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                                begin: const Offset(0, 0.08), end: Offset.zero)
                                            .animate(anim),
                                        child: child,
                                      ),
                                    ),
                                    child: Text(
                                      _quickTips[_quickTipIndex],
                                      key: ValueKey<int>(_quickTipIndex),
                                      style: TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),
                          const SizedBox(height: 20),
                          StaggeredChild(
                            index: 2,
                            child: _buildGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [Icon(Icons.code_rounded, color: textColor, size: 18), const SizedBox(width: 8), Text('Hızlı Hatırlatıcı', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor))]),
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    _buildSmallTag('%d: int', textColor),
                                    _buildSmallTag('%f: float', textColor),
                                    _buildSmallTag('%s: string', textColor),
                                    _buildSmallTag('\\n: newline', textColor),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                          ),
                          const SizedBox(height: 20),
                          StaggeredChild(
                            index: 3,
                            child: _buildGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.emoji_events_rounded,
                                          color: Color(0xFFF59E0B), size: 18),
                                      const SizedBox(width: 8),
                                      Text('Haftanın Liderleri',
                                          style: TextStyle(
                                              fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (_leadersLoading)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Color(0xFFAF4C00)),
                                        ),
                                      ),
                                    )
                                  else if (_leaders.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Text('Henüz veri yok.',
                                          style: TextStyle(fontSize: 12, color: subtitleColor)),
                                    )
                                  else
                                    ..._leaders.take(5).toList().asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final l = entry.value;
                                      final rankColor = i == 0
                                          ? const Color(0xFFF59E0B) 
                                          : i == 1
                                              ? const Color(0xFF9CA3AF) 
                                              : i == 2
                                                  ? const Color(0xFFB45309) 
                                                  : accentColor.withOpacity(0.6);
                                      return _buildLeaderItem(
                                        '${l['rank'] ?? i + 1}',
                                        (l['name'] ?? 'Anon') as String,
                                        (l['score'] ?? 0) as int,
                                        rankColor,
                                        textColor,
                                        subtitleColor,
                                      );
                                    }),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSmallTag(String text, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: textColor.withOpacity(0.1))),
      child: Text(text, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7), fontFamily: 'monospace')),
    );
  }
}

class HoverableProblemCard extends StatefulWidget {
  final Map<String, dynamic> problem;
  final bool isUnlocked;
  final bool isCompleted;
  final Color diffColor;
  final Color? borderColor;
  final Color defaultTextColor;
  final Color defaultSubtitleColor;
  final Widget Function({required Widget child, bool isLocked, Color? borderColor}) buildGlassCard;

  const HoverableProblemCard({
    super.key,
    required this.problem,
    required this.isUnlocked,
    required this.isCompleted,
    required this.diffColor,
    required this.borderColor,
    required this.defaultTextColor,
    required this.defaultSubtitleColor,
    required this.buildGlassCard,
  });

  @override
  State<HoverableProblemCard> createState() => _HoverableProblemCardState();
}

class _HoverableProblemCardState extends State<HoverableProblemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isInteractable = widget.isUnlocked || widget.isCompleted;
    const accentColor = Color(0xFFAF4C00);

    return RepaintBoundary(
      child: MouseRegion(
      cursor: isInteractable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) { if (isInteractable) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: isInteractable ? () => context.go('/editor', extra: widget.problem) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(
            bottom: 12,
            left: _hovered ? 0 : 0,
          ),
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.22),
                      blurRadius: 20,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: widget.buildGlassCard(
            isLocked: !isInteractable,
            borderColor: _hovered
                ? accentColor.withOpacity(0.55)
                : widget.borderColor,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? accentColor.withOpacity(0.12)
                          : (isInteractable
                              ? (widget.isCompleted
                                  ? Colors.grey.withOpacity(0.15)
                                  : Colors.black.withOpacity(0.12))
                              : Colors.grey.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.isCompleted
                          ? Icons.check_circle_rounded
                          : (isInteractable ? Icons.code_rounded : Icons.lock_rounded),
                      color: widget.isCompleted
                          ? accentColor
                          : (isInteractable
                              ? (_hovered ? accentColor : Colors.black)
                              : Colors.grey),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.problem['title'],
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _hovered ? accentColor : widget.defaultTextColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isInteractable ? widget.problem['topic'] : 'Kilitli Bölüm',
                          style: TextStyle(fontSize: 12, color: widget.defaultSubtitleColor),
                        ),
                      ],
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _hovered
                          ? widget.diffColor.withOpacity(0.28)
                          : (isInteractable
                              ? widget.diffColor.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.problem['difficulty'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isInteractable ? widget.diffColor : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _HoverNavButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _HoverNavButton({required this.child, required this.onTap});

  @override
  State<_HoverNavButton> createState() => _HoverNavButtonState();
}

class _HoverNavButtonState extends State<_HoverNavButton> {
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
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: _hovered
                ? [BoxShadow(color: const Color(0xFFAF4C00).withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 4))]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoverFilterChip extends StatefulWidget {
  final String title;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _HoverFilterChip({
    required this.title,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_HoverFilterChip> createState() => _HoverFilterChipState();
}

class _HoverFilterChipState extends State<_HoverFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? color.withOpacity(0.15)
                : (_hovered ? color.withOpacity(0.07) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: (widget.isActive || _hovered)
                  ? color
                  : const Color.fromARGB(40, 0, 0, 0),
              width: 1,
            ),
          ),
          // The Text widget by itself fills the parent's horizontal space and
          // its glyphs honour textAlign. textAlign.center is what actually
          // centres the characters inside the pill — wrapping in Center() did
          // not, because Text still expanded to chip width.
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w600,
              color: (widget.isActive || _hovered) ? color : Colors.black.withOpacity(0.7),
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderVideoBackground extends StatefulWidget {
  const _HeaderVideoBackground();

  @override
  State<_HeaderVideoBackground> createState() => _HeaderVideoBackgroundState();
}

class _HeaderVideoBackgroundState extends State<_HeaderVideoBackground> {
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
        ..setPlaybackSpeed(1.0)
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
    if (!_ready || c == null) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: Transform.scale(scale: 1.05, child: VideoPlayer(c)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Clickable topic row inside the Subject Menu expansion tiles. Hover lifts
// the row slightly and tints the bullet and label in the accent color; tap
// goes to /context/:topicId.
// ─────────────────────────────────────────────────────────────────────────────
class _TopicRow extends StatefulWidget {
  final CourseTopic topic;
  final Color accentColor;
  final Color textColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _TopicRow({
    super.key,
    required this.topic,
    required this.accentColor,
    required this.textColor,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  State<_TopicRow> createState() => _TopicRowState();
}

class _TopicRowState extends State<_TopicRow> {
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
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accentColor.withOpacity(0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 6,
                color: _hovered
                    ? widget.accentColor
                    : widget.accentColor.withOpacity(0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.topic.title,
                  style: TextStyle(
                    fontSize: 12,
                    color: _hovered ? widget.accentColor : widget.subtitleColor,
                    fontWeight: _hovered ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: widget.accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}