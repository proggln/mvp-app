import 'dart:async';
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
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

const String apiBase = 'https://mvp-news-api.mvp-shop.workers.dev';
const String discordUrl = 'https://discord.gg/CWTBxgBdr';
const String siteUrl = 'https://mvp.mvp-shop.workers.dev';
const String storeUrl = 'https://mvp.mvp-shop.workers.dev/store/';
const String serverIp = 'mc.playmvp.org';
const String pushTopic = 'news';

const Color accent = Color(0xFF0070B8);
const Color accentLight = Color(0xFF0094E6);
const Color accentDark = Color(0xFF0A4D86);
const Color bgColor = Color(0xFFEEF2F6);
const Color inkColor = Color(0xFF0B1B2B);
const Color mutedColor = Color(0xFF5B6F82);
const Color navMuted = Color(0xFF8A9AAB);

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
  runApp(MvpApp(firebaseOk: firebaseOk));
}

class MvpApp extends StatelessWidget {
  const MvpApp({super.key, required this.firebaseOk});

  final bool firebaseOk;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: accent).copyWith(
          primary: accent,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: bgColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgColor,
          foregroundColor: inkColor,
          elevation: 0,
        ),
      ),
      home: Shell(firebaseOk: firebaseOk),
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
  CardStyle({required this.id, required this.name, required this.colors});
  final String id;
  final String name;
  final List<Color> colors;

  factory CardStyle.fromJson(Map<String, dynamic> j) => CardStyle(
        id: (j['id'] ?? 'default').toString(),
        name: (j['name'] ?? '').toString(),
        colors: ((j['colors'] as List<dynamic>?) ?? <dynamic>[])
            .map((c) => Color(
                int.tryParse('FF${c.toString().replaceAll('#', '')}',
                        radix: 16) ??
                    0xFF0070B8))
            .toList(),
      );
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
  int playtime = 0;
  bool linked = false;
  String storageNote = '';
  String since = '';
  String themeId = 'default';
  String localTheme = '';
  final CardStyle auroraStyle = CardStyle(
      id: 'aurora',
      name: 'Aurora (app only)',
      colors: const [Color(0xFF5CFFB0), Color(0xFF7A5CFF), Color(0xFF0B1030)]);
  List<CardStyle> themes = <CardStyle>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _sub?.cancel();
    super.dispose();
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
        final r = await apiCall('POST', '/api/app/register');
        if (r['_status'] == 200 && r['token'] is String) {
          token = r['token'] as String;
          cardNo = (r['card_no'] ?? '').toString();
          await savePref('token', token);
          await savePref('cardno', cardNo);
          if (mounted) setState(() {});
        } else {
          return;
        }
      }
      final me = await apiCall('GET', '/api/app/me', token: token);
      final st = me['_status'];
      if (st == 401 && retry) {
        // the card was deleted in the admin panel: this phone gets a new one
        token = '';
        await savePref('token', '');
        await refreshProfile(retry: false);
        return;
      }
      if (st == 200 && mounted) {
        setState(() {
          cardNo = (me['card_no'] ?? cardNo).toString();
          nick = (me['nick'] ?? '').toString();
          rank = (me['rank'] ?? 'Member').toString();
          coins = (me['coins'] as num?)?.toInt() ?? 0;
          kills = (me['kills'] as num?)?.toInt() ?? 0;
          playtime = (me['playtime'] as num?)?.toInt() ?? 0;
          linked = me['linked'] == true;
          themeId = (me['theme'] ?? 'default').toString();
          themes = ((me['themes'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => CardStyle.fromJson(e as Map<String, dynamic>))
              .toList();
          themes.add(auroraStyle);
          if (localTheme == 'aurora') themeId = 'aurora';
        });
        await savePref('cardno', cardNo);
      }
    } catch (_) {
      // offline: keep what we have
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
      backgroundColor: Colors.white,
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
        note(m.notification?.title ?? 'New news');
        load();
      });
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
              NewsPage(item: n, onVote: voteNews, onPollVote: votePoll)),
    );
  }

  List<Color> get cardColors {
    for (final t in themes) {
      if (t.id == themeId && t.colors.length >= 3) return t.colors;
    }
    return const [accentLight, accent, accentDark];
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
    if (t.id == 'aurora') {
      setState(() {
        themeId = 'aurora';
        localTheme = 'aurora';
      });
      await savePref('localtheme', 'aurora');
      return;
    }
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Card style',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: inkColor)),
              const SizedBox(height: 4),
              const Text('Special styles are given out at events.',
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
                              style: const TextStyle(
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
    final pages = <Widget>[
      _cardTab(),
      _newsTab(),
      _serverTab(),
      _settingsTab(),
    ];
    return Scaffold(
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
      decoration: const BoxDecoration(
        color: Colors.white,
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
    final name = nick.isEmpty ? 'Player' : nick;
    final cardNum = cardNo.length == 8 ? cardNo : '';
    return RefreshIndicator(
      color: accent,
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        children: [
          for (final e in events.where((x) => x.pinned))
            EventCard(key: ValueKey('p${e.id}'), item: e),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Welcome back',
                      style: TextStyle(color: mutedColor, fontSize: 13),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: inkColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.firebaseOk)
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  shadowColor: const Color(0x220B1B2B),
                  child: IconButton(
                    tooltip: pushOn
                        ? 'Turn notifications off'
                        : 'Turn notifications on',
                    onPressed: () => setPush(!pushOn),
                    icon: Icon(
                      pushOn
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: pushOn ? accent : navMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          MemberCard(
            nick: nick,
            cardNo: cardNum,
            since: since,
            rank: rank,
            colors: cardColors,
            animated: themeId == 'aurora',
            onTap: linked ? null : startLink,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.schedule_rounded,
                  tint: const Color(0xFFE3F2FC),
                  color: accent,
                  value: formatPlaytime(playtime),
                  label: 'Playtime',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  asset: 'assets/coin.png',
                  tint: const Color(0xFFFFF1D6),
                  color: const Color(0xFFB87400),
                  value: '$coins',
                  label: 'Coins',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  asset: 'assets/sword.png',
                  tint: const Color(0xFFFDE4E6),
                  color: const Color(0xFFC0343F),
                  value: '$kills',
                  label: 'Kills',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _storeTile(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
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
                        linked ? 'Account linked' : 'Link your account',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: inkColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        linked
                            ? 'Playing as $nick'
                            : 'Get a code, then type /link CODE in the game.',
                        style: const TextStyle(color: mutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (linked)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E9E5B), size: 30)
                else
                  FilledButton(
                    onPressed: startLink,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 44),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Link'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: softShadow(),
              ),
              child: Text(
                loading
                    ? 'Loading...'
                    : (error ?? 'No news yet. Check back soon!'),
                style: const TextStyle(color: mutedColor),
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
          const Text(
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
                  const Icon(Icons.wifi_off_rounded,
                      size: 42, color: mutedColor),
                  const SizedBox(height: 12),
                  Text(error!, textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: load, child: const Text('Try again')),
                ],
              ),
            )
          else if (list.isEmpty)
            const Padding(
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
        const Text(
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
        color: Colors.white,
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
                    color: const Color(0xFFE3F2FC),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: inkColor,
                        ),
                      ),
                      Text(
                        sub,
                        style: const TextStyle(
                          color: mutedColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: navMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------- settings tab

  Widget _storeTile() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      shadowColor: const Color(0x220B1B2B),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => openLink(storeUrl),
        child: const Padding(
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
        const Text(
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: softShadow(),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_rounded, color: accent),
                title: const Text('Game account'),
                subtitle: Text(linked ? nick : 'Not linked. Tap to link.'),
                trailing: linked
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2E9E5B))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: linked ? null : startLink,
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
                leading: const Icon(Icons.login_rounded, color: accent),
                title: const Text('Sign in to the website'),
                subtitle: const Text('Enter the code shown on the site'),
                onTap: webLogin,
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
            style: const TextStyle(color: mutedColor, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- widgets

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
  });

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
      vsync: this, duration: const Duration(seconds: 7))
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
            gradient: LinearGradient(
              colors: widget.animated
                  ? [
                      widget.colors[0],
                      widget.colors[1],
                      widget.colors[2],
                      widget.colors[1],
                      widget.colors[0],
                    ]
                  : widget.colors,
              stops: widget.animated
                  ? const [0, 0.25, 0.5, 0.75, 1]
                  : const [0, 0.55, 1],
              begin: widget.animated
                  ? Alignment(-1 + 2 * _anim.value, -1)
                  : Alignment.topLeft,
              end: widget.animated
                  ? Alignment(1 + 2 * _anim.value, 1)
                  : Alignment.bottomRight,
              tileMode: widget.animated ? TileMode.mirror : TileMode.clamp,
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
  });

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
        color: Colors.white,
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
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: inkColor,
              ),
            ),
          ),
          Text(label, style: const TextStyle(color: mutedColor, fontSize: 11)),
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
          const Text(
            'Link your account',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Join the server and type this command in the game chat:',
            style: TextStyle(color: mutedColor),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FC),
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
            children: const [
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
              color: const Color(0xFFE3F2FC),
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
        color: Colors.white,
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
                  style: const TextStyle(
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
                  style: const TextStyle(color: mutedColor, height: 1.4),
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
            color: on ? const Color(0xFFE3F2FC) : const Color(0xFFF1F5F9),
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
        const Spacer(),
        const Icon(Icons.visibility_outlined, size: 20, color: mutedColor),
        const SizedBox(width: 6),
        Text('${item.views}',
            style: const TextStyle(
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
      required this.onPollVote});

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
            style: const TextStyle(
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
            style: const TextStyle(fontSize: 16, height: 1.5, color: inkColor),
          ),
          for (final id in videoIds(item.body)) VideoTile(id: id),
          if (item.poll != null) PollView(poll: item.poll!, onVote: pollVote),
          const SizedBox(height: 20),
          VoteBar(item: item, onVote: vote),
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
        color: const Color(0xFFEAF5FD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: const TextStyle(
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: poll.my == o.id ? accent : const Color(0xFFD3E3EE),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: inkColor)),
                              ),
                              if (show)
                                Text(
                                  '${total == 0 ? 0 : (o.votes * 100 / total).round()}%',
                                  style: const TextStyle(
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
            style: const TextStyle(color: mutedColor, fontSize: 12),
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
