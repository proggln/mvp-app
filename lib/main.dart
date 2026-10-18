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

Future<Map<String, dynamic>> apiCall(String method, String path,
    {String? token}) async {
  final uri = Uri.parse('$apiBase$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  final res = await (method == 'POST'
          ? http.post(uri, headers: headers, body: '{}')
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
  bool linked = false;
  String since = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadQuiet();
      refreshProfile();
    }
  }

  Future<void> loadQuiet() async {
    try {
      final list = await fetchNews();
      if (!mounted) return;
      setState(() {
        items = list;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> savePref(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    token = prefs?.getString('token') ?? '';
    final cachedCard = prefs?.getString('cardno') ?? '';
    var s = prefs?.getString('since') ?? '';
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
          linked = me['linked'] == true;
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
    final cardNum = cardNo.length == 8 ? cardNo : '';
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
            cardNo: cardNum,
            since: since,
            rank: rank,
            onTap: linked ? null : startLink,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  icon: Icons.workspace_premium_rounded,
                  tint: const Color(0xFFE3F2FC),
                  color: accent,
                  value: rank,
                  label: 'Rank',
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
                title: const Text('Game account'),
                subtitle: Text(linked ? nick : 'Not linked. Tap to link.'),
                trailing: linked
                    ? const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF2E9E5B))
                    : const Icon(Icons.chevron_right_rounded),
                onTap: linked ? null : startLink,
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
    required this.rank,
    required this.onTap,
  });

  final String nick;
  final String cardNo;
  final String since;
  final String rank;
  final VoidCallback? onTap;

  @override
  State<MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends State<MemberCard> {
  Offset tilt = Offset.zero;

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
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
