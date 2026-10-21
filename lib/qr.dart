import 'dart:convert';

import 'package:flutter/material.dart';

/// Tiny QR code generator (byte mode, error correction M, versions 1-6).
class QrData {
  QrData(this.size, this._m);
  final int size;
  final List<List<bool>> _m;
  bool get(int x, int y) => _m[y][x];

  static const _tab = {
    1: [16, 10, 1],
    2: [28, 16, 1],
    3: [44, 26, 1],
    4: [64, 18, 2],
    5: [86, 24, 2],
    6: [108, 16, 4],
  };
  static const _align = {
    1: <int>[],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
  };
  static final List<int> _exp = List<int>.filled(512, 0);
  static final List<int> _log = List<int>.filled(256, 0);
  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _exp[i] = x;
      _log[x] = i;
      x <<= 1;
      if (x & 256 != 0) x ^= 0x11d;
    }
    for (var i = 255; i < 512; i++) {
      _exp[i] = _exp[i - 255];
    }
    _ready = true;
  }

  static int _mul(int a, int b) => (a != 0 && b != 0) ? _exp[_log[a] + _log[b]] : 0;

  static List<int> _rsGen(int n) {
    var g = <int>[1];
    for (var i = 0; i < n; i++) {
      final ng = List<int>.filled(g.length + 1, 0);
      for (var j = 0; j < g.length; j++) {
        ng[j] ^= g[j];
        ng[j + 1] ^= _mul(g[j], _exp[i]);
      }
      g = ng;
    }
    return g;
  }

  static List<int> _rsEc(List<int> data, int n) {
    final g = _rsGen(n);
    final res = List<int>.filled(n, 0, growable: true);
    for (final d in data) {
      final f = d ^ res[0];
      res.removeAt(0);
      res.add(0);
      for (var j = 0; j < n; j++) {
        res[j] ^= _mul(g[j + 1], f);
      }
    }
    return res;
  }

  static bool _bit(int v, int i) => ((v >> i) & 1) != 0;

  static QrData? make(String text) {
    _init();
    final bytes = utf8.encode(text);
    var ver = 0;
    for (var v = 1; v <= 6; v++) {
      if (bytes.length <= _tab[v]![0] - 2) {
        ver = v;
        break;
      }
    }
    if (ver == 0) return null;
    final cap = _tab[ver]![0], ecn = _tab[ver]![1], nb = _tab[ver]![2];
    final size = 17 + 4 * ver;

    final bits = <int>[];
    void put(int val, int len) {
      for (var i = len - 1; i >= 0; i--) {
        bits.add((val >> i) & 1);
      }
    }

    put(4, 4);
    put(bytes.length, 8);
    for (final b in bytes) {
      put(b, 8);
    }
    for (var k = 0; k < 4 && bits.length < cap * 8; k++) {
      bits.add(0);
    }
    while (bits.length % 8 != 0) {
      bits.add(0);
    }
    final cw = <int>[];
    for (var i = 0; i < bits.length; i += 8) {
      var b = 0;
      for (var j = 0; j < 8; j++) {
        b = (b << 1) | bits[i + j];
      }
      cw.add(b);
    }
    var pad = 0xEC;
    while (cw.length < cap) {
      cw.add(pad);
      pad ^= 0xEC ^ 0x11;
    }
    final per = cap ~/ nb;
    final blocks = <List<int>>[], ecs = <List<int>>[];
    for (var i = 0; i < nb; i++) {
      final d = cw.sublist(i * per, (i + 1) * per);
      blocks.add(d);
      ecs.add(_rsEc(d, ecn));
    }
    final all = <int>[];
    for (var i = 0; i < per; i++) {
      for (final d in blocks) {
        all.add(d[i]);
      }
    }
    for (var i = 0; i < ecn; i++) {
      for (final e in ecs) {
        all.add(e[i]);
      }
    }

    final m = List.generate(size, (_) => List<bool>.filled(size, false));
    final fn = List.generate(size, (_) => List<bool>.filled(size, false));
    void setM(int x, int y, bool v) {
      m[y][x] = v;
      fn[y][x] = true;
    }

    for (var i = 0; i < size; i++) {
      setM(6, i, i % 2 == 0);
      setM(i, 6, i % 2 == 0);
    }
    void finder(int cx, int cy) {
      for (var dy = -4; dy <= 4; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          final dist = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
          final xx = cx + dx, yy = cy + dy;
          if (xx >= 0 && xx < size && yy >= 0 && yy < size) {
            setM(xx, yy, dist != 2 && dist != 4);
          }
        }
      }
    }

    finder(3, 3);
    finder(size - 4, 3);
    finder(3, size - 4);
    final ap = _align[ver]!;
    for (var i = 0; i < ap.length; i++) {
      for (var j = 0; j < ap.length; j++) {
        if ((i == 0 && j == 0) ||
            (i == 0 && j == ap.length - 1) ||
            (i == ap.length - 1 && j == 0)) {
          continue;
        }
        for (var dy = -2; dy <= 2; dy++) {
          for (var dx = -2; dx <= 2; dx++) {
            final dist = dx.abs() > dy.abs() ? dx.abs() : dy.abs();
            setM(ap[i] + dx, ap[j] + dy, dist != 1);
          }
        }
      }
    }

    void formatBits(int mask) {
      final data = mask;
      var rem = data;
      for (var q = 0; q < 10; q++) {
        rem = (rem << 1) ^ ((rem >> 9) * 0x537);
      }
      final bts = ((data << 10) | rem) ^ 0x5412;
      for (var q = 0; q <= 5; q++) {
        setM(8, q, _bit(bts, q));
      }
      setM(8, 7, _bit(bts, 6));
      setM(8, 8, _bit(bts, 7));
      setM(7, 8, _bit(bts, 8));
      for (var q = 9; q < 15; q++) {
        setM(14 - q, 8, _bit(bts, q));
      }
      for (var q = 0; q < 8; q++) {
        setM(size - 1 - q, 8, _bit(bts, q));
      }
      for (var q = 8; q < 15; q++) {
        setM(8, size - 15 + q, _bit(bts, q));
      }
      setM(8, size - 8, true);
    }

    formatBits(0);
    var idx = 0;
    for (var right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (var vert = 0; vert < size; vert++) {
        for (var j = 0; j < 2; j++) {
          final x = right - j;
          final up = ((right + 1) & 2) == 0;
          final y = up ? size - 1 - vert : vert;
          if (!fn[y][x] && idx < all.length * 8) {
            m[y][x] = _bit(all[idx >> 3], 7 - (idx & 7));
            idx++;
          }
        }
      }
    }

    void applyMask(int mask) {
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          bool inv;
          switch (mask) {
            case 0:
              inv = (x + y) % 2 == 0;
              break;
            case 1:
              inv = y % 2 == 0;
              break;
            case 2:
              inv = x % 3 == 0;
              break;
            case 3:
              inv = (x + y) % 3 == 0;
              break;
            case 4:
              inv = (x ~/ 3 + y ~/ 2) % 2 == 0;
              break;
            case 5:
              inv = (x * y) % 2 + (x * y) % 3 == 0;
              break;
            case 6:
              inv = ((x * y) % 2 + (x * y) % 3) % 2 == 0;
              break;
            default:
              inv = ((x + y) % 2 + (x * y) % 3) % 2 == 0;
          }
          if (inv && !fn[y][x]) m[y][x] = !m[y][x];
        }
      }
    }

    int penalty() {
      var p = 0;
      void lines(bool Function(int, int) get) {
        for (var a = 0; a < size; a++) {
          var run = 1;
          final line = StringBuffer();
          for (var b = 0; b < size; b++) {
            final c = get(a, b);
            line.write(c ? '1' : '0');
            if (b > 0 && c == get(a, b - 1)) {
              run++;
              if (run == 5) {
                p += 3;
              } else if (run > 5) {
                p++;
              }
            } else {
              run = 1;
            }
          }
          final s = line.toString();
          for (final pat in const ['10111010000', '00001011101']) {
            var from = 0;
            while (true) {
              final at = s.indexOf(pat, from);
              if (at < 0) break;
              p += 40;
              from = at + 1;
            }
          }
        }
      }

      lines((a, b) => m[a][b]);
      lines((a, b) => m[b][a]);
      for (var y = 0; y < size - 1; y++) {
        for (var x = 0; x < size - 1; x++) {
          final c = m[y][x];
          if (c == m[y][x + 1] && c == m[y + 1][x] && c == m[y + 1][x + 1]) p += 3;
        }
      }
      var dark = 0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (m[y][x]) dark++;
        }
      }
      p += (((dark * 20 - size * size * 10).abs() / (size * size)).ceil() - 1) * 10;
      return p;
    }

    var best = 0, bestP = 1 << 30;
    for (var mk = 0; mk < 8; mk++) {
      applyMask(mk);
      formatBits(mk);
      final pp = penalty();
      if (pp < bestP) {
        bestP = pp;
        best = mk;
      }
      applyMask(mk);
    }
    applyMask(best);
    formatBits(best);
    return QrData(size, m);
  }
}

/// White plate with a dark QR code for [data].
class QrPlate extends StatelessWidget {
  const QrPlate({super.key, required this.data, this.size = 84});
  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final q = QrData.make(data);
    if (q == null) return const SizedBox.shrink();
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x59001E3C), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: CustomPaint(painter: _QrPainter(q)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.q);
  final QrData q;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / q.size;
    final paint = Paint()
      ..color = const Color(0xFF0A2A43)
      ..isAntiAlias = false;
    for (var y = 0; y < q.size; y++) {
      for (var x = 0; x < q.size; x++) {
        if (q.get(x, y)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell - 0.2, y * cell - 0.2, cell + 0.4, cell + 0.4),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.q != q;
}
