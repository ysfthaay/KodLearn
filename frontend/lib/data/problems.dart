/// Canonical problem catalog — single source of truth for the dashboard
/// problem list, profile per-chapter progress, and the command palette.
///
/// Ids match the backend's problem ids in `backend/src/routes/code.js`.

class CourseProblem {
  /// Backend id (stringified integer).
  final String id;

  /// Short Turkish title shown in cards and search results.
  final String title;

  /// Difficulty tier: `Kolay` | `Orta` | `Zor`.
  final String difficulty;

  /// Sub-topic label inside the chapter, e.g. "Döngüler".
  final String topic;

  /// 0-based chapter index — aligns with kCourseContent ordering.
  final int chapterIndex;

  const CourseProblem({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.topic,
    required this.chapterIndex,
  });
}

const List<CourseProblem> kProblems = [
  // ── Bölüm 0: C Diline Giriş ──
  CourseProblem(id: '1',  title: 'Merhaba Dünya',                difficulty: 'Kolay', topic: 'Temel Giriş/Çıkış',  chapterIndex: 0),
  CourseProblem(id: '2',  title: 'Toplama İşlemi',               difficulty: 'Kolay', topic: 'Değişkenler',         chapterIndex: 0),
  CourseProblem(id: '3',  title: 'Dairenin Alanı',               difficulty: 'Orta',  topic: 'Matematiksel İşlem',  chapterIndex: 0),
  CourseProblem(id: '4',  title: "Celsius'tan Fahrenheit'a",     difficulty: 'Orta',  topic: 'Tip Dönüşümü',        chapterIndex: 0),
  CourseProblem(id: '5',  title: 'Dikdörtgen Çevresi',           difficulty: 'Zor',   topic: 'Çıktı Formatlama',    chapterIndex: 0),

  // ── Bölüm 1: Akış Kontrolü ──
  CourseProblem(id: '6',  title: "1'den 10'a Sayma",             difficulty: 'Kolay', topic: 'Döngüler',            chapterIndex: 1),
  CourseProblem(id: '7',  title: 'Tek mi Çift mi?',              difficulty: 'Kolay', topic: 'Koşullar',            chapterIndex: 1),
  CourseProblem(id: '8',  title: 'Çarpım Tablosu (5ler)',        difficulty: 'Orta',  topic: 'Döngüler',            chapterIndex: 1),
  CourseProblem(id: '9',  title: 'Geçme Notu',                   difficulty: 'Orta',  topic: 'Koşullar',            chapterIndex: 1),
  CourseProblem(id: '10', title: 'FizzBuzz',                     difficulty: 'Zor',   topic: 'Döngüler',            chapterIndex: 1),

  // ── Bölüm 2: Fonksiyonlar ──
  CourseProblem(id: '11', title: 'Faktöriyel Hesaplama',         difficulty: 'Kolay', topic: 'Fonksiyonlar',        chapterIndex: 2),
  CourseProblem(id: '12', title: 'Maksimum Bulma',               difficulty: 'Kolay', topic: 'Fonksiyonlar',        chapterIndex: 2),
  CourseProblem(id: '13', title: 'Asal Sayı Kontrolü',           difficulty: 'Orta',  topic: 'Fonksiyonlar',        chapterIndex: 2),
  CourseProblem(id: '14', title: 'Üs Alma',                      difficulty: 'Orta',  topic: 'Fonksiyonlar',        chapterIndex: 2),
  CourseProblem(id: '15', title: 'Protein Hedefi',               difficulty: 'Zor',   topic: 'Fonksiyonlar',        chapterIndex: 2),

  // ── Bölüm 3: Diziler ──
  CourseProblem(id: '16', title: 'En Büyük Elemanı Bulma',       difficulty: 'Kolay', topic: 'Diziler',             chapterIndex: 3),
  CourseProblem(id: '17', title: 'Dizide Eleman Arama',          difficulty: 'Kolay', topic: 'Diziler',             chapterIndex: 3),
  CourseProblem(id: '18', title: 'Dizi Sıralama',                difficulty: 'Orta',  topic: 'Diziler',             chapterIndex: 3),
  CourseProblem(id: '19', title: 'String Ters Çevirme',          difficulty: 'Orta',  topic: 'Diziler',             chapterIndex: 3),
  CourseProblem(id: '20', title: 'Satranç Piyon Terfisi',        difficulty: 'Zor',   topic: 'Diziler',             chapterIndex: 3),

  // ── Bölüm 4: İşaretçiler ──
  CourseProblem(id: '21', title: 'Pointer Değerini Güncelleme',  difficulty: 'Kolay', topic: 'İşaretçiler',         chapterIndex: 4),
  CourseProblem(id: '22', title: 'Karakter Karakter Yazdırma',   difficulty: 'Kolay', topic: 'İşaretçiler',         chapterIndex: 4),
  CourseProblem(id: '23', title: 'Pointer ile Dizi Toplamı',     difficulty: 'Orta',  topic: 'İşaretçiler',         chapterIndex: 4),
  CourseProblem(id: '24', title: 'Pointer ile String Uzunluğu',  difficulty: 'Orta',  topic: 'İşaretçiler',         chapterIndex: 4),
  CourseProblem(id: '25', title: 'Pointer ile Yer Değiştirme',   difficulty: 'Zor',   topic: 'İşaretçiler',         chapterIndex: 4),

  // ── Bölüm 5: Yapı ve Dosya ──
  CourseProblem(id: '26', title: 'Öğrenci Not Kaydı',            difficulty: 'Kolay', topic: 'Yapı ve Dosya',       chapterIndex: 5),
  CourseProblem(id: '27', title: 'Antrenman Kaydı',              difficulty: 'Kolay', topic: 'Yapı ve Dosya',       chapterIndex: 5),
  CourseProblem(id: '28', title: 'İki Nokta Arası Mesafe',       difficulty: 'Orta',  topic: 'Yapı ve Dosya',       chapterIndex: 5),
  CourseProblem(id: '29', title: 'Dosyaya Metin Yazma',          difficulty: 'Orta',  topic: 'Yapı ve Dosya',       chapterIndex: 5),
  CourseProblem(id: '30', title: 'Dosyadan Veri Okuma',          difficulty: 'Zor',   topic: 'Yapı ve Dosya',       chapterIndex: 5),
];

/// Convert the typed catalog back into the legacy `Map<String, dynamic>`
/// shape that the dashboard/profile widgets currently consume. Lets us
/// migrate without rewriting every call site in one go.
List<Map<String, dynamic>> kProblemsAsLegacyMap() {
  return kProblems
      .map((p) => <String, dynamic>{
            'id': p.id,
            'title': p.title,
            'difficulty': p.difficulty,
            'topic': p.topic,
            'chapterIndex': p.chapterIndex,
          })
      .toList(growable: false);
}
