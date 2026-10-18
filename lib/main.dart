import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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

class _ShellState extends State<Shell> {
  int tab = 0;

  List<NewsItem>? items;
  String? error;
  bool loading = true;

  bool pushOn = true;
  StreamSubscription<RemoteMessage>? _sub;

  String nick = '';
  String cardNo = '00000000';
  String since = '';

  @override
  void initState() {
    super.initState();
    loadProfile();
    load();
    if (widget.firebaseOk) {
      setupPush();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => note(
          'Push setup failed: ${firebaseError.isEmpty ? 'Firebase off' : firebaseError}'));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void note(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    var no = prefs.getString('cardno');
    if (no == null || no.length != 8) {
      final r = Random.secure();
      no = List.generate(8, (_) => r.nextInt(10)).join();
      await prefs.setString('cardno', no);
    }
    var s = prefs.getString('since');
    if (s == null) {
      final n = DateTime.now();
      s = '${two(n.month)} / ${two(n.year % 100)}';
      await prefs.setString('since', s);
    }
    if (!mounted) return;
    setState(() {
      nick = prefs.getString('nick') ?? '';
      cardNo = no!;
      since = s!;
    });
  }

  Future<void> editNick() async {
    final controller = TextEditingController(text: nick);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Your nickname'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 16,
                  decoration: InputDecoration(
                    hintText: 'Minecraft nickname',
                    errorText: err,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (!RegExp(r'^[A-Za-z0-9_]{3,16}$').hasMatch(v)) {
                    setD(() => err = '3-16 letters, digits or _');
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nick', result);
    if (!mounted) return;
    setState(() => nick = result);
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
        final st = await fm.requestPermission();
        await fm.subscribeToTopic(pushTopic);
        if (st.authorizationStatus != AuthorizationStatus.authorized) {
          note('Notifications are blocked. Allow them in phone settings.');
        }
      }
      _sub = FirebaseMessaging.onMessage.listen((RemoteMessage m) {
        if (!mounted) return;
        note(m.notification?.title ?? 'New news');
        load();
      });
    } catch (e) {
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('push', next);
      if (!mounted) return;
      setState(() => pushOn = next);
    } catch (_) {
      note('Could not change notifications. Try again later.');
    }
  }

  void openNews(NewsItem n) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NewsPage(item: n)),
    );
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
    return RefreshIndicator(
      color: accent,
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        children: [
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
            cardNo: cardNo,
            since: since,
            onTapNick: editNick,
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(
                child: StatTile(
                  icon: Icons.workspace_premium_rounded,
                  tint: Color(0xFFE3F2FC),
                  color: accent,
                  value: '—',
                  label: 'Rank',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.monetization_on_rounded,
                  tint: Color(0xFFFFF1D6),
                  color: Color(0xFFB87400),
                  value: '—',
                  label: 'Coins',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  icon: Icons.sports_martial_arts_rounded,
                  tint: Color(0xFFFDE4E6),
                  color: Color(0xFFC0343F),
                  value: '—',
                  label: 'Kills',
                ),
              ),
            ],
          ),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link your account',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: inkColor,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Stats from the server will appear here soon.',
                        style: TextStyle(color: mutedColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => note('Account linking is coming soon.'),
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
            NewsCard(item: items!.first, onTap: () => openNews(items!.first))
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
            'Server news',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: inkColor,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Events and updates from the MVP server',
            style: TextStyle(color: mutedColor),
          ),
          const SizedBox(height: 16),
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
            ...list.map((n) => NewsCard(item: n, onTap: () => openNews(n))),
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
                title: const Text('Nickname'),
                subtitle: Text(nick.isEmpty ? 'Not set' : nick),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: editNick,
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary:
                    const Icon(Icons.notifications_rounded, color: accent),
                title: const Text('News notifications'),
                subtitle: Text(widget.firebaseOk
                    ? 'Get a push when new server news appears'
                    : 'Not available right now'),
                value: pushOn && widget.firebaseOk,
                onChanged: widget.firebaseOk ? setPush : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'MVP app',
            style: TextStyle(color: mutedColor, fontSize: 12),
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
    required this.onTapNick,
  });

  final String nick;
  final String cardNo;
  final String since;
  final VoidCallback onTapNick;

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  Offset tilt = Offset.zero;

  String get number =>
      '${widget.cardNo.substring(0, 4)} ${widget.cardNo.substring(4)}';

  @override
  Widget build(BuildContext context) {
    final nick = widget.nick.isEmpty ? 'SET NICKNAME' : widget.nick.toUpperCase();
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
        child: Container(
          height: 216,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [accentLight, accent, accentDark],
              stops: [0, 0.55, 1],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x610070B8),
                blurRadius: 40,
                offset: Offset(0, 22),
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
                          child: const Text(
                            'Member',
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
                            onTap: widget.onTapNick,
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
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.tint,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
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
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 19,
              color: inkColor,
            ),
          ),
          Text(label, style: const TextStyle(color: mutedColor, fontSize: 11)),
        ],
      ),
    );
  }
}

class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item, required this.onTap});

  final NewsItem item;
  final VoidCallback onTap;

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
        padding: const EdgeInsets.all(22),
        children: [
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
          SelectableText(
            item.body,
            style: const TextStyle(fontSize: 16, height: 1.5, color: inkColor),
          ),
        ],
      ),
    );
  }
}
