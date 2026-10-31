// Draws the app icon and writes every platform's icon files.
//
// Run from the project root after changing the design:
//
//   dart run tool/generate_icon.dart
//
// The icon shows two columns of text, the source and the translation, with
// stepping stones joining each pair of lines across a river: a ford.
//
// Coordinates use Android's 108-unit adaptive icon canvas. Launchers show at
// least the middle 72 units, and everything except the river stays within the
// 66-unit circle they never crop.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _background = 0xFF303F9F;
const _river = 0xFF5C6BC0;
const _text = 0xFFFFFFFF;
const _stone = 0xFFFFC107;

const _androidRes = 'android/app/src/main/res';

void main() {
  final foreground = _riverShapes() + _rowShapes();
  final monochrome = _rowShapes();

  const androidSizes = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  androidSizes.forEach((density, size) {
    _write(
      '$_androidRes/mipmap-$density/ic_launcher.png',
      _encodePng(_renderSquareIcon(foreground, size)),
    );
  });

  _writeText(
    '$_androidRes/drawable/ic_launcher_foreground.xml',
    _vectorDrawable(foreground),
  );
  _writeText(
    '$_androidRes/drawable/ic_launcher_monochrome.xml',
    _vectorDrawable([
      for (final shape in monochrome) _Shape(shape.path, _text),
    ]),
  );
  _writeText(
    '$_androidRes/values/ic_launcher_background.xml',
    '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">${_hex(_background)}</color>\n'
        '</resources>\n',
  );
  _writeText(
    '$_androidRes/mipmap-anydpi-v26/ic_launcher.xml',
    '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android='
        '"http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n',
  );

  _write(
    'windows/runner/resources/app_icon.ico',
    _encodeIco([
      for (final size in [16, 24, 32, 48, 64, 256])
        _renderSquareIcon(foreground, size),
    ]),
  );
  _write(
    'linux/runner/resources/app_icon.png',
    _encodePng(_renderSquareIcon(foreground, 256)),
  );
  _writeText('assets/icon/app_icon.svg', _svg(foreground));
}

// --- Design ---

const _riverWidth = 14.0;
const _riverSwing = 8.0;
const _rowYs = [38.0, 54.0, 70.0];
const _rowHeight = 7.0;
const _stoneRadius = 4.5;
const _textLeft = 27.0;
const _textRight = 81.0;
const _stoneGap = 1.5;

double _riverCenter(double y) =>
    54 + _riverSwing * math.sin(2 * math.pi * (y - 54) / 108);

double _riverSlope(double y) =>
    _riverSwing * (2 * math.pi / 108) * math.cos(2 * math.pi * (y - 54) / 108);

List<_Shape> _riverShapes() {
  // Runs past the top and bottom of the canvas, following a sine wave drawn
  // as Hermite cubics.
  const top = -6.0;
  const bottom = 114.0;
  const steps = 10;
  const step = (bottom - top) / steps;
  final path = _Path();

  void edge(double offset, {required bool down}) {
    for (var i = 0; i < steps; i++) {
      final y0 = down ? top + i * step : bottom - i * step;
      final y1 = down ? y0 + step : y0 - step;
      final dy = (y1 - y0) / 3;
      path.cubicTo(
        _riverCenter(y0) + offset + _riverSlope(y0) * dy,
        y0 + dy,
        _riverCenter(y1) + offset - _riverSlope(y1) * dy,
        y1 - dy,
        _riverCenter(y1) + offset,
        y1,
      );
    }
  }

  path.moveTo(_riverCenter(top) - _riverWidth / 2, top);
  edge(-_riverWidth / 2, down: true);
  path.lineTo(_riverCenter(bottom) + _riverWidth / 2, bottom);
  edge(_riverWidth / 2, down: false);
  path.close();
  return [_Shape(path, _river)];
}

List<_Shape> _rowShapes() {
  final shapes = <_Shape>[];
  for (final y in _rowYs) {
    final center = _riverCenter(y);
    final reach = _riverWidth / 2 + _stoneGap;
    shapes.add(_Shape(_Path.capsule(_textLeft, center - reach, y), _text));
    shapes.add(_Shape(_Path.capsule(center + reach, _textRight, y), _text));
    shapes.add(_Shape(_Path.circle(center, y, _stoneRadius), _stone));
  }
  return shapes;
}

// --- Paths ---

class _Shape {
  const _Shape(this.path, this.color);
  final _Path path;
  final int color;
}

class _Path {
  _Path();

  /// A horizontal bar with round ends, spanning [x0] to [x1] on row [y].
  factory _Path.capsule(double x0, double x1, double y) {
    const r = _rowHeight / 2;
    const k = r * _arcHandle;
    return _Path()
      ..moveTo(x0 + r, y - r)
      ..lineTo(x1 - r, y - r)
      ..cubicTo(x1 - r + k, y - r, x1, y - k, x1, y)
      ..cubicTo(x1, y + k, x1 - r + k, y + r, x1 - r, y + r)
      ..lineTo(x0 + r, y + r)
      ..cubicTo(x0 + r - k, y + r, x0, y + k, x0, y)
      ..cubicTo(x0, y - k, x0 + r - k, y - r, x0 + r, y - r)
      ..close();
  }

  factory _Path.circle(double cx, double cy, double r) {
    final k = r * _arcHandle;
    return _Path()
      ..moveTo(cx, cy - r)
      ..cubicTo(cx + k, cy - r, cx + r, cy - k, cx + r, cy)
      ..cubicTo(cx + r, cy + k, cx + k, cy + r, cx, cy + r)
      ..cubicTo(cx - k, cy + r, cx - r, cy + k, cx - r, cy)
      ..cubicTo(cx - r, cy - k, cx - k, cy - r, cx, cy - r)
      ..close();
  }

  /// A square with corners of radius [r].
  factory _Path.roundedSquare(double x0, double x1, double r) {
    final k = r * _arcHandle;
    return _Path()
      ..moveTo(x0 + r, x0)
      ..lineTo(x1 - r, x0)
      ..cubicTo(x1 - r + k, x0, x1, x0 + r - k, x1, x0 + r)
      ..lineTo(x1, x1 - r)
      ..cubicTo(x1, x1 - r + k, x1 - r + k, x1, x1 - r, x1)
      ..lineTo(x0 + r, x1)
      ..cubicTo(x0 + r - k, x1, x0, x1 - r + k, x0, x1 - r)
      ..lineTo(x0, x0 + r)
      ..cubicTo(x0, x0 + r - k, x0 + r - k, x0, x0 + r, x0)
      ..close();
  }

  static const _arcHandle = 0.5523;

  final _data = StringBuffer();
  final _points = <math.Point<double>>[];

  /// The path in the syntax SVG and Android vector drawables share.
  String get data => _data.toString().trim();

  void moveTo(double x, double y) {
    _data.write('M${_n(x)} ${_n(y)} ');
    _points.add(math.Point(x, y));
  }

  void lineTo(double x, double y) {
    _data.write('L${_n(x)} ${_n(y)} ');
    _points.add(math.Point(x, y));
  }

  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _data.write(
      'C${_n(x1)} ${_n(y1)} ${_n(x2)} ${_n(y2)} ${_n(x3)} ${_n(y3)} ',
    );
    final start = _points.last;
    const segments = 16;
    for (var i = 1; i <= segments; i++) {
      final t = i / segments;
      final u = 1 - t;
      final a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
      _points.add(
        math.Point(
          a * start.x + b * x1 + c * x2 + d * x3,
          a * start.y + b * y1 + c * y2 + d * y3,
        ),
      );
    }
  }

  void close() => _data.write('Z');

  static String _n(double v) {
    final text = v.toStringAsFixed(3);
    return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
  }
}

// --- Rasterizing ---

/// RGBA pixels, not premultiplied.
class _Image {
  _Image(this.size) : rgba = Float64List(size * size * 4);
  final int size;
  final Float64List rgba;

  void fill(int color) {
    for (var i = 0; i < size * size; i++) {
      rgba[i * 4] = _channel(color, 16);
      rgba[i * 4 + 1] = _channel(color, 8);
      rgba[i * 4 + 2] = _channel(color, 0);
      rgba[i * 4 + 3] = 1;
    }
  }

  void paint(_Path path, int color, double scale, double offset) {
    final coverage = _coverage(path, size, scale, offset);
    final r = _channel(color, 16);
    final g = _channel(color, 8);
    final b = _channel(color, 0);
    for (var i = 0; i < coverage.length; i++) {
      final c = coverage[i];
      rgba[i * 4] += (r - rgba[i * 4]) * c;
      rgba[i * 4 + 1] += (g - rgba[i * 4 + 1]) * c;
      rgba[i * 4 + 2] += (b - rgba[i * 4 + 2]) * c;
    }
  }

  void mask(Float64List coverage) {
    for (var i = 0; i < coverage.length; i++) {
      rgba[i * 4 + 3] *= coverage[i];
    }
  }

  Uint8List toBytes() {
    final bytes = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i++) {
      bytes[i] = (rgba[i].clamp(0.0, 1.0) * 255).round();
    }
    return bytes;
  }

  static double _channel(int color, int shift) =>
      ((color >> shift) & 0xFF) / 255;
}

/// How much of each pixel the closed polygon covers, from sub-scanlines with
/// exact horizontal coverage.
Float64List _coverage(_Path path, int size, double scale, double offset) {
  const subRows = 16;
  final out = Float64List(size * size);
  final points = [
    for (final p in path._points)
      math.Point(p.x * scale + offset, p.y * scale + offset),
  ];
  final crossings = <double>[];
  for (var row = 0; row < size * subRows; row++) {
    final y = (row + 0.5) / subRows;
    crossings.clear();
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      if ((a.y <= y) != (b.y <= y)) {
        crossings.add(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
      }
    }
    crossings.sort();
    final base = (row ~/ subRows) * size;
    for (var i = 0; i + 1 < crossings.length; i += 2) {
      final x0 = crossings[i].clamp(0.0, size.toDouble());
      final x1 = crossings[i + 1].clamp(0.0, size.toDouble());
      final last = math.min(x1.floor(), size - 1);
      for (var x = x0.floor(); x <= last; x++) {
        final span = math.min(x1, x + 1.0) - math.max(x0, x.toDouble());
        if (span > 0) out[base + x] += span / subRows;
      }
    }
  }
  return out;
}

/// The icon as a rounded square, for places that don't apply their own mask.
_Image _renderSquareIcon(List<_Shape> shapes, int size) {
  const canvas = 108.0;
  const shown = 72.0;
  final image = _Image(size)..fill(_background);
  final scale = size / shown;
  final offset = -(canvas - shown) / 2 * scale;
  for (final shape in shapes) {
    image.paint(shape.path, shape.color, scale, offset);
  }
  image.mask(
    _coverage(
      _Path.roundedSquare(0, size.toDouble(), size * _cornerRatio),
      size,
      1,
      0,
    ),
  );
  return image;
}

const _cornerRatio = 0.22;

// --- File formats ---

Uint8List _encodePng(_Image image) {
  final size = image.size;
  final bytes = image.toBytes();
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < size; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(bytes, y * size * 4, (y + 1) * size * 4));
  }
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typed = [...type.codeUnits, ...data];
    out
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(typed)
      ..add((ByteData(4)..setUint32(0, _crc32(typed))).buffer.asUint8List());
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

int _crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = crc.isOdd ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// PNG for the 256px entry, as is usual, and uncompressed bitmaps for the rest,
/// which every Windows icon reader understands.
Uint8List _encodeIco(List<_Image> images) {
  final entries = [
    for (final image in images)
      image.size >= 256 ? _encodePng(image) : _encodeIcoBitmap(image),
  ];
  final directory = ByteData(6 + 16 * images.length)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  var dataOffset = directory.lengthInBytes;
  for (var i = 0; i < images.length; i++) {
    final at = 6 + 16 * i;
    final size = images[i].size;
    directory
      ..setUint8(at, size >= 256 ? 0 : size)
      ..setUint8(at + 1, size >= 256 ? 0 : size)
      ..setUint16(at + 4, 1, Endian.little)
      ..setUint16(at + 6, 32, Endian.little)
      ..setUint32(at + 8, entries[i].length, Endian.little)
      ..setUint32(at + 12, dataOffset, Endian.little);
    dataOffset += entries[i].length;
  }
  final out = BytesBuilder(copy: false)..add(directory.buffer.asUint8List());
  entries.forEach(out.add);
  return out.takeBytes();
}

Uint8List _encodeIcoBitmap(_Image image) {
  final size = image.size;
  final rgba = image.toBytes();
  final maskStride = ((size + 31) ~/ 32) * 4;
  final out = ByteData(40 + size * size * 4 + maskStride * size)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, size, Endian.little)
    ..setInt32(8, size * 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little);
  var at = 40;
  for (var y = size - 1; y >= 0; y--) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      out
        ..setUint8(at++, rgba[i + 2])
        ..setUint8(at++, rgba[i + 1])
        ..setUint8(at++, rgba[i])
        ..setUint8(at++, rgba[i + 3]);
    }
  }
  // The AND mask stays zero: the alpha channel already says what shows.
  return out.buffer.asUint8List();
}

String _vectorDrawable(List<_Shape> shapes) {
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<!-- Generated by tool/generate_icon.dart. -->')
    ..writeln(
      '<vector xmlns:android="http://schemas.android.com/apk/res/android"',
    )
    ..writeln('    android:width="108dp"')
    ..writeln('    android:height="108dp"')
    ..writeln('    android:viewportWidth="108"')
    ..writeln('    android:viewportHeight="108">');
  for (final shape in shapes) {
    out
      ..writeln('    <path')
      ..writeln('        android:fillColor="${_hex(shape.color)}"')
      ..writeln('        android:pathData="${shape.path.data}" />');
  }
  out.writeln('</vector>');
  return out.toString();
}

String _svg(List<_Shape> shapes) {
  const r = 72 * _cornerRatio;
  final corners = _Path.roundedSquare(18, 90, r);
  final out = StringBuffer()
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" viewBox="18 18 72 72">')
    ..writeln('  <!-- Generated by tool/generate_icon.dart. -->')
    ..writeln(
      '  <clipPath id="corners"><path d="${corners.data}" /></clipPath>',
    )
    ..writeln('  <g clip-path="url(#corners)">')
    ..writeln(
      '    <rect x="18" y="18" width="72" height="72" '
      'fill="${_hex(_background)}" />',
    );
  for (final shape in shapes) {
    out.writeln(
      '    <path fill="${_hex(shape.color)}" d="${shape.path.data}" />',
    );
  }
  out
    ..writeln('  </g>')
    ..writeln('</svg>');
  return out.toString();
}

String _hex(int color) =>
    '#${(color & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stdout.writeln('wrote $path');
}

void _writeText(String path, String text) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  stdout.writeln('wrote $path');
}
