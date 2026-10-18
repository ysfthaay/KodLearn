/// Catalog of chapters and topics — single source of truth for both the
/// dashboard's left-column subject menu and the per-topic Context page.
///
/// Topic [id]s are URL-safe slugs. They are stable identifiers; renaming
/// a topic's [title] should never change its id (URLs out in the wild
/// would break otherwise).

class CourseTopic {
  final String id;
  final String title;

  const CourseTopic({required this.id, required this.title});
}

class CourseChapter {
  final String title;
  final List<CourseTopic> topics;

  const CourseChapter({required this.title, required this.topics});
}

const List<CourseChapter> kCourseContent = [
  CourseChapter(
    title: '1. Bölüm : C Diline Giriş',
    topics: [
      CourseTopic(id: 'ch1-t1', title: 'C Dilini Tanıyalım'),
      CourseTopic(id: 'ch1-t2', title: 'C Anahtar Kelimeler ve Tanımlayıcılar'),
      CourseTopic(id: 'ch1-t3', title: 'Değişkenler ve Sabitler'),
      CourseTopic(id: 'ch1-t4', title: 'C Veri Tipleri'),
      CourseTopic(id: 'ch1-t5', title: 'C Giriş / Çıkış'),
      CourseTopic(id: 'ch1-t6', title: 'C Operatörleri'),
      CourseTopic(id: 'ch1-t7', title: 'C Programlamaya Giriş Örnekleri'),
    ],
  ),
  CourseChapter(
    title: '2. Bölüm : Akış Kontrolü',
    topics: [
      CourseTopic(id: 'ch2-t1', title: 'C if else'),
      CourseTopic(id: 'ch2-t2', title: 'C For Döngüsü'),
      CourseTopic(id: 'ch2-t3', title: 'C While ve do…While'),
      CourseTopic(id: 'ch2-t4', title: 'C break ve continue'),
      CourseTopic(id: 'ch2-t5', title: 'C switch … case'),
      CourseTopic(id: 'ch2-t6', title: 'C goto'),
      CourseTopic(id: 'ch2-t7', title: 'Karar Verme Yapıları ve Örnekler'),
    ],
  ),
  CourseChapter(
    title: '3. Bölüm : Fonksiyonlar',
    topics: [
      CourseTopic(id: 'ch3-t1', title: 'C ile Fonksiyonlara Giriş'),
      CourseTopic(id: 'ch3-t2', title: 'C ile Kullanıcı tanımlı fonksiyonlar'),
      CourseTopic(id: 'ch3-t3', title: 'C Fonksiyon Türleri'),
      CourseTopic(id: 'ch3-t4', title: 'C Özyineleme'),
      CourseTopic(id: 'ch3-t5', title: 'C Depolama Sınıfı'),
      CourseTopic(id: 'ch3-t6', title: 'C Fonksiyon Örnekleri'),
    ],
  ),
  CourseChapter(
    title: '4. Bölüm : Diziler',
    topics: [
      CourseTopic(id: 'ch4-t1', title: 'Diziler'),
      CourseTopic(id: 'ch4-t2', title: 'Çok Boyutlu Diziler'),
      CourseTopic(id: 'ch4-t3', title: 'Diziler ve Fonksiyonlar'),
      CourseTopic(id: 'ch4-t4', title: 'Dizi Örnekleri'),
    ],
  ),
  CourseChapter(
    title: '5. Bölüm : İşaretçiler',
    topics: [
      CourseTopic(id: 'ch5-t1', title: 'C İşaretçiler (Pointers)'),
      CourseTopic(id: 'ch5-t2', title: 'C İşaretçiler ve Diziler'),
      CourseTopic(id: 'ch5-t3', title: 'C İşaretçiler ve Fonksiyonlar'),
      CourseTopic(id: 'ch5-t4', title: 'C Bellek Ayırma'),
      CourseTopic(id: 'ch5-t5', title: 'C İşaretçi Örnekler'),
    ],
  ),
  CourseChapter(
    title: '6. Bölüm : Yapı ve Dosya',
    topics: [
      CourseTopic(id: 'ch6-t1', title: 'C Yapılar'),
      CourseTopic(id: 'ch6-t2', title: 'C Yapılar ve İşaretçiler'),
      CourseTopic(id: 'ch6-t3', title: 'C Yapılar ve Fonksiyonlar'),
      CourseTopic(id: 'ch6-t4', title: 'C Unions'),
      CourseTopic(id: 'ch6-t5', title: 'C Yapı (Struct) Örnekleri'),
      CourseTopic(id: 'ch6-t6', title: 'C Dosya İşleme'),
      CourseTopic(id: 'ch6-t7', title: 'C Dosya Örnekleri'),
    ],
  ),
];

/// Look up a topic by its id. Returns the [CourseTopic] and its parent
/// [CourseChapter], or `null` if no match exists.
({CourseTopic topic, CourseChapter chapter})? findTopicById(String id) {
  for (final ch in kCourseContent) {
    for (final t in ch.topics) {
      if (t.id == id) return (topic: t, chapter: ch);
    }
  }
  return null;
}
