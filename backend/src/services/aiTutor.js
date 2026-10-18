const { GoogleGenerativeAI, SchemaType } = require('@google/generative-ai');

// The user named their env var `Gemini_API_Key`. We tolerate two extra
// casings (all-caps and lowercase) so a tiny typo in .env can't silently
// break every AI call.
function resolveGeminiKey() {
  return (
    process.env.Gemini_API_Key ||
    process.env.GEMINI_API_KEY ||
    process.env.gemini_api_key ||
    null
  );
}

// Lazy client. Building the GoogleGenerativeAI() at module load means that
// if .env hasn't loaded yet (e.g. dotenv path mis-resolved) the key is
// frozen as `undefined` for the lifetime of the process. Lazy = always
// reads the latest env at first call.
let _genAI = null;
function genAI() {
  if (_genAI) return _genAI;
  const key = resolveGeminiKey();
  if (!key) {
    throw new Error(
      'Gemini_API_Key bulunamadı. backend/.env içine `Gemini_API_Key=...` '
      + 'satırını ekle ve node sunucusunu yeniden başlat.'
    );
  }
  _genAI = new GoogleGenerativeAI(key);
  return _genAI;
}

// One-time startup signal — easier than digging through logs to know which
// provider the process is actually running with.
console.log(`📡 aiTutor: Gemini  |  key ${resolveGeminiKey() ? 'present' : 'MISSING'}`);

// Model used for both free-form tutor replies and structured-output hints.
// NOTE: Google retired the gemini-1.5-* family in 2025; calling those names
// now returns 404. Stay on a current model — 2.5-flash is the fast tier
// and supports `responseSchema` for structured JSON output.
const TEXT_MODEL = 'gemini-2.5-flash';

const problems = {
  // ── Bölüm 1: C Diline Giriş ──
  '1': {
    title: 'Merhaba Dünya',
    description: 'printf fonksiyonu ile ekrana "Merhaba Dunya!" yazdır.',
    expectedOutput: 'Merhaba Dunya!',
    concepts: ['printf', 'stdio.h', 'main fonksiyonu'],
  },
  '2': {
    title: 'Toplama İşlemi',
    description: '5 ve 7 sayılarını topla, sonucu ekrana yazdır.',
    expectedOutput: '12',
    concepts: ['değişkenler', 'aritmetik operatörler', 'int'],
  },
  '3': {
    title: 'Dairenin Alanı',
    description: 'Yarıçapı 5 olan dairenin alanını hesapla (pi=3.14), ondalıklı yazdır.',
    expectedOutput: '78.50',
    concepts: ['float', 'sabitler (#define veya const)', 'matematiksel işlemler'],
  },
  '4': {
    title: "Celsius'tan Fahrenheit'a",
    description: "20°C'yi Fahrenheit'a çevir (F = C * 1.8 + 32), tam sayı olarak yazdır.",
    expectedOutput: '68',
    concepts: ['tip dönüşümü', 'temel matematik', 'printf format'],
  },
  '5': {
    title: 'Dikdörtgen Çevresi',
    description: 'Kısa kenarı 4, uzun kenarı 7 olan dikdörtgenin çevresini "Cevre: 22" şeklinde yazdır.',
    expectedOutput: 'Cevre: 22',
    concepts: ['değişkenler', 'temel matematik', 'çıktı formatlama'],
  },

  // ── Bölüm 2: Akış Kontrolü ──
  '6': {
    title: "1'den 10'a Sayma",
    description: "1'den 10'a kadar sayıları aralarında boşluk bırakarak yazdır.",
    expectedOutput: '1 2 3 4 5 6 7 8 9 10 ',
    concepts: ['for döngüsü', 'sayaç değişkenleri'],
  },
  '7': {
    title: 'Tek mi Çift mi?',
    description: '14 sayısının tek mi çift mi olduğunu kontrol et; "Tek" veya "Cift" yazdır.',
    expectedOutput: 'Cift',
    concepts: ['if-else', 'mod alma operatörü (%)'],
  },
  '8': {
    title: 'Çarpım Tablosu (5ler)',
    description: "5'in çarpım tablosunu 1'den 10'a kadar \"5 x 1 = 5\" formatında yazdır.",
    expectedOutput: '5 x 1 = 5\n5 x 2 = 10\n5 x 3 = 15\n5 x 4 = 20\n5 x 5 = 25\n5 x 6 = 30\n5 x 7 = 35\n5 x 8 = 40\n5 x 9 = 45\n5 x 10 = 50',
    concepts: ['for döngüsü', 'formatlı string (%d)'],
  },
  '9': {
    title: 'Geçme Notu',
    description: 'Vize 45 (%40), final 70 (%60); ortalama ≥60 → "Gecti", değilse "Kaldi".',
    expectedOutput: 'Gecti',
    concepts: ['if-else', 'ağırlıklı ortalama', 'koşullu ifadeler'],
  },
  '10': {
    title: 'FizzBuzz',
    description: "1'den 15'e: 3'ün katı→Fizz, 5'in katı→Buzz, ikisinin katı→FizzBuzz, diğerleri→sayı. Boşluklu yaz.",
    expectedOutput: '1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz ',
    concepts: ['if-else if-else', 'mantıksal operatörler (&&)', 'döngüler'],
  },

  // ── Bölüm 3: Fonksiyonlar ──
  '11': {
    title: 'Faktöriyel Hesaplama',
    description: '"faktoriyel" fonksiyonu yaz, 5 ile çağır, sonucu yazdır.',
    expectedOutput: '120',
    concepts: ['fonksiyon tanımlama', 'parametreler', 'return ifadesi'],
  },
  '12': {
    title: 'Maksimum Bulma',
    description: '"maxBul" fonksiyonu yaz; 15 ve 25 gönder, büyüğünü yazdır.',
    expectedOutput: '25',
    concepts: ['fonksiyonlar', 'if-else', 'return mekanizması'],
  },
  '13': {
    title: 'Asal Sayı Kontrolü',
    description: '17 için asal kontrolü yapan fonksiyon yaz; "Asal" veya "Asal Degil" yazdır.',
    expectedOutput: 'Asal',
    concepts: ['yardımcı fonksiyonlar', 'döngü ile bölünebilme kontrolü', 'boolean mantığı'],
  },
  '14': {
    title: 'Üs Alma',
    description: 'Taban=2, üs=3 için sonucu döndüren fonksiyon yaz.',
    expectedOutput: '8',
    concepts: ['fonksiyon argümanları', 'döngü ile hesaplama'],
  },
  '15': {
    title: 'Protein Hedefi',
    description: '70 kg × 2.0 g/kg → günlük protein ihtiyacını hesapla ve yazdır.',
    expectedOutput: '140',
    concepts: ['fonksiyon parametreleri', 'float', 'return'],
  },

  // ── Bölüm 4: Diziler ──
  '16': {
    title: 'En Büyük Elemanı Bulma',
    description: '{12,45,7,89,23} dizisindeki en büyük sayıyı bul ve yazdır.',
    expectedOutput: '89',
    concepts: ['dizilerde gezinme', 'maksimum değer bulma algoritması'],
  },
  '17': {
    title: 'Dizide Eleman Arama',
    description: '{10,25,30,45,50} dizisinde 30\'un indeksini bul; "Bulundu: 2" yazdır.',
    expectedOutput: 'Bulundu: 2',
    concepts: ['diziler', 'lineer arama (linear search)', 'break deyimi'],
  },
  '18': {
    title: 'Dizi Sıralama',
    description: '{5,2,8,1,3} dizisini küçükten büyüğe sırala, boşluk bırakarak yazdır.',
    expectedOutput: '1 2 3 5 8 ',
    concepts: ['diziler', 'iç içe döngüler', 'Bubble Sort mantığı'],
  },
  '19': {
    title: 'String Ters Çevirme',
    description: '"KodLearn" stringini tersine çevir ve yazdır.',
    expectedOutput: 'nraeLdoK',
    concepts: ['char array', 'string.h', 'indeks manipülasyonu'],
  },
  '20': {
    title: 'Satranç Piyon Terfisi',
    description: '{0,0,0,0,0,0,0,1} dizisinde piyon indeks 7\'deyse "Terfi", değilse "Devam" yazdır.',
    expectedOutput: 'Terfi',
    concepts: ['diziler', 'indeks kontrolü', 'koşullu ifadeler'],
  },

  // ── Bölüm 5: İşaretçiler ──
  '21': {
    title: 'Pointer Değerini Güncelleme',
    description: 'int değişkene 50 ata, pointer aracılığıyla 100 yap ve yazdır.',
    expectedOutput: '100',
    concepts: ['pointer ile atama (*ptr = x)', 'bellek manipülasyonu'],
  },
  '22': {
    title: 'Karakter Karakter Yazdırma',
    description: '"C Programlama" stringini char pointer + döngü ile \\0\'a kadar yazdır.',
    expectedOutput: 'C Programlama',
    concepts: ['char pointer', 'null terminator (\\0)'],
  },
  '23': {
    title: 'Pointer ile Dizi Toplamı',
    description: '{1,2,3,4,5} toplamını sadece pointer aritmetiğiyle (ptr++) hesapla.',
    expectedOutput: '15',
    concepts: ['pointer aritmetiği', 'diziler ve pointer ilişkisi'],
  },
  '24': {
    title: 'Pointer ile String Uzunluğu',
    description: '"KodLearn" uzunluğunu strlen kullanmadan pointer ile hesapla.',
    expectedOutput: '8',
    concepts: ['pointer aritmetiği', 'string döngüleri'],
  },
  '25': {
    title: 'Pointer ile Yer Değiştirme',
    description: 'a=10, b=20 değişkenlerini pointer kullanan swap fonksiyonuyla değiştir; önce a sonra boşluk b yazdır.',
    expectedOutput: '20 10',
    concepts: ['pointer (*)', 'adres operatörü (&)', 'pass by reference'],
  },

  // ── Bölüm 6: Yapı ve Dosya ──
  '26': {
    title: 'Öğrenci Not Kaydı',
    description: '"Ogrenci" struct: ad, yaş, not. Ali/20/85.5 ile "Ad: Ali, Not: 85.50" yazdır.',
    expectedOutput: 'Ad: Ali, Not: 85.50',
    concepts: ['struct', 'typedef', 'nokta operatörü (.)'],
  },
  '27': {
    title: 'Antrenman Kaydı',
    description: '"Antrenman" struct: hareket, set, tekrar. "Bench Press"/4/10 ile "Hareket: Bench Press, Set: 4, Tekrar: 10" yazdır.',
    expectedOutput: 'Hareket: Bench Press, Set: 4, Tekrar: 10',
    concepts: ['struct', 'strcpy'],
  },
  '28': {
    title: 'İki Nokta Arası Mesafe',
    description: '"Nokta" struct ile (0,0)-(3,4) mesafesini hesapla; "5.00" yazdır.',
    expectedOutput: '5.00',
    concepts: ['math.h (sqrt, pow)', 'struct', 'fonksiyon argümanı'],
  },
  '29': {
    title: 'Dosyaya Metin Yazma',
    description: '"sonuc.txt" aç, "Test basarili" yaz, kapat. Ekrana "Dosya yazildi" yazdır.',
    expectedOutput: 'Dosya yazildi',
    concepts: ['fopen', 'fprintf', 'fclose', 'w modu'],
  },
  '30': {
    title: 'Dosyadan Veri Okuma',
    description: '"veri.txt" dosyasını oku (içinde "KodLearn" var), ekrana yazdır.',
    expectedOutput: 'KodLearn',
    concepts: ['fopen', 'fscanf', 'fclose', 'r modu'],
  },
};

// Gemini's `Content` shape uses `parts` and `role` (with `model` instead of
// `assistant`). Convert the OpenAI/Groq-style {role, content} chat history
// that the rest of the codebase already uses.
function toGeminiHistory(chatHistory) {
  return (chatHistory || []).map((m) => ({
    role: m.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: m.content || '' }],
  }));
}

const buildTutorSystemPrompt = (problem, extraLines = '') => `Sen "Koda" adında yardımsever bir C programlama eğitmenisin.
Türkçe konuşuyorsun.
Öğrenciye asla direkt cevabı söylemiyorsun.
Onları düşündürecek sorular soruyorsun.
Hataları nazikçe işaret ediyorsun.
Her zaman cesaretlendirici ve pozitif bir ton kullanıyorsun.
${problem ? `
Şu an öğrenci "${problem.title}" problemini çözmeye çalışıyor.
Problem açıklaması: ${problem.description}
Beklenen çıktı: ${problem.expectedOutput}
Bu problemde öğrencinin öğrenmesi gereken kavramlar: ${problem.concepts.join(', ')}
Yönlendirmelerini bu kavramlara göre yap.
` : ''}${extraLines}`;

const getFeedback = async (code, result, problemId = null, chatHistory = []) => {
  try {
    const statusMessages = {
      SUCCESS: 'Kod başarıyla çalıştı.',
      COMPILE_ERROR: 'Kodda derleme hatası var.',
      RUNTIME_ERROR: 'Kod çalışma sırasında hata verdi.',
    };

    const problem = problemId ? problems[problemId] : null;
    const systemPrompt = buildTutorSystemPrompt(problem);

    const prompt = `Öğrencinin yazdığı C kodu:
\`\`\`c
${code}
\`\`\`

Sonuç: ${statusMessages[result.status]}
${result.error ? `Hata mesajı: ${result.error}` : `Çıktı: ${result.output}`}

Lütfen öğrenciye bu problemi çözmesi için yardımcı ol.`;

    const model = genAI().getGenerativeModel({
      model: TEXT_MODEL,
      systemInstruction: systemPrompt,
    });

    const chat = model.startChat({ history: toGeminiHistory(chatHistory) });
    const resp = await chat.sendMessage(prompt);
    return resp.response.text();

  } catch (error) {
    console.error('Gemini feedback hatası:', error);
    return 'Şu an geri bildirim verilemiyor, lütfen tekrar dene.';
  }
};

const chat = async (userMessage, problemId = null, chatHistory = []) => {
  try {
    const problem = problemId ? problems[problemId] : null;
    const systemPrompt = buildTutorSystemPrompt(
      problem,
      '\nCevapların çok uzun olmamalı, kısa ve öz olmalı.',
    );

    const model = genAI().getGenerativeModel({
      model: TEXT_MODEL,
      systemInstruction: systemPrompt,
    });

    const session = model.startChat({ history: toGeminiHistory(chatHistory) });
    const resp = await session.sendMessage(userMessage);
    return resp.response.text();

  } catch (error) {
    console.error('Gemini chat hatası:', error);
    return 'Şu an cevap verilemiyor, lütfen tekrar dene.';
  }
};

// ─────────────────────────────────────────────────────────────────────────────
// getHint — structured JSON output via Gemini's responseSchema.
//
// Always returns an object of shape { success, errorLine, hint }. The schema
// is enforced server-side by Gemini, so we don't have to defensively re-parse
// free-form text. errorLine is 1-indexed; 0 means "no specific line".
// ─────────────────────────────────────────────────────────────────────────────
const HINT_SCHEMA = {
  type: SchemaType.OBJECT,
  properties: {
    success: {
      type: SchemaType.BOOLEAN,
      description: 'Kod problemi doğru çözüyorsa true, aksi halde false.',
    },
    errorLine: {
      type: SchemaType.INTEGER,
      description:
        'Hatanın bulunduğu satır (1\'den başlar). Hata yoksa veya genel bir hatayı tek satıra indirgemek mümkün değilse 0 döndür.',
    },
    hint: {
      type: SchemaType.STRING,
      description:
        'Türkçe, kısa ipucu. Direkt cevap verme; öğrenciyi yönlendiren bir cümle.',
    },
  },
  required: ['success', 'errorLine', 'hint'],
};

const getHint = async (code, problemId = null) => {
  const fallback = {
    success: false,
    errorLine: 0,
    hint: 'Şu an ipucu üretilemiyor, lütfen birazdan tekrar dene.',
  };
  try {
    const problem = problemId ? problems[problemId] : null;

    const systemPrompt = `Sen "Koda" adında bir C programlama eğitmenisin.
Aşağıdaki C kodunu analiz et ve yalnızca şema ile uyumlu bir JSON nesnesi döndür.
${problem ? `Şu an çözülmesi gereken problem: "${problem.title}"
Açıklama: ${problem.description}
Beklenen çıktı: ${problem.expectedOutput}
Kavramlar: ${problem.concepts.join(', ')}
` : ''}
Kural: "hint" alanı Türkçe olmalı, kısa olmalı, doğrudan cevabı vermemeli.
"errorLine" 1'den başlar. Belirgin bir tek satır işaret edilemiyorsa 0 ver.`;

    const userPrompt = `Öğrencinin kodu:
\`\`\`c
${code}
\`\`\``;

    const model = genAI().getGenerativeModel({
      model: TEXT_MODEL,
      systemInstruction: systemPrompt,
      generationConfig: {
        responseMimeType: 'application/json',
        responseSchema: HINT_SCHEMA,
        temperature: 0.4,
      },
    });

    const resp = await model.generateContent(userPrompt);
    const raw = resp.response.text();
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      console.error('Gemini hint JSON parse edilemedi. Cevap:', raw);
      return fallback;
    }

    // Coerce shapes defensively just in case the model surprises us.
    return {
      success: typeof parsed.success === 'boolean' ? parsed.success : false,
      errorLine: Number.isInteger(parsed.errorLine) ? parsed.errorLine : 0,
      hint: typeof parsed.hint === 'string' ? parsed.hint : fallback.hint,
    };

  } catch (error) {
    console.error('Gemini hint hatası:', error);
    return fallback;
  }
};

module.exports = { getFeedback, chat, getHint };
