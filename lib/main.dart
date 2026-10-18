import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

const String apiBase = 'https://mvp-news-api.mvp-shop.workers.dev';
const String discordUrl = 'https://discord.gg/CWTBxgBdr';
const String siteUrl = 'https://playmvp.org';
const String pushTopic = 'news';

const Color accent = Color(0xFF0081CC);
const Color bgColor = Color(0xFF07101C);
const Color cardColor = Color(0xFF0D1B2E);
const Color lineColor = Color(0xFF1C3250);
const Color mutedColor = Color(0xFF8FA7BD);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool firebaseOk = false;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      firebaseOk = true;
    } catch (_) {
      firebaseOk = false;
    }
  }
  runApp(MvpApp(firebaseOk: firebaseOk));
}

class MvpApp extends StatelessWidget {
  const MvpApp({super.key, required this.firebaseOk});

  final bool firebaseOk;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(primary: accent, surface: cardColor);
    return MaterialApp(
      title: 'MVP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: bgColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: bgColor,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: HomePage(firebaseOk: firebaseOk),
    );
  }
}

class NewsItem {
  NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final DateTime createdAt;

  factory NewsItem.fromJson(Map<String, dynamic> j) {
    return NewsItem(
      id: (j['id'] as num).toInt(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

Future<List<NewsItem>> fetchNews() async {
  final res = await http
      .get(Uri.parse('$apiBase/api/news'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) {
    throw Exception('Server error ${res.statusCode}');
  }
  final data = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  return data
      .map((e) => NewsItem.fromJson(e as Map<String, dynamic>))
      .toList();
}

String two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) {
  final l = d.toLocal();
  return '${two(l.day)}.${two(l.month)}.${l.year}  ${two(l.hour)}:${two(l.minute)}';
}

Future<void> openLink(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.firebaseOk});

  final bool firebaseOk;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NewsItem>? items;
  String? error;
  bool loading = true;
  bool pushOn = true;
  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    load();
    if (widget.firebaseOk) {
      setupPush();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await fetchNews();
      if (!mounted) return;
      setState(() {
        items = list;
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
      final prefs = await SharedPreferences.getInstance();
      pushOn = prefs.getBool('push') ?? true;
      if (mounted) setState(() {});
      final fm = FirebaseMessaging.instance;
      if (pushOn) {
        await fm.requestPermission();
        await fm.subscribeToTopic(pushTopic);
      }
      _sub = FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        if (!mounted) return;
        final title = m.notification?.title ?? 'New news';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(title), behavior: SnackBarBehavior.floating),
        );
        load();
      });
    } catch (_) {
      // push is optional: the app still works without it
    }
  }

  Future<void> togglePush() async {
    final fm = FirebaseMessaging.instance;
    final next = !pushOn;
    try {
      if (next) {
        await fm.requestPermission();
        await fm.subscribeToTopic(pushTopic);
      } else {
        await fm.unsubscribeFromTopic(pushTopic);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('push', next);
      if (!mounted) return;
      setState(() => pushOn = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next ? 'Notifications are on' : 'Notifications are off'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change notifications. Try again later.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MVP',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        actions: [
          if (widget.firebaseOk)
            IconButton(
              tooltip: pushOn ? 'Turn notifications off' : 'Turn notifications on',
              onPressed: togglePush,
              icon: Icon(
                pushOn ? Icons.notifications_active : Icons.notifications_off,
                color: pushOn ? accent : mutedColor,
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: accent,
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            const Text(
              'Server news',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Events and updates from the MVP server',
              style: TextStyle(color: mutedColor),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openLink(discordUrl),
                    icon: const Icon(Icons.forum),
                    label: const Text('Discord'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openLink(siteUrl),
                    icon: const Icon(Icons.public),
                    label: const Text('Website'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ..._content(),
          ],
        ),
      ),
    );
  }

  List<Widget> _content() {
    if (loading && items == null) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator(color: accent)),
        ),
      ];
    }
    if (error != null && items == null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Column(
            children: [
              const Icon(Icons.wifi_off, size: 42, color: mutedColor),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: load, child: const Text('Try again')),
            ],
          ),
        ),
      ];
    }
    final list = items ?? <NewsItem>[];
    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 50),
          child: Center(
            child: Text(
              'No news yet. Check back soon!',
              style: TextStyle(color: mutedColor),
            ),
          ),
        ),
      ];
    }
    return list.map((n) => NewsCard(item: n)).toList();
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => NewsPage(item: item)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: lineColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDate(item.createdAt),
                  style: const TextStyle(color: accent, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  item.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: mutedColor, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NewsPage extends StatelessWidget {
  const NewsPage({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            item.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            formatDate(item.createdAt),
            style: const TextStyle(color: accent),
          ),
          const SizedBox(height: 16),
          SelectableText(
            item.body,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }
}
