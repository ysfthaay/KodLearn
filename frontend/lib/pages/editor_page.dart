import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../widgets/confetti_burst.dart';
import '../widgets/staggered_fade_in.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  // Custom controller paints the same text with token-level colors via
  // `buildTextSpan`. The TextField itself doesn't need to know.
  final _codeController = _CSyntaxController(text: '''#include <stdio.h>

int main() {
    printf("Merhaba Dunya!\\n");
    return 0;
}''');

  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _terminalScrollController = ScrollController();
  final _terminalInputController = TextEditingController();
  final _terminalFocusNode = FocusNode();

  String _terminalOutput = '';
  bool _isRunning = false;
  int _accuracy = 0;
  bool _completed = false;
  bool _isChatLoading = false;
  Map<String, dynamic>? _problem;
  List<Map<String, String>> _chatHistory = [];

  // Bumped each time the user completes a problem in this session. Used as
  // the trigger key for the ConfettiBurst — incrementing replays the burst.
  int _confettiTrigger = 0;

  // ── İpucu (hint) state ──
  // `_errorLine` is 1-indexed; 0 means "no line to highlight". When > 0, an
  // overlay band is painted behind the code area at that line.
  bool _isHintLoading = false;
  int _errorLine = 0;
  // Must match TextField fontSize * height in the code area. Keep them in
  // lock-step so the highlight band lines up exactly with the row glyphs.
  static const double _kCodeFontSize = 14.0;
  static const double _kCodeLineHeightFactor = 1.6;
  static const double _kCodeLineHeight = _kCodeFontSize * _kCodeLineHeightFactor;
  static const double _kCodePadding = 16.0;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  // ── Session persistence ──
  // Per-problem document at users/{uid}/editorSessions/{problemId}.
  // Stores `code` (latest text) + `updatedAt` (server timestamp). On mount we
  // read it back, restore the code, and toast the user with the timestamp.
  DocumentReference<Map<String, dynamic>>? _sessionRef;
  Timer? _autoSaveTimer;
  bool _sessionInitialised = false;

  static const bg = Color.fromARGB(255, 227, 226, 226);
  static const accentColor = Color.fromARGB(255, 175, 76, 0);
  static const textColor = Colors.black;
  static const subtitleColor = Color.fromARGB(128, 0, 0, 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = GoRouterState.of(context);
    if (state.extra != null && state.extra is Map<String, dynamic>) {
      _problem = state.extra as Map<String, dynamic>;
    }
    // Kick off the session restore exactly once, after _problem is known.
    if (!_sessionInitialised && _problem != null) {
      _sessionInitialised = true;
      _initSession();
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Best-effort final save when leaving the page. Fire-and-forget; we don't
    // await because dispose is sync. The Firestore client batches and ships.
    _saveSession();
    _subscription?.cancel();
    _channel?.sink.close();
    _terminalFocusNode.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Session persistence
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _initSession() async {
    final user = FirebaseAuth.instance.currentUser;
    final pid = _problem?['id'] as String?;
    if (user == null || pid == null) return;

    _sessionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('editorSessions')
        .doc(pid);

    try {
      final snap = await _sessionRef!.get();
      if (snap.exists && mounted) {
        final data = snap.data();
        final savedCode = data?['code'] as String?;
        final ts = data?['updatedAt'] as Timestamp?;

        // Restore code only if there is meaningful saved content.
        if (savedCode != null && savedCode.trim().isNotEmpty) {
          _codeController.text = savedCode;
        }

        if (ts != null) {
          // Schedule the snackbar for after the first frame so the Scaffold
          // is mounted and ScaffoldMessenger can find it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showWelcomeBack(ts.toDate());
          });
        }
      }
    } catch (e) {
      debugPrint('Session restore failed: $e');
    }

    // Autosave every 30s while the editor is open.
    _autoSaveTimer?.cancel();
    _autoSaveTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _saveSession());
  }

  Future<void> _saveSession() async {
    final ref = _sessionRef;
    if (ref == null) return;
    try {
      await ref.set({
        'code': _codeController.text,
        'updatedAt': FieldValue.serverTimestamp(),
        'problemTitle': _problem?['title'],
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Session save failed: $e');
    }
  }

  // "12 May 2026, 14:30" — no intl dependency, just hand-rolled Turkish.
  String _formatTr(DateTime d) {
    const months = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }

  void _showWelcomeBack(DateTime when) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final formatted = _formatTr(when);
    // Compact, top-floating toast. Slides in from above, hangs for 4s,
    // slides back out. No ScaffoldMessenger involved — that gave us a
    // tall bottom banner that ate into the editor's vertical space.
    final entry = OverlayEntry(
      builder: (_) => _SessionToast(
        message: 'Son oturum',
        timestamp: formatted,
      ),
    );
    overlay.insert(entry);
    // Auto-remove after the toast's full in-hang-out cycle finishes.
    Future.delayed(const Duration(milliseconds: 4400), () {
      if (entry.mounted) entry.remove();
    });
  }

 String _problemDescription() {
  final descriptions = {
    '1':  'printf ile "Merhaba Dunya!" yazdır.',
    '2':  '5 ve 7\'yi topla, sonucu yazdır.',
    '3':  'Yarıçapı 5 olan dairenin alanını hesapla (pi=3.14).',
    '4':  '20°C\'yi Fahrenheit\'a çevir.',
    '5':  'Kenarları 4 ve 7 olan dikdörtgenin çevresini yazdır.',
    '6':  '1\'den 10\'a kadar boşluklu yazdır.',
    '7':  '14 sayısı tek mi çift mi?',
    '8':  '5\'in çarpım tablosunu yazdır.',
    '9':  'Vize 45, final 70 → geçti mi?',
    '10': '1-15 arası FizzBuzz.',
    '11': 'faktoriyel(5) fonksiyonu yaz.',
    '12': 'maxBul(15, 25) fonksiyonu yaz.',
    '13': '17 asal mı?',
    '14': '2 üzeri 3\'ü hesapla.',
    '15': '70 kg için günlük protein hesapla.',
    '16': '{12,45,7,89,23} içinde en büyüğü bul.',
    '17': '{10,25,30,45,50} içinde 30\'u ara.',
    '18': '{5,2,8,1,3} dizisini sırala.',
    '19': '"KodLearn" stringini tersine çevir.',
    '20': 'Piyon indeks 7\'de mi? Terfi!',
    '21': 'Pointer ile değişkeni 100 yap.',
    '22': '"C Programlama"yı char pointer ile yazdır.',
    '23': '{1,2,3,4,5} toplamını pointer ile hesapla.',
    '24': '"KodLearn" uzunluğunu pointer ile bul.',
    '25': 'a=10, b=20\'yi pointer ile swap et.',
    '26': 'Ogrenci struct: Ali, 20, 85.5 yazdır.',
    '27': 'Antrenman struct: Bench Press, 4, 10 yazdır.',
    '28': '(0,0) ile (3,4) arası mesafeyi hesapla.',
    '29': '"sonuc.txt"e yaz, "Dosya yazildi" yazdır.',
    '30': '"veri.txt" dosyasından oku ve yazdır.',
  };
  return descriptions[_problem?['id']] ?? '';
}

  void _connectAndRun() {
    _subscription?.cancel();
    _channel?.sink.close();

    // Snapshot the code at run-time so the user's progress is persisted even
    // if they close the tab before the autosave timer fires.
    _saveSession();

    setState(() {
      _terminalOutput = '';
      _isRunning = true;
      _accuracy = 0;
      _completed = false;
      _errorLine = 0; // stale highlight from previous hint no longer relevant
    });

    _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:3000'));

    _subscription = _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        final type = data['type'];

        if (type == 'output') {
          setState(() {
            _terminalOutput += data['data'];
          });
          _scrollTerminalToBottom();
          // Çıktı geldiğinde terminale odaklan ki kullanıcı hemen yazabilsin
          _terminalFocusNode.requestFocus();
        } else if (type == 'error') {
          final chunk = data['data'] as String;
          setState(() {
            _terminalOutput += chunk;
            // Compile errors look like `.../foo.c:7:13: error: ...`. Pull the
            // first :LINE:COL: triple we see and pin _errorLine. Now that the
            // backend's setvbuf shim stays on one line, this number matches
            // the editor's line numbers directly.
            if (_errorLine == 0) {
              final m = RegExp(r':(\d+):\d+:').firstMatch(_terminalOutput);
              final parsed = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
              if (parsed > 0) _errorLine = parsed;
            }
          });
          _scrollTerminalToBottom();
        } else if (type == 'started') {
          setState(() => _terminalOutput = '');
        } else if (type == 'done') {
          setState(() {
            _isRunning = false;
          });
          _scrollTerminalToBottom();
          if (_terminalOutput.isNotEmpty) {
            _getAiFeedback();
          }
        }
      },
      onError: (e) {
        setState(() {
          _terminalOutput += '\nBağlantı hatası: $e';
          _isRunning = false;
        });
      },
      onDone: () {
        setState(() => _isRunning = false);
      },
    );

    _channel!.sink.add(jsonEncode({
      'type': 'run',
      'code': _codeController.text,
    }));
  }

  void _sendTerminalInput(String input) {
    if (_channel != null && _isRunning) {
      setState(() {
        // Kullanıcının yazdığını terminale kendimiz ekliyoruz ki ekranda kalsın
        _terminalOutput += '$input\n';
      });
      _channel!.sink.add(jsonEncode({
        'type': 'input',
        'data': '$input\n', // Backend genelde enter (\n) karakterini bekler
      }));
      _terminalInputController.clear();
      _scrollTerminalToBottom();
      
      // Tekrar focus istiyoruz ki arka arkaya input girebilsin
      _terminalFocusNode.requestFocus();
    }
  }

  Future<void> _getAiFeedback() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/code/run'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': _codeController.text,
          'problemId': _problem?['id'],
          'uid': user?.uid,
          'stdin': '',
        }),
      );
      final data = jsonDecode(response.body);
      final feedback = data['feedback'] ?? '';
      final accuracy = data['accuracy'] ?? 0;

      final wasCompleted = _completed;
      setState(() {
        _accuracy = accuracy;
        _completed = accuracy >= 90;
        if (!wasCompleted && _completed) {
          // Flipped to "completed" — fire the celebration.
          _confettiTrigger++;
        }
        if (feedback.isNotEmpty) {
          _chatHistory.add({'role': 'assistant', 'content': feedback});
        }
      });
      _scrollChatToBottom();
    } catch (e) {
      debugPrint('AI feedback hatası: $e');
    }
  }

  // ── İpucu Al (Get Hint) — Gemini structured-output call ──
  // Hits /api/code/hint, expects {success, errorLine, hint}. The hint is
  // pushed into the chat panel with a `hint` role so it renders distinctly,
  // and `errorLine` is parked in state so the editor paints the band.
  Future<void> _fetchHint() async {
    if (_isHintLoading) return;
    setState(() {
      _isHintLoading = true;
    });
    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/code/hint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': _codeController.text,
          'problemId': _problem?['id'],
        }),
      );
      if (response.statusCode != 200) {
        throw 'HTTP ${response.statusCode}';
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final success = (data['success'] as bool?) ?? false;
      final errorLine = (data['errorLine'] as num?)?.toInt() ?? 0;
      final hint = (data['hint'] as String?) ?? '';

      if (!mounted) return;
      setState(() {
        _errorLine = errorLine;
        if (hint.isNotEmpty) {
          _chatHistory.add({
            'role': 'hint',
            'content': success ? '✅ $hint' : hint,
          });
        }
      });
      _scrollChatToBottom();
    } catch (e) {
      debugPrint('Hint hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'İpucu alınamadı. Tekrar dene.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isHintLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _chatHistory.add({'role': 'user', 'content': message});
      _chatController.clear();
      _isChatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/code/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'problemId': _problem?['id'],
          'chatHistory': _chatHistory,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': data['response'] ?? ''});
      });
      _scrollChatToBottom();
    } catch (e) {
      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': 'Bağlantı hatası: $e'});
      });
    } finally {
      setState(() => _isChatLoading = false);
    }
  }

  void _scrollTerminalToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_terminalScrollController.hasClients) {
        _terminalScrollController.animateTo(
          _terminalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _accuracyColor() {
    if (_accuracy >= 90) return const Color(0xFF10B981);
    if (_accuracy >= 50) return accentColor;
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          Column(
        children: [
          // Navbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              border: Border(bottom: BorderSide(color: accentColor.withOpacity(0.12), width: 1.5)),
              boxShadow: [BoxShadow(color: accentColor.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 4))],
            ),
            // Navbar items cascade in on a fast interval so they're settled
            // by the time the main code/chat area finishes its own stagger.
            child: StaggeredGroup(
              interval: const Duration(milliseconds: 55),
              itemDuration: const Duration(milliseconds: 420),
              slideOffset: 10,
              child: Row(
              children: [
                StaggeredChild(
                  index: 0,
                  child: GestureDetector(
                  onTap: () {
                    _channel?.sink.add(jsonEncode({'type': 'kill'}));
                    context.go('/dashboard');
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withOpacity(0.2)),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: accentColor, size: 18),
                  ),
                ),
                ),
                const SizedBox(width: 14),
                StaggeredChild(
                  index: 1,
                  child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.black, Color.fromARGB(255, 175, 76, 0), Colors.white],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.code_rounded, color: Colors.white, size: 16),
                ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StaggeredChild(
                    index: 2,
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_problem?['title'] ?? 'Kod Editörü',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                      if (_problemDescription().isNotEmpty)
                        Text(_problemDescription(),
                            style: const TextStyle(fontSize: 11, color: subtitleColor),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  ),
                ),
                if (_accuracy > 0) ...[
                  StaggeredChild(
                    index: 3,
                    child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _accuracyColor().withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accuracyColor().withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        if (_completed) const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                        if (_completed) const SizedBox(width: 4),
                        Text('%$_accuracy',
                            style: TextStyle(color: _accuracyColor(), fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ),
                  ),
                  const SizedBox(width: 10),
                ],
                // Secondary action — Get Hint. Distinct from "Çalıştır"
                // visually (outlined accent, lightbulb icon).
                StaggeredChild(
                  index: 4,
                  child: GestureDetector(
                  onTap: _isHintLoading ? null : _fetchHint,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(_isHintLoading ? 0.06 : 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: accentColor.withOpacity(_isHintLoading ? 0.25 : 0.5),
                        width: 1.4,
                      ),
                    ),
                    child: Row(
                      children: [
                        _isHintLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    color: accentColor, strokeWidth: 2),
                              )
                            : const Icon(Icons.lightbulb_rounded,
                                color: accentColor, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'İpucu Al',
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ),
                const SizedBox(width: 10),
                StaggeredChild(
                  index: 5,
                  child: GestureDetector(
                  onTap: _isRunning ? null : _connectAndRun,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: _isRunning
                          ? null
                          : const LinearGradient(
                              colors: [Colors.black, Color.fromARGB(255, 175, 76, 0),Colors.white],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: _isRunning ? Colors.grey.withOpacity(0.3) : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _isRunning
                          ? []
                          : [BoxShadow(color: accentColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        _isRunning
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(_isRunning ? 'Çalışıyor...' : 'Çalıştır',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                ),
              ],
            ),
            ),
          ),

          if (_completed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                border: Border(bottom: BorderSide(color: const Color(0xFF10B981).withOpacity(0.2))),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.celebration_rounded, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text('Tebrikler! Problemi tamamladın! +10 puan 🎉',
                      style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),

          Expanded(
            // Main row staggers in slightly behind the navbar — first the
            // code editor (the eye lands there), then the chat panel.
            child: StaggeredGroup(
              startDelay: const Duration(milliseconds: 260),
              interval: const Duration(milliseconds: 110),
              slideOffset: 18,
              child: Row(
              children: [
                // Code editor + terminal
                Expanded(
                  flex: 2,
                  child: StaggeredChild(
                    index: 0,
                    child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children: [
                          // macOS header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              border: const Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
                            ),
                            child: Row(
                              children: [
                                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF5F57), shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF28C840), shape: BoxShape.circle)),
                                const SizedBox(width: 14),
                                Text('main.c', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontFamily: 'monospace')),
                              ],
                            ),
                          ),

                          // Code area
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(_kCodePadding),
                              // Stack lets us paint a horizontal band UNDER
                              // the TextField at the offending line. We need
                              // a stable, predictable line height — that's
                              // why _kCodeLineHeight is derived from the same
                              // fontSize × height used by the TextField.
                              child: Stack(
                                children: [
                                  if (_errorLine > 0)
                                    Positioned(
                                      top: (_errorLine - 1) * _kCodeLineHeight,
                                      left: 0,
                                      right: 0,
                                      height: _kCodeLineHeight,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withOpacity(0.18),
                                          border: const Border(
                                            left: BorderSide(
                                              color: Color(0xFFEF4444),
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  CallbackShortcuts(
                                    bindings: {
                                      const SingleActivator(LogicalKeyboardKey.tab): () {
                                        final text = _codeController.text;
                                        final selection = _codeController.selection;
                                        final newText = text.replaceRange(selection.start, selection.end, '    ');
                                        _codeController.value = TextEditingValue(
                                          text: newText,
                                          selection: TextSelection.collapsed(offset: selection.start + 4),
                                        );
                                      },
                                    },
                                    child: TextField(
                                      controller: _codeController,
                                      maxLines: null,
                                      expands: true,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontFamily: 'monospace',
                                        fontSize: _kCodeFontSize,
                                        height: _kCodeLineHeightFactor,
                                      ),
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText: '// C kodunu buraya yaz...',
                                        hintStyle: TextStyle(color: Color(0xFF555555)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Terminal
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              border: const Border(top: BorderSide(color: Color(0xFF2A2A2A))),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Terminal header
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.terminal_rounded, color: Color(0xFF10B981), size: 13),
                                      const SizedBox(width: 6),
                                      const Text('TERMINAL',
                                          style: TextStyle(
                                              color: Color(0xFF10B981),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              letterSpacing: 1)),
                                      const Spacer(),
                                      // Secondary "Çalıştır" — same action as
                                      // the navbar button, placed here so the
                                      // user doesn't have to scroll back up
                                      // after editing the code.
                                      _TerminalRunButton(
                                        isRunning: _isRunning,
                                        onTap: _isRunning ? null : _connectAndRun,
                                      ),
                                      if (!_isRunning && _terminalOutput.isNotEmpty) ...[
                                        const SizedBox(width: 10),
                                        GestureDetector(
                                          onTap: () => setState(() => _terminalOutput = ''),
                                          child: const Text(
                                            'Temizle',
                                            style: TextStyle(color: Color(0xFF888888), fontSize: 10),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Terminal Output & Inline Input Area
                                Expanded(
                                  child: GestureDetector(
                                    // Terminal alanina tiklanirsa TextField'a odaklan
                                    onTap: () {
                                      if (_isRunning) _terminalFocusNode.requestFocus();
                                    },
                                    child: Container(
                                      color: Colors.transparent, // Tıklamaları yakalaması için
                                      width: double.infinity,
                                      child: SingleChildScrollView(
                                        controller: _terminalScrollController,
                                        padding: const EdgeInsets.all(16),
                                        child: _terminalOutput.isEmpty && !_isRunning
                                            ? RichText(
                                                text: TextSpan(
                                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                                  children: [
                                                    TextSpan(text: '➜  ', style: TextStyle(color: const Color(0xFF10B981).withOpacity(0.7))),
                                                    const TextSpan(text: 'Çalıştır butonuna bas...', style: TextStyle(color: Color(0xFF555555))),
                                                  ],
                                                ),
                                              )
                                            : Builder(
                                                builder: (context) {
                                                  // Çıktıyı satırlara böl
                                                  List<String> lines = _terminalOutput.split('\n');
                                                  String lastLine = lines.isNotEmpty ? lines.last : '';
                                                  String prevLines = lines.length > 1 
                                                      ? lines.sublist(0, lines.length - 1).join('\n') + '\n' 
                                                      : '';

                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // Önceki satırların tümü normal Text olarak
                                                      if (prevLines.isNotEmpty)
                                                        Text(prevLines, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
                                                      
                                                      // En son satır (prompt kısmı) ve yanına TextField
                                                      if (_isRunning)
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                          children: [
                                                            Text(lastLine, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
                                                            Expanded(
                                                              child: TextField(
                                                                controller: _terminalInputController,
                                                                focusNode: _terminalFocusNode,
                                                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, height: 1.5),
                                                                cursorColor: Colors.white,
                                                                cursorWidth: 2,
                                                                decoration: const InputDecoration(
                                                                  border: InputBorder.none,
                                                                  isDense: true,
                                                                  contentPadding: EdgeInsets.zero,
                                                                ),
                                                                onSubmitted: (val) {
                                                                  if (val.isNotEmpty) {
                                                                    _sendTerminalInput(val);
                                                                  }
                                                                },
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      else if (lastLine.isNotEmpty)
                                                        Text(lastLine, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, height: 1.5)),
                                                    ],
                                                  );
                                                },
                                              ),
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
                  ),
                ),

                // Chat panel (Aynı kaldı)
                StaggeredChild(
                  index: 1,
                  child: Container(
                  width: 320,
                  margin: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withOpacity(0.15), width: 1.5),
                    boxShadow: [BoxShadow(color: accentColor.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            border: Border(bottom: BorderSide(color: accentColor.withOpacity(0.12))),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.black, Color.fromARGB(255, 175, 76, 0),Colors.white],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Center(
                                  child: Text('K', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Koda', style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14)),
                                  Text('C Programlama Eğitmeni', style: TextStyle(color: subtitleColor, fontSize: 11)),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Çevrimiçi',
                                    style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: _chatHistory.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(color: accentColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                                        child: const Icon(Icons.chat_bubble_outline_rounded, color: accentColor, size: 22),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text('Kodu çalıştır veya\nbana bir şey sor!',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: subtitleColor, fontSize: 13)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  controller: _chatScrollController,
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _chatHistory.length + (_isChatLoading ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _chatHistory.length) {
                                      return Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Row(
                                          children: [
                                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: accentColor, shape: BoxShape.circle)),
                                            const SizedBox(width: 6),
                                            const Text('Koda düşünüyor...', style: TextStyle(color: subtitleColor, fontSize: 12)),
                                          ],
                                        ),
                                      );
                                    }
                                    final msg = _chatHistory[index];
                                    final role = msg['role'];
                                    final isUser = role == 'user';
                                    final isHint = role == 'hint';
                                    return Align(
                                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.all(12),
                                        constraints: const BoxConstraints(maxWidth: 240),
                                        decoration: BoxDecoration(
                                          color: isUser
                                              ? accentColor
                                              : (isHint
                                                  ? const Color(0xFFFFF4E5) // warm hint cream
                                                  : Colors.white),
                                          borderRadius: BorderRadius.circular(14).copyWith(
                                            bottomRight: isUser ? const Radius.circular(4) : null,
                                            bottomLeft: !isUser ? const Radius.circular(4) : null,
                                          ),
                                          border: isUser
                                              ? null
                                              : Border.all(
                                                  color: accentColor
                                                      .withOpacity(isHint ? 0.45 : 0.15),
                                                  width: isHint ? 1.2 : 1.0,
                                                ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: isHint
                                            ? Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.lightbulb_rounded,
                                                    color: accentColor,
                                                    size: 15,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      msg['content'] ?? '',
                                                      style: const TextStyle(
                                                        color: textColor,
                                                        fontSize: 13,
                                                        height: 1.5,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                msg['content'] ?? '',
                                                style: TextStyle(
                                                  color: isUser ? Colors.white : textColor,
                                                  fontSize: 13,
                                                  height: 1.5,
                                                ),
                                              ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            border: Border(top: BorderSide(color: accentColor.withOpacity(0.12))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _chatController,
                                  style: const TextStyle(fontSize: 13, color: textColor),
                                  decoration: InputDecoration(
                                    hintText: 'Koda\'ya bir şey sor...',
                                    hintStyle: const TextStyle(color: subtitleColor, fontSize: 13),
                                    filled: true,
                                    fillColor: bg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: accentColor.withOpacity(0.2)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: accentColor.withOpacity(0.2)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: accentColor, width: 1.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _isChatLoading ? null : _sendMessage,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Colors.black, Color.fromARGB(255, 175, 76, 0),Colors.white],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 16),
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
              ],
            ),
            ),
          ),
        ],
      ),
          // Confetti overlay — fires on every transition into _completed.
          // Lives in its own Positioned.fill above the column so the burst
          // can spray across the entire viewport, including the chat panel.
          if (_confettiTrigger > 0)
            Positioned.fill(
              child: ConfettiBurst(
                key: const ValueKey('confetti-overlay'),
                trigger: _confettiTrigger,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Secondary "Çalıştır" pill that lives in the terminal header so the user
// can re-run after editing without scrolling back to the navbar. Same action
// as the primary run button; renders compact and shows running state.
// ─────────────────────────────────────────────────────────────────────────────
class _TerminalRunButton extends StatefulWidget {
  final bool isRunning;
  final VoidCallback? onTap;

  const _TerminalRunButton({required this.isRunning, required this.onTap});

  @override
  State<_TerminalRunButton> createState() => _TerminalRunButtonState();
}

class _TerminalRunButtonState extends State<_TerminalRunButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    const accent = Color(0xFFAF4C00);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) { if (enabled) setState(() => _hovered = true); },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: widget.isRunning
                ? null
                : const LinearGradient(
                    colors: [accent, Color(0xFFD65C00)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            color: widget.isRunning ? const Color(0xFF333333) : null,
            borderRadius: BorderRadius.circular(8),
            boxShadow: widget.isRunning || !_hovered
                ? const []
                : [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.isRunning
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.4, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 13),
              const SizedBox(width: 5),
              Text(
                widget.isRunning ? 'Çalışıyor' : 'Çalıştır',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// C syntax-highlighting controller.
//
// Overrides `buildTextSpan` so the same text the user types is rendered as a
// styled TextSpan tree — keywords, types, strings, comments, numbers, the
// preprocessor and function-call identifiers each get their own color. The
// TextField is otherwise untouched: cursor, selection, and editing all
// continue to work as they would with a plain TextEditingController.
// ─────────────────────────────────────────────────────────────────────────────
class _CSyntaxController extends TextEditingController {
  _CSyntaxController({super.text});

  // One Dark-ish palette, picked to read well on the editor's #1A1A1A bg.
  static const _kComment      = Color(0xFF6B7280); // gray, italic
  static const _kString       = Color(0xFF98C379); // green
  static const _kPreprocessor = Color(0xFFC678DD); // purple
  static const _kNumber       = Color(0xFFD19A66); // amber
  static const _kKeyword      = Color(0xFFE5C07B); // soft yellow-orange
  static const _kType         = Color(0xFF56B6C2); // cyan
  static const _kFunction     = Color(0xFF61AFEF); // blue

  // Single regex with named groups, alternation tried left-to-right. The
  // order matters: comments and strings come first so their contents (which
  // might look like keywords) are not re-highlighted.
  static final RegExp _regex = RegExp(
    r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/)'
    r'|(?<string>"(?:\\.|[^"\\])*"' r"|'(?:\\.|[^'\\])*')"
    r'|(?<preprocessor>^\s*#\s*\w+)'
    r'|(?<number>\b\d+(?:\.\d+)?[fFlLuU]?\b)'
    r'|(?<keyword>\b(?:if|else|for|while|do|switch|case|break|continue|return|goto|default|sizeof|typedef|struct|union|enum|const|static|extern|volatile|register|inline|auto)\b)'
    r'|(?<type>\b(?:int|char|float|double|long|short|void|signed|unsigned|bool|_Bool|FILE|size_t|ssize_t)\b)'
    r'|(?<function>\b[a-zA-Z_]\w*(?=\s*\())',
    multiLine: true,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final src = text;
    if (src.isEmpty) {
      return TextSpan(text: '', style: base);
    }

    final children = <TextSpan>[];
    int cursor = 0;
    for (final m in _regex.allMatches(src)) {
      if (m.start > cursor) {
        children.add(TextSpan(text: src.substring(cursor, m.start), style: base));
      }
      Color? color;
      FontStyle? fontStyle;
      if (m.namedGroup('comment') != null) {
        color = _kComment;
        fontStyle = FontStyle.italic;
      } else if (m.namedGroup('string') != null) {
        color = _kString;
      } else if (m.namedGroup('preprocessor') != null) {
        color = _kPreprocessor;
      } else if (m.namedGroup('number') != null) {
        color = _kNumber;
      } else if (m.namedGroup('keyword') != null) {
        color = _kKeyword;
      } else if (m.namedGroup('type') != null) {
        color = _kType;
      } else if (m.namedGroup('function') != null) {
        color = _kFunction;
      }
      children.add(TextSpan(
        text: m[0],
        style: base.copyWith(color: color, fontStyle: fontStyle),
      ));
      cursor = m.end;
    }
    if (cursor < src.length) {
      children.add(TextSpan(text: src.substring(cursor), style: base));
    }
    return TextSpan(style: base, children: children);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact top-floating session toast.
//
// Slides in from the top, hangs for ~3 seconds, slides out. Single-row layout
// with a small history icon, a label and a bold timestamp. Sits high enough
// not to cover the navbar's action buttons.
// ─────────────────────────────────────────────────────────────────────────────
class _SessionToast extends StatefulWidget {
  final String message;
  final String timestamp;

  const _SessionToast({required this.message, required this.timestamp});

  @override
  State<_SessionToast> createState() => _SessionToastState();
}

class _SessionToastState extends State<_SessionToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    // 0.00–0.07: slide+fade in. 0.07–0.93: hold. 0.93–1.00: slide+fade out.
    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 7,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 86),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 7,
      ),
    ]).animate(_controller);
    _offset = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween(begin: const Offset(0, -0.6), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 7,
      ),
      TweenSequenceItem(tween: ConstantTween(Offset.zero), weight: 86),
      TweenSequenceItem(
        tween: Tween(begin: Offset.zero, end: const Offset(0, -0.6))
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 7,
      ),
    ]).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      // Sits just below the navbar's bottom edge.
      top: mq.padding.top + 80,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(
                position: _offset,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      // Slightly translucent dark glass, accent border, soft
                      // shadow. Sits at attention without dominating.
                      color: const Color(0xFF1A1A1A).withOpacity(0.94),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFAF4C00).withOpacity(0.55),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFAF4C00).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.history_rounded,
                            size: 13,
                            color: Color(0xFFFFB680),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                              children: [
                                TextSpan(text: '${widget.message} '),
                                TextSpan(
                                  text: widget.timestamp,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFFB680),
                                  ),
                                ),
                              ],
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
        ),
      ),
    );
  }
}