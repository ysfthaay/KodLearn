import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/activity_heatmap.dart';

import '../widgets/staggered_fade_in.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────────────────────
const _kBg          = Color(0xFFF4F2EF);
const _kSurface     = Color(0xFFFFFFFF);
const _kText        = Color(0xFF111111);
const _kSubtitle    = Color(0xAA000000);
const _kAccent      = Color(0xFFAF4C00);
const _kAccentLight = Color(0xFFD65C00);
const _kSuccess     = Color(0xFF10B981);
const _kWarning     = Color(0xFFF59E0B);
const _kDanger      = Color(0xFFEF4444);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _loadError;

  // Chapter names matching dashboard
  final List<String> _chapterNames = [
    'C Diline Giriş',
    'Akış Kontrolü',
    'Fonksiyonlar',
    'Diziler',
    'İşaretçiler',
    'Yapı ve Dosya',
  ];

  final List<Map<String, dynamic>> problems = const [
    {'id': '1',  'title': 'Merhaba Dünya',               'difficulty': 'Kolay', 'topic': 'Temel Giriş/Çıkış',  'chapterIndex': 0},
    {'id': '2',  'title': 'Toplama İşlemi',              'difficulty': 'Kolay', 'topic': 'Değişkenler',         'chapterIndex': 0},
    {'id': '3',  'title': 'Dairenin Alanı',              'difficulty': 'Orta',  'topic': 'Matematiksel İşlem',  'chapterIndex': 0},
    {'id': '4',  'title': "Celsius'tan Fahrenheit'a",    'difficulty': 'Orta',  'topic': 'Tip Dönüşümü',        'chapterIndex': 0},
    {'id': '5',  'title': 'Dikdörtgen Çevresi',          'difficulty': 'Zor',   'topic': 'Çıktı Formatlama',    'chapterIndex': 0},
    {'id': '6',  'title': "1'den 10'a Sayma",            'difficulty': 'Kolay', 'topic': 'Döngüler',            'chapterIndex': 1},
    {'id': '7',  'title': 'Tek mi Çift mi?',             'difficulty': 'Kolay', 'topic': 'Koşullar',            'chapterIndex': 1},
    {'id': '8',  'title': 'Çarpım Tablosu (5ler)',       'difficulty': 'Orta',  'topic': 'Döngüler',            'chapterIndex': 1},
    {'id': '9',  'title': 'Geçme Notu',                  'difficulty': 'Orta',  'topic': 'Koşullar',            'chapterIndex': 1},
    {'id': '10', 'title': 'FizzBuzz',                    'difficulty': 'Zor',   'topic': 'Döngüler',            'chapterIndex': 1},
    {'id': '11', 'title': 'Faktöriyel Hesaplama',        'difficulty': 'Kolay', 'topic': 'Fonksiyonlar',        'chapterIndex': 2},
    {'id': '12', 'title': 'Maksimum Bulma',              'difficulty': 'Kolay', 'topic': 'Fonksiyonlar',        'chapterIndex': 2},
    {'id': '13', 'title': 'Asal Sayı Kontrolü',          'difficulty': 'Orta',  'topic': 'Fonksiyonlar',        'chapterIndex': 2},
    {'id': '14', 'title': 'Üs Alma',                     'difficulty': 'Orta',  'topic': 'Fonksiyonlar',        'chapterIndex': 2},
    {'id': '15', 'title': 'Protein Hedefi',              'difficulty': 'Zor',   'topic': 'Fonksiyonlar',        'chapterIndex': 2},
    {'id': '16', 'title': 'En Büyük Elemanı Bulma',      'difficulty': 'Kolay', 'topic': 'Diziler',             'chapterIndex': 3},
    {'id': '17', 'title': 'Dizide Eleman Arama',         'difficulty': 'Kolay', 'topic': 'Diziler',             'chapterIndex': 3},
    {'id': '18', 'title': 'Dizi Sıralama',               'difficulty': 'Orta',  'topic': 'Diziler',             'chapterIndex': 3},
    {'id': '19', 'title': 'String Ters Çevirme',         'difficulty': 'Orta',  'topic': 'Diziler',             'chapterIndex': 3},
    {'id': '20', 'title': 'Satranç Piyon Terfisi',       'difficulty': 'Zor',   'topic': 'Diziler',             'chapterIndex': 3},
    {'id': '21', 'title': 'Pointer Değerini Güncelleme', 'difficulty': 'Kolay', 'topic': 'İşaretçiler',         'chapterIndex': 4},
    {'id': '22', 'title': 'Karakter Karakter Yazdırma',  'difficulty': 'Kolay', 'topic': 'İşaretçiler',         'chapterIndex': 4},
    {'id': '23', 'title': 'Pointer ile Dizi Toplamı',    'difficulty': 'Orta',  'topic': 'İşaretçiler',         'chapterIndex': 4},
    {'id': '24', 'title': 'Pointer ile String Uzunluğu', 'difficulty': 'Orta',  'topic': 'İşaretçiler',         'chapterIndex': 4},
    {'id': '25', 'title': 'Pointer ile Yer Değiştirme',  'difficulty': 'Zor',   'topic': 'İşaretçiler',         'chapterIndex': 4},
    {'id': '26', 'title': 'Öğrenci Not Kaydı',           'difficulty': 'Kolay', 'topic': 'Yapı ve Dosya',       'chapterIndex': 5},
    {'id': '27', 'title': 'Antrenman Kaydı',             'difficulty': 'Kolay', 'topic': 'Yapı ve Dosya',       'chapterIndex': 5},
    {'id': '28', 'title': 'İki Nokta Arası Mesafe',      'difficulty': 'Orta',  'topic': 'Yapı ve Dosya',       'chapterIndex': 5},
    {'id': '29', 'title': 'Dosyaya Metin Yazma',         'difficulty': 'Orta',  'topic': 'Yapı ve Dosya',       'chapterIndex': 5},
    {'id': '30', 'title': 'Dosyadan Veri Okuma',         'difficulty': 'Zor',   'topic': 'Yapı ve Dosya',       'chapterIndex': 5},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted && !_isLoading) setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _userData = doc.data();
          _loadError = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Without this the spinner never stops when Firestore rejects the
      // read (e.g. permission-denied from security rules).
      debugPrint('Profil yüklenemedi: $e');
      if (mounted) {
        setState(() {
          _loadError = e is FirebaseException && e.code == 'permission-denied'
              ? 'Profil verilerine erişim izni yok.'
              : 'Profil yüklenemedi. Bağlantını kontrol edip tekrar dene.';
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLoadError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 40, color: _kDanger),
          const SizedBox(height: 12),
          Text(_loadError!,
              style: const TextStyle(fontSize: 14, color: _kText), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text("Dashboard'a Dön", style: TextStyle(color: _kSubtitle)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _loadUserData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Parses the dailyActivity map from the user doc into a typed
  // Map<String, int>. Returns an empty map if the field doesn't exist yet.
  Map<String, int> _readActivity() {
    final raw = _userData?['dailyActivity'];
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k is String && v is num) out[k] = v.toInt();
    });
    return out;
  }

  // Groups problems by chapter and returns completion info
  List<Map<String, dynamic>> _getChapterStats(List<String> completed) {
    return List.generate(_chapterNames.length, (i) {
      final chapterProblems = problems.where((p) => p['chapterIndex'] == i).toList();
      final doneCount = chapterProblems.where((p) => completed.contains(p['id'])).length;
      return {
        'name': _chapterNames[i],
        'total': chapterProblems.length,
        'done': doneCount,
        'problems': chapterProblems,
      };
    });
  }

  Future<void> _showEditDialog() async {
    final nameController = TextEditingController(text: _userData?['name'] ?? '');
    final surnameController = TextEditingController(text: _userData?['surname'] ?? '');
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Profili Düzenle',
              style: TextStyle(fontWeight: FontWeight.bold, color: _kText)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInput(nameController, 'Ad', Icons.person_outline),
              const SizedBox(height: 12),
              _buildInput(surnameController, 'Soyad', Icons.person_outline),
              const SizedBox(height: 20),
              Divider(color: _kText.withOpacity(0.1)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _confirmDeleteAccount();
                  },
                  icon: const Icon(Icons.delete_forever, color: _kDanger),
                  label: const Text('Hesabımı Sil', style: TextStyle(color: _kDanger)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _kDanger),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal', style: TextStyle(color: _kSubtitle)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty || surnameController.text.trim().isEmpty) return;
                      setDialogState(() => isSaving = true);
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                          'name': nameController.text.trim(),
                          'surname': surnameController.text.trim(),
                        });
                      }
                      if (mounted) {
                        Navigator.pop(context);
                        await _loadUserData();
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: _kDanger),
            SizedBox(width: 8),
            Text('Hesabı Sil', style: TextStyle(color: _kDanger)),
          ],
        ),
        content: const Text(
          'Hesabını silmek istediğine emin misin? Bu işlem geri alınamaz.',
          style: TextStyle(color: _kSubtitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç', style: TextStyle(color: _kSubtitle)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAccount();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _kDanger, foregroundColor: Colors.white),
            child: const Text('Evet, Sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hata oluştu. Tekrar giriş yapıp deneyin.'), backgroundColor: _kDanger),
        );
      }
    }
  }

  String _levelText(String? level) {
    switch (level) {
      case 'beginner': return 'Başlangıç';
      case 'intermediate': return 'Orta Seviye';
      case 'advanced': return 'İleri Seviye';
      default: return 'Başlangıç';
    }
  }

  Color _levelColor(String? level) {
    switch (level) {
      case 'beginner': return _kSuccess;
      case 'intermediate': return _kAccent;
      case 'advanced': return _kDanger;
      default: return _kSuccess;
    }
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Kolay': return _kSuccess;
      case 'Orta':  return _kWarning;
      case 'Zor':   return _kDanger;
      default:      return Colors.grey;
    }
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: _kText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kSubtitle, fontSize: 14),
        prefixIcon: const Icon(Icons.person_outline, size: 18, color: _kSubtitle),
        filled: true,
        fillColor: Colors.white.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _kAccent.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, Color? borderColor, double radius = 24}) {
    final defaultBorder = const Color.fromARGB(30, 175, 76, 0);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor ?? defaultBorder, width: 1.5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  // ── Stat chip (score / completed / streak) ──
  Widget _buildStatChip(IconData icon, Color iconBg, Color iconColor, String label, String value) {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: _kSubtitle, fontWeight: FontWeight.w600, letterSpacing: 0.4),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(value,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kText),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Per-chapter progress row ──
  Widget _buildChapterProgress(Map<String, dynamic> chapter, List<String> completed) {
    final int done = chapter['done'] as int;
    final int total = chapter['total'] as int;
    final double pct = total == 0 ? 0 : done / total;
    final bool allDone = done == total;

    return _buildGlassCard(
      borderColor: allDone ? _kSuccess.withOpacity(0.35) : null,
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          iconColor: _kAccent,
          collapsedIconColor: _kSubtitle,
          title: Row(
            children: [
              // progress circle
              SizedBox(
                width: 38, height: 38,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: pct,
                      strokeWidth: 3,
                      backgroundColor: _kText.withOpacity(0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        allDone ? _kSuccess : _kAccent,
                      ),
                    ),
                    Text(
                      '$done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: allDone ? _kSuccess : _kText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(chapter['name'],
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)),
                    const SizedBox(height: 2),
                    Text('$done / $total problem',
                        style: const TextStyle(fontSize: 11, color: _kSubtitle)),
                  ],
                ),
              ),
              if (allDone)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _kSuccess.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('✓ Tamam',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _kSuccess)),
                ),
            ],
          ),
          children: (chapter['problems'] as List<Map<String, dynamic>>).map((p) {
            final isDone = completed.contains(p['id']);
            final diffColor = _difficultyColor(p['difficulty']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: isDone ? _kSuccess : _kSubtitle.withOpacity(0.4),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p['title'],
                        style: TextStyle(
                            fontSize: 13,
                            color: isDone ? _kText : _kSubtitle,
                            fontWeight: isDone ? FontWeight.w600 : FontWeight.w400)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: diffColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(p['difficulty'],
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: diffColor)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Section header used on the right column ──
  Widget _sectionHeader(IconData icon, String label) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: _kAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.bolt_rounded, size: 16, color: _kAccent),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)),
      ],
    );
  }

  // ── Overall progress card (right column, top) ──
  Widget _buildOverallProgress(int completedCount, int totalCount) {
    final pct = totalCount == 0 ? 0.0 : completedCount / totalCount;
    final percentRound = (pct * 100).round();

    return _buildGlassCard(
      borderColor: _kAccent.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: _kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.donut_large_rounded, size: 16, color: _kAccent),
                ),
                const SizedBox(width: 10),
                const Text('Genel İlerleme',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 110, height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 110, height: 110,
                      child: CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 10,
                        backgroundColor: _kText.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(_kAccent),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$percentRound%',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _kText),
                        ),
                        const Text('tamam',
                            style: TextStyle(fontSize: 10, color: _kSubtitle)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('$completedCount / $totalCount problem',
                  style: const TextStyle(fontSize: 12, color: _kSubtitle, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final completed = List<String>.from(_userData?['completedProblems'] ?? []);
    final totalScore = _userData?['totalScore'] ?? 0;
    final streak = _userData?['streak'] ?? 0;
    final level = _userData?['level'];
    final name = (_userData?['name'] ?? '') as String;
    final surname = (_userData?['surname'] ?? '') as String;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final chapterStats = _getChapterStats(completed);

    return Scaffold(
      backgroundColor: _kBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _loadError != null
          ? _buildLoadError()
          : SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── LEFT: Profile card ──
                  SizedBox(
                    width: 300,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 40, 12, 24),
                      child: StaggeredGroup(
                        interval: const Duration(milliseconds: 90),
                        child: Column(
                        children: [
                          // Back to dashboard button
                          StaggeredChild(
                            index: 0,
                            child: _HoverNavButton(
                            onTap: () => context.go('/dashboard'),
                            child: _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30, height: 30,
                                      decoration: BoxDecoration(
                                        color: _kAccent.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.arrow_back_rounded, color: _kAccent, size: 16),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text("Dashboard'a Dön",
                                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _kText)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          ),

                          const SizedBox(height: 16),

                          // Hero profile card with animated aurora background
                          StaggeredChild(
                            index: 1,
                            child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(color: _kAccent.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12)),
                                BoxShadow(color: _kAccent.withOpacity(0.15), blurRadius: 60, spreadRadius: 6),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: _kAccent.withOpacity(0.5), width: 1.5),
                                ),
                                child: Stack(
                                  children: [
                                    // Animated gradient background
                                    const Positioned.fill(child: _AuroraBackground()),
                                    Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        children: [
                                          // Avatar
                                          Container(
                                            width: 84, height: 84,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [_kAccent, _kAccentLight, Colors.white],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(24),
                                              border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                                              boxShadow: [
                                                BoxShadow(
                                                    color: Colors.black.withOpacity(0.35),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 8)),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                style: const TextStyle(
                                                    fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          // Name & email
                                          Text('$name $surname',
                                              style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white),
                                              textAlign: TextAlign.center),
                                          const SizedBox(height: 4),
                                          Text(email,
                                              style: TextStyle(
                                                  fontSize: 11, color: Colors.white.withOpacity(0.7)),
                                              textAlign: TextAlign.center,
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 14),
                                          // Level badge
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: _levelColor(level).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: _levelColor(level).withOpacity(0.55)),
                                            ),
                                            child: Text(_levelText(level),
                                                style: TextStyle(
                                                    color: _levelColor(level),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12)),
                                          ),
                                          const SizedBox(height: 20),
                                          // Edit button
                                          _HoverNavButton(
                                            onTap: _showEditDialog,
                                            child: Container(
                                              width: double.infinity,
                                              height: 46,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [_kAccent, _kAccentLight],
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                ),
                                                borderRadius: BorderRadius.circular(14),
                                                boxShadow: [
                                                  BoxShadow(
                                                      color: _kAccent.withOpacity(0.4),
                                                      blurRadius: 14,
                                                      offset: const Offset(0, 5)),
                                                ],
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                                                  SizedBox(width: 8),
                                                  Text('Profili Düzenle',
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.white)),
                                                ],
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
                          ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),

                  // ── CENTRE: Stats + Chapter progress ──
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 40, 12, 24),
                      child: StaggeredGroup(
                        interval: const Duration(milliseconds: 70),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Stat chips row — each chip is its own
                          // StaggeredChild so they cascade left → right.
                          Row(
                            children: [
                              Expanded(
                                child: StaggeredChild(
                                  index: 0,
                                  child: _buildStatChip(
                                    Icons.star_rounded,
                                    _kWarning.withOpacity(0.15),
                                    _kWarning,
                                    'TOPLAM PUAN',
                                    '$totalScore',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: StaggeredChild(
                                  index: 1,
                                  child: _buildStatChip(
                                    Icons.check_circle_rounded,
                                    _kSuccess.withOpacity(0.15),
                                    _kSuccess,
                                    'TAMAMLANAN',
                                    '${completed.length}/${problems.length}',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: StaggeredChild(
                                  index: 2,
                                  child: _buildStatChip(
                                    Icons.local_fire_department_rounded,
                                    _kAccent.withOpacity(0.15),
                                    _kAccent,
                                    'GÜNLÜK SERİ',
                                    '$streak gün',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Activity heatmap — GitHub-style 52-week grid of
                          // daily engagement intensity. Reads dailyActivity
                          // straight from the user doc.
                          StaggeredChild(
                            index: 3,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: _kAccent.withOpacity(0.12), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6)),
                                ],
                              ),
                              child: ActivityHeatmap(
                                activity: _readActivity(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Chapter progress list — wrapped via Expanded so
                          // it fills remaining space; StaggeredChild lives
                          // *inside* the Expanded so the parent-data rule
                          // (Expanded must be a direct Flex child) is kept.
                          Expanded(
                            child: StaggeredChild(
                              index: 4,
                              child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.92),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: _kAccent.withOpacity(0.12), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Bölüm İlerlemesi',
                                              style: TextStyle(
                                                  fontSize: 20, fontWeight: FontWeight.bold, color: _kText)),
                                          const SizedBox(height: 4),
                                          Text('Her bölümdeki problemlerin detaylı görünümü',
                                              style: TextStyle(
                                                  fontSize: 13, color: Colors.black.withOpacity(0.45))),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                                        itemCount: chapterStats.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                                        itemBuilder: (context, i) =>
                                            _buildChapterProgress(chapterStats[i], completed),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),

                  // ── RIGHT: Overall progress + difficulty + recent ──
                  SizedBox(
                    width: 280,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 40, 24, 24),
                      child: StaggeredGroup(
                        interval: const Duration(milliseconds: 90),
                        child: Column(
                        children: [
                          // Overall ring
                          StaggeredChild(
                            index: 0,
                            child: _buildOverallProgress(completed.length, problems.length),
                          ),

                          const SizedBox(height: 16),

                          // Difficulty breakdown
                          StaggeredChild(
                            index: 1,
                            child: _buildGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 28, height: 28,
                                        decoration: BoxDecoration(
                                          color: _kAccent.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.bar_chart_rounded,
                                            size: 16, color: _kAccent),
                                      ),
                                      const SizedBox(width: 10),
                                      const Text('Zorluk Dağılımı',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: _kText)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  ...[
                                    ('Kolay', _kSuccess),
                                    ('Orta',  _kWarning),
                                    ('Zor',   _kDanger),
                                  ].map((entry) {
                                    final diff = entry.$1;
                                    final color = entry.$2;
                                    final total = problems.where((p) => p['difficulty'] == diff).length;
                                    final done  = problems
                                        .where((p) => p['difficulty'] == diff && completed.contains(p['id']))
                                        .length;
                                    final pct   = total == 0 ? 0.0 : done / total;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(children: [
                                                Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                        color: color, shape: BoxShape.circle)),
                                                const SizedBox(width: 8),
                                                Text(diff,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: _kText)),
                                              ]),
                                              Text('$done/$total',
                                                  style: const TextStyle(fontSize: 11, color: _kSubtitle)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: pct,
                                              minHeight: 6,
                                              backgroundColor: color.withOpacity(0.12),
                                              valueColor: AlwaysStoppedAnimation<Color>(color),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          ),

                          const SizedBox(height: 16),

                          // Recent completions — StaggeredChild lives
                          // inside the Expanded.
                          Expanded(
                            child: StaggeredChild(
                              index: 2,
                              child: _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionHeader(Icons.history_rounded, 'Son Tamamlananlar'),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: completed.isEmpty
                                          ? const Center(
                                              child: Text(
                                                'Henüz tamamlanan problem yok.',
                                                style: TextStyle(fontSize: 12, color: _kSubtitle),
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                          : ListView.builder(
                                              itemCount: completed.length > 5 ? 5 : completed.length,
                                              itemBuilder: (context, i) {
                                                // Show most recently completed (last in list)
                                                final id = completed[completed.length - 1 - i];
                                                final prob = problems.firstWhere(
                                                  (p) => p['id'] == id,
                                                  orElse: () => {'title': id, 'difficulty': ''},
                                                );
                                                final diffColor = _difficultyColor(prob['difficulty'] ?? '');
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 10),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 28, height: 28,
                                                        decoration: BoxDecoration(
                                                            color: _kSuccess.withOpacity(0.12),
                                                            borderRadius: BorderRadius.circular(8)),
                                                        child: const Icon(Icons.check_rounded,
                                                            size: 14, color: _kSuccess),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(prob['title'] ?? id,
                                                            style: const TextStyle(
                                                                fontSize: 12,
                                                                color: _kText,
                                                                fontWeight: FontWeight.w500),
                                                            overflow: TextOverflow.ellipsis),
                                                      ),
                                                      if ((prob['difficulty'] ?? '').isNotEmpty)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                              color: diffColor.withOpacity(0.12),
                                                              borderRadius: BorderRadius.circular(5)),
                                                          child: Text(prob['difficulty'],
                                                              style: TextStyle(
                                                                  fontSize: 9,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: diffColor)),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                  ],
                                ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated nav button (subtle hover lift)
// ─────────────────────────────────────────────────────────────────────────────
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
                ? [BoxShadow(color: _kAccent.withOpacity(0.25), blurRadius: 14, offset: const Offset(0, 4))]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated aurora background — replaces the video, light on CPU, looks clean
// ─────────────────────────────────────────────────────────────────────────────
class _AuroraBackground extends StatefulWidget {
  const _AuroraBackground();

  @override
  State<_AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<_AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _AuroraPainter(t: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  _AuroraPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base dark gradient
    final basePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF1A0F08), Color(0xFF0A0A0F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Two slow-moving radial "auroras" that drift across the card
    final angle1 = t * 2 * math.pi;
    final angle2 = (t + 0.5) * 2 * math.pi;

    final orb1 = Offset(
      size.width  * (0.30 + 0.18 * math.sin(angle1)),
      size.height * (0.25 + 0.18 * math.cos(angle1 * 0.8)),
    );
    final orb2 = Offset(
      size.width  * (0.70 + 0.18 * math.cos(angle2)),
      size.height * (0.70 + 0.18 * math.sin(angle2 * 0.9)),
    );

    final r1 = size.longestSide * 0.55;
    final r2 = size.longestSide * 0.45;

    final orb1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFAF4C00).withOpacity(0.55),
          const Color(0xFFAF4C00).withOpacity(0.00),
        ],
      ).createShader(Rect.fromCircle(center: orb1, radius: r1));
    canvas.drawCircle(orb1, r1, orb1Paint);

    final orb2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFD65C00).withOpacity(0.40),
          const Color(0xFFD65C00).withOpacity(0.00),
        ],
      ).createShader(Rect.fromCircle(center: orb2, radius: r2));
    canvas.drawCircle(orb2, r2, orb2Paint);

    // A few subtle drifting "stars" for depth
    final starPaint = Paint()..color = Colors.white.withOpacity(0.10);
    final rng = math.Random(7); // deterministic seed
    for (var i = 0; i < 18; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final drift = math.sin((t * 2 * math.pi) + i) * 0.015;
      final dx = ((baseX + drift) % 1.0) * size.width;
      final dy = ((baseY + drift * 0.6) % 1.0) * size.height;
      final radius = 0.6 + rng.nextDouble() * 1.4;
      canvas.drawCircle(Offset(dx, dy), radius, starPaint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}
