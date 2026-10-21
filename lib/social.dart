// Social features of the MVP app: skin avatars, comments, friends, chat and profiles.
// They talk to the same API as the website.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'main.dart';

const Color _red = Color(0xFFC0343F);
const Color _green = Color(0xFF2E9E5B);

Map<String, dynamic> _m(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic v) => v is List
    ? v.map((e) => _m(e)).toList()
    : <Map<String, dynamic>>[];

String _ago(int ms) {
  if (ms <= 0) return 'a long time ago';
  final s = ((DateTime.now().millisecondsSinceEpoch - ms) / 1000).floor();
  if (s < 60) return 'just now';
  if (s < 3600) return '${(s / 60).floor()} min ago';
  if (s < 86400) return '${(s / 3600).floor()} h ago';
  if (s < 2592000) return '${(s / 86400).floor()} d ago';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day}.${d.month}.${d.year}';
}

Color _hex(dynamic v, Color fallback) {
  final t = (v ?? '').toString().replaceAll('#', '');
  final n = int.tryParse('FF$t', radix: 16);
  return n == null ? fallback : Color(n);
}

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

void openProfile(BuildContext context, String token, String nick) {
  Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfilePage(token: token, nick: nick)));
}

// ---------------------------------------------------------------- skin avatar

class _DefaultHeadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 8;
    void px(double x, double y, double w, double h, Color c) {
      canvas.drawRect(Rect.fromLTWH(x * u, y * u, w * u, h * u), Paint()..color = c);
    }

    px(0, 0, 8, 8, const Color(0xFFB98A63));
    px(0, 0, 8, 2, const Color(0xFF3B2A1D));
    px(0, 2, 1, 1, const Color(0xFF3B2A1D));
    px(7, 2, 1, 1, const Color(0xFF3B2A1D));
    px(1, 4, 2, 1, Colors.white);
    px(5, 4, 2, 1, Colors.white);
    px(2, 4, 1, 1, const Color(0xFF3A4FA0));
    px(5, 4, 1, 1, const Color(0xFF3A4FA0));
    px(3, 5, 2, 1, const Color(0xFF8F6444));
    px(2, 6, 4, 1, const Color(0xFF6E4A31));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DefaultHead extends StatelessWidget {
  const _DefaultHead();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DefaultHeadPainter(), size: Size.infinite);
}

/// The face of a player's Minecraft skin (same picture as on the website).
class SkinHead extends StatelessWidget {
  const SkinHead({super.key, required this.nick, this.size = 40});

  final String nick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = nick.trim();
    final valid = RegExp(r'^[A-Za-z0-9_]{2,16}$').hasMatch(n);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: valid
            ? Image.network(
                '$apiBase/api/skin/$n',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.none,
                frameBuilder: (ctx, child, frame, sync) =>
                    (frame == null && !sync) ? const _DefaultHead() : child,
                errorBuilder: (ctx, e, s) => const _DefaultHead(),
              )
            : const _DefaultHead(),
      ),
    );
  }
}

// ---------------------------------------------------------------- comments

const Map<String, String> _commentErrors = {
  'not_allowed': 'Please keep it friendly. This text is not allowed.',
  'no_links': 'Links are not allowed in comments.',
  'slow_down': 'You are posting too fast. Wait a little.',
  'duplicate': 'You already wrote this.',
  'banned': 'You can not comment right now.',
  'link_first': 'Link your Minecraft account to comment.',
  'email_first': 'Add an e-mail to your account to comment.',
  'too_many': 'Too many tries. Wait a little.',
  'bad_text': 'Write 1 to 500 characters.',
  'self_profile': 'You can not comment on your own profile.',
  'private': 'This profile is private.',
};

/// Comments under a news item (newsId) or under a profile (profile = nickname).
class SxComments extends StatefulWidget {
  const SxComments({super.key, required this.token, this.newsId, this.profile});

  final String token;
  final int? newsId;
  final String? profile;

  @override
  State<SxComments> createState() => _SxCommentsState();
}

class _SxCommentsState extends State<SxComments> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool failed = false;
  bool canComment = false;
  bool canLike = false;
  bool isAdmin = false;
  String why = '';
  bool showAll = false;
  int? replyTo;
  bool sending = false;
  String msg = '';
  final TextEditingController ctl = TextEditingController();
  final TextEditingController replyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    ctl.dispose();
    replyCtl.dispose();
    super.dispose();
  }

  String get _path => widget.profile != null
      ? '/api/comments?profile=${Uri.encodeQueryComponent(widget.profile!)}'
      : '/api/comments?news=${widget.newsId}';

  Future<void> load() async {
    try {
      final r = await apiCall('GET', _path, token: widget.token);
      if (!mounted) return;
      if (r['_status'] != 200) {
        setState(() {
          loading = false;
          failed = true;
          why = (r['error'] ?? '').toString();
        });
        return;
      }
      setState(() {
        items = _list(r['items']);
        canComment = r['can_comment'] == true;
        canLike = r['can_like'] == null ? r['can_comment'] == true : r['can_like'] == true;
        isAdmin = r['admin'] == true;
        why = (r['why'] ?? '').toString();
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> post(String text, int? parent) async {
    final t = text.trim();
    if (t.isEmpty || sending) return;
    setState(() {
      sending = true;
      msg = '';
    });
    try {
      final r = await apiCall('POST', '/api/app/comments', token: widget.token, data: {
        if (widget.profile != null) 'profile': widget.profile else 'news': widget.newsId,
        'body': t,
        if (parent != null) 'parent': parent,
      });
      if (!mounted) return;
      if (r['_status'] == 200 && r['item'] != null) {
        setState(() {
          items.add(_m(r['item']));
          sending = false;
          if (parent == null) {
            ctl.clear();
          } else {
            replyCtl.clear();
            replyTo = null;
          }
        });
      } else {
        setState(() {
          sending = false;
          msg = _commentErrors[(r['error'] ?? '').toString()] ?? 'Could not post. Try again later.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          sending = false;
          msg = 'Cannot reach the server.';
        });
      }
    }
  }

  Future<void> like(Map<String, dynamic> c) async {
    if (!canLike) {
      _toast(context, why == 'signin'
          ? 'Log in to like comments.'
          : 'Link your Minecraft account and add an e-mail to like comments.');
      return;
    }
    final was = c['liked'] == true;
    final n = (c['likes'] as num?)?.toInt() ?? 0;
    setState(() {
      c['liked'] = !was;
      c['likes'] = was ? (n > 0 ? n - 1 : 0) : n + 1;
    });
    try {
      final r = await apiCall('POST', '/api/app/comments/like',
          token: widget.token, data: {'id': c['id']});
      if (!mounted) return;
      if (r['_status'] == 200) {
        setState(() {
          c['liked'] = r['liked'] == true;
          c['likes'] = (r['likes'] as num?)?.toInt() ?? 0;
        });
      } else {
        setState(() {
          c['liked'] = was;
          c['likes'] = n;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          c['liked'] = was;
          c['likes'] = n;
        });
      }
    }
  }

  Future<void> report(Map<String, dynamic> c) async {
    if (c['mine'] == true) {
      _toast(context, 'You can not report your own comment.');
      return;
    }
    if (!canLike) {
      _toast(context, 'Log in with a linked account to report comments.');
      return;
    }
    try {
      final r = await apiCall('POST', '/api/app/comments/report',
          token: widget.token, data: {'id': c['id']});
      if (mounted) {
        _toast(context, r['_status'] == 200 ? 'Reported. Thank you.' : 'Try again later.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'Cannot reach the server.');
    }
  }

  Future<void> remove(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this comment?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final admin = c['mine'] != true && isAdmin;
      final r = await apiCall('POST',
          admin ? '/api/app/comments/mod' : '/api/app/comments/delete',
          token: widget.token,
          data: admin ? {'action': 'delete', 'id': c['id']} : {'id': c['id']});
      if (r['_status'] == 200 && mounted) {
        setState(() {
          items.removeWhere((x) => x['id'] == c['id'] || x['parent_id'] == c['id']);
        });
      }
    } catch (_) {}
  }

  Widget _composer(TextEditingController controller, int? parent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      decoration: BoxDecoration(
        color: tintGrey,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: lineColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              style: TextStyle(color: inkColor),
              decoration: InputDecoration(
                hintText: parent == null ? 'Share your thoughts...' : 'Write a reply...',
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
          IconButton(
            onPressed: sending ? null : () => post(controller.text, parent),
            icon: Icon(Icons.send_rounded, color: sending ? mutedColor : accent),
            tooltip: parent == null ? 'Post comment' : 'Reply',
          ),
        ],
      ),
    );
  }

  Widget _actionIcon(Object icon, Color color, VoidCallback onTap,
      {String? label, String? tip, double px = 1}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon is String) PxIcon(icon, 20, opacity: px) else Icon(icon as IconData, size: 18, color: color),
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _item(Map<String, dynamic> c, bool isReply) {
    final nick = (c['nick'] ?? '').toString();
    final liked = c['liked'] == true;
    final likes = (c['likes'] as num?)?.toInt() ?? 0;
    final rank = (c['rank'] ?? '').toString();
    return Padding(
      padding: EdgeInsets.only(left: isReply ? 34 : 0, top: 10, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => openProfile(context, widget.token, nick),
            child: SkinHead(nick: nick, size: isReply ? 34 : 44),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    GestureDetector(
                      onTap: () => openProfile(context, widget.token, nick),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(nick,
                              style: TextStyle(fontWeight: FontWeight.w800, color: inkColor)),
                          if (c['verified'] == true) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(size: 14),
                          ],
                        ],
                      ),
                    ),
                    if (rank.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: tintBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(rank,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                      ),
                    Text(_ago((c['at'] as num?)?.toInt() ?? 0),
                        style: TextStyle(color: mutedColor, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 3),
                Text((c['body'] ?? '').toString(),
                    style: TextStyle(color: inkColor, height: 1.4)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _actionIcon(
                      'heart',
                      liked ? const Color(0xFFE8424F) : mutedColor,
                      () => like(c),
                      px: liked ? 1 : 0.4,
                      label: likes > 0 ? '$likes' : null,
                    ),
                    const SizedBox(width: 10),
                    if (!isReply)
                      _actionIcon(Icons.arrow_forward_rounded, mutedColor, () {
                        setState(() {
                          replyTo = replyTo == c['id'] ? null : (c['id'] as num?)?.toInt();
                          replyCtl.clear();
                        });
                      }, label: 'Reply'),
                    const SizedBox(width: 10),
                    if (c['mine'] == true || isAdmin)
                      _actionIcon(Icons.delete_outline_rounded, mutedColor, () => remove(c),
                          label: 'Delete'),
                    const Spacer(),
                    _actionIcon('warning', _red, () => report(c)),
                  ],
                ),
                if (replyTo != null && replyTo == (c['id'] as num?)?.toInt() && canComment)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _composer(replyCtl, replyTo),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tops = items.where((x) => ((x['parent_id'] as num?)?.toInt() ?? 0) == 0).toList()
      ..sort((a, b) {
        final la = (a['likes'] as num?)?.toInt() ?? 0;
        final lb = (b['likes'] as num?)?.toInt() ?? 0;
        if (la != lb) return lb.compareTo(la);
        return ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0);
      });
    final total = tops.length;
    final shown = (!showAll && tops.length > 5) ? tops.sublist(0, 5) : tops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.chat_bubble_outline_rounded, color: accent, size: 20),
            const SizedBox(width: 8),
            Text(items.isEmpty ? 'Comments' : 'Comments (${items.length})',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: inkColor)),
          ],
        ),
        const SizedBox(height: 12),
        if (loading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Loading...', style: TextStyle(color: mutedColor)),
          )
        else if (failed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
                why == 'private' ? 'This profile is private.' : 'Could not load comments.',
                style: TextStyle(color: mutedColor)),
          )
        else ...[
          if (canComment)
            _composer(ctl, null)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                why == 'self'
                    ? 'You can not comment on your own profile.'
                    : why == 'signin'
                        ? 'Log in to comment.'
                        : why == 'link'
                            ? 'Link your Minecraft account to comment (see Settings).'
                            : why == 'email'
                                ? 'Add an e-mail to your account to comment.'
                                : 'You can not comment right now.',
                style: TextStyle(color: mutedColor),
              ),
            ),
          if (msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(msg, style: const TextStyle(color: _red)),
            ),
          if (tops.isEmpty)
            Text('No comments yet.', style: TextStyle(color: mutedColor)),
          for (final c in shown) ...[
            _item(c, false),
            for (final r in items.where((x) => x['parent_id'] == c['id'])) _item(r, true),
            Divider(height: 8, color: lineColor),
          ],
          if (total > 5)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => showAll = !showAll),
                child: Text(showAll ? 'Show top 5 only' : 'Show all $total comments'),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- chat

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.token, required this.nick});

  final String token;
  final String nick;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<Map<String, dynamic>> msgs = [];
  final TextEditingController ctl = TextEditingController();
  Timer? timer;
  int last = 0;
  bool busy = false;
  bool sending = false;
  bool online = false;
  String error = '';

  static const Map<String, String> _errs = {
    'not_friends': 'You can only message friends.',
    'slow_down': 'You are sending too fast.',
    'too_many': 'Too many messages. Wait a little.',
    'not_allowed': 'Please keep it friendly.',
    'no_links': 'Links are not allowed.',
    'banned': 'You can not send messages right now.',
    'email_first': 'Add an e-mail to your account first.',
    'link_first': 'Link your Minecraft account first.',
  };

  @override
  void initState() {
    super.initState();
    pull();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (appInForeground) pull();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    ctl.dispose();
    super.dispose();
  }

  Future<void> pull() async {
    if (busy) return;
    busy = true;
    try {
      final r = await apiCall('GET',
          '/api/app/messages?nick=${Uri.encodeQueryComponent(widget.nick)}&after=$last',
          token: widget.token);
      if (!mounted) return;
      if (r['_status'] == 200) {
        final fresh = _list(r['items']);
        setState(() {
          online = r['online'] == true;
          final gone = (r['deleted'] is List)
              ? (r['deleted'] as List).map((e) => (e as num).toInt()).toSet()
              : <int>{};
          if (gone.isNotEmpty) {
            msgs.removeWhere((x) => gone.contains((x['id'] as num?)?.toInt() ?? -1));
          }
          for (final m in fresh) {
            final id = (m['id'] as num?)?.toInt() ?? 0;
            if (id > 0 && msgs.any((x) => x['id'] == id)) continue;
            msgs.add(m);
            if (id > last) last = id;
          }
        });
      }
    } catch (_) {
      // try again on the next tick
    }
    busy = false;
  }

  String _fmtTime(dynamic v) {
    final ms = (v as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int n) => n < 10 ? '0$n' : '$n';
    final t = '${two(d.hour)}:${two(d.minute)}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return t;
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${mon[d.month - 1]}, $t';
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final id = (m['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    try {
      final r = await apiCall('POST', '/api/app/messages/delete',
          token: widget.token, data: {'id': id});
      if (!mounted) return;
      if (r['_status'] == 200) {
        setState(() => msgs.remove(m));
      } else {
        setState(() => error = 'Could not delete. Try again.');
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Cannot reach the server.');
    }
  }

  void _zoom(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: InteractiveViewer(
            child: Image.network(url, headers: {'Authorization': 'Bearer ${widget.token}'}),
          ),
        ),
      ),
    );
  }

  Future<void> pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200, imageQuality: 75);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      String mime = 'jpeg';
      if (bytes.length > 4 && bytes[0] == 0x89) mime = 'png';
      if (bytes.length > 4 && bytes[0] == 0x52) mime = 'webp';
      final url = 'data:image/$mime;base64,${base64Encode(bytes)}';
      if (url.length > 640000) {
        if (mounted) setState(() => error = 'This photo is too big. Choose a smaller one.');
        return;
      }
      await send(image: url, local: bytes);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not open the photo.');
    }
  }

  void openAttach() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Photo'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  pickPhoto();
                },
              ),
              const SizedBox(height: 6),
              Text('Stickers', style: TextStyle(color: mutedColor, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final n in const ['approved', 'pending', 'denied'])
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          send(text: ':$n:');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.asset('assets/sticker_$n.png', height: 84),
                        ),
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

  Future<void> send({String? text, String? image, Uint8List? local}) async {
    final t = (text ?? ctl.text).trim();
    if (t.isEmpty && image == null) return;
    final fromBox = text == null && image == null;
    // show the message at once; the server answer only replaces it
    final tmp = <String, dynamic>{'id': 0, 'mine': true, 'body': t, 'pending': true, 'local': local};
    setState(() {
      error = '';
      msgs.add(tmp);
      if (fromBox) ctl.clear();
    });
    try {
      final data = <String, dynamic>{'nick': widget.nick, 'body': t};
      if (image != null) data['image'] = image;
      final r = await apiCall('POST', '/api/app/messages/send',
          token: widget.token, data: data);
      if (!mounted) return;
      if (r['_status'] == 200 && r['item'] != null) {
        final m = _m(r['item']);
        setState(() {
          final id = (m['id'] as num?)?.toInt() ?? 0;
          final dup = id > 0 && msgs.any((x) => x['id'] == id);
          if (dup) {
            msgs.remove(tmp);
          } else {
            final i = msgs.indexOf(tmp);
            if (i >= 0) {
              msgs[i] = m;
            } else {
              msgs.add(m);
            }
          }
          if (id > last) last = id;
        });
      } else {
        setState(() {
          msgs.remove(tmp);
          if (fromBox) ctl.text = t;
          error = _errs[(r['error'] ?? '').toString()] ?? 'Could not send. Try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          msgs.remove(tmp);
          if (fromBox) ctl.text = t;
          error = 'Cannot reach the server.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reversed = msgs.reversed.toList();
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () => openProfile(context, widget.token, widget.nick),
          child: Row(
            children: [
              SkinHead(nick: widget.nick, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(online ? 'Online now' : 'Offline',
                        style: TextStyle(
                            fontSize: 12,
                            color: online ? _green : mutedColor,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: reversed.isEmpty
                ? Center(
                    child: Text('No messages yet. Say hi!',
                        style: TextStyle(color: mutedColor)))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: reversed.length,
                    itemBuilder: (ctx, i) {
                      final m = reversed[i];
                      final mine = m['mine'] == true;
                      final imgId = (m['img'] as num?)?.toInt() ?? 0;
                      final localImg = m['local'] is Uint8List ? m['local'] as Uint8List : null;
                      final hasImg = imgId > 0 || localImg != null;
                      final stk = RegExp(r'^:(approved|pending|denied):$').firstMatch((m['body'] ?? '').toString());
                      final imgUrl = '$apiBase/api/app/chat-image?id=$imgId';
                      final canDel = mine && ((m['id'] as num?)?.toInt() ?? 0) > 0;
                      // show the time only on the last message of a run (same sender, same minute)
                      bool showTime = true;
                      if (i > 0) {
                        final nx = reversed[i - 1];
                        final a = ((m['at'] as num?)?.toInt() ?? 0) ~/ 60000;
                        final b = ((nx['at'] as num?)?.toInt() ?? 0) ~/ 60000;
                        if ((nx['mine'] == true) == mine && a == b && a != 0) showTime = false;
                      }
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment:
                              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              padding: stk != null
                                  ? EdgeInsets.zero
                                  : hasImg
                                  ? const EdgeInsets.all(4)
                                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                              constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.78),
                              decoration: stk != null ? null : BoxDecoration(
                                color: mine ? (m['pending'] == true ? accent.withAlpha(170) : accent) : tintGrey,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(mine ? 16 : 4),
                                  bottomRight: Radius.circular(mine ? 4 : 16),
                                ),
                              ),
                              child: stk != null
                                  ? Image.asset('assets/sticker_${stk.group(1)}.png', height: 110)
                                  : hasImg
                                  ? GestureDetector(
                                      onTap: () { if (imgId > 0) _zoom(imgUrl); },
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxHeight: 280, minHeight: 80, minWidth: 80),
                                          child: localImg != null && imgId == 0
                                              ? Image.memory(localImg, fit: BoxFit.cover)
                                              : Image.network(imgUrl,
                                              headers: {'Authorization': 'Bearer ${widget.token}'},
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, st) => const SizedBox(
                                                  width: 80, height: 80, child: Icon(Icons.image_not_supported_outlined))),
                                        ),
                                      ),
                                    )
                                  : Text((m['body'] ?? '').toString(),
                                      style: TextStyle(
                                          color: mine ? Colors.white : inkColor,
                                          fontSize: 17,
                                          height: 1.35)),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showTime)
                                  Text(_fmtTime(m['at']),
                                      style: TextStyle(fontSize: 11, color: mutedColor)),
                                if (canDel)
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    icon: Icon(Icons.more_horiz, color: mutedColor, size: 18),
                                    tooltip: 'Message options',
                                    onSelected: (v) {
                                      if (v == 'delete') _delete(m);
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem<String>(
                                          value: 'delete',
                                          child: Text('Delete', style: TextStyle(color: Color(0xFFE8424F)))),
                                    ],
                                  )
                                else if (showTime)
                                  const SizedBox(height: 28),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(error, style: const TextStyle(color: _red, fontSize: 13)),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: openAttach,
                    tooltip: 'Photo and stickers',
                    icon: Icon(Icons.add_photo_alternate_outlined, color: mutedColor),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: tintGrey,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: lineColor),
                      ),
                      child: TextField(
                        controller: ctl,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 300,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => send(),
                        style: TextStyle(color: inkColor, fontSize: 17),
                        decoration: InputDecoration(
                          hintText: 'Message ${widget.nick}',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: send,
                    style: IconButton.styleFrom(backgroundColor: accent),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- friends

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.token});

  final String token;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> incoming = [];
  List<Map<String, dynamic>> outgoing = [];
  List<Map<String, dynamic>> blocked = [];
  List<Map<String, dynamic>> suggestions = [];
  bool loading = true;
  bool failed = false;
  String msg = '';
  final TextEditingController ctl = TextEditingController();
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (appInForeground) load(quiet: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    ctl.dispose();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    try {
      final r = await apiCall('GET', '/api/app/friends', token: widget.token);
      final s = await apiCall('GET', '/api/app/friends/suggestions', token: widget.token);
      if (!mounted) return;
      if (r['_status'] != 200) {
        if (!quiet) {
          setState(() {
            loading = false;
            failed = true;
          });
        }
        return;
      }
      setState(() {
        friends = _list(r['friends']);
        incoming = _list(r['incoming']);
        outgoing = _list(r['outgoing']);
        blocked = _list(r['blocked']);
        suggestions = s['_status'] == 200 ? _list(s['items']) : <Map<String, dynamic>>[];
        loading = false;
        failed = false;
      });
    } catch (_) {
      if (mounted && !quiet) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  static const Map<String, String> _errs = {
    'no_player': 'No player with this name.',
    'self': 'That is you.',
    'limit': 'Your friends list is full.',
    'too_many': 'Too many requests. Wait a little.',
    'too_many_pending': 'You have too many unanswered requests.',
    'cooldown': 'You can not send a request to this player right now.',
    'you_blocked': 'You blocked this player. Unblock them first.',
    'link_first': 'Link your Minecraft account first (Settings).',
    'email_first': 'Add an e-mail to your account first.',
  };

  Future<bool> act(String path, String nick, {Map<String, dynamic>? extra}) async {
    try {
      final r = await apiCall('POST', path,
          token: widget.token, data: {'nick': nick, ...?extra});
      if (!mounted) return false;
      if (r['_status'] == 200) {
        await load(quiet: true);
        return true;
      }
      setState(() => msg = _errs[(r['error'] ?? '').toString()] ?? 'Something went wrong. Try again later.');
    } catch (_) {
      if (mounted) setState(() => msg = 'Cannot reach the server.');
    }
    return false;
  }

  Future<void> addFriend(String nick) async {
    final n = nick.trim();
    if (n.isEmpty) return;
    setState(() => msg = '');
    final ok = await act('/api/app/friends/request', n);
    if (ok && mounted) {
      ctl.clear();
      setState(() => msg = 'Request sent to $n.');
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: mutedColor)),
      );

  Widget _group(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: softShadow(),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: lineColor),
              rows[i],
            ],
          ],
        ),
      );

  Widget _row(String nick,
      {String? sub, bool? online, bool verified = false, int unread = 0, List<Widget> actions = const [], VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Row(
          children: [
            SkinHead(nick: nick, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(nick,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, color: inkColor)),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14),
                      ],
                    ],
                  ),
                  if (sub != null)
                    Row(
                      children: [
                        if (online != null)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: online ? _green : mutedColor,
                            ),
                          ),
                        Flexible(
                          child: Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: mutedColor, fontSize: 12.5)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$unread',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            if (actions.length == 1) ...actions,
          ],
        ),
            if (actions.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 46, top: 8),
                child: Wrap(spacing: 0, runSpacing: 6, children: actions),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, VoidCallback onTap, {bool red = false}) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: red ? _red : accent,
            side: BorderSide(color: red ? _red : accent),
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('Friends')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
              ? Center(child: Text('Could not load friends.', style: TextStyle(color: mutedColor)))
              : RefreshIndicator(
                  onRefresh: () => load(),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                        18, 4, 18, 28 + MediaQuery.of(context).padding.bottom),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      _label('Add a friend'),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: softShadow(),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ctl,
                                maxLength: 24,
                                autocorrect: false,
                                textInputAction: TextInputAction.send,
                                onSubmitted: addFriend,
                                style: TextStyle(color: inkColor),
                                decoration: const InputDecoration(
                                    hintText: 'Nickname',
                                    border: InputBorder.none,
                                    counterText: ''),
                              ),
                            ),
                            FilledButton(
                              onPressed: () => addFriend(ctl.text),
                              style: FilledButton.styleFrom(backgroundColor: accent),
                              child: const Text('Send'),
                            ),
                          ],
                        ),
                      ),
                      if (msg.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                          child: Text(msg, style: TextStyle(color: mutedColor)),
                        ),
                      if (incoming.isNotEmpty) ...[
                        _label('Requests'),
                        _group([
                          for (final f in incoming)
                            _row(
                              (f['nick'] ?? '').toString(),
                              verified: f['verified'] == true,
                              sub: 'Wants to be your friend',
                              onTap: () => openProfile(context, widget.token, (f['nick'] ?? '').toString()),
                              actions: [
                                _pill('Accept', () => act('/api/app/friends/respond', (f['nick'] ?? '').toString(), extra: {'accept': true})),
                                _pill('Decline', () => act('/api/app/friends/respond', (f['nick'] ?? '').toString(), extra: {'accept': false})),
                              ],
                            ),
                        ]),
                      ],
                      _label('Your friends'),
                      if (friends.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                          child: Text('No friends yet. Add a friend by nickname above, or pick someone below.',
                              style: TextStyle(color: mutedColor)),
                        )
                      else
                        _group([
                          for (final f in friends)
                            _row(
                              (f['nick'] ?? '').toString(),
                              verified: f['verified'] == true,
                              online: f['online'] == true,
                              sub: f['online'] == true
                                  ? '${f['rank'] ?? ''} · Online now'
                                  : '${f['rank'] ?? ''} · Last seen ${_ago((f['last_online'] as num?)?.toInt() ?? 0)}',
                              unread: (f['unread'] as num?)?.toInt() ?? 0,
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (_) => ChatPage(token: widget.token, nick: (f['nick'] ?? '').toString())));
                                load(quiet: true);
                              },
                              actions: [
                                PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert_rounded, color: mutedColor),
                                  onSelected: (v) async {
                                    final n = (f['nick'] ?? '').toString();
                                    if (v == 'profile') {
                                      openProfile(context, widget.token, n);
                                    } else if (v == 'remove') {
                                      await act('/api/app/friends/remove', n);
                                    } else if (v == 'block') {
                                      await act('/api/app/friends/block', n);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'profile', child: Text('View profile')),
                                    PopupMenuItem(value: 'remove', child: Text('Remove friend')),
                                    PopupMenuItem(value: 'block', child: Text('Block')),
                                  ],
                                ),
                              ],
                            ),
                        ]),
                      if (outgoing.isNotEmpty) ...[
                        _label('Sent requests'),
                        _group([
                          for (final f in outgoing)
                            _row((f['nick'] ?? '').toString(),
                                sub: 'Request sent',
                                onTap: () => openProfile(context, widget.token, (f['nick'] ?? '').toString()),
                                actions: [
                                  _pill('Cancel', () => act('/api/app/friends/remove', (f['nick'] ?? '').toString())),
                                ]),
                        ]),
                      ],
                      if (suggestions.isNotEmpty) ...[
                        _label('People you may know'),
                        _group([
                          for (final f in suggestions)
                            _row((f['nick'] ?? '').toString(),
                                verified: f['verified'] == true,
                                sub: ((f['rank'] ?? '').toString().isEmpty ? 'Member' : f['rank'].toString()) +
                                    (((f['mutual'] as num?)?.toInt() ?? 0) > 0
                                        ? ' · ${f['mutual']} mutual friend${f['mutual'] == 1 ? '' : 's'}'
                                        : ''),
                                onTap: () => openProfile(context, widget.token, (f['nick'] ?? '').toString()),
                                actions: [
                                  _pill('Add', () => addFriend((f['nick'] ?? '').toString())),
                                ]),
                        ]),
                      ],
                      if (blocked.isNotEmpty) ...[
                        _label('Blocked'),
                        _group([
                          for (final f in blocked)
                            _row((f['nick'] ?? '').toString(),
                                sub: 'Blocked',
                                actions: [
                                  _pill('Unblock', () => act('/api/app/friends/unblock', (f['nick'] ?? '').toString())),
                                ]),
                        ]),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------- profile

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.token, required this.nick});

  final String token;
  final String nick;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? d;
  bool loading = true;
  bool failed = false;
  String msg = '';
  late final AnimationController anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    anim.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await apiCall('GET', '/api/profile?nick=${Uri.encodeQueryComponent(widget.nick)}',
          token: widget.token);
      if (!mounted) return;
      setState(() {
        loading = false;
        failed = r['_status'] != 200;
        d = r;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<void> relation(String path, {Map<String, dynamic>? extra}) async {
    setState(() => msg = '');
    try {
      final r = await apiCall('POST', path,
          token: widget.token, data: {'nick': widget.nick, ...?extra});
      if (!mounted) return;
      if (r['_status'] == 200) {
        await load();
      } else {
        setState(() => msg = (r['error'] ?? '').toString() == 'cooldown'
            ? 'You can not send a request to this player right now.'
            : (r['error'] ?? '').toString() == 'link_first'
                ? 'Link your Minecraft account first (Settings).'
                : 'Something went wrong. Try again later.');
      }
    } catch (_) {
      if (mounted) setState(() => msg = 'Cannot reach the server.');
    }
  }

  Future<void> vote(int v) async {
    final p = d;
    if (p == null) return;
    final my = (p['my_vote'] as num?)?.toInt() ?? 0;
    final nv = my == v ? 0 : v;
    final up = (p['up'] as num?)?.toInt() ?? 0;
    final down = (p['down'] as num?)?.toInt() ?? 0;
    setState(() {
      p['up'] = up - (my > 0 ? 1 : 0) + (nv > 0 ? 1 : 0);
      p['down'] = down - (my < 0 ? 1 : 0) + (nv < 0 ? 1 : 0);
      p['my_vote'] = nv;
    });
    try {
      final r = await apiCall('POST', '/api/app/profile-vote',
          token: widget.token, data: {'nick': widget.nick, 'vote': nv});
      if (!mounted) return;
      if (r['_status'] == 200) {
        setState(() {
          p['up'] = (r['up'] as num?)?.toInt() ?? 0;
          p['down'] = (r['down'] as num?)?.toInt() ?? 0;
          p['my_vote'] = (r['my_vote'] as num?)?.toInt() ?? 0;
        });
      } else {
        setState(() {
          p['up'] = up;
          p['down'] = down;
          p['my_vote'] = my;
        });
        _toast(context, 'Link your Minecraft account and add an e-mail to rate profiles.');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          p['up'] = up;
          p['down'] = down;
          p['my_vote'] = my;
        });
      }
    }
  }

  Widget _card(Map<String, dynamic> p) {
    final t = _m(p['theme']);
    final cs = (t['colors'] is List ? (t['colors'] as List) : const <dynamic>[]);
    final c0 = _hex(cs.isNotEmpty ? cs[0] : null, accentLight);
    final c1 = _hex(cs.length > 1 ? cs[1] : null, accent);
    final c2 = _hex(cs.length > 2 ? cs[2] : null, accentDark);
    final animated = t['anim'] == true;
    final tex = (t['tex'] ?? '').toString();
    final shade = (t['shade'] as num?)?.toDouble() ?? 0;
    return AnimatedBuilder(
      animation: anim,
      builder: (ctx, child) => Container(
        height: 168,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          image: tex.isEmpty
              ? null
              : DecorationImage(
                  image: AssetImage('assets/tex_$tex.png'),
                  repeat: ImageRepeat.repeat,
                  scale: 0.25,
                  alignment: Alignment.topLeft,
                  filterQuality: FilterQuality.none,
                  colorFilter: shade > 0
                      ? ColorFilter.mode(Color.fromARGB((shade * 255).round(), 0, 0, 0), BlendMode.srcOver)
                      : null,
                ),
          gradient: tex.isNotEmpty
              ? null
              : animated
              ? LinearGradient(
                  colors: [c0, c1, c2, c1, c0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  tileMode: TileMode.repeated,
                  transform: _Slide(anim.value),
                )
              : LinearGradient(
                  colors: [c0, c1, c2],
                  stops: const [0, 0.55, 1],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          boxShadow: [
            BoxShadow(color: c1.withAlpha(97), blurRadius: 36, offset: const Offset(0, 18)),
          ],
        ),
        child: tex.isEmpty
            ? child
            : ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: PixelShine(anim, _hex(t['spark'], const Color(0xFFBBFFFF)))),
                      ),
                    ),
                    child!,
                  ],
                ),
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.asset('assets/logo.png', width: 32, height: 32),
                ),
                const SizedBox(width: 8),
                const Text('MVP',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        fontSize: 14)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x38FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text((p['rank'] ?? '').toString(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SkinHead(nick: (p['nick'] ?? '').toString(), size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PLAYER',
                          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 10, letterSpacing: 2)),
                      Row(
                        children: [
                          Flexible(
                            child: Text((p['nick'] ?? '').toString().toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          ),
                          if (p['verified'] == true) ...[
                            const SizedBox(width: 5),
                            const VerifiedBadge(size: 16),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('SINCE',
                        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 10, letterSpacing: 2)),
                    Text((p['since'] ?? '').toString(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(Widget icon, String value, String label, {String? sub}) => Expanded(
        child: Container(
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
                width: 34,
                height: 34,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: tintBlue, borderRadius: BorderRadius.circular(11)),
                child: icon,
              ),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: inkColor)),
              Text(label, style: TextStyle(color: mutedColor, fontSize: 11)),
              if (sub != null)
                Text(sub,
                    style: const TextStyle(
                        color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      );

  void _showMedal(Map<String, dynamic> m) {
    final medal = Medal.fromJson(m);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: medal.color.withAlpha(40),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: PixelIcon(medal.icon, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medal.name,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: inkColor)),
                    if (medal.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(medal.description, style: TextStyle(color: inkColor, height: 1.4)),
                      ),
                    if (medal.dateText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(medal.dateText, style: TextStyle(color: mutedColor, fontSize: 12)),
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

  Widget _actions(Map<String, dynamic> p) {
    final rel = (p['relation'] ?? 'none').toString();
    final children = <Widget>[];
    if (rel == 'friend') {
      children.add(FilledButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ChatPage(token: widget.token, nick: widget.nick))),
        style: FilledButton.styleFrom(backgroundColor: accent),
        icon: const Icon(Icons.chat_bubble_rounded, size: 18),
        label: const Text('Message'),
      ));
      children.add(OutlinedButton(
        onPressed: () => relation('/api/app/friends/remove'),
        child: const Text('Remove friend'),
      ));
    } else if (rel == 'none') {
      children.add(FilledButton.icon(
        onPressed: () => relation('/api/app/friends/request'),
        style: FilledButton.styleFrom(backgroundColor: accent),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
        label: const Text('Add to friends'),
      ));
    } else if (rel == 'pending_out') {
      children.add(const OutlinedButton(onPressed: null, child: Text('Request sent')));
      children.add(OutlinedButton(
        onPressed: () => relation('/api/app/friends/remove'),
        child: const Text('Cancel'),
      ));
    } else if (rel == 'pending_in') {
      children.add(FilledButton(
        onPressed: () => relation('/api/app/friends/respond', extra: {'accept': true}),
        style: FilledButton.styleFrom(backgroundColor: accent),
        child: const Text('Accept request'),
      ));
      children.add(OutlinedButton(
        onPressed: () => relation('/api/app/friends/respond', extra: {'accept': false}),
        child: const Text('Decline'),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 10, runSpacing: 8, children: children);
  }

  Widget _rating(Map<String, dynamic> p) {
    final self = (p['relation'] ?? '') == 'self';
    final my = (p['my_vote'] as num?)?.toInt() ?? 0;
    Widget btn(IconData icon, int n, bool on, Color color, VoidCallback? tap) => OutlinedButton.icon(
          onPressed: tap,
          style: OutlinedButton.styleFrom(
            foregroundColor: on ? color : mutedColor,
            side: BorderSide(color: on ? color : lineColor),
          ),
          icon: Icon(icon, size: 18),
          label: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    return Row(
      children: [
        btn(Icons.thumb_up_alt_rounded, (p['up'] as num?)?.toInt() ?? 0, my > 0, _green,
            self ? null : () => vote(1)),
        const SizedBox(width: 10),
        btn(Icons.thumb_down_alt_rounded, (p['down'] as num?)?.toInt() ?? 0, my < 0, _red,
            self ? null : () => vote(-1)),
        if (self) ...[
          const SizedBox(width: 12),
          Text('Your rating', style: TextStyle(color: mutedColor)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = d;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: Text(widget.nick)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (failed || p == null)
              ? Center(child: Text('Could not load this profile.', style: TextStyle(color: mutedColor)))
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      20, 6, 20, 30 + MediaQuery.of(context).padding.bottom),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (p['private'] == true) ...[
                      Text('This profile is private.',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: inkColor)),
                      const SizedBox(height: 6),
                      Text('Only friends can see it.', style: TextStyle(color: mutedColor)),
                      const SizedBox(height: 16),
                      _actions(p),
                    ] else ...[
                      _card(p),
                      const SizedBox(height: 10),
                      if (p['online'] != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                          child: Row(
                            children: [
                              Container(
                                width: 9,
                                height: 9,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: p['online'] == true ? _green : mutedColor,
                                ),
                              ),
                              Text(
                                p['online'] == true
                                    ? 'Online now'
                                    : 'Last seen ${_ago((p['last_online'] as num?)?.toInt() ?? 0)}',
                                style: TextStyle(color: mutedColor),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (p['coins'] != null) ...[
                            _stat(Image.asset('assets/coin.png'), '${(p['coins'] as num?)?.toInt() ?? 0}', 'Coins'),
                            const SizedBox(width: 10),
                          ],
                          _stat(Image.asset('assets/sword.png'), '${(p['kills'] as num?)?.toInt() ?? 0}', 'Kills',
                              sub: ((p['kills_rank'] as num?)?.toInt() ?? 0) > 0
                                  ? 'TOP #${p['kills_rank']}'
                                  : null),
                          const SizedBox(width: 10),
                          _stat(const _Skull(), '${(p['deaths'] as num?)?.toInt() ?? 0}', 'Deaths'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_list(p['medals']).isNotEmpty) ...[
                        Text('Badges',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800, color: inkColor)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in _list(p['medals']))
                              GestureDetector(
                                onTap: () => _showMedal(m),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _hex(m['color'], accent).withAlpha(40),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _hex(m['color'], accent).withAlpha(140)),
                                  ),
                                  child: PixelIcon(
                                      kMedalIcons.containsKey((m['icon'] ?? '').toString())
                                          ? (m['icon'] ?? '').toString()
                                          : 'medal',
                                      size: 32),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      _actions(p),
                      if (msg.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(msg, style: const TextStyle(color: _red)),
                        ),
                      const SizedBox(height: 14),
                      _rating(p),
                      const SizedBox(height: 26),
                      SxComments(token: widget.token, profile: widget.nick),
                    ],
                  ],
                ),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t, bounds.height * t, 0);
}


class _Skull extends StatelessWidget {
  const _Skull();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _SkullPainter());
}

class _SkullPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final paint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset o(double x, double y) => Offset(x * k, y * k);
    final path = Path()
      ..moveTo(12 * k, 3 * k)
      ..cubicTo(7.6 * k, 3 * k, 4 * k, 6.2 * k, 4 * k, 10.5 * k)
      ..cubicTo(4 * k, 12.9 * k, 5.1 * k, 14.7 * k, 7 * k, 15.9 * k)
      ..lineTo(7 * k, 19 * k)
      ..lineTo(17 * k, 19 * k)
      ..lineTo(17 * k, 15.9 * k)
      ..cubicTo(18.9 * k, 14.7 * k, 20 * k, 12.9 * k, 20 * k, 10.5 * k)
      ..cubicTo(20 * k, 6.2 * k, 16.4 * k, 3 * k, 12 * k, 3 * k)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(o(9, 11), 1.3 * k, paint);
    canvas.drawCircle(o(15, 11), 1.3 * k, paint);
    canvas.drawLine(o(10, 19), o(10, 17), paint);
    canvas.drawLine(o(14, 19), o(14, 17), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Privacy switches: public profile, coins, online status, suggestions.
class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key, required this.token});

  final String token;

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  Map<String, dynamic>? me;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await apiCall('GET', '/api/app/me', token: widget.token);
      if (!mounted) return;
      setState(() {
        me = r;
        failed = r['_status'] != 200;
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> flip(String route, String field, bool shown) async {
    final m = me;
    if (m == null) return;
    final hidden = !shown;
    final was = m[field];
    setState(() => m[field] = hidden);
    try {
      final r = await apiCall('POST', route, token: widget.token, data: {'on': hidden});
      if (r['_status'] != 200 && mounted) {
        setState(() => m[field] = was);
        _toast(context, 'Could not save. Try again later.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => m[field] = was);
        _toast(context, 'Cannot reach the server.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = me;
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('Privacy')),
      body: m == null
          ? Center(
              child: failed
                  ? Text('Could not load.', style: TextStyle(color: mutedColor))
                  : const CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                  18, 8, 18, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: softShadow(),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Show when I am online'),
                        subtitle: const Text('Turn off to look offline to others.'),
                        value: m['hide_online'] != true,
                        onChanged: (v) => flip('/api/app/hide-online', 'hide_online', v),
                      ),
                      Divider(height: 1, color: lineColor),
                      SwitchListTile(
                        title: const Text('Show MVP coins in my public profile'),
                        value: m['hide_coins'] != true,
                        onChanged: (v) => flip('/api/app/hide-coins', 'hide_coins', v),
                      ),
                      Divider(height: 1, color: lineColor),
                      SwitchListTile(
                        title: const Text('Show me in People you may know'),
                        value: m['hide_suggest'] != true,
                        onChanged: (v) => flip('/api/app/hide-suggest', 'hide_suggest', v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
