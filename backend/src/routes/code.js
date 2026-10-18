const express = require('express');
const admin = require('firebase-admin');
const router = express.Router();
const { runCode } = require('../services/codeRunner');
const { getFeedback, chat, getHint } = require('../services/aiTutor'); // ← moved to top

// ── Daily activity helpers ──
// Records per-day engagement on the user doc as a map `dailyActivity.{YYYY-MM-DD} = count`.
// The map is pruned to the last 365 days on each write so the doc never grows
// unbounded. The profile page reads this directly to render a contribution
// heatmap.

function _dateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

async function _recordActivity(userRef, userData, weight = 1) {
  try {
    const todayKey = _dateKey(new Date());
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - 365);
    const cutoffKey = _dateKey(cutoff);

    // Read current map, prune anything older than the cutoff, then increment
    // today's count by `weight`. Rewriting the whole field is fine for a
    // ~366-entry map; it stays well under Firestore's 1 MB doc limit.
    const current = (userData && userData.dailyActivity) || {};
    const pruned = {};
    for (const [k, v] of Object.entries(current)) {
      if (k >= cutoffKey) pruned[k] = v;
    }
    pruned[todayKey] = (pruned[todayKey] || 0) + weight;
    await userRef.update({ dailyActivity: pruned });
  } catch (e) {
    // Never let activity-tracking failures bubble up and break the user's
    // run/login.
    console.error('dailyActivity record failed:', e);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lenient output grading.
//
// The old grader compared expected vs actual character-by-character, which
// punished cosmetic decoration: e.g. expected "12" vs actual "Sonuç: 12"
// would score ~10% because the strings don't line up positionally. That's
// not how a human teacher would grade.
//
// The new grader runs a series of cheap checks in priority order. The first
// one that matches wins; the score reflects how close the match is.
//
//   1. Exact byte-for-byte:                                   100
//   2. Whitespace-normalised:                                 100
//   3. Case-insensitive (Turkish locale):                      98
//   4. Expected appears as a word-bounded substring of actual: 95
//   5. Otherwise, character-similarity ratio (capped at 80):  variable
//
// A defensive negation check blocks (4) when one side contains a Turkish
// negator ("değil", "yok", "kaldı") and the other doesn't — that's how we
// avoid "Asal" matching "Asal Değil".
// ─────────────────────────────────────────────────────────────────────────────

const _NEGATION_WORDS_TR = [
  'değil', 'degil', 'yok', 'hayır', 'hayir', 'kaldı', 'kaldi',
];

function _hasNegation(s, word) {
  return new RegExp(`(?:^|\\W)${word}(?:\\W|$)`, 'u').test(s);
}

function _negationMismatch(eLower, aLower) {
  for (const w of _NEGATION_WORDS_TR) {
    if (_hasNegation(eLower, w) !== _hasNegation(aLower, w)) return true;
  }
  return false;
}

function _escRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function gradeOutput(expectedRaw, actualRaw) {
  const e0 = expectedRaw || '';
  const a0 = actualRaw || '';

  // 1) Exact match.
  if (e0 === a0) return 100;

  // 2) Whitespace-normalised match (handles trailing newlines, double spaces,
  //    Windows CRLF, etc.).
  const eN = e0.replace(/\s+/g, ' ').trim();
  const aN = a0.replace(/\s+/g, ' ').trim();
  if (eN === aN) return 100;

  // 3) Case-insensitive (Turkish-aware) match.
  const eL = eN.toLocaleLowerCase('tr-TR');
  const aL = aN.toLocaleLowerCase('tr-TR');
  if (eL === aL) return 98;

  // 4) Expected output appears verbatim inside the actual output, with word
  //    boundaries on both sides. This is what catches "Sonuç: 12" matching
  //    "12" without ever matching "120".
  if (eL.length >= 2 && !_negationMismatch(eL, aL)) {
    const re = new RegExp(`(?:^|\\W)${_escRe(eL)}(?:\\W|$)`, 'u');
    if (re.test(aL)) return 95;
  }

  // 5) Fallback: character-similarity ratio. Capped at 80 so that a near-
  //    miss never crosses the 90% completion threshold by accident.
  const maxLen = Math.max(e0.length, a0.length) || 1;
  let matches = 0;
  for (let i = 0; i < Math.min(e0.length, a0.length); i++) {
    if (e0[i] === a0[i]) matches++;
  }
  return Math.min(80, Math.round((matches / maxLen) * 100));
}

const problems = {
  // ── Bölüm 1: C Diline Giriş ──
  '1':  { expectedOutput: 'Merhaba Dunya!\n',                   topic: 'Temel Giriş/Çıkış' },  // Kolay
  '2':  { expectedOutput: '12\n',                               topic: 'Değişkenler' },          // Kolay
  '3':  { expectedOutput: '78.50\n',                            topic: 'Matematiksel İşlem' },   // Orta
  '4':  { expectedOutput: '68\n',                               topic: 'Tip Dönüşümü' },         // Orta
  '5':  { expectedOutput: 'Cevre: 22\n',                        topic: 'Çıktı Formatlama' },     // Zor

  // ── Bölüm 2: Akış Kontrolü ──
  '6':  { expectedOutput: '1 2 3 4 5 6 7 8 9 10 \n',           topic: 'Döngüler' },             // Kolay
  '7':  { expectedOutput: 'Cift\n',                             topic: 'Koşullar' },             // Kolay
  '8':  { expectedOutput: '5 x 1 = 5\n5 x 2 = 10\n5 x 3 = 15\n5 x 4 = 20\n5 x 5 = 25\n5 x 6 = 30\n5 x 7 = 35\n5 x 8 = 40\n5 x 9 = 45\n5 x 10 = 50\n', topic: 'Döngüler' }, // Orta
  '9':  { expectedOutput: 'Gecti\n',                            topic: 'Koşullar' },             // Orta
  '10': { expectedOutput: '1 2 Fizz 4 Buzz Fizz 7 8 Fizz Buzz 11 Fizz 13 14 FizzBuzz \n', topic: 'Döngüler' }, // Zor

  // ── Bölüm 3: Fonksiyonlar ──
  '11': { expectedOutput: '120\n',                              topic: 'Fonksiyonlar' },         // Kolay
  '12': { expectedOutput: '25\n',                               topic: 'Fonksiyonlar' },         // Kolay
  '13': { expectedOutput: 'Asal\n',                             topic: 'Fonksiyonlar' },         // Orta
  '14': { expectedOutput: '8\n',                                topic: 'Fonksiyonlar' },         // Orta
  '15': { expectedOutput: '140\n',                              topic: 'Fonksiyonlar' },         // Zor

  // ── Bölüm 4: Diziler ──
  '16': { expectedOutput: '89\n',                               topic: 'Diziler' },              // Kolay
  '17': { expectedOutput: 'Bulundu: 2\n',                       topic: 'Diziler' },              // Kolay
  '18': { expectedOutput: '1 2 3 5 8 \n',                       topic: 'Diziler' },              // Orta
  '19': { expectedOutput: 'nraeLdoK\n',                         topic: 'Diziler' },              // Orta
  '20': { expectedOutput: 'Terfi\n',                            topic: 'Diziler' },              // Zor

  // ── Bölüm 5: İşaretçiler ──
  '21': { expectedOutput: '100\n',                              topic: 'İşaretçiler' },          // Kolay
  '22': { expectedOutput: 'C Programlama\n',                    topic: 'İşaretçiler' },          // Kolay
  '23': { expectedOutput: '15\n',                               topic: 'İşaretçiler' },          // Orta
  '24': { expectedOutput: '8\n',                                topic: 'İşaretçiler' },          // Orta
  '25': { expectedOutput: '20 10\n',                            topic: 'İşaretçiler' },          // Zor

  // ── Bölüm 6: Yapı ve Dosya ──
  '26': { expectedOutput: 'Ad: Ali, Not: 85.50\n',              topic: 'Yapı ve Dosya' },        // Kolay
  '27': { expectedOutput: 'Hareket: Bench Press, Set: 4, Tekrar: 10\n', topic: 'Yapı ve Dosya' }, // Kolay
  '28': { expectedOutput: '5.00\n',                             topic: 'Yapı ve Dosya' },        // Orta
  '29': { expectedOutput: 'Dosya yazildi\n',                    topic: 'Yapı ve Dosya' },        // Orta
  '30': { expectedOutput: 'KodLearn\n',                         topic: 'Yapı ve Dosya' },        // Zor
};

router.post('/run', async (req, res) => {
  try {
    const { code, problemId, uid, stdin } = req.body;

    console.log('📥 Gelen problemId:', problemId);
    console.log('📚 Problem bulundu mu:', !!problems[problemId]);

    if (!code) {
      return res.status(400).json({ error: 'Kod boş olamaz' });
    }

    const result = await runCode(code, stdin || '');
    const feedback = await getFeedback(code, result, problemId);

    let accuracy = 0;
    if (result.status === 'SUCCESS' && problemId && problems[problemId]) {
      accuracy = gradeOutput(
        problems[problemId].expectedOutput,
        result.output || '',
      );
    }

    if (uid) {
      const { db } = require('../config/firebase');
      const userRef = db.collection('users').doc(uid);
      await userRef.collection('sessions').add({
        code,
        problemId,
        status: result.status,
        output: result.output,
        error: result.error,
        feedback,
        accuracy,
        timestamp: new Date(),
      });

      const userDoc = await userRef.get();
      const userData = userDoc.data() || {};

      if (accuracy >= 90) {
        const completed = userData.completedProblems || [];
        if (!completed.includes(problemId)) {
          await userRef.update({
            completedProblems: [...completed, problemId],
            totalScore: (userData.totalScore || 0) + 10,
          });
        }
      }

      // Heatmap input: running code counts as engagement. A completing run
      // weighs more than a failing one so the heatmap reflects effort, not
      // just time on the page.
      const weight = accuracy >= 90 ? 3 : 1;
      await _recordActivity(userRef, userData, weight);
    }

    res.json({ result, feedback, accuracy });

  } catch (error) {
    console.error('Run hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

// Per-chapter, per-difficulty problem map. Order inside each tier is the
// natural problem order; it doesn't affect unlock logic (we just check
// "all of this tier" for the chapter).
const CHAPTERS = [
  { Kolay: ['1',  '2'],  Orta: ['3',  '4'],  Zor: ['5']  }, // Bölüm 1
  { Kolay: ['6',  '7'],  Orta: ['8',  '9'],  Zor: ['10'] }, // Bölüm 2
  { Kolay: ['11', '12'], Orta: ['13', '14'], Zor: ['15'] }, // Bölüm 3
  { Kolay: ['16', '17'], Orta: ['18', '19'], Zor: ['20'] }, // Bölüm 4
  { Kolay: ['21', '22'], Orta: ['23', '24'], Zor: ['25'] }, // Bölüm 5
  { Kolay: ['26', '27'], Orta: ['28', '29'], Zor: ['30'] }, // Bölüm 6
];

router.get('/level/:uid', async (req, res) => {
  try {
    const { uid } = req.params;
    const { db } = require('../config/firebase');

    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data() || {};
    const completedProblems = userData.completedProblems || [];
    const done = (id) => completedProblems.includes(id);
    const allDone = (ids) => ids.every(done);

    // ── Per-chapter sequential unlock ──
    // Within a chapter:
    //   Kolay   → always unlocked
    //   Orta    → unlocked once all of THIS chapter's Kolay are done
    //   Zor     → unlocked once all of THIS chapter's Orta are done
    // Chapters are independent of each other — finishing Chapter 1 fully
    // doesn't gate Chapter 2's Kolay (those are always reachable).
    const unlockedProblems = [];
    for (const ch of CHAPTERS) {
      unlockedProblems.push(...ch.Kolay);
      if (allDone(ch.Kolay)) {
        unlockedProblems.push(...ch.Orta);
        if (allDone(ch.Orta)) {
          unlockedProblems.push(...ch.Zor);
        }
      }
    }

    // ── Global level label (display only) ──
    // Kept around so the "Mevcut Seviye" badge on the dashboard still
    // tells the user where they are overall.
    const allEasy   = CHAPTERS.flatMap((c) => c.Kolay);
    const allMedium = CHAPTERS.flatMap((c) => c.Orta);
    const allHard   = CHAPTERS.flatMap((c) => c.Zor);

    let level;
    let unlockedDifficulties;
    if (allDone(allHard)) {
      level = 'advanced';
      unlockedDifficulties = ['Kolay', 'Orta', 'Zor'];
    } else if (allDone(allMedium)) {
      level = 'advanced';
      unlockedDifficulties = ['Kolay', 'Orta', 'Zor'];
    } else if (allDone(allEasy)) {
      level = 'intermediate';
      unlockedDifficulties = ['Kolay', 'Orta'];
    } else {
      level = 'beginner';
      unlockedDifficulties = ['Kolay'];
    }

    await db.collection('users').doc(uid).update({ level });
    // `unlockedProblems` is the new authoritative gate; the legacy
    // `unlockedDifficulties` is kept for backward-compat with any client
    // still using it.
    res.json({
      level,
      unlockedDifficulties,
      unlockedProblems,
      completedProblems,
    });

  } catch (error) {
    console.error('Level hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

router.post('/hint', async (req, res) => {
  try {
    const { code, problemId } = req.body;
    if (!code) return res.status(400).json({ error: 'Kod boş olamaz' });

    const result = await getHint(code, problemId);
    // Always returns { success, errorLine, hint } even on internal errors.
    res.json(result);
  } catch (error) {
    console.error('Hint hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

router.post('/chat', async (req, res) => {
  try {
    const { message, problemId, chatHistory = [] } = req.body;

    console.log('💬 Chat isteği:', { message, problemId });

    if (!message) {
      return res.status(400).json({ error: 'Mesaj boş olamaz' });
    }

    const response = await chat(message, problemId, chatHistory);
    res.json({ response });

  } catch (error) {
    console.error('Chat hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

router.post('/streak', async (req, res) => {
  try {
    const { uid } = req.body;
    if (!uid) return res.status(400).json({ error: 'uid gerekli' });

    const { db } = require('../config/firebase');
    const userRef = db.collection('users').doc(uid);
    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const lastLogin = userData.lastLoginDate ? userData.lastLoginDate.toDate() : null;

    // ── Total streak (multi-week, only resets if a calendar day is missed) ──
    let streak = userData.streak || 0;
    if (lastLogin) {
      const lastLoginDay = new Date(lastLogin.getFullYear(), lastLogin.getMonth(), lastLogin.getDate());
      const diffDays = Math.round((today - lastLoginDay) / (1000 * 60 * 60 * 24));
      if (diffDays === 0) {
        // Same day, no change.
      } else if (diffDays === 1) {
        streak += 1;
      } else {
        streak = 1;
      }
    } else {
      streak = 1;
    }

    // ── Weekly active-days tracking ──
    // JS Date.getDay() is 0=Sun…6=Sat. Convert to ISO-style 0=Mon…6=Sun so
    // the array indices line up with the UI's "P S Ç P C C P" row, which
    // reads left-to-right starting with Monday.
    const jsDow = today.getDay();
    const todayMondayIdx = jsDow === 0 ? 6 : jsDow - 1;
    const thisMonday = new Date(today);
    thisMonday.setDate(today.getDate() - todayMondayIdx);

    // We rebuild weekActiveDays from scratch each call. Two sources:
    //
    //   1) Backfill from streak. `streak === N` means today plus the
    //      previous N-1 days were consecutively active. Mark the ones
    //      that fall on or after this Monday. This is what fixes the
    //      "streak says 2 but only one dot is lit" migration bug — old
    //      users had streak data but no weekActiveDays array yet.
    //
    //   2) Merge with the previously stored array IF and only if it
    //      belongs to the current week. This preserves days that aren't
    //      part of the consecutive streak — e.g. user logged in Mon,
    //      Tue, skipped Wed, logged in Thu (streak=1 but the Mon/Tue
    //      dots should still be lit).
    //
    // Crossing into a new Monday resets naturally: storedWeekStart won't
    // match thisMonday, so nothing from last week gets merged in.
    const activeDaysSet = new Set();

    const daysToBackfill = Math.min(streak, todayMondayIdx + 1);
    for (let i = 0; i < daysToBackfill; i++) {
      activeDaysSet.add(todayMondayIdx - i);
    }

    const storedWeekStart = userData.weekStart ? userData.weekStart.toDate() : null;
    if (storedWeekStart &&
        storedWeekStart.getTime() === thisMonday.getTime() &&
        Array.isArray(userData.weekActiveDays)) {
      for (const d of userData.weekActiveDays) {
        if (typeof d === 'number' && d >= 0 && d <= 6) {
          activeDaysSet.add(d);
        }
      }
    }

    const weekActiveDays = [...activeDaysSet].sort((a, b) => a - b);

    await userRef.update({
      streak,
      lastLoginDate: now,
      weekStart: thisMonday,
      weekActiveDays,
    });

    // Logging in counts as activity for the heatmap.
    await _recordActivity(userRef, userData, 1);

    // weekActiveDays is the new source of truth; lastLoginDate stays for
    // backward-compat with older clients that still infer dots from streak.
    res.json({
      streak,
      lastLoginDate: now.getTime(),
      weekActiveDays,
      weekStart: thisMonday.getTime(),
    });

  } catch (error) {
    console.error('Streak hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

router.get('/leaderboard', async (req, res) => {
  try {
    const { db } = require('../config/firebase');
    const limit = Math.min(parseInt(req.query.limit, 10) || 10, 50);

    const snapshot = await db.collection('users')
      .orderBy('totalScore', 'desc')
      .limit(limit)
      .get();

    const leaders = snapshot.docs.map((doc, idx) => {
      const data = doc.data() || {};
      const fullName = `${data.name || ''} ${data.surname || ''}`.trim();
      const fallback = (data.email || 'Anon').split('@')[0];
      return {
        uid: doc.id,
        rank: idx + 1,
        name: fullName.length > 0 ? fullName : fallback,
        score: data.totalScore || 0,
      };
    });

    res.json({ leaders });
  } catch (error) {
    console.error('Leaderboard hatası:', error);
    res.status(500).json({ error: 'Sunucu hatası' });
  }
});

module.exports = router;