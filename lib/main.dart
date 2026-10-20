import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';
import 'social.dart';

const String apiBase = 'https://mvp-news-api.mvp-shop.workers.dev';
const String discordUrl = 'https://playmvp.org/discord';
const String siteUrl = 'https://playmvp.org';
const String storeUrl = 'https://playmvp.org/store/';
const String serverIp = 'mc.playmvp.org';
const String pushTopic = 'news';

const Color accent = Color(0xFF0070B8);
const Color accentLight = Color(0xFF0094E6);
const Color accentDark = Color(0xFF0A4D86);

/// White theme switch (Settings > Theme: Default / Light). Every color below reads it.
bool kWhite = false;

/// Dark theme (Settings > Theme: Dark).
bool kDark = false;
final ValueNotifier<ThemeMode> themeMode =
    ValueNotifier<ThemeMode>(ThemeMode.system);

Color get bgColor =>
    kDark ? const Color(0xFF07111B) : kWhite ? const Color(0xFFFFFFFF) : const Color(0xFFEEF2F6);
Color get surfaceColor => kDark ? const Color(0xFF0F1D2B) : kWhite ? const Color(0xFFF1F5F9) : Colors.white;
Color get inkColor =>
    kDark ? const Color(0xFFE8F1F8) : kWhite ? const Color(0xFF0B1B2B) : const Color(0xFF0B1B2B);
Color get mutedColor =>
    kDark ? const Color(0xFF9DB2C4) : kWhite ? const Color(0xFF5B6F82) : const Color(0xFF5B6F82);
Color get navMuted =>
    kDark ? const Color(0xFF6E8396) : kWhite ? const Color(0xFF8A9AAB) : const Color(0xFF8A9AAB);
Color get tintBlue =>
    kDark ? const Color(0xFF10304A) : kWhite ? const Color(0xFFE3F2FC) : const Color(0xFFE3F2FC);
Color get tintAmber =>
    kDark ? const Color(0xFF3A2E10) : kWhite ? const Color(0xFFFFF1D6) : const Color(0xFFFFF1D6);
Color get tintRed =>
    kDark ? const Color(0xFF3A1519) : kWhite ? const Color(0xFFFDE4E6) : const Color(0xFFFDE4E6);
Color get tintGrey =>
    kDark ? const Color(0xFF16222F) : kWhite ? const Color(0xFFE8EEF4) : const Color(0xFFF1F5F9);
Color get tintPoll =>
    kDark ? const Color(0xFF0F2A40) : kWhite ? const Color(0xFFEAF5FD) : const Color(0xFFEAF5FD);
Color get lineColor =>
    kDark ? const Color(0xFF22384B) : kWhite ? const Color(0xFFD3E3EE) : const Color(0xFFD3E3EE);

String firebaseError = '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseOk = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      firebaseOk = true;
    } catch (e) {
      firebaseOk = false;
      firebaseError = e.toString();
    }
  }
  try {
    final p = await SharedPreferences.getInstance();
    themeMode.value =
        p.getString('theme_mode') == 'light'
            ? ThemeMode.light
            : p.getString('theme_mode') == 'dark'
                ? ThemeMode.dark
                : ThemeMode.system;
  } catch (_) {}
  runApp(MvpApp(firebaseOk: firebaseOk));
}

class MvpApp extends StatelessWidget {
  const MvpApp({super.key, required this.firebaseOk});

  final bool firebaseOk;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) {
        kWhite = mode == ThemeMode.light;
        kDark = mode == ThemeMode.dark;
        return MaterialApp(
          title: 'MVP',
          debugShowCheckedModeBanner: false,
          themeMode: kDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: accent).copyWith(
              primary: accent,
              surface: Colors.white,
            ),
            scaffoldBackgroundColor: bgColor,
            appBarTheme: AppBarTheme(
              backgroundColor: bgColor,
              foregroundColor: inkColor,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
                    seedColor: accent, brightness: Brightness.dark)
                .copyWith(primary: accentLight, surface: surfaceColor),
            scaffoldBackgroundColor: bgColor,
            appBarTheme: AppBarTheme(
              backgroundColor: bgColor,
              foregroundColor: inkColor,
              elevation: 0,
            ),
          ),
          home: Shell(firebaseOk: firebaseOk),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- data

class PollOption {
  PollOption({required this.id, required this.text, required this.votes});
  final int id;
  final String text;
  int votes;
}

class Poll {
  Poll({
    required this.id,
    required this.question,
    required this.closed,
    required this.options,
    required this.my,
  });

  final int id;
  final String question;
  bool closed;
  final List<PollOption> options;
  int my;

  int get total => options.fold<int>(0, (a, o) => a + o.votes);

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        id: (j['id'] as num).toInt(),
        question: (j['question'] ?? '').toString(),
        closed: j['closed'] == true,
        my: (j['my'] as num?)?.toInt() ?? 0,
        options: ((j['options'] as List<dynamic>?) ?? <dynamic>[])
            .map((e) => PollOption(
                  id: ((e as Map<String, dynamic>)['id'] as num).toInt(),
                  text: (e['text'] ?? '').toString(),
                  votes: (e['votes'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );
}

class CardStyle {
  CardStyle({required this.id, required this.name, required this.colors, this.anim = false});
  final bool anim;
  final String id;
  final String name;
  final List<Color> colors;

  factory CardStyle.fromJson(Map<String, dynamic> j) => CardStyle(
        id: (j['id'] ?? 'default').toString(),
        name: (j['name'] ?? '').toString(),
        anim: j['anim'] == true,
        colors: ((j['colors'] as List<dynamic>?) ?? <dynamic>[])
            .map((c) => Color(
                int.tryParse('FF${c.toString().replaceAll('#', '')}',
                        radix: 16) ??
                    0xFF0070B8))
            .toList(),
      );
}

// Pixel icons for medals (12x12, drawn in code, no emoji). Same set as on the website.
const Map<String, int> kMedalPalette = {
  'Y': 0xFFFFCF3A,
  'y': 0xFFC98A00,
  'R': 0xFFE8424F,
  'B': 0xFF2EA2EA,
  'O': 0xFFFF8A1F,
  'k': 0xFF3A1D08,
  'G': 0xFF3FAE4A,
  'g': 0xFF2A7A33,
  'W': 0xFFF2F6FA,
  'w': 0xFFB9C6D3,
  'I': 0xFFBFE9FF,
  'C': 0xFF5EE3F0,
  'c': 0xFFD6FBFF,
  'T': 0xFF8A5A2B,
  'P': 0xFF9AA7B4,
  'D': 0xFF1F6FA8,
};
const Map<String, List<String>> kMedalIcons = {
  'medal': ['..RR....BB..', '..RRR..BBB..', '...RRR.BB...', '....RRBB....', '.....yy.....', '...yYYYYy...', '..yYYyyYYy..', '..YYyYYyYY..', '..YYyYYyYY..', '..yYYyyYYy..', '...yYYYYy...', '.....yy.....'],
  'star': ['.....YY.....', '.....YY.....', '....YYYY....', '....YYYY....', 'YYYYYYYYYYYY', '.YYYYYYYYYY.', '..YYYYYYYY..', '...YYYYYY...', '...YYYYYY...', '..YYY..YYY..', '..YY....YY..', '.YY......YY.'],
  'trophy': ['.YYYYYYYYYY.', 'YYYYYYYYYYYY', 'Y.YYYYYYyY.Y', 'Y.YYYYYYyY.Y', '.YYYYYYYyYY.', '...YYYYyY...', '....YYyY....', '.....yY.....', '.....yY.....', '....yYYY....', '...TTTTTT...', '...TTTTTT...'],
  'pumpkin': ['.....gg.....', '.....g......', '..OOOOOOOO..', '.OOOOOOOOOO.', 'OOkkOOOOkkOO', 'OOkkOOOOkkOO', 'OOOOOkkOOOOO', 'OOOOOOOOOOOO', 'OOkOkkkkOkOO', 'OOOkkkkkkOOO', '.OOOOOOOOOO.', '..OOOOOOOO..'],
  'ghost': ['....WWWW....', '..WWWWWWWW..', '.WWWWWWWWWW.', '.WWkkWWkkWW.', '.WWkkWWkkWW.', '.WWWWWWWWWW.', '.WWWWkkWWWW.', '.WWWWkkWWWW.', '.WWWWWWWWWW.', '.WWWWWWWWWW.', '.WWW.WW.WWW.', '.WW...W..WW.'],
  'tree': ['.....YY.....', '.....GG.....', '....GGGG....', '...GGRGGG...', '....GGGG....', '...GGGGBG...', '..GGRGGGGG..', '...GGGGGG...', '..GGGGGGYG..', '.GGGGRGGGGG.', '.....TT.....', '.....TT.....'],
  'snow': ['.....I......', '...I.I.I....', '....III.....', '.I...I...I..', '..I..I..I...', 'IIIIIIIIIII.', '..I..I..I...', '.I...I...I..', '....III.....', '...I.I.I....', '.....I......', '............'],
  'fire': ['.....R......', '....RR......', '....RRR..R..', '...RRRR.RR..', '..RRORRRRR..', '..RROORRRR..', '.RROOOORRRR.', '.RROOYOORRR.', '.RROYYYORRR.', '.RROYYYYORR.', '..RROYYORR..', '...RRRRRR...'],
  'sword': ['..........WW', '.........WwW', '........WwW.', '.......WwW..', '......WwW...', '..Y..WwW....', '...YWwW.....', '....YW......', '...TTY......', '..TT..Y.....', '.TT.........', 'TT..........'],
  'diamond': ['............', '............', '...CCCCCC...', '..CcCCCCcC..', '.CcCCCCCCcC.', 'CCCCCCCCCCCC', '.CCCCCCCCCC.', '..CCCCCCCC..', '...CCCCCC...', '....CCCC....', '.....CC.....', '............'],
  'crown': ['............', '............', 'Y....Y....Y.', 'YY..YYY..YY.', 'YYY.YYY.YYY.', 'YYYYYYYYYYY.', 'YYRYYBYYRYY.', 'YYYYYYYYYYY.', 'yyyyyyyyyyy.', '............', '............', '............'],
  'heart': ['............', '.RRR....RRR.', 'RRRRR..RRRRR', 'RRWRRRRRRRRR', 'RRRRRRRRRRRR', 'RRRRRRRRRRRR', '.RRRRRRRRRR.', '..RRRRRRRR..', '...RRRRRR...', '....RRRR....', '.....RR.....', '............'],
  'flag': ['.P..........', '.PBBBBBB....', '.PBBBBBBB...', '.PBBWWBBBB..', '.PBBWWBBBBB.', '.PBBBBBBBB..', '.PBBBBBBB...', '.P..........', '.P..........', '.P..........', '.P..........', 'PPP.........'],
};

class PixelIcon extends StatelessWidget {
  const PixelIcon(this.name, {super.key, this.size = 24});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PixelPainter(kMedalIcons[name] ?? kMedalIcons['medal']!)),
      );
}

class _PixelPainter extends CustomPainter {
  _PixelPainter(this.rows);
  final List<String> rows;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 12;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        final col = kMedalPalette[rows[y][x]];
        if (col == null) continue;
        paint.color = Color(col);
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c + 0.5, c + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) => old.rows != rows;
}

// Line icons (24x24 grid, stroke 2, round ends), drawn in code. Same set as on the website.
const Map<String, List<String>> kIconPaths = {
  'inbox': ['M3 13 L5.5 5.5 Q6 4 7.5 4 L16.5 4 Q18 4 18.5 5.5 L21 13 L21 18 Q21 20 19 20 L5 20 Q3 20 3 18 Z', 'M3 13 L8 13 L9.5 15.5 L14.5 15.5 L16 13 L21 13'],
  'medal': ['M8.5 11 L5 3 L9 3 L12 9', 'M15.5 11 L19 3 L15 3 L12 9', 'M10.5 15.5 L12 14 L12 18'],
  'star': ['M12 3 L14.7 8.6 L20.6 9.3 L16.3 13.4 L17.4 19.4 L12 16.5 L6.6 19.4 L7.7 13.4 L3.4 9.3 L9.3 8.6 Z'],
  'trophy': ['M8 4 L16 4 L16 10 Q16 14 12 14 Q8 14 8 10 Z', 'M8 6 L5.5 6 Q4 6 4 7.5 Q4 10.5 8 11', 'M16 6 L18.5 6 Q20 6 20 7.5 Q20 10.5 16 11', 'M12 14 L12 17', 'M8 20 L16 20 L15 17 L9 17 Z'],
  'pumpkin': ['M12 7 C6 7 3 9.5 3 13.5 C3 17.5 6 20 12 20 C18 20 21 17.5 21 13.5 C21 9.5 18 7 12 7 Z', 'M12 7 C9.5 9 9.5 18 12 20', 'M12 7 C14.5 9 14.5 18 12 20', 'M12 7 L12 4.5 Q12.5 3 14.5 3.5'],
  'ghost': ['M6 20 L6 10 C6 6.5 8.7 4 12 4 C15.3 4 18 6.5 18 10 L18 20 L16 18.5 L14 20 L12 18.5 L10 20 L8 18.5 Z'],
  'tree': ['M12 3 L17 9 L14.5 9 L19 15 L5 15 L9.5 9 L7 9 Z', 'M12 15 L12 20', 'M9 20 L15 20'],
  'snow': ['M12 3 L12 21', 'M4.2 7.5 L19.8 16.5', 'M4.2 16.5 L19.8 7.5', 'M10 4.5 L12 6.5 L14 4.5', 'M10 19.5 L12 17.5 L14 19.5'],
  'fire': ['M12 21 C8 21 6 18.5 6 15.5 C6 11.5 9 10 9.5 6 C11.5 7.5 12.5 9.5 12.5 11 C14 10 14.5 8.5 14.5 7 C16.5 9 18 11.5 18 15 C18 18.5 15.5 21 12 21 Z', 'M12 21 C10.5 21 9.5 19.8 9.5 18.3 C9.5 16.5 11 15.8 12 14 C13 15.8 14.5 16.5 14.5 18.3 C14.5 19.8 13.5 21 12 21 Z'],
  'sword': ['M20 4 L20 8 L10 18 L6 14 L16 4 Z', 'M5 13 L11 19', 'M7.5 16.5 L4 20'],
  'diamond': ['M7 4 L17 4 L21 9 L12 20 L3 9 Z', 'M3 9 L21 9', 'M9.5 4 L8 9 L12 20 L16 9 L14.5 4'],
  'crown': ['M4 17 L3 7 L8 11 L12 5 L16 11 L21 7 L20 17 Z', 'M4 20 L20 20'],
  'heart': ['M12 20 C12 20 3 14.5 3 8.8 C3 6 5.2 4 7.8 4 C9.6 4 11.1 5 12 6.5 C12.9 5 14.4 4 16.2 4 C18.8 4 21 6 21 8.8 C21 14.5 12 20 12 20 Z'],
  'flag': ['M5 21 L5 4', 'M5 4 L17 4 L15 8 L17 12 L5 12'],
};
const Map<String, List<List<double>>> kIconCircles = {
  'medal': [[12.0, 16.0, 5.0]],
  'ghost': [[10.0, 10.0, 1.0], [14.0, 10.0, 1.0]],
};

// draws one line icon in the given colour
class LineIcon extends StatelessWidget {
  const LineIcon(this.name, {super.key, this.size = 24, this.color = accentLight});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LinePainter(name, color)),
      );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.name, this.color);
  final String name;
  final Color color;
  static final RegExp _tok = RegExp(r'[MLCQZ]|-?[0-9]*\.?[0-9]+');

  static Path parse(String d, double k) {
    final t = _tok.allMatches(d).map((m) => m.group(0)!).toList();
    final p = Path();
    var i = 0;
    var cmd = 'M';
    double n() => double.parse(t[i++]) * k;
    while (i < t.length) {
      if (RegExp(r'^[MLCQZ]$').hasMatch(t[i])) cmd = t[i++];
      switch (cmd) {
        case 'M':
          p.moveTo(n(), n());
          cmd = 'L';
          break;
        case 'L':
          p.lineTo(n(), n());
          break;
        case 'Q':
          p.quadraticBezierTo(n(), n(), n(), n());
          break;
        case 'C':
          p.cubicTo(n(), n(), n(), n(), n(), n());
          break;
        case 'Z':
          p.close();
          break;
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paths = kIconPaths[name] ?? kIconPaths['medal']!;
    for (final d in paths) {
      canvas.drawPath(parse(d, k), paint);
    }
    for (final c in kIconCircles[name] ?? const <List<double>>[]) {
      canvas.drawCircle(Offset(c[0] * k, c[1] * k), c[2] * k, paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.name != name || old.color != color;
}


// ---------------------------------------------------------------- inbox

// blue "verified" badge with a white tick, drawn in code
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 14});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Verified',
        child: SizedBox(width: size, height: size, child: CustomPaint(painter: _VerifiedPainter())),
      );
}

class _VerifiedPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final shape = Path();
    for (var i = 0; i < 24; i++) {
      final r = (i.isEven ? 10.0 : 8.6) * k;
      final a = math.pi * 2 * i / 24 - math.pi / 2;
      final o = Offset(12 * k + r * math.cos(a), 12 * k + r * math.sin(a));
      if (i == 0) {
        shape.moveTo(o.dx, o.dy);
      } else {
        shape.lineTo(o.dx, o.dy);
      }
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = const Color(0xFF2EA2EA));
    final tick = Path()
      ..moveTo(8 * k, 12.3 * k)
      ..lineTo(10.8 * k, 15 * k)
      ..lineTo(16.2 * k, 9.4 * k);
    canvas.drawPath(
        tick,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_VerifiedPainter old) => false;
}

class InboxMessage {
  InboxMessage({required this.id, required this.title, required this.body, required this.sender, required this.createdAt, this.image, required this.read});
  final int id;
  final String title;
  final String body;
  final String sender;
  final DateTime createdAt;
  final String? image;
  final bool read;

  factory InboxMessage.fromJson(Map<String, dynamic> j) => InboxMessage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        sender: (j['sender'] ?? 'admin').toString(),
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num?)?.toInt() ?? 0),
        image: j['image'] as String?,
        read: j['read'] == true,
      );
}

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.token});
  final String token;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<InboxMessage> items = <InboxMessage>[];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await apiCall('GET', '/api/app/inbox', token: widget.token);
      if (r['_status'] != 200) throw Exception('status');
      final list = ((r['items'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(InboxMessage.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        items = list;
        loading = false;
        error = null;
      });
      if (((r['unread'] as num?)?.toInt() ?? 0) > 0) {
        apiCall('POST', '/api/app/inbox/read', token: widget.token, data: {'all': true}).catchError((_) => <String, dynamic>{});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load your messages. Check your internet and try again.';
      });
    }
  }

  void hide(InboxMessage m) {
    setState(() => items.remove(m));
    apiCall('POST', '/api/app/inbox/read', token: widget.token, data: {'id': m.id, 'hide': true}).catchError((_) => <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('Inbox')),
      body: RefreshIndicator(
        color: accent,
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            if (loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: accent)))
            else if (error != null)
              Padding(padding: const EdgeInsets.all(30), child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: mutedColor)))
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Column(children: [
                  const LineIcon('inbox', size: 56, color: accentLight),
                  const SizedBox(height: 12),
                  Text('No messages yet. Messages from the server and the team will appear here.',
                      textAlign: TextAlign.center, style: TextStyle(color: mutedColor)),
                ]),
              ),
            for (final m in items)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: softShadow(),
                  border: m.read ? null : Border.all(color: accentLight, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(m.sender == 'server' ? 'GAME SERVER' : 'MVP TEAM',
                          style: const TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      if (m.sender != 'server') ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                      const Spacer(),
                      Text(formatDate(m.createdAt), style: TextStyle(color: mutedColor, fontSize: 11)),
                    ]),
                    const SizedBox(height: 6),
                    Text(m.title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: inkColor)),
                    if (m.image != null) ...[
                      const SizedBox(height: 10),
                      NewsPicture(url: m.image!, height: null),
                    ],
                    const SizedBox(height: 8),
                    RichBody(text: m.body, style: TextStyle(fontSize: 15, height: 1.45, color: inkColor)),
                    for (final id in videoIds(m.body)) VideoTile(id: id),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// A medal on the player card ("Welcome", event medals, medals given by the admin).
class Medal {
  Medal({required this.name, required this.description, required this.icon, required this.color, required this.awardedAt});
  final String name;
  final String description;
  final String icon;
  final Color color;
  final int awardedAt;

  factory Medal.fromJson(Map<String, dynamic> j) {
    final hex = (j['color'] ?? '').toString().replaceAll('#', '');
    return Medal(
      name: (j['name'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      icon: kMedalIcons.containsKey((j['icon'] ?? '').toString()) ? (j['icon'] ?? '').toString() : 'medal',
      color: Color(int.tryParse('FF$hex', radix: 16) ?? 0xFF0070B8),
      awardedAt: (j['awarded_at'] as num?)?.toInt() ?? 0,
    );
  }

  String get dateText {
    if (awardedAt <= 0) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.fromMillisecondsSinceEpoch(awardedAt);
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class MedalTile extends StatelessWidget {
  const MedalTile({super.key, required this.medal});
  final Medal medal;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: medal.color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: medal.color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: PixelIcon(medal.icon, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('[${medal.name}]',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color.lerp(medal.color, inkColor, 0.35))),
                    if (medal.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(medal.description, style: TextStyle(color: inkColor, fontSize: 13)),
                      ),
                    if (medal.dateText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(medal.dateText, style: TextStyle(color: mutedColor, fontSize: 11)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewsItem {
  NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.image,
    this.likes = 0,
    this.dislikes = 0,
    this.views = 0,
    this.my = 0,
    this.poll,
  });

  Poll? poll;
  final int id;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? image;
  int likes;
  int dislikes;
  int views;
  int my;

  factory NewsItem.fromJson(Map<String, dynamic> j) {
    return NewsItem(
      id: (j['id'] as num).toInt(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      image: j['image'] is String ? j['image'] as String : null,
      likes: (j['likes'] as num?)?.toInt() ?? 0,
      dislikes: (j['dislikes'] as num?)?.toInt() ?? 0,
      views: (j['views'] as num?)?.toInt() ?? 0,
      my: (j['my'] as num?)?.toInt() ?? 0,
      poll: j['poll'] is Map<String, dynamic>
          ? Poll.fromJson(j['poll'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}


final RegExp _linkRe = RegExp(
    r'\[([^\]]{1,80})\]\((https?://[^\s)]+)\)|(https?://[^\s<>()\[\]]+)');
final RegExp _ytRe = RegExp(
    r'(?:youtube\.com/(?:watch\?(?:[^\s&]*&)*v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})');

String? youtubeId(String url) => _ytRe.firstMatch(url)?.group(1);

/// Video ids found in a post, in order, without repeats.
List<String> videoIds(String text) {
  final out = <String>[];
  for (final m in _linkRe.allMatches(text)) {
    final url = m.group(2) ?? m.group(3) ?? '';
    final id = youtubeId(url);
    if (id != null && !out.contains(id)) out.add(id);
  }
  return out;
}

/// Text for list previews: markup removed, video links dropped.
String plainBody(String text) {
  return text
      .replaceAllMapped(_linkRe, (m) {
        if (m.group(1) != null) return m.group(1)!;
        final url = m.group(3) ?? '';
        return youtubeId(url) != null ? '' : url;
      })
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class RichBody extends StatefulWidget {
  const RichBody({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  TextSpan _link(String label, String url) {
    final tap = TapGestureRecognizer()..onTap = () => openLink(url);
    _taps.add(tap);
    return TextSpan(
      text: label,
      recognizer: tap,
      style: const TextStyle(
          color: accent,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final spans = <InlineSpan>[];
    var pos = 0;
    final text = widget.text;
    for (final m in _linkRe.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      if (m.group(1) != null) {
        spans.add(_link(m.group(1)!, m.group(2)!));
      } else {
        final url = m.group(3)!;
        if (youtubeId(url) == null) spans.add(_link(url, url));
      }
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        button: true,
        label: 'Play video',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openLink('https://www.youtube.com/watch?v=$id'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://img.youtube.com/vi/$id/hqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF0B1B2B)),
                  ),
                  Container(color: const Color(0x55000000)),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        size: 64, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Build number comes from the GitHub build (--dart-define=BUILD=...).
const int kBuild = int.fromEnvironment('BUILD', defaultValue: 0);

/// Shown version: build 35 -> v35.0
String get kVersion => kBuild == 0 ? 'dev' : 'v$kBuild.0';
const String apkUrl =
    'https://github.com/proggln/mvp-app/releases/latest/download/mvp-app.apk';

/// Newest published build number (0 when unknown).
Future<int> latestBuild() async {
  final res = await http.get(
    Uri.parse('https://api.github.com/repos/proggln/mvp-app/releases/latest'),
    headers: {'Accept': 'application/vnd.github+json'},
  ).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return 0;
  final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  final m = RegExp(r'build (\d+)').firstMatch((j['name'] ?? '').toString());
  return m == null ? 0 : int.parse(m.group(1)!);
}

Future<List<NewsItem>> fetchNews([String token = '']) async {
  final res = await http
      .get(Uri.parse('$apiBase/api/news'),
          headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Server error ${res.statusCode}');
  }
  final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  return data
      .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

String formatPlaytime(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${two(l.day)}.${two(l.month)}.${l.year}  ${two(l.hour)}:${two(l.minute)}';
}

Future<void> openLink(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<Map<String, dynamic>> apiCall(String method, String path,
    {String? token, Map<String, dynamic>? data}) async {
  final uri = Uri.parse('$apiBase$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  final res = await (method == 'POST'
          ? http.post(uri, headers: headers, body: jsonEncode(data ?? <String, dynamic>{}))
          : http.get(uri, headers: headers))
      .timeout(const Duration(seconds: 15));
  Map<String, dynamic> body;
  try {
    body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  } catch (_) {
    body = <String, dynamic>{};
  }
  body['_status'] = res.statusCode;
  return body;
}

List<BoxShadow> softShadow() => const [
      BoxShadow(
        color: Color(0x0F0B1B2B),
        blurRadius: 14,
        offset: Offset(0, 4),
      ),
    ];

// ---------------------------------------------------------------- e-mail sign in / add e-mail

class EmailFlow extends StatefulWidget {
  const EmailFlow({super.key, required this.addMode, this.createMode = false, this.token = '', required this.onDone});

  /// false: sign in (or create an account) with an e-mail. true: add an e-mail to the signed-in card.
  final bool addMode;

  /// true: new account (asks for a nickname first)
  final bool createMode;
  final String token;
  final void Function(String token) onDone;

  @override
  State<EmailFlow> createState() => _EmailFlowState();
}

class _EmailFlowState extends State<EmailFlow> {
  final emailC = TextEditingController();
  final codeC = TextEditingController();
  final nameC = TextEditingController();
  bool codeStep = false;
  bool busy = false;
  bool news = false;
  String msg = '';
  String email = '';

  @override
  void dispose() {
    emailC.dispose();
    codeC.dispose();
    nameC.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final em = emailC.text.trim().toLowerCase();
    if (widget.createMode && !RegExp(r'^[A-Za-z0-9_.]{2,16}$').hasMatch(nameC.text.trim())) {
      setState(() => msg = 'Nickname: 2 to 16 letters, numbers, _ or .');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(em)) {
      setState(() => msg = 'Type a valid e-mail.');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final r = await apiCall('POST', widget.addMode ? '/api/app/email-change-start' : '/api/web/email-start',
          token: widget.addMode ? widget.token : null,
          data: {'email': em, if (widget.createMode) 'create': true});
      final st = r['_status'];
      if (!mounted) return;
      if (st == 200) {
        setState(() {
          email = em;
          codeStep = true;
          busy = false;
        });
        return;
      }
      setState(() {
        busy = false;
        msg = st == 429
            ? 'Too many tries. Wait a little.'
            : st == 409
                ? (r['error'] == 'exists'
                    ? 'This e-mail already has an account. Use Log in below instead.'
                    : r['error'] == 'email_taken'
                        ? 'This e-mail is already used by another account.'
                        : 'This is already your e-mail.')
                : st == 503
                    ? 'E-mail sign in is not ready yet.'
                    : 'Could not send the code. Try again later.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          msg = 'No connection. Check your internet and try again.';
        });
      }
    }
  }

  Future<void> verify() async {
    final code = codeC.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => msg = 'The code has 6 digits.');
      return;
    }
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      final r = await apiCall('POST', widget.addMode ? '/api/app/email-change-verify' : '/api/web/email-verify',
          token: widget.addMode ? widget.token : null,
          data: widget.addMode
              ? {'email': email, 'code': code}
              : {
                  'email': email,
                  'code': code,
                  'newsletter': news,
                  if (widget.createMode) 'name': nameC.text.trim(),
                });
      final st = r['_status'];
      if (!mounted) return;
      if (st == 200 && r['status'] == 'need_name') {
        setState(() {
          busy = false;
          msg = 'There is no account with this e-mail yet. Tap "Create one" below.';
        });
        return;
      }
      if (st == 200) {
        widget.onDone(widget.addMode ? '' : (r['token'] ?? '').toString());
        return;
      }
      setState(() {
        busy = false;
        msg = r['error'] == 'email_taken' ? 'This e-mail is already used by another account.' : 'Wrong or expired code.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          msg = 'No connection. Check your internet and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!codeStep) ...[
          Text(
            widget.addMode
                ? 'Type your e-mail. We send you a 6-digit code.'
                : 'Type your e-mail. We send you a 6-digit code. No password needed. New here? An account is created for you.',
            style: TextStyle(color: mutedColor, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (widget.createMode) ...[
            TextField(
              controller: nameC,
              autocorrect: false,
              maxLength: 16,
              enabled: !busy,
              style: TextStyle(color: inkColor),
              decoration: const InputDecoration(
                  labelText: 'Your Minecraft nickname', border: OutlineInputBorder(), counterText: ''),
            ),
            const SizedBox(height: 6),
            Text('Your account shows this name plus a short code until you link your Minecraft account with /link. Then your real game nickname is used.',
                style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: emailC,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enabled: !busy,
            style: TextStyle(color: inkColor),
            decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
          ),
          if (!widget.addMode && widget.createMode)
            CheckboxListTile(
              value: news,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: busy ? null : (v) => setState(() => news = v ?? false),
              title: Text('Send me MVP news by e-mail (optional, you can unsubscribe any time)',
                  style: TextStyle(color: inkColor, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : send,
            style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(48)),
            child: Text(busy ? 'Sending...' : 'Send code'),
          ),
        ] else ...[
          Text('We sent a code to $email.', style: TextStyle(color: mutedColor, height: 1.4)),
          const SizedBox(height: 14),
          TextField(
            controller: codeC,
            keyboardType: TextInputType.number,
            maxLength: 6,
            enabled: !busy,
            style: TextStyle(color: inkColor, letterSpacing: 6, fontSize: 20),
            decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder(), counterText: ''),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : verify,
            style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(48)),
            child: Text(busy ? 'Checking...' : 'Confirm'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      codeStep = false;
                      msg = '';
                      codeC.clear();
                    }),
            child: const Text('Use another e-mail'),
          ),
        ],
        if (msg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(msg, style: const TextStyle(color: Color(0xFFC0343F))),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- shell

class Shell extends StatefulWidget {
  const Shell({super.key, required this.firebaseOk});

  final bool firebaseOk;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;

  List<NewsItem>? items;
  List<EventItem> events = <EventItem>[];
  String? error;
  bool loading = true;

  bool pushOn = true;
  String pushStatus = 'Checking...';
  StreamSubscription<RemoteMessage>? _sub;

  String token = '';
  String cardNo = '';
  String nick = '';
  String rank = 'Member';
  int coins = 0;
  int kills = 0;
  int deaths = 0;
  int killsRank = 0;
  int coinsRank = 0;
  int playtime = 0;
  bool linked = false;
  String pendingNick = '';
  String storageNote = '';
  String since = '';
  String themeId = 'default';
  String localTheme = '';
  List<CardStyle> themes = <CardStyle>[];
  List<Medal> medals = <Medal>[];
  int deleteAt = 0;
  int inboxUnread = 0;
  String email = '';
  String displayName = '';
  bool creating = false;
  bool needLogin = false;
  bool _pushLinked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    themeMode.addListener(_themeChanged);
    () async {
      try {
        final f = File('${Directory.systemTemp.path}/mvp-app.apk');
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }();
    loadProfile();
    load();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkUpdate());
    if (widget.firebaseOk) {
      setupPush();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => note(
          'Push setup failed: ${firebaseError.isEmpty ? 'Firebase off' : firebaseError}'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadQuiet();
      refreshProfile();
    }
  }

  Future<void> loadQuiet() async {
    try {
      final list = await fetchNews(token);
      List<EventItem> ev = events;
      try {
        ev = await fetchEvents();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        items = list;
        events = ev;
        error = null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeMode.removeListener(_themeChanged);
    _sub?.cancel();
    super.dispose();
  }

  void _themeChanged() {
    if (mounted) setState(() {});
  }

  /// Settings > Theme: Default, Light (white) or Dark.
  Future<void> chooseTheme() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in const [
              ['system', 'Default', ThemeMode.system],
              ['light', 'Light (white)', ThemeMode.light],
              ['dark', 'Dark', ThemeMode.dark],
            ])
              ListTile(
                title: Text(o[1] as String, style: TextStyle(color: inkColor)),
                trailing: themeMode.value == o[2]
                    ? const Icon(Icons.check_circle_rounded, color: accent)
                    : null,
                onTap: () {
                  themeMode.value = o[2] as ThemeMode;
                  savePref('theme_mode', o[0] as String);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _loginScreen() {
    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
                24, 48, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('MVP', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4, color: accent)),
                  const SizedBox(height: 6),
                  Text(creating ? 'Create your MVP account' : 'Log in with e-mail',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: inkColor)),
                  const SizedBox(height: 16),
                  EmailFlow(
                    key: ValueKey(creating),
                    addMode: false,
                    createMode: creating,
                    onDone: (t) async {
                      if (t.isEmpty) return;
                      token = t;
                      await savePref('token', t);
                      if (!mounted) return;
                      setState(() => needLogin = false);
                      await refreshProfile();
                      load();
                    },
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(creating ? 'Already have an account? ' : 'Don\u2019t have an MVP account yet? ',
                            style: TextStyle(color: mutedColor)),
                        GestureDetector(
                          onTap: () => setState(() => creating = !creating),
                          child: Text(creating ? 'Log in' : 'Create one',
                              style: const TextStyle(color: accent, decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
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
    );
  }

  Future<void> addEmail() async {
    if (token.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(title: const Text('Add e-mail')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: EmailFlow(
                addMode: true,
                token: token,
                onDone: (_) {
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await refreshProfile();
  }

  Future<void> signOut() async {
    final noMail = email.isEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(noMail
            ? 'This card has no e-mail. If you sign out, you can NOT get this card back. Add an e-mail first (Settings > E-mail), then sign out.'
            : 'You can sign in again any time with your e-mail ($email).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay signed in')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: noMail ? const Color(0xFFC0343F) : accent),
            child: Text(noMail ? 'Sign out anyway' : 'Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final old = token;
    try {
      await apiCall('POST', '/api/web/logout', token: old);
    } catch (_) {}
    token = '';
    await savePref('token', '');
    await savePref('cardno', '');
    if (!mounted) return;
    setState(() {
      cardNo = '';
      nick = '';
      rank = 'Member';
      coins = 0;
      kills = 0;
      deaths = 0;
      killsRank = 0;
      coinsRank = 0;
      playtime = 0;
      linked = false;
      pendingNick = '';
      email = '';
      displayName = '';
      creating = false;
      medals = <Medal>[];
      themes = <CardStyle>[];
      themeId = 'default';
      deleteAt = 0;
      inboxUnread = 0;
      _pushLinked = false;
      tab = 0;
      needLogin = true;
    });
  }

  void note(String text) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _checkingUpdate = false;

  // Backup storage: a small file in the app's private folder. It is used
  // together with SharedPreferences, so the login survives even if one of
  // them fails on a phone.
  File? backupFile() {
    try {
      if (!Platform.isAndroid) return null;
      return File('/data/user/0/org.playmvp.app/files/mvp_session.json');
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> readBackup() async {
    try {
      final f = backupFile();
      if (f == null || !await f.exists()) return <String, String>{};
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return j.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> checkUpdate({bool manual = false}) async {
    if (kBuild == 0 && !manual) return;
    if (_checkingUpdate) return;
    _checkingUpdate = true;
    if (manual) note('Checking for updates...');
    try {
      final latest = await latestBuild();
      if (!mounted) return;
      if (latest <= kBuild) {
        if (manual) note('You have the latest version.');
        return;
      }
      if (manual && mounted) ScaffoldMessenger.of(context).clearSnackBars();
      if (!manual) {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getInt('dismissed_build') == latest) return;
          await prefs.setInt('dismissed_build', latest);
        } catch (_) {}
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Update available'),
          content: const Text(
              'A new version of the MVP app is ready. Tap Update to download and install it. Your login stays.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const UpdateDialog(),
                );
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (manual) note('Could not check for updates.');
    } finally {
      _checkingUpdate = false;
    }
  }

  Future<void> savePref(String key, String value) async {
    storageNote = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      storageNote = 'prefs';
    }
    try {
      final f = backupFile();
      if (f != null) {
        final m = await readBackup();
        m[key] = value;
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode(m));
      }
    } catch (e) {
      storageNote = storageNote.isEmpty ? 'file' : 'both';
    }
  }

  Future<void> loadProfile() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final backup = await readBackup();
    String pick(String key) {
      final a = prefs?.getString(key) ?? '';
      return a.isNotEmpty ? a : (backup[key] ?? '');
    }

    token = pick('token');
    localTheme = prefs?.getString('localtheme') ?? '';
    final cachedCard = pick('cardno');
    var s = pick('since');
    if (s.isEmpty) {
      final n = DateTime.now();
      s = '${two(n.month)} / ${two(n.year % 100)}';
      await savePref('since', s);
    }
    if (mounted) {
      setState(() {
        since = s;
        if (cardNo.isEmpty) cardNo = cachedCard;
      });
    }
    await refreshProfile();
  }

  /// Gets (or creates) this phone's card and reads the profile from the server.
  Future<void> refreshProfile({bool retry = true}) async {
    try {
      if (token.isEmpty) {
        if (mounted) setState(() => needLogin = true);
        return;
      }
      final me = await apiCall('GET', '/api/app/me', token: token);
      final st = me['_status'];
      if (st == 401 && retry) {
        // the card was deleted or the session ended: sign in again
        token = '';
        await savePref('token', '');
        await refreshProfile(retry: false);
        return;
      }
      if (st == 200 && mounted) {
        setState(() {
          needLogin = false;
          email = (me['email'] ?? '').toString();
          displayName = (me['display_name'] ?? '').toString();
          cardNo = (me['card_no'] ?? cardNo).toString();
          nick = (me['nick'] ?? '').toString();
          rank = (me['rank'] ?? 'Member').toString();
          coins = (me['coins'] as num?)?.toInt() ?? 0;
          kills = (me['kills'] as num?)?.toInt() ?? 0;
          deaths = (me['deaths'] as num?)?.toInt() ?? 0;
          killsRank = (me['kills_rank'] as num?)?.toInt() ?? 0;
          coinsRank = (me['coins_rank'] as num?)?.toInt() ?? 0;
          playtime = (me['playtime'] as num?)?.toInt() ?? 0;
          linked = me['linked'] == true;
          pendingNick = (me['pending_nick'] ?? '').toString();
          themeId = (me['theme'] ?? 'default').toString();
          themes = ((me['themes'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => CardStyle.fromJson(e as Map<String, dynamic>))
              .toList();
          deleteAt = (me['delete_at'] as num?)?.toInt() ?? 0;
          inboxUnread = (me['inbox_unread'] as num?)?.toInt() ?? 0;
          medals = ((me['medals'] as List<dynamic>?) ?? <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(Medal.fromJson)
              .toList();
        });
        await savePref('cardno', cardNo);
        linkPushToken();
      }
    } catch (_) {
      // offline: keep what we have
    }
  }

  // tells the server which card this phone belongs to, so personal inbox messages can send a notification here
  Future<void> linkPushToken({String? fresh}) async {
    if (!widget.firebaseOk || token.isEmpty || (_pushLinked && fresh == null)) return;
    try {
      final t = fresh ?? await FirebaseMessaging.instance.getToken();
      if (t == null || t.isEmpty) return;
      final r = await apiCall('POST', '/api/app/push-token', token: token, data: {'token': t, 'kind': 'app'});
      if (r['_status'] == 200) _pushLinked = true;
    } catch (_) {}
  }

  Future<void> openInbox() async {
    if (token.isEmpty) {
      note('No connection. Check your internet and try again.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InboxPage(token: token)),
    );
    if (mounted) setState(() => inboxUnread = 0);
    refreshProfile();
  }

  Future<void> openRegister() async {
    if (linked) return;
    if (token.isEmpty) await refreshProfile();
    if (token.isEmpty) {
      note('No connection. Check your internet and try again.');
      return;
    }
    if (pendingNick.isNotEmpty) {
      note('Waiting for registration (wait some time).');
      return;
    }
    final c = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Register'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Type your exact Minecraft nickname. An admin will confirm it, this can take some time. Accounts that are not confirmed within 48 hours are deleted.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(hintText: 'Nickname'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop('code'),
              child: const Text('Use a game code')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: const Text('Send')),
        ],
      ),
    );
    if (choice == null || choice.isEmpty) return;
    if (choice == 'code') {
      startLink();
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9_.]{2,20}$').hasMatch(choice)) {
      note('Use 2-20 letters, digits, _ or .');
      return;
    }
    try {
      final r = await apiCall('POST', '/api/app/nick-request',
          token: token, data: {'nick': choice});
      if (r['_status'] == 200) {
        setState(() => pendingNick = (r['pending_nick'] ?? choice).toString());
        note('Sent. Waiting for registration (wait some time).');
      } else if (r['_status'] == 409) {
        note('This nickname is already taken.');
      } else {
        note('Could not send the request. Try again later.');
      }
    } catch (_) {
      note('No connection. Check your internet.');
    }
  }

  Future<void> startLink() async {
    if (token.isEmpty) await refreshProfile();
    if (token.isEmpty) {
      note('No connection. Check your internet and try again.');
      return;
    }
    Map<String, dynamic> r;
    try {
      r = await apiCall('POST', '/api/app/link-code', token: token);
    } catch (_) {
      note('No connection. Check your internet and try again.');
      return;
    }
    if (r['_status'] == 409) {
      await refreshProfile();
      return;
    }
    if (r['_status'] != 200 || r['code'] is! String) {
      note('Could not get a code. Try again later.');
      return;
    }
    final code = r['code'] as String;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => LinkSheet(
        code: code,
        check: () async {
          await refreshProfile();
          return linked;
        },
      ),
    );
    if (linked && nick.isNotEmpty) note('Linked as $nick!');
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await fetchNews(token);
      List<EventItem> ev = events;
      try {
        ev = await fetchEvents();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        items = list;
        events = ev;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = 'Could not load the news. Check your internet and try again.';
        loading = false;
      });
    }
  }

  Future<void> setupPush() async {
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        pushOn = prefs.getBool('push') ?? true;
      } catch (_) {
        pushOn = true;
      }
      if (mounted) setState(() {});
      final fm = FirebaseMessaging.instance;
      if (pushOn) {
        final st = await fm.requestPermission();
        await fm.subscribeToTopic(pushTopic);
        final ok = st.authorizationStatus == AuthorizationStatus.authorized;
        if (mounted) {
          setState(() => pushStatus =
              ok ? 'Ready' : 'Blocked: ${st.authorizationStatus.name}');
        }
        if (!ok) {
          note('Notifications are blocked. Allow them in phone settings.');
        }
      } else if (mounted) {
        setState(() => pushStatus = 'Off');
      }
      _sub = FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        if (!mounted) return;
        if (m.data['type'] == 'inbox') {
          note('New message: ${m.notification?.title ?? 'Inbox'}');
          refreshProfile();
          return;
        }
        note(m.notification?.title ?? 'New news');
        load();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
        if (mounted && m.data['type'] == 'inbox') openInbox();
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => linkPushToken(fresh: t));
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null && first.data['type'] == 'inbox') {
        WidgetsBinding.instance.addPostFrameCallback((_) => openInbox());
      }
      linkPushToken();
    } catch (e) {
      if (mounted) setState(() => pushStatus = 'Error: $e');
      note('Push error: $e');
    }
  }

  Future<void> setPush(bool next) async {
    final fm = FirebaseMessaging.instance;
    try {
      if (next) {
        await fm.requestPermission();
        await fm.subscribeToTopic(pushTopic);
      } else {
        await fm.unsubscribeFromTopic(pushTopic);
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('push', next);
      } catch (_) {}
      if (!mounted) return;
      setState(() => pushOn = next);
    } catch (_) {
      note('Could not change notifications. Try again later.');
    }
  }

  Future<void> markViewed(NewsItem n) async {
    if (token.isEmpty) return;
    try {
      final r = await apiCall('POST', '/api/app/view',
          token: token, data: {'news_id': n.id});
      if (r['_status'] == 200 && mounted) {
        setState(() => n.views = (r['views'] as num).toInt());
      }
    } catch (_) {}
  }

  void openNews(NewsItem n) {
    markViewed(n);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) =>
              NewsPage(item: n, token: token, onVote: voteNews, onPollVote: votePoll)),
    );
  }

  List<Color> get cardColors {
    for (final t in themes) {
      if (t.id == themeId && t.colors.length >= 3) return t.colors;
    }
    return const [accentLight, accent, accentDark];
  }

  bool get cardAnimated {
    for (final t in themes) {
      if (t.id == themeId) return t.anim;
    }
    return false;
  }

  Future<void> votePoll(NewsItem n, int optionId) async {
    final p = n.poll;
    if (p == null || p.closed) return;
    if (token.isEmpty || !linked) {
      note('Link your game account to vote in polls.');
      return;
    }
    final next = p.my == optionId ? 0 : optionId;
    final oldMy = p.my;
    final oldVotes = {for (final o in p.options) o.id: o.votes};
    setState(() {
      for (final o in p.options) {
        if (o.id == oldMy) o.votes--;
        if (o.id == next) o.votes++;
      }
      p.my = next;
    });
    try {
      final r = await apiCall('POST', '/api/app/poll-vote',
          token: token, data: {'poll_id': p.id, 'option_id': next});
      if (r['_status'] != 200) throw Exception('poll');
      final fresh = Poll.fromJson(r);
      if (!mounted) return;
      setState(() {
        p.my = fresh.my;
        p.closed = fresh.closed;
        for (final o in p.options) {
          for (final f in fresh.options) {
            if (f.id == o.id) o.votes = f.votes;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        p.my = oldMy;
        for (final o in p.options) {
          o.votes = oldVotes[o.id] ?? o.votes;
        }
      });
      note('Could not save your vote. Try again.');
    }
  }

  Future<void> webLogin() async {
    if (token.isEmpty) {
      note('Your card is not ready yet. Try again in a moment.');
      return;
    }
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign in to the website'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Open the MVP website, tap Sign in and enter the 6-character code you see there.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(hintText: 'CODE'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
              child: const Text('Sign in')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final r = await apiCall('POST', '/api/app/weblogin',
          token: token, data: {'code': code});
      if (r['_status'] == 200) {
        note('Done. The website signs in within a few seconds.');
      } else if (r['_status'] == 404) {
        note('That code is wrong or expired. Check the site.');
      } else {
        note('Could not sign in. Try again later.');
      }
    } catch (_) {
      note('No connection. Check your internet.');
    }
  }

  Future<void> setTheme(CardStyle t) async {
    if (localTheme.isNotEmpty) {
      localTheme = '';
      await savePref('localtheme', '');
    }
    final old = themeId;
    setState(() => themeId = t.id);
    try {
      final r = await apiCall('POST', '/api/app/theme',
          token: token, data: {'theme_id': t.id});
      if (r['_status'] != 200) throw Exception('theme');
    } catch (_) {
      if (!mounted) return;
      setState(() => themeId = old);
      note('Could not change the card style.');
    }
  }

  void chooseStyle() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Card style',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: inkColor)),
              const SizedBox(height: 4),
              Text('Special styles are given out at events.',
                  style: TextStyle(color: mutedColor)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final t in themes)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        setTheme(t);
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 74,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: t.colors.length >= 3
                                    ? t.colors
                                    : const [accentLight, accent, accentDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: t.id == themeId
                                    ? inkColor
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(t.name,
                              style: TextStyle(
                                  fontSize: 12, color: inkColor)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> voteNews(NewsItem n, int v) async {
    if (token.isEmpty || !linked) {
      note('Link your game account to like or dislike news.');
      return;
    }
    final next = n.my == v ? 0 : v;
    final oldMy = n.my, oldL = n.likes, oldD = n.dislikes;
    setState(() {
      if (oldMy == 1) n.likes--;
      if (oldMy == -1) n.dislikes--;
      if (next == 1) n.likes++;
      if (next == -1) n.dislikes++;
      n.my = next;
    });
    try {
      final r = await apiCall('POST', '/api/app/vote',
          token: token, data: {'news_id': n.id, 'vote': next});
      if (r['_status'] != 200) throw Exception('vote');
      if (!mounted) return;
      setState(() {
        n.likes = (r['likes'] as num).toInt();
        n.dislikes = (r['dislikes'] as num).toInt();
        n.my = (r['my'] as num).toInt();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        n.my = oldMy;
        n.likes = oldL;
        n.dislikes = oldD;
      });
      note('Could not save your vote. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // pick the colors: Default or Light (white)
    kWhite = themeMode.value == ThemeMode.light;
    kDark = themeMode.value == ThemeMode.dark;
    if (needLogin) return _loginScreen();
    final pages = <Widget>[
      _cardTab(),
      _newsTab(),
      _serverTab(),
      _settingsTab(),
    ];
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: _navBar(),
    );
  }

  // -------------------------------------------------------- nav bar

  Widget _navBar() {
    const labels = ['Card', 'News', 'Server', 'Settings'];
    const icons = [
      Icons.credit_card_rounded,
      Icons.newspaper_rounded,
      Icons.dns_rounded,
      Icons.settings_rounded,
    ];
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Color(0x140B1B2B),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: List.generate(4, (i) {
              final on = tab == i;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => tab = i),
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icons[i], color: on ? accent : navMuted, size: 24),
                      const SizedBox(height: 2),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? accent : navMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------- card tab

  Widget _cardTab() {
    final name = nick.isNotEmpty ? nick : (displayName.isNotEmpty ? displayName : 'Player');
    final cardNum = cardNo.length == 8 ? cardNo : '';
    return RefreshIndicator(
      color: accent,
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        children: [
          if (deleteAt > 0) _deleteBanner(),
          for (final e in events.where((x) => x.pinned))
            EventCard(key: ValueKey('p${e.id}'), item: e),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back',
                      style: TextStyle(color: mutedColor, fontSize: 13),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: inkColor,
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: surfaceColor,
                shape: const CircleBorder(),
                elevation: 2,
                shadowColor: const Color(0x220B1B2B),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: openInbox,
                  child: Tooltip(
                    message: 'Inbox',
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          const LineIcon('inbox', size: 24, color: accentLight),
                          if (inboxUnread > 0)
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                constraints: const BoxConstraints(minWidth: 20),
                                height: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8424F),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: surfaceColor, width: 2),
                                ),
                                child: Text(
                                  inboxUnread > 99 ? '99+' : '$inboxUnread',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                                ),
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
          const SizedBox(height: 18),
          MemberCard(
            nick: nick.isNotEmpty ? nick : displayName,
            cardNo: cardNum,
            since: since,
            rank: rank,
            colors: cardColors,
            animated: cardAnimated,
            avatarNick: linked ? nick : '',
            onTap: linked ? null : openRegister,
          ),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  asset: 'assets/coin.png',
                  tint: tintAmber,
                  color: const Color(0xFFB87400),
                  value: '$coins',
                  label: 'Coins',
                  sub: coinsRank > 0 ? 'TOP #$coinsRank' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  asset: 'assets/sword.png',
                  tint: tintRed,
                  color: const Color(0xFFC0343F),
                  value: '$kills',
                  label: 'Kills',
                  sub: killsRank > 0 ? 'TOP #$killsRank' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.heart_broken_rounded,
                  tint: tintBlue,
                  color: accent,
                  value: '$deaths',
                  label: 'Deaths',
                ),
              ),
            ],
          ),
          ),
          const SizedBox(height: 14),
          _medalsButton(),
          if (linked) ...[
            const SizedBox(height: 12),
            _socialTile(Icons.people_alt_rounded, 'Friends', 'Chat and add friends',
                () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FriendsPage(token: token)))),
            const SizedBox(height: 12),
            _socialTile(Icons.badge_rounded, 'See my profile', 'How others see you',
                () => openProfile(context, token, nick)),
          ],
          const SizedBox(height: 14),
          _storeTile(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: softShadow(),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        linked
                            ? 'Account linked'
                            : (pendingNick.isNotEmpty
                                ? 'Registration pending'
                                : 'Register your account'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: inkColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        linked
                            ? 'Playing as $nick'
                            : (pendingNick.isNotEmpty
                                ? 'Waiting for registration (wait some time). Requested: $pendingNick'
                                : 'Pick your Minecraft nickname. An admin will confirm it.'),
                        style: TextStyle(color: mutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (linked)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E9E5B), size: 30)
                else if (pendingNick.isNotEmpty)
                  const Icon(Icons.hourglass_top_rounded, color: accent, size: 28)
                else
                  FilledButton(
                    onPressed: openRegister,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 44),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Register'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Latest news',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: inkColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => tab = 1),
                child: const Text('See all'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (items != null && items!.isNotEmpty)
            NewsCard(
                item: items!.first,
                onTap: () => openNews(items!.first),
                onVote: voteNews)
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(18),
                boxShadow: softShadow(),
              ),
              child: Text(
                loading
                    ? 'Loading...'
                    : (error ?? 'No news yet. Check back soon!'),
                style: TextStyle(color: mutedColor),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- news tab

  Widget _newsTab() {
    final list = items ?? <NewsItem>[];
    return RefreshIndicator(
      color: accent,
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        children: [
          Text(
            'News',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 16),
          for (final e in events)
            EventCard(key: ValueKey('n${e.id}'), item: e),
          if (loading && items == null)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator(color: accent)),
            )
          else if (error != null && items == null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                children: [
                  Icon(Icons.wifi_off_rounded,
                      size: 42, color: mutedColor),
                  const SizedBox(height: 12),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: load, child: const Text('Try again')),
                ],
              ),
            )
          else if (list.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(
                child: Text(
                  'No news yet. Check back soon!',
                  style: TextStyle(color: mutedColor),
                ),
              ),
            )
          else
            ...list.map((n) =>
                NewsCard(item: n, onTap: () => openNews(n), onVote: voteNews)),
        ],
      ),
    );
  }

  // -------------------------------------------------------- server tab

  Widget _serverTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      children: [
        Text(
          'Server',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: inkColor,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [accentLight, accent, accentDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SERVER ADDRESS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      serverIp,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                          const ClipboardData(text: serverIp));
                      note('Address copied');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: accent,
                      minimumSize: const Size(0, 44),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _linkTile(Icons.forum_rounded, 'Discord', 'Chat with the community',
            discordUrl),
        _linkTile(Icons.shopping_bag_rounded, 'Store',
            'Ranks, keys and coins', storeUrl),
        _linkTile(Icons.public_rounded, 'Website', 'News, rules and wiki',
            siteUrl),
      ],
    );
  }

  Widget _linkTile(IconData icon, String title, String sub, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        shadowColor: const Color(0x220B1B2B),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openLink(url),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tintBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: inkColor,
                        ),
                      ),
                      Text(
                        sub,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: navMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------- settings tab

  String fmtDeleteDate(int ms) {
    const m = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = d.hour.toString().padLeft(2, '0'), mm = d.minute.toString().padLeft(2, '0');
    return '${m[d.month - 1]} ${d.day}, ${d.year} at $hh:$mm';
  }

  Widget _deleteBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE4E6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2A7AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your account will be deleted on ${fmtDeleteDate(deleteAt)}.',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8E1F2A))),
          const SizedBox(height: 4),
          const Text('Your card, medals and stats will be removed. Changed your mind?',
              style: TextStyle(color: Color(0xFF8E1F2A), fontSize: 13)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: cancelDelete,
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Cancel deletion'),
          ),
        ],
      ),
    );
  }

  Future<void> askDelete() async {
    if (token.isEmpty) {
      note('No connection. Check your internet and try again.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'Your MVP card, medals, card styles and stats in the app and on the website will be deleted in 3 days. '
            'Until then you can cancel it here or on the website. Your Minecraft account and your items in the game are not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my account')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0343F)),
            child: const Text('Delete in 3 days'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await apiCall('POST', '/api/app/delete-account', token: token);
      if (r['_status'] == 200 && mounted) {
        setState(() => deleteAt = (r['delete_at'] as num?)?.toInt() ?? 0);
        note('Your account will be deleted in 3 days. You can cancel until then.');
      } else {
        note('Could not start the deletion. Try again later.');
      }
    } catch (_) {
      note('No connection. Check your internet and try again.');
    }
  }

  Future<void> cancelDelete() async {
    try {
      final r = await apiCall('POST', '/api/app/delete-account', token: token, data: {'cancel': true});
      if (r['_status'] == 200 && mounted) {
        setState(() => deleteAt = 0);
        note('Deletion cancelled. Your account stays.');
      } else {
        note('Could not cancel. Try again later.');
      }
    } catch (_) {
      note('No connection. Check your internet and try again.');
    }
  }

  // "Medals" button on the card screen: opens a sheet with all medals of the player
  Widget _socialTile(IconData icon, String title, String sub, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: surfaceColor, borderRadius: BorderRadius.circular(20), boxShadow: softShadow()),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: tintBlue, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: inkColor)),
                  Text(sub, style: TextStyle(color: mutedColor, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: mutedColor),
          ],
        ),
      ),
    );
  }

  Widget _medalsButton() {
    final preview = medals.take(6).toList();
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: openMedals,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: softShadow()),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tintBlue, borderRadius: BorderRadius.circular(12)),
                child: const LineIcon('medal', size: 24, color: accentLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medals.isEmpty ? 'Medals' : 'Medals (${medals.length})',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: inkColor)),
                    const SizedBox(height: 3),
                    preview.isEmpty
                        ? Text('See your medals and achievements', style: TextStyle(color: mutedColor, fontSize: 12))
                        : Row(children: [
                            for (final m in preview)
                              Padding(padding: const EdgeInsets.only(right: 5), child: PixelIcon(m.icon, size: 18)),
                          ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: navMuted),
            ],
          ),
        ),
      ),
    );
  }

  void openMedals() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: navMuted, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Medals', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: inkColor)),
                const SizedBox(width: 8),
                Text('${medals.length}', style: TextStyle(fontWeight: FontWeight.w700, color: mutedColor)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Join events and play to collect more.', style: TextStyle(color: mutedColor, fontSize: 13)),
            const SizedBox(height: 14),
            if (medals.isEmpty)
              Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('No medals yet.', style: TextStyle(color: mutedColor))),
              ),
            ...medals.map((m) => MedalTile(medal: m)),
          ],
        ),
      ),
    );
  }

  Widget _storeTile() {
    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: const Color(0x220B1B2B),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openLink(storeUrl),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.storefront_rounded, color: accent, size: 30),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MVP Store',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: inkColor)),
                    Text('Ranks and perks on the website',
                        style: TextStyle(color: mutedColor, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: mutedColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      children: [
        Text(
          'Settings',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: inkColor,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: softShadow(),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.mail_rounded, color: accent),
                title: const Text('E-mail'),
                subtitle: Text(email.isNotEmpty ? email : 'No e-mail yet. Tap to add one.'),
                trailing: email.isNotEmpty
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2E9E5B))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: email.isNotEmpty ? null : addEmail,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_rounded, color: accent),
                title: const Text('Game account'),
                subtitle: Text(linked
                    ? nick
                    : (pendingNick.isNotEmpty
                        ? 'Waiting for registration (wait some time)'
                        : 'Not registered. Tap to choose a nickname.')),
                trailing: linked
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2E9E5B))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: linked ? null : openRegister,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.palette_rounded, color: accent),
                title: const Text('Card style'),
                subtitle: Text(themes.length > 1
                    ? themes
                        .firstWhere((t) => t.id == themeId,
                            orElse: () => themes.first)
                        .name
                    : 'Classic Blue. More styles come from events.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: themes.length > 1
                    ? chooseStyle
                    : () => note('You have no special styles yet. They are given out at events.'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary:
                    const Icon(Icons.notifications_rounded, color: accent),
                title: const Text('News notifications'),
                subtitle: Text(widget.firebaseOk
                    ? 'Status: $pushStatus'
                    : 'Not available: ${firebaseError.isEmpty ? 'Firebase off' : firebaseError}'),
                value: pushOn && widget.firebaseOk,
                onChanged: widget.firebaseOk ? setPush : null,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dark_mode_rounded, color: accent),
                title: const Text('Theme'),
                subtitle: Text(themeMode.value == ThemeMode.light ? 'Light (white)' : themeMode.value == ThemeMode.dark ? 'Dark' : 'Default'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: chooseTheme,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.login_rounded, color: accent),
                title: const Text('Sign in to the website'),
                subtitle: const Text('Enter the code shown on the site'),
                onTap: webLogin,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFC0343F)),
                title: const Text('Sign out'),
                subtitle: const Text('Sign out of this phone'),
                onTap: signOut,
              ),
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.system_update_rounded, color: accent),
                title: const Text('Check for updates'),
                subtitle: Text('Version: $kVersion'),
                onTap: () => checkUpdate(manual: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'MVP app',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
        ),
        const SizedBox(height: 36),
        Center(
          child: TextButton(
            onPressed: deleteAt > 0 ? cancelDelete : askDelete,
            style: TextButton.styleFrom(foregroundColor: navMuted),
            child: Text(
              deleteAt > 0 ? 'Cancel account deletion' : 'Delete account',
              style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- widgets

/// Slides a repeating gradient by exactly one period, so the loop has no seam.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t, bounds.height * t, 0);
}

class MemberCard extends StatefulWidget {
  const MemberCard({
    super.key,
    required this.nick,
    required this.cardNo,
    required this.since,
    required this.rank,
    required this.onTap,
    this.colors = const [accentLight, accent, accentDark],
    this.animated = false,
    this.avatarNick = '',
  });

  final String avatarNick;
  final bool animated;
  final List<Color> colors;
  final String nick;
  final String cardNo;
  final String since;
  final String rank;
  final VoidCallback? onTap;

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard>
    with SingleTickerProviderStateMixin {
  Offset tilt = Offset.zero;
  late final AnimationController _anim = AnimationController(
      vsync: this, duration: const Duration(seconds: 9))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String get number => widget.cardNo.length == 8
      ? '${widget.cardNo.substring(0, 4)} ${widget.cardNo.substring(4)}'
      : '···· ····';

  @override
  Widget build(BuildContext context) {
    final nick = widget.nick.isEmpty ? 'NOT LINKED' : widget.nick.toUpperCase();
    return GestureDetector(
      onPanUpdate: (d) {
        setState(() {
          tilt = Offset(
            (tilt.dx + d.delta.dx / 400).clamp(-0.25, 0.25),
            (tilt.dy + d.delta.dy / 400).clamp(-0.25, 0.25),
          );
        });
      },
      onPanEnd: (_) => setState(() => tilt = Offset.zero),
      onPanCancel: () => setState(() => tilt = Offset.zero),
      child: TweenAnimationBuilder<Offset>(
        tween: Tween<Offset>(begin: tilt, end: tilt),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        builder: (context, o, child) {
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-o.dy)
              ..rotateY(o.dx),
            child: child,
          );
        },
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, inner) => Container(
          height: 216,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: widget.animated
                ? LinearGradient(
                    colors: [
                      widget.colors[0],
                      widget.colors[1],
                      widget.colors[2],
                      widget.colors[1],
                      widget.colors[0],
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    tileMode: TileMode.repeated,
                    transform: _SlideGradient(_anim.value),
                  )
                : LinearGradient(
                    colors: widget.colors,
                    stops: const [0, 0.55, 1],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            boxShadow: [
              BoxShadow(
                color: widget.colors[1].withAlpha(97),
                blurRadius: 40,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -72,
                  bottom: -92,
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x1FFFFFFF),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: -132,
                  child: Container(
                    width: 230,
                    height: 230,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x14FFFFFF),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 36,
                            height: 36,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'MVP',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0x38FFFFFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.rank,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        number,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          letterSpacing: 3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.avatarNick.isNotEmpty) ...[
                          SkinHead(nick: widget.avatarNick, size: 44),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: InkWell(
                            onTap: widget.onTap,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PLAYER',
                                  style: TextStyle(
                                    color: Color(0xCCFFFFFF),
                                    fontSize: 10,
                                    letterSpacing: 2,
                                  ),
                                ),
                                Text(
                                  nick,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'SINCE',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 10,
                                letterSpacing: 2,
                              ),
                            ),
                            Text(
                              widget.since,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
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
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    this.icon,
    this.asset,
    required this.tint,
    required this.color,
    required this.value,
    required this.label,
    this.sub,
  });

  final String? sub;
  final IconData? icon;
  final String? asset;
  final Color tint;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: asset != null
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      asset!,
                      filterQuality: FilterQuality.none,
                      fit: BoxFit.contain,
                    ),
                  )
                : Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: inkColor,
              ),
            ),
          ),
          Text(label, style: TextStyle(color: mutedColor, fontSize: 11)),
          if (sub != null)
            Text(sub!,
                style: const TextStyle(
                    color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class LinkSheet extends StatefulWidget {
  const LinkSheet({super.key, required this.code, required this.check});

  final String code;
  final Future<bool> Function() check;

  @override
  State<LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<LinkSheet> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_busy) return;
      _busy = true;
      final ok = await widget.check();
      _busy = false;
      if (ok && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final command = '/link ${widget.code}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        22,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Link your account',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Join the server and type this command in the game chat:',
            style: TextStyle(color: mutedColor),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: tintBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                command,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: command));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Command copied'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy command'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Waiting for the game... The code works for 10 minutes.',
                  style: TextStyle(color: mutedColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class NewsPicture extends StatelessWidget {
  const NewsPicture({super.key, required this.url, required this.height});

  final String url;
  final double? height; // kept for old callers; pictures are always 16:9

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: tintBlue,
              child: const Center(
                child:
                    CircularProgressIndicator(color: accent, strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard(
      {super.key,
      required this.item,
      required this.onTap,
      required this.onVote});

  final NewsItem item;
  final VoidCallback onTap;
  final Future<void> Function(NewsItem, int) onVote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        elevation: 1,
        shadowColor: const Color(0x220B1B2B),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.image != null) ...[
                  NewsPicture(url: item.image!, height: 170),
                  const SizedBox(height: 12),
                ],
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: inkColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDate(item.createdAt),
                  style: const TextStyle(color: accent, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  plainBody(item.body),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: mutedColor, height: 1.4),
                ),
                const SizedBox(height: 8),
                if (item.poll != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.poll_rounded, color: accent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        item.poll!.closed ? 'Poll closed' : 'Poll: tap to vote',
                        style: const TextStyle(
                            color: accent, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                VoteBar(item: item, onVote: onVote),
              ],
            ),
          ),
        ),
        ),
    );
  }
}

// opens the phone's share menu (Discord, Snapchat, WhatsApp, ...) with a link to this news item
Future<void> shareNews(NewsItem n) async {
  final url = '$siteUrl/n/${n.id}';
  try {
    await Share.share('${n.title}\n$url', subject: n.title);
  } catch (_) {}
}

class VoteBar extends StatelessWidget {
  const VoteBar({super.key, required this.item, required this.onVote});

  final NewsItem item;
  final Future<void> Function(NewsItem, int) onVote;

  Widget btn(IconData icon, IconData iconOn, int count, bool on, int v,
      String label) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onVote(item, v),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? tintBlue : tintGrey,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? iconOn : icon, size: 20, color: on ? accent : mutedColor),
              const SizedBox(width: 6),
              Text('$count',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: on ? accent : mutedColor)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        btn(Icons.thumb_up_outlined, Icons.thumb_up, item.likes, item.my == 1,
            1, 'Like'),
        const SizedBox(width: 10),
        btn(Icons.thumb_down_outlined, Icons.thumb_down, item.dislikes,
            item.my == -1, -1, 'Dislike'),
        const SizedBox(width: 10),
        Semantics(
          label: 'Share',
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => shareNews(item),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: tintGrey, borderRadius: BorderRadius.circular(999)),
              child: Icon(Icons.share_outlined, size: 20, color: mutedColor),
            ),
          ),
        ),
        const Spacer(),
        Icon(Icons.visibility_outlined, size: 20, color: mutedColor),
        const SizedBox(width: 6),
        Text('${item.views}',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: mutedColor)),
      ],
    );
  }
}

class NewsPage extends StatefulWidget {
  const NewsPage(
      {super.key,
      required this.item,
      required this.onVote,
      required this.onPollVote,
      this.token = ''});

  final String token;
  final NewsItem item;
  final Future<void> Function(NewsItem, int) onVote;
  final Future<void> Function(NewsItem, int) onPollVote;

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  Future<void> vote(NewsItem n, int v) async {
    final f = widget.onVote(n, v);
    if (mounted) setState(() {});
    await f;
    if (mounted) setState(() {});
  }

  Future<void> pollVote(int optionId) async {
    final f = widget.onPollVote(widget.item, optionId);
    if (mounted) setState(() {});
    await f;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          if (item.image != null) ...[
            NewsPicture(url: item.image!, height: null),
            const SizedBox(height: 16),
          ],
          Text(
            item.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatDate(item.createdAt),
            style: const TextStyle(color: accent),
          ),
          const SizedBox(height: 16),
          RichBody(
            text: item.body,
            style: TextStyle(fontSize: 16, height: 1.5, color: inkColor),
          ),
          for (final id in videoIds(item.body)) VideoTile(id: id),
          if (item.poll != null) PollView(poll: item.poll!, onVote: pollVote),
          const SizedBox(height: 20),
          VoteBar(item: item, onVote: vote),
          const SizedBox(height: 24),
          SxComments(token: widget.token, newsId: item.id),
        ],
      ),
    );
  }
}


class EventItem {
  EventItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.targetAt,
    required this.startAt,
    required this.pinned,
  });

  final int id;
  final String title;
  final String subtitle;
  final String label;
  final int targetAt;
  final int startAt;
  final bool pinned;

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        label: (j['label'] ?? 'Starts in').toString(),
        targetAt: (j['target_at'] as num).toInt(),
        startAt: (j['start_at'] as num).toInt(),
        pinned: (j['pinned'] ?? 0) == 1,
      );
}

Future<List<EventItem>> fetchEvents() async {
  final res = await http
      .get(Uri.parse('$apiBase/api/events'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return <EventItem>[];
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  if (data is! List) return <EventItem>[];
  return data
      .map((e) => EventItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

class EventCard extends StatefulWidget {
  const EventCard({super.key, required this.item});

  final EventItem item;

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _p(int n) => n < 10 ? '0$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final e = widget.item;
    final now = DateTime.now().millisecondsSinceEpoch;
    final left = e.targetAt - now;
    final starts = e.label != 'Ends in';
    final done = left <= 0;
    final secs = done ? 0 : left ~/ 1000;
    final d = secs ~/ 86400;
    final h = (secs % 86400) ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    final total = max(1, e.targetAt - e.startAt);
    final pc = done ? 100 : ((now - e.startAt) * 100 ~/ total).clamp(0, 100);
    const big = TextStyle(
        fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white);
    const unit = TextStyle(
        fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xCCFFFFFF));
    final spans = <InlineSpan>[
      if (d > 0) ...[
        TextSpan(text: '$d', style: big),
        const TextSpan(text: 'd  ', style: unit),
      ],
      TextSpan(text: _p(h), style: big),
      const TextSpan(text: 'h  ', style: unit),
      TextSpan(text: _p(m), style: big),
      const TextSpan(text: 'm  ', style: unit),
      TextSpan(text: _p(s), style: big),
      const TextSpan(text: 's', style: unit),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentLight, accentDark, Color(0xFF06223D)],
          stops: [0, 0.7, 1],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x4D0070B8), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (done ? (starts ? 'Started' : 'Finished') : e.label)
                    .toUpperCase(),
                style: const TextStyle(
                  color: Color(0xD9FFFFFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              if (e.pinned) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0x38FFFFFF),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    'PINNED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            e.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (e.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(e.subtitle,
                style: const TextStyle(color: Color(0xFFD8EFFF), fontSize: 14)),
          ],
          const SizedBox(height: 14),
          if (done)
            Text(starts ? 'It has begun!' : 'Finished', style: big)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: spans)),
            ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: LinearProgressIndicator(
              value: pc / 100,
              minHeight: 10,
              backgroundColor: const Color(0x38FFFFFF),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          if (!done) ...[
            const SizedBox(height: 6),
            Text('$pc% of the time has passed',
                style:
                    const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class PollView extends StatelessWidget {
  const PollView({super.key, required this.poll, required this.onVote});

  final Poll poll;
  final Future<void> Function(int) onVote;

  @override
  Widget build(BuildContext context) {
    final show = poll.my != 0 || poll.closed;
    final total = poll.total;
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tintPoll,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: inkColor),
          ),
          const SizedBox(height: 12),
          for (final o in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: poll.closed ? null : () => onVote(o.id),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: poll.my == o.id ? accent : lineColor,
                      width: poll.my == o.id ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      children: [
                        if (show)
                          FractionallySizedBox(
                            widthFactor: total == 0 ? 0 : o.votes / total,
                            child: Container(
                              color: poll.my == o.id
                                  ? const Color(0x550094E6)
                                  : const Color(0x2A0094E6),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              if (poll.my == o.id)
                                const Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(Icons.check_circle_rounded,
                                      color: accent, size: 18),
                                ),
                              Expanded(
                                child: Text(o.text,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: inkColor)),
                              ),
                              if (show)
                                Text(
                                  '${total == 0 ? 0 : (o.votes * 100 / total).round()}%',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: inkColor),
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
          Text(
            '$total ${total == 1 ? 'vote' : 'votes'}${poll.closed ? '  |  Poll closed' : ''}',
            style: TextStyle(color: mutedColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  http.Client? _client;
  bool _cancelled = false;
  double? progress;
  String text = 'Starting the download...';
  bool failed = false;
  bool done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _cancelled = false;
    if (mounted) {
      setState(() {
        failed = false;
        done = false;
        progress = null;
        text = 'Starting the download...';
      });
    }
    final client = http.Client();
    _client = client;
    IOSink? sink;
    try {
      final file = File('${Directory.systemTemp.path}/mvp-app.apk');
      if (await file.exists()) await file.delete();
      final res = await client
          .send(http.Request('GET', Uri.parse(apkUrl)))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('http ${res.statusCode}');
      final total = res.contentLength ?? 0;
      var got = 0;
      sink = file.openWrite();
      await for (final chunk in res.stream) {
        if (_cancelled) throw Exception('cancelled');
        sink.add(chunk);
        got += chunk.length;
        if (mounted && total > 0) {
          setState(() {
            progress = got / total;
            text = 'Downloading... ${(got * 100 ~/ total)}%';
          });
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!mounted) return;
      setState(() {
        progress = 1;
        text = 'Opening the installer. Confirm the update on the next screen.';
        done = true;
      });
      final r = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (!mounted) return;
      if (r.type != ResultType.done) {
        setState(() {
          done = false;
          failed = true;
          text =
              'Allow installing apps from MVP in the Android settings, then tap Try again.';
        });
      }
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (!mounted || _cancelled) return;
      setState(() {
        failed = true;
        done = false;
        text = 'The update could not be downloaded. Check your internet.';
      });
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Updating MVP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!failed)
            LinearProgressIndicator(value: progress, color: accent),
          const SizedBox(height: 14),
          Text(text),
        ],
      ),
      actions: [
        if (failed) ...[
          TextButton(
            onPressed: () => openLink(apkUrl),
            child: const Text('Download in browser'),
          ),
          TextButton(onPressed: () => _start(), child: const Text('Try again')),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(done ? 'Close' : 'Cancel'),
        ),
      ],
    );
  }
}
