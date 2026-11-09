// GeoPulse v1.3 - TEFSM groundwater survey viewer (ESP32 over BLE)
// Isolate parsing, LTTB downsampling, OSM map, estimated soil resistivity, dynamic depth
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart'
    show FlutterMap, MapOptions, TileLayer, MarkerLayer, Marker, PolylineLayer, Polyline;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = AppState();
  await app.init();
  runApp(GeoPulseApp(app));
}

// ───────────────────────── TRANSLATIONS ─────────────────────────
String appLang = 'ar';

const Map<String, Map<String, String>> _tr = {
  'ar': {
    'connect': 'الاتصال',
    'files': 'الملفات',
    'map': 'الخريطة',
    'settings': 'الإعدادات',
    'scan_connect': 'بحث واتصال',
    'connected': 'متصل',
    'connect_ok': 'تم الاتصال',
    'disconnect': 'قطع الاتصال',
    'bt_perm': 'مطلوب إذن البلوتوث',
    'get_files': 'جلب قائمة الملفات',
    'no_files': 'لا توجد ملفات بعد',
    'download': 'تحميل',
    'lines_recv': 'تم استلام {n} سطر...',
    'downloaded': 'تم تحميل {n}',
    'import_csv': 'استيراد ملف CSV من الهاتف',
    'imported': 'تم استيراد {n}',
    'need_csv': 'اختر ملفاً بصيغة CSV',
    'read_fail': 'تعذّرت قراءة الملف',
    'saved_files': 'الملفات المحفوظة',
    'import_or_dl': 'استورد أو حمّل ملف CSV',
    'generate_map': 'إنشاء الخريطة',
    'blue_water': 'الأزرق = احتمال وجود ماء',
    'red_dry': 'الأحمر = صخر جاف',
    'site': 'الموقع',
    'firmware': 'التحقق من تحديث البرنامج الثابت',
    'firmware_sub': 'يتحقق الجهاز من إصدار جديد عبر الواي فاي',
    'fw_title': 'البرنامج الثابت',
    'connect_first': 'اتصل بالجهاز أولاً',
    'no_reply': 'لا يوجد رد من الجهاز',
    'language': 'اللغة',
    'smooth': 'تنعيم الخريطة',
    'share_map': 'مشاركة صورة الخريطة',
    'delete': 'حذف',
    'delete_q': 'حذف الملف {n}؟',
    'cancel': 'إلغاء',
    'ok': 'موافق',
    'stats': 'الإحصائيات',
    'min': 'الأدنى',
    'max': 'الأعلى',
    'mean': 'المتوسط',
    'analysis': 'تحليل المواقع',
    'analysis_sub': 'أقل جهد (الأزرق) مؤشر محتمل لوجود مياه',
    'zone_item': 'الموقع {s} عند {f} هرتز (عمق ~{d} {u}): {v} mV',
    'analysis_note': 'نتيجة استرشادية فقط، ولا تغني عن الخبرة الميدانية أو الحفر التجريبي.',
    'tap_hint': 'المس الخريطة لعرض قيمة أي نقطة',
    'picked': 'الموقع {s} • {f} هرتز • {v} mV • عمق ~{d} {u}',
    'no_rows': 'لا توجد بيانات صالحة في الملف',
    'no_uart': 'لم يتم العثور على خدمة UART في الجهاز',
    'no_list': 'لم يرجع الجهاز أي ملفات',
    'timeout': 'انتهت مهلة النقل',
    'version': 'الإصدار',
    'mv_unit': 'mV',
    'soil': 'نوع التربة',
    'soil_clay': 'طين',
    'soil_silt': 'طمي',
    'soil_loam': 'تربة طينية رملية',
    'soil_wetsand': 'رمل رطب',
    'soil_drysand': 'رمل جاف',
    'soil_gravel': 'حصى',
    'soil_limestone': 'حجر جيري',
    'soil_granite': 'صخر صلب (جرانيت/بازلت)',
    'soil_custom': 'قيمة مخصصة',
    'rho_title': 'المقاومية (Ω·m)',
    'depth_note': 'العمق التقريبي = 500 × √(المقاومية ÷ التردد). تُقدَّر المقاومية تلقائياً من تخامد الإشارة، ويمكنك اختيار نوع التربة يدوياً. للدقة عاير على بئر معروفة العمق.',
    'm_unit': 'م',
    'soil_average': 'متوسط',
    'soil_auto': 'تلقائي (مقدّر من الإشارة)',
    'est_soil': 'التربة المقدّرة: {r} Ω·m',
    'manual_used': 'المستخدم في حساب العمق (يدوي): {r} Ω·m',
    'processing': 'جارٍ المعالجة...',
    'view_heat': 'الخريطة الحرارية',
    'view_gps': 'عرض الخريطة',
    'no_maps_key': 'مفتاح Google Maps غير مضاف، لذلك تظهر مواقع النقاط بدون خلفية خريطة.',
    'zoom_hint': 'اقرص بإصبعين للتكبير، واسحب للتحريك',
    'reset_zoom': 'إعادة الضبط',
    'target_title': 'الهدف (أقل جهد)',
    'tab3d': 'مجسم 3D',
    'import_many': 'اختيار عدة ملفات CSV',
    'select_lines': 'اختر ملفات خطوط المسح (ملف لكل خط)',
    'build_3d': 'بناء المجسم ثلاثي الأبعاد',
    'need_files': 'اختر ملفاً واحداً على الأقل',
    'cutoff': 'إظهار الجهد الأقل فقط',
    'opacity': 'الشفافية',
    'pocket': 'أقل جهد (جيب مائي محتمل): الخط {l}، الموقع {s}، {f} هرتز (عمق ~{d} {u})',
    'one_line_warn': 'ملف واحد فقط: يظهر مقطع واحد وليس مجسماً كاملاً',
    'imported_n': 'تم استيراد {n} ملف',
    'hint3d': 'اسحب للتدوير، واقرص بإصبعين للتكبير',
    'no_maps_data': 'الملف لا يحتوي على إحداثيات GPS',
  },
  'en': {
    'connect': 'Connect',
    'files': 'Files',
    'map': 'Map',
    'settings': 'Settings',
    'scan_connect': 'Scan & Connect',
    'connected': 'Connected',
    'connect_ok': 'Connected',
    'disconnect': 'Disconnect',
    'bt_perm': 'Bluetooth permission required',
    'get_files': 'Get file list',
    'no_files': 'No files yet',
    'download': 'Download',
    'lines_recv': '{n} lines received...',
    'downloaded': 'Downloaded {n}',
    'import_csv': 'Import CSV from phone',
    'imported': 'Imported {n}',
    'need_csv': 'Please choose a .csv file',
    'read_fail': 'Could not read the selected file',
    'saved_files': 'Saved files',
    'import_or_dl': 'Import or download a CSV file',
    'generate_map': 'Generate Map',
    'blue_water': 'Blue = Water Potential',
    'red_dry': 'Red = Dry Rock',
    'site': 'Site',
    'firmware': 'Check for Firmware Update',
    'firmware_sub': 'Device checks for a new version over Wi-Fi',
    'fw_title': 'Firmware',
    'connect_first': 'Connect to the device first',
    'no_reply': 'No reply from the device',
    'language': 'Language',
    'smooth': 'Smooth map',
    'share_map': 'Share map image',
    'delete': 'Delete',
    'delete_q': 'Delete file {n}?',
    'cancel': 'Cancel',
    'ok': 'OK',
    'stats': 'Statistics',
    'min': 'Min',
    'max': 'Max',
    'mean': 'Mean',
    'analysis': 'Site analysis',
    'analysis_sub': 'Lowest voltage (blue) is a possible water indicator',
    'zone_item': 'Site {s} at {f} Hz (depth ~{d} {u}): {v} mV',
    'analysis_note': 'Indicative only. It does not replace field experience or test drilling.',
    'tap_hint': 'Tap the map to read any point',
    'picked': 'Site {s} • {f} Hz • {v} mV • depth ~{d} {u}',
    'no_rows': 'No valid data rows in file',
    'no_uart': 'UART service not found on device',
    'no_list': 'The device returned no files',
    'timeout': 'Transfer timed out',
    'version': 'Version',
    'mv_unit': 'mV',
    'soil': 'Soil type',
    'soil_clay': 'Clay',
    'soil_silt': 'Silt',
    'soil_loam': 'Sandy loam',
    'soil_wetsand': 'Wet sand',
    'soil_drysand': 'Dry sand',
    'soil_gravel': 'Gravel',
    'soil_limestone': 'Limestone',
    'soil_granite': 'Hard rock (granite/basalt)',
    'soil_custom': 'Custom value',
    'rho_title': 'Resistivity (Ω·m)',
    'depth_note': 'Approx. depth = 500 × √(resistivity ÷ frequency). Resistivity is estimated automatically from signal attenuation; you can also pick a soil type manually. For accuracy, calibrate on a well of known depth.',
    'm_unit': 'm',
    'soil_average': 'Average',
    'soil_auto': 'Auto (estimated from signal)',
    'est_soil': 'Estimated Soil: {r} Ω·m',
    'manual_used': 'Used for depth (manual): {r} Ω·m',
    'processing': 'Processing...',
    'view_heat': 'Heatmap',
    'view_gps': 'Map view',
    'no_maps_key': 'No Google Maps key configured, so site points are shown without a map background.',
    'zoom_hint': 'Pinch to zoom, drag to pan',
    'reset_zoom': 'Reset',
    'target_title': 'Target (lowest voltage)',
    'tab3d': '3D volume',
    'import_many': 'Select multiple CSV files',
    'select_lines': 'Choose survey line files (one file per line)',
    'build_3d': 'Build 3D volume',
    'need_files': 'Choose at least one file',
    'cutoff': 'Show lowest voltage only',
    'opacity': 'Opacity',
    'pocket': 'Lowest voltage (possible water pocket): line {l}, site {s}, {f} Hz (depth ~{d} {u})',
    'one_line_warn': 'Only one file: a single slice is shown, not a full volume',
    'imported_n': 'Imported {n} files',
    'hint3d': 'Drag to rotate, pinch to zoom',
    'no_maps_data': 'The file has no GPS coordinates',
  },
};

String tr(String k) => _tr[appLang]?[k] ?? _tr['en']![k] ?? k;

String errText(Object e) =>
    e.toString().replaceFirst('Exception: ', '').replaceFirst('TimeoutException: ', '');

// ───────────────────────── BLE SERVICE ─────────────────────────
// ESP32 exposes Nordic UART Service:
//   RX (phone writes) 6e400002-...   TX (phone gets notifications) 6e400003-...
class BleService {
  static final Guid nus = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid rxUuid = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid txUuid = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  BluetoothDevice? device;
  BluetoothCharacteristic? _rx, _tx;
  StreamSubscription<List<int>>? _sub;
  final _lines = StreamController<String>.broadcast();
  String _buf = '';
  int _mtu = 23;

  Stream<String> get lines => _lines.stream;
  bool get connected => device?.isConnected ?? false;

  Future<void> connect(BluetoothDevice d) async {
    await FlutterBluePlus.stopScan();
    await d.connect(timeout: const Duration(seconds: 15));
    device = d;
    if (Platform.isAndroid) {
      try {
        _mtu = await d.requestMtu(247);
      } catch (_) {}
    }
    final services = await d.discoverServices();
    for (final s in services) {
      if (s.uuid != nus) continue;
      for (final c in s.characteristics) {
        if (c.uuid == rxUuid) _rx = c;
        if (c.uuid == txUuid) _tx = c;
      }
    }
    if (_rx == null || _tx == null) {
      await d.disconnect();
      throw Exception(tr('no_uart'));
    }
    await _tx!.setNotifyValue(true);
    await _sub?.cancel();
    _sub = _tx!.onValueReceived.listen(_onData);
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    await device?.disconnect();
  }

  void _onData(List<int> bytes) {
    _buf += utf8.decode(bytes, allowMalformed: true);
    int i;
    while ((i = _buf.indexOf('\n')) >= 0) {
      final line = _buf.substring(0, i).replaceAll('\r', '');
      _buf = _buf.substring(i + 1);
      _lines.add(line);
    }
  }

  Future<void> send(String cmd) async {
    final bytes = utf8.encode(cmd);
    final chunk = math.max(20, _mtu - 3);
    for (var i = 0; i < bytes.length; i += chunk) {
      await _rx!.write(bytes.sublist(i, math.min(i + chunk, bytes.length)));
    }
  }

  /// LIST\n -> file names until END_LIST (8 s timeout)
  Future<List<String>> listFiles() async {
    final names = <String>[];
    final done = Completer<void>();
    final sub = lines.listen((l) {
      final t = l.trim();
      if (t == 'END_LIST') {
        if (!done.isCompleted) done.complete();
      } else if (t.toLowerCase().endsWith('.csv')) {
        names.add(t);
      }
    });
    try {
      await send('LIST\n');
      await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    } finally {
      await sub.cancel();
    }
    return names;
  }

  /// GET name\n -> writes lines to a local file until END_FILE (15 s idle timeout)
  Future<File> download(String name, void Function(int lines) onProgress) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${name.split('/').last}');
    final sink = file.openWrite();
    final done = Completer<void>();
    Timer? idle;
    var n = 0;
    void resetIdle() {
      idle?.cancel();
      idle = Timer(const Duration(seconds: 15), () {
        if (!done.isCompleted) done.completeError(TimeoutException(tr('timeout')));
      });
    }

    final sub = lines.listen((l) {
      if (done.isCompleted) return;
      resetIdle();
      final t = l.trim();
      if (t == 'END_FILE') {
        done.complete();
      } else if (t.startsWith('ERR')) {
        done.completeError(Exception(t));
      } else {
        sink.writeln(l);
        onProgress(++n);
      }
    });
    resetIdle();
    try {
      await send('GET $name\n');
      await done.future;
    } finally {
      idle?.cancel();
      await sub.cancel();
      await sink.flush();
      await sink.close();
    }
    return file;
  }

  Future<String> request(String cmd, {Duration timeout = const Duration(seconds: 20)}) async {
    final reply = lines.first.timeout(timeout);
    await send(cmd);
    return reply;
  }
}

// ───────────────────────── DATA MODEL / PARSER ─────────────────────────
class Zone {
  final int si, fi;
  final double v;
  Zone(this.si, this.fi, this.v);
}

/// Largest-Triangle-Three-Buckets: indices of `target` points of the series
/// (x = index, y = ys[i]) that best preserve its visual shape. First and last are kept.
List<int> lttbIndices(List<double> ys, int target) {
  final n = ys.length;
  if (target >= n || target < 3) return List.generate(n, (i) => i);
  final out = <int>[0];
  final every = (n - 2) / (target - 2);
  var a = 0;
  for (var i = 0; i < target - 2; i++) {
    final avgStart = ((i + 1) * every).floor() + 1;
    var avgEnd = ((i + 2) * every).floor() + 1;
    if (avgEnd > n) avgEnd = n;
    var avgX = 0.0, avgY = 0.0;
    final cnt = avgEnd - avgStart;
    if (cnt > 0) {
      for (var j = avgStart; j < avgEnd; j++) {
        avgX += j;
        avgY += ys[j];
      }
      avgX /= cnt;
      avgY /= cnt;
    } else {
      avgX = (n - 1).toDouble();
      avgY = ys[n - 1];
    }
    final rs = (i * every).floor() + 1;
    final re = ((i + 1) * every).floor() + 1;
    var maxArea = -1.0;
    var next = rs;
    for (var j = rs; j < re && j < n; j++) {
      final area = ((a - avgX) * (ys[j] - ys[a]) - (a - j) * (avgY - ys[a])).abs() * 0.5;
      if (area > maxArea) {
        maxArea = area;
        next = j;
      }
    }
    out.add(next);
    a = next;
  }
  out.add(n - 1);
  return out;
}

class SurveyData {
  final int line;
  final List<int> sites;
  final List<double> freqs; // ascending (row 0 = lowest freq = deepest)
  final List<List<double>> matrix; // matrix[freqIndex][siteIndex] = mV
  final Map<int, List<double>> gps; // site -> [lat, lon] (optional)
  final double min, max, mean;
  final double rho; // estimated soil resistivity (ohm.m) from signal attenuation
  SurveyData(this.line, this.sites, this.freqs, this.matrix, this.gps, this.min, this.max, this.mean, this.rho);

  bool get hasGps => gps.isNotEmpty;

  /// Heuristic: ratio = V_high / V_low (average voltage at highest / lowest frequency),
  /// resistivity = 100 * (1 / ratio), clamped to 10..1000 ohm.m.
  static double estimateRho(List<List<double>> m) {
    if (m.isEmpty) return 100;
    double avg(List<double> r) => r.reduce((a, b) => a + b) / r.length;
    final low = avg(m.first), high = avg(m.last);
    if (high.abs() < 1e-9) return 1000;
    final ratio = high / low; // low == 0 -> infinity -> 10
    if (ratio.abs() < 1e-9) return 1000;
    return (100 * (1 / ratio)).abs().clamp(10.0, 1000.0).toDouble();
  }

  /// Accepts both:  Line,Site,Frequency,Voltage
  ///          and:  Line,Site,Latitude,Longitude,Frequency,Voltage
  static SurveyData parse(String csvText, {int fallbackLine = 1}) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: true)
        .convert(csvText.replaceAll('\r', ''));
    final vals = <String, double>{};
    final siteSet = <int>{};
    final freqSet = <double>{};
    final gps = <int, List<double>>{};
    int? lineNo;
    for (final r in rows) {
      num? line, site, freq, v, lat, lon;
      if (r.length >= 6) {
        line = num.tryParse(r[0].toString());
        site = num.tryParse(r[1].toString());
        lat = num.tryParse(r[2].toString());
        lon = num.tryParse(r[3].toString());
        freq = num.tryParse(r[4].toString());
        v = num.tryParse(r[5].toString());
      } else if (r.length >= 4) {
        line = num.tryParse(r[0].toString());
        site = num.tryParse(r[1].toString());
        freq = num.tryParse(r[2].toString());
        v = num.tryParse(r[3].toString());
      } else {
        continue;
      }
      if (site == null || freq == null || v == null) continue; // header / junk
      if (lineNo == null && line != null) lineNo = line.toInt();
      final s = site.toInt();
      siteSet.add(s);
      freqSet.add(freq.toDouble());
      vals['$s|${freq.toDouble()}'] = v.toDouble();
      if (lat != null && lon != null && lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0)) {
        if (!gps.containsKey(s)) gps[s] = [lat.toDouble(), lon.toDouble()];
      }
    }
    // thrown inside an isolate: keep it a plain code, translated on the UI side
    if (vals.isEmpty) throw const FormatException('no_rows');
    final sites = siteSet.toList()..sort();
    final freqs = freqSet.toList()..sort();
    final m = List.generate(
        freqs.length,
        (fi) => List.generate(
            sites.length, (si) => vals['${sites[si]}|${freqs[fi]}'] ?? double.nan));
    final all = vals.values;
    final mean = all.reduce((a, b) => a + b) / all.length;
    for (final row in m) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].isNaN) row[i] = mean;
      }
    }
    return SurveyData(lineNo ?? fallbackLine, sites, freqs, m, gps, all.reduce(math.min),
        all.reduce(math.max), mean, estimateRho(m));
  }

  /// If rows*cols > maxPoints, keep the rows/columns picked by LTTB (on the mean profiles)
  /// plus the cells of [keep] (the strongest anomalies), so the "shape" of the anomaly survives.
  SurveyData downsample(int maxPoints, {List<Zone> keep = const []}) {
    final rows = freqs.length, cols = sites.length;
    if (rows * cols <= maxPoints) return this;
    final f = math.sqrt(maxPoints / (rows * cols));
    final tCols = math.max(3, (cols * f).round());
    final tRows = math.max(3, (rows * f).round());
    final colProfile = List.generate(cols, (c) {
      var s = 0.0;
      for (var r = 0; r < rows; r++) {
        s += matrix[r][c];
      }
      return s / rows;
    });
    final rowProfile = List.generate(rows, (r) => matrix[r].reduce((a, b) => a + b) / cols);
    final ci = <int>{...lttbIndices(colProfile, tCols), ...keep.map((z) => z.si)}.toList()..sort();
    final ri = <int>{...lttbIndices(rowProfile, tRows), ...keep.map((z) => z.fi)}.toList()..sort();
    final nm = [
      for (final r in ri) [for (final c in ci) matrix[r][c]]
    ];
    return SurveyData(line, [for (final c in ci) sites[c]], [for (final r in ri) freqs[r]], nm, gps, min,
        max, mean, rho);
  }

  /// Lowest-voltage cells that are not neighbours of each other.
  List<Zone> bestZones([int n = 3]) {
    final cells = <Zone>[];
    for (var fi = 0; fi < freqs.length; fi++) {
      for (var si = 0; si < sites.length; si++) {
        cells.add(Zone(si, fi, matrix[fi][si]));
      }
    }
    cells.sort((a, b) => a.v.compareTo(b.v));
    final out = <Zone>[];
    for (final c in cells) {
      if (out.length >= n) break;
      if (out.every((o) => (o.si - c.si).abs() > 1 || (o.fi - c.fi).abs() > 1)) out.add(c);
    }
    return out;
  }

  /// Lowest voltage found at one site (any frequency) and its frequency index.
  Zone siteMin(int si) {
    var best = 0;
    for (var fi = 1; fi < freqs.length; fi++) {
      if (matrix[fi][si] < matrix[best][si]) best = fi;
    }
    return Zone(si, best, matrix[best][si]);
  }
}

// ───────────────────────── SOIL / DEPTH ─────────────────────────
// Typical resistivity (ohm-metre) per soil type; used by the Bostick depth estimate.
const Map<String, double> soilRho = {
  'average': 50,
  'clay': 20,
  'silt': 40,
  'loam': 60,
  'wetsand': 100,
  'drysand': 250,
  'gravel': 300,
  'limestone': 500,
  'granite': 1000,
};

/// Approximate depth in metres: Depth = 500 * sqrt(resistivity / frequency).
const double depthCoef = 500;
double postickDepth(double rho, double freq) => depthCoef * math.sqrt(rho / freq);

// ───────────────────────── COLOR + INTERPOLATION ─────────────────────────
Color coolwarm(double t) {
  t = t.clamp(0.0, 1.0);
  const c0 = Color(0xFF3B4CC0), c1 = Color(0xFFDDDDDD), c2 = Color(0xFFB40426);
  return t < 0.5 ? Color.lerp(c0, c1, t * 2)! : Color.lerp(c1, c2, (t - 0.5) * 2)!;
}

/// coolwarm as plain RGB ints (used for pixel buffers built inside isolates)
List<int> coolwarmRgb(double t) {
  t = t.clamp(0.0, 1.0).toDouble();
  const c0 = [0x3B, 0x4C, 0xC0], c1 = [0xDD, 0xDD, 0xDD], c2 = [0xB4, 0x04, 0x26];
  final a = t < 0.5 ? c0 : c1, b = t < 0.5 ? c1 : c2;
  final u = t < 0.5 ? t * 2 : (t - 0.5) * 2;
  return [for (var i = 0; i < 3; i++) (a[i] + (b[i] - a[i]) * u).round()];
}

double bilinear(List<List<double>> m, double x, double y) {
  final rows = m.length, cols = m[0].length;
  final x0 = x.floor().clamp(0, cols - 1), x1 = math.min(x0 + 1, cols - 1);
  final y0 = y.floor().clamp(0, rows - 1), y1 = math.min(y0 + 1, rows - 1);
  final tx = (x - x0).clamp(0.0, 1.0), ty = (y - y0).clamp(0.0, 1.0);
  final top = m[y0][x0] * (1 - tx) + m[y0][x1] * tx;
  final bot = m[y1][x0] * (1 - tx) + m[y1][x1] * tx;
  return top * (1 - ty) + bot * ty;
}

// ───────────────────────── HEATMAP PAINTER ─────────────────────────
void drawText(Canvas c, String s, Offset o,
    {bool centerX = false,
    bool right = false,
    bool centerY = false,
    Color color = Colors.black87,
    double size = 10,
    FontWeight? weight}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
    textDirection: TextDirection.ltr,
  )..layout();
  var dx = o.dx, dy = o.dy;
  if (centerX) dx -= tp.width / 2;
  if (right) dx -= tp.width;
  if (centerY) dy -= tp.height / 2;
  tp.paint(c, Offset(dx, dy));
}

class HeatmapPainter extends CustomPainter {
  final SurveyData data;
  final ui.Image? image; // pre-rendered (interpolated) heat image, built in an isolate
  final bool smooth;
  final int? selSi, selFi;
  final double rho;
  final Zone? target;
  final String lang = appLang;
  HeatmapPainter(this.data, this.image, this.smooth, this.selSi, this.selFi, this.rho, {this.target});

  static Rect plotRect(Size s) => Rect.fromLTRB(46, 8, s.width - 54, s.height - 30);

  void _drop(Canvas c, Offset o) {
    final path = Path()
      ..moveTo(o.dx, o.dy - 17)
      ..cubicTo(o.dx + 11, o.dy - 4, o.dx + 10, o.dy + 9, o.dx, o.dy + 9)
      ..cubicTo(o.dx - 10, o.dy + 9, o.dx - 11, o.dy - 4, o.dx, o.dy - 17)
      ..close();
    c.drawPath(path, Paint()..color = Colors.white);
    c.drawPath(path,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFF0D47A1));
    c.drawCircle(Offset(o.dx, o.dy + 1), 3.5, Paint()..color = const Color(0xFF0D47A1));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    final rows = data.freqs.length, cols = data.sites.length;
    final img = image;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        plot,
        Paint()..filterQuality = smooth ? FilterQuality.medium : FilterQuality.none,
      );
    }
    canvas.drawRect(plot, Paint()..style = PaintingStyle.stroke..color = Colors.black54);

    final fs = rows > 12 ? 9.0 : 10.0;
    final xTicks = cols <= 14 ? cols : 8;
    for (var i = 0; i < xTicks; i++) {
      final idx = xTicks == 1 ? 0 : (i * (cols - 1) / (xTicks - 1)).round();
      final x = cols == 1 ? plot.center.dx : plot.left + idx / (cols - 1) * plot.width;
      drawText(canvas, '${data.sites[idx]}', Offset(x, plot.bottom + 3), centerX: true);
    }
    drawText(canvas, tr('site'), Offset(plot.center.dx, plot.bottom + 15), centerX: true);

    // every frequency gets a label (up to 45); left = Hz, right = approximate depth
    final yTicks = rows <= 45 ? rows : 10;
    for (var i = 0; i < yTicks; i++) {
      final idx = yTicks == 1 ? 0 : (i * (rows - 1) / (yTicks - 1)).round();
      final y = rows == 1 ? plot.center.dy : plot.bottom - idx / (rows - 1) * plot.height;
      drawText(canvas, '${data.freqs[idx].toStringAsFixed(0)} Hz', Offset(plot.left - 4, y),
          right: true, centerY: true, size: fs);
      drawText(canvas, '~${postickDepth(rho, data.freqs[idx]).toStringAsFixed(0)} m',
          Offset(plot.right + 4, y),
          centerY: true, color: const Color(0xFF8D5A1B), size: fs);
    }

    Offset cellPos(int si, int fi) {
      final x = cols == 1 ? plot.center.dx : plot.left + si / (cols - 1) * plot.width;
      final y = rows == 1 ? plot.center.dy : plot.bottom - fi / (rows - 1) * plot.height;
      return Offset(x, y);
    }

    if (selSi != null && selFi != null) {
      final o = cellPos(selSi!, selFi!);
      canvas.drawCircle(o, 7, Paint()..color = Colors.white);
      canvas.drawCircle(
          o, 7, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black);
    }

    // target marker: lowest voltage = strongest water indication
    final t = target;
    if (t != null) {
      final o = cellPos(t.si, t.fi);
      _drop(canvas, o);
      final label = '~${postickDepth(rho, data.freqs[t.fi]).toStringAsFixed(0)} m';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
        textDirection: TextDirection.ltr,
      )..layout();
      final onRight = o.dx < plot.center.dx;
      final bx = onRight ? o.dx + 14 : o.dx - 14 - tp.width - 8;
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, o.dy - tp.height / 2 - 2, tp.width + 8, tp.height + 4),
          const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = Colors.white.withAlpha(235));
      canvas.drawRRect(
          rect, Paint()..style = PaintingStyle.stroke..color = const Color(0xFF0D47A1));
      tp.paint(canvas, Offset(bx + 4, o.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapPainter old) =>
      old.data != data ||
      old.image != image ||
      old.smooth != smooth ||
      old.selSi != selSi ||
      old.selFi != selFi ||
      old.rho != rho ||
      old.target?.si != target?.si ||
      old.target?.fi != target?.fi ||
      old.lang != lang;
}

class ColorBarLegend extends StatelessWidget {
  final double min, max;
  const ColorBarLegend({super.key, required this.min, required this.max});
  @override
  Widget build(BuildContext context) {
    // Gradient is always left=blue, right=red, so keep this block left-to-right.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(children: [
        Container(
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: List.generate(11, (i) => coolwarm(i / 10))),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${min.toStringAsFixed(1)} mV', style: const TextStyle(color: Colors.black87)),
          Text('${max.toStringAsFixed(1)} mV', style: const TextStyle(color: Colors.black87)),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tr('blue_water'),
              style: const TextStyle(color: Color(0xFF3B4CC0), fontWeight: FontWeight.bold)),
          Text(tr('red_dry'),
              style: const TextStyle(color: Color(0xFFB40426), fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }
}

// ───────────────────────── 3D VOLUME ─────────────────────────
/// 3D data matrix: v[line][freqIndex][siteIndex]  (X = Site, Y = Frequency/Depth, Z = Line)
class Volume3D {
  final List<int> sites, lines;
  final List<double> freqs;
  final List<List<List<double>>> v;
  final double min, max;
  final double rho; // estimated soil resistivity for the whole volume
  Volume3D(this.sites, this.freqs, this.lines, this.v, this.min, this.max, this.rho);

  static Volume3D build(List<SurveyData> sets) {
    final sorted = [...sets]..sort((a, b) => a.line.compareTo(b.line));
    final siteSet = <int>{};
    final freqSet = <double>{};
    for (final s in sorted) {
      siteSet.addAll(s.sites);
      freqSet.addAll(s.freqs);
    }
    final sites = siteSet.toList()..sort();
    final freqs = freqSet.toList()..sort();
    final v = <List<List<double>>>[];
    var mn = double.infinity, mx = -double.infinity;
    for (final s in sorted) {
      final si = <int, int>{for (var i = 0; i < s.sites.length; i++) s.sites[i]: i};
      final fi = <double, int>{for (var i = 0; i < s.freqs.length; i++) s.freqs[i]: i};
      final grid = List.generate(freqs.length, (f) {
        return List.generate(sites.length, (x) {
          final a = fi[freqs[f]], b = si[sites[x]];
          final val = (a == null || b == null) ? s.mean : s.matrix[a][b];
          if (val < mn) mn = val;
          if (val > mx) mx = val;
          return val;
        });
      });
      v.add(grid);
    }
    final lowVals = <double>[], highVals = <double>[];
    for (final g in v) {
      lowVals.addAll(g.first);
      highVals.addAll(g.last);
    }
    final rho = SurveyData.estimateRho([lowVals, highVals]);
    return Volume3D(sites, freqs, sorted.map((s) => s.line).toList(), v, mn, mx, rho);
  }

  /// LTTB downsampling of the Site and Frequency axes when S*F*L > maxPoints.
  Volume3D downsample(int maxPoints) {
    final s = sites.length, f = freqs.length, l = v.length;
    if (s * f * l <= maxPoints) return this;
    final g = math.sqrt(maxPoints / (s * f * l));
    final tS = math.max(3, (s * g).round()), tF = math.max(3, (f * g).round());
    final sp = List.generate(s, (x) {
      var a = 0.0;
      for (var z = 0; z < l; z++) {
        for (var y = 0; y < f; y++) {
          a += v[z][y][x];
        }
      }
      return a / (l * f);
    });
    final fp = List.generate(f, (y) {
      var a = 0.0;
      for (var z = 0; z < l; z++) {
        for (var x = 0; x < s; x++) {
          a += v[z][y][x];
        }
      }
      return a / (l * s);
    });
    final low = lowestCell();
    final xi = <int>{...lttbIndices(sp, tS), low[2]}.toList()..sort();
    final yi = <int>{...lttbIndices(fp, tF), low[1]}.toList()..sort();
    final nv = [
      for (var z = 0; z < l; z++)
        [
          for (final y in yi) [for (final x in xi) v[z][y][x]]
        ]
    ];
    return Volume3D([for (final x in xi) sites[x]], [for (final y in yi) freqs[y]], lines, nv, min, max, rho);
  }

  /// Trilinear sample at fractional index coordinates.
  double sample(double gx, double gy, double gz) {
    final nz = v.length, ny = freqs.length, nx = sites.length;
    final x0 = gx.floor().clamp(0, nx - 1), x1 = math.min(x0 + 1, nx - 1);
    final y0 = gy.floor().clamp(0, ny - 1), y1 = math.min(y0 + 1, ny - 1);
    final z0 = gz.floor().clamp(0, nz - 1), z1 = math.min(z0 + 1, nz - 1);
    final tx = (gx - x0).clamp(0.0, 1.0), ty = (gy - y0).clamp(0.0, 1.0), tz = (gz - z0).clamp(0.0, 1.0);
    double l(int z, int y) => v[z][y][x0] * (1 - tx) + v[z][y][x1] * tx;
    final a = l(z0, y0) * (1 - ty) + l(z0, y1) * ty;
    final b = l(z1, y0) * (1 - ty) + l(z1, y1) * ty;
    return a * (1 - tz) + b * tz;
  }

  /// Real (not interpolated) lowest voltage: [lineIndex, freqIndex, siteIndex]
  List<int> lowestCell() {
    var best = [0, 0, 0];
    var bv = double.infinity;
    for (var z = 0; z < v.length; z++) {
      for (var y = 0; y < freqs.length; y++) {
        for (var x = 0; x < sites.length; x++) {
          if (v[z][y][x] < bv) {
            bv = v[z][y][x];
            best = [z, y, x];
          }
        }
      }
    }
    return best;
  }
}

/// Voxel cloud stored in (z, y, x) order (x fastest): world coordinates + normalised value.
class VolumeGrid {
  static const double sx = 1.6, sy = 1.0, sz = 1.2; // box size in world units
  final Float32List xs, ys, zs, ts;
  final int count, nx, ny, nz;
  final double cell;
  VolumeGrid(this.xs, this.ys, this.zs, this.ts, this.count, this.cell, this.nx, this.ny, this.nz);

  static VolumeGrid fromVolume(Volume3D vol) {
    final s = vol.sites.length, f = vol.freqs.length, l = vol.lines.length;
    int dim(int n, int k) => n <= 1 ? 1 : (n - 1) * k + 1;
    var k = 4, kz = l <= 1 ? 1 : 6;
    int total() => dim(s, k) * dim(f, k) * dim(l, kz);
    while (total() > 20000 && (k > 1 || kz > 1)) {
      if (k > 1) {
        k--;
      } else {
        kz--;
      }
    }
    final nx = dim(s, k), ny = dim(f, k), nz = dim(l, kz);
    final n = nx * ny * nz;
    final xs = Float32List(n), ys = Float32List(n), zs = Float32List(n), ts = Float32List(n);
    final range = (vol.max - vol.min).abs() < 1e-9 ? 1.0 : vol.max - vol.min;
    var i = 0;
    for (var iz = 0; iz < nz; iz++) {
      final gz = nz == 1 ? 0.0 : iz / (nz - 1) * (l - 1);
      for (var iy = 0; iy < ny; iy++) {
        final gy = ny == 1 ? 0.0 : iy / (ny - 1) * (f - 1);
        for (var ix = 0; ix < nx; ix++) {
          final gx = nx == 1 ? 0.0 : ix / (nx - 1) * (s - 1);
          final val = vol.sample(gx, gy, gz);
          xs[i] = s == 1 ? 0.0 : (gx / (s - 1) - 0.5) * sx;
          ys[i] = f == 1 ? 0.0 : (gy / (f - 1) - 0.5) * sy; // row 0 (lowest freq) = bottom
          zs[i] = l == 1 ? 0.0 : (gz / (l - 1) - 0.5) * sz;
          ts[i] = ((val - vol.min) / range).clamp(0.0, 1.0).toDouble();
          i++;
        }
      }
    }
    return VolumeGrid(xs, ys, zs, ts, n, math.max(sx / nx, sy / ny), nx, ny, nz);
  }
}

/// Semi-transparent block. Voxels are drawn back-to-front by walking each grid axis in the
/// direction given by the view (no per-frame sorting). Low voltage (blue/water) is more opaque.
class Volume3DPainter extends CustomPainter {
  final VolumeGrid g;
  final Volume3D vol;
  final double yaw, pitch, zoom, cutoff, opacity, rho;
  Volume3DPainter(this.g, this.vol, this.yaw, this.pitch, this.zoom, this.cutoff, this.opacity, this.rho);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final scale = math.min(size.width, size.height) * 0.36 * zoom;
    final cy = math.cos(yaw), sy = math.sin(yaw), cp = math.cos(pitch), sp = math.sin(pitch);

    // depth = kx*x + ky*y + kz*z ; far-first means ascending depth along each axis
    final kx = -sy * cp, ky = sp, kz = cy * cp;
    int at(int j, int n, double k) => k >= 0 ? j : n - 1 - j;
    final nx = g.nx, ny = g.ny, nz = g.nz;
    final s = math.max(2.0, scale * g.cell * 1.25);
    final paint = Paint();
    for (var jz = 0; jz < nz; jz++) {
      final iz = at(jz, nz, kz);
      for (var jy = 0; jy < ny; jy++) {
        final iy = at(jy, ny, ky);
        for (var jx = 0; jx < nx; jx++) {
          final ix = at(jx, nx, kx);
          final i = (iz * ny + iy) * nx + ix;
          final t = g.ts[i];
          if (t > cutoff) continue;
          final x = g.xs[i], y = g.ys[i], z = g.zs[i];
          final x1 = x * cy + z * sy;
          final z1 = -x * sy + z * cy;
          final y2 = y * cp - z1 * sp;
          final a = (opacity * (0.08 + 0.8 * math.pow(1 - t, 1.6))).clamp(0.0, 1.0);
          paint.color = coolwarm(t).withAlpha((a * 255).round());
          canvas.drawRect(
              Rect.fromCenter(center: Offset(c.dx + x1 * scale, c.dy - y2 * scale), width: s, height: s),
              paint);
        }
      }
    }

    // bounding box + labels
    Offset tf(double x, double y, double z) {
      final x1 = x * cy + z * sy;
      final z1 = -x * sy + z * cy;
      final y2 = y * cp - z1 * sp;
      return Offset(c.dx + x1 * scale, c.dy - y2 * scale);
    }

    const hx = VolumeGrid.sx / 2, hy = VolumeGrid.sy / 2;
    final hz = vol.lines.length <= 1 ? 0.02 : VolumeGrid.sz / 2;
    Offset corner(int i) => tf((i & 1) == 0 ? -hx : hx, (i & 2) == 0 ? -hy : hy, (i & 4) == 0 ? -hz : hz);
    final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white38;
    for (var i = 0; i < 8; i++) {
      for (final bit in [1, 2, 4]) {
        if ((i & bit) == 0) canvas.drawLine(corner(i), corner(i | bit), edge);
      }
    }
    const lc = Colors.white70;
    final fMin = vol.freqs.first, fMax = vol.freqs.last;
    drawText(canvas, '${fMax.toStringAsFixed(0)}Hz ~${postickDepth(rho, fMax).toStringAsFixed(0)}m',
        tf(-hx, hy, hz) + const Offset(-6, 0), right: true, centerY: true, color: lc, size: 10);
    drawText(canvas, '${fMin.toStringAsFixed(0)}Hz ~${postickDepth(rho, fMin).toStringAsFixed(0)}m',
        tf(-hx, -hy, hz) + const Offset(-6, 0), right: true, centerY: true, color: lc, size: 10);
    drawText(canvas, 'Site ${vol.sites.first}→${vol.sites.last}', tf(0, -hy, hz) + const Offset(0, 8),
        centerX: true, color: lc, size: 10);
    if (vol.lines.length > 1) {
      drawText(canvas, 'Line ${vol.lines.first}→${vol.lines.last}', tf(hx, -hy, 0) + const Offset(8, 4),
          color: lc, size: 10);
    }
  }

  @override
  bool shouldRepaint(covariant Volume3DPainter old) =>
      old.g != g ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.cutoff != cutoff ||
      old.opacity != opacity ||
      old.rho != rho;
}

// ───────────────────────── BACKGROUND JOBS (run with Isolate.run) ─────────────────────────
class HeatPixels {
  final int w, h;
  final Uint8List smooth, nearest; // RGBA buffers
  HeatPixels(this.w, this.h, this.smooth, this.nearest);
}

class ParseResult {
  final SurveyData data;
  final HeatPixels heat;
  ParseResult(this.data, this.heat);
}

class VolumeResult {
  final Volume3D vol;
  final VolumeGrid grid;
  VolumeResult(this.vol, this.grid);
}

/// Bilinear-interpolated heat image (and a nearest-neighbour twin) as raw RGBA pixels.
/// Row 0 of the matrix (lowest frequency = deepest) ends up at the BOTTOM of the image.
HeatPixels buildHeatPixels(SurveyData d) {
  final rows = d.freqs.length, cols = d.sites.length;
  final w = (cols * 8).clamp(64, 400).toInt();
  final h = (rows * 8).clamp(64, 400).toInt();
  final range = (d.max - d.min).abs() < 1e-9 ? 1.0 : d.max - d.min;
  Uint8List make(bool smooth) {
    final out = Uint8List(w * h * 4);
    for (var py = 0; py < h; py++) {
      final gy = rows == 1 ? 0.0 : (h - 1 - py) / (h - 1) * (rows - 1);
      for (var px = 0; px < w; px++) {
        final gx = cols == 1 ? 0.0 : px / (w - 1) * (cols - 1);
        final v = smooth ? bilinear(d.matrix, gx, gy) : d.matrix[gy.round()][gx.round()];
        final rgb = coolwarmRgb((v - d.min) / range);
        final o = (py * w + px) * 4;
        out[o] = rgb[0];
        out[o + 1] = rgb[1];
        out[o + 2] = rgb[2];
        out[o + 3] = 255;
      }
    }
    return out;
  }

  return HeatPixels(w, h, make(true), make(false));
}

/// Everything heavy for the 2D map: read file, parse, estimate resistivity, LTTB, pixels.
ParseResult parseFileJob(String path, int fallbackLine) {
  var d = SurveyData.parse(File(path).readAsStringSync(), fallbackLine: fallbackLine);
  d = d.downsample(5000, keep: d.bestZones(3));
  return ParseResult(d, buildHeatPixels(d));
}

Future<ParseResult> runParseInIsolate(String path) => Isolate.run(() => parseFileJob(path, 1));

/// Everything heavy for the 3D block: parse all files, build matrix, LTTB, voxel grid.
VolumeResult volumeJob(List<String> paths) {
  final sets = <SurveyData>[];
  var idx = 1;
  for (final p in paths) {
    sets.add(SurveyData.parse(File(p).readAsStringSync(), fallbackLine: idx++));
  }
  final vol = Volume3D.build(sets).downsample(5000);
  return VolumeResult(vol, VolumeGrid.fromVolume(vol));
}

Future<VolumeResult> runVolumeInIsolate(List<String> paths) => Isolate.run(() => volumeJob(paths));

// ───────────────────────── APP STATE ─────────────────────────
class AppState extends ChangeNotifier {
  final ble = BleService();
  final langNotifier = ValueNotifier<String>('ar');
  String get lang => langNotifier.value;

  List<String> files = [];
  List<File> localFiles = [];
  final downloaded = <String, File>{};
  String? busyFile;
  int progress = 0;
  bool loadingList = false;
  File? currentFile;
  SurveyData? data;
  ui.Image? heatSmooth, heatNearest;
  bool loadingMap = false, loadingVol = false;
  VolumeGrid? volumeGrid;
  String soilKey = 'auto'; // 'auto' = estimated from the signal
  double customRho = 100;

  /// Resistivity used for depth: estimated (auto) or the manually chosen soil.
  double rhoFor(double autoRho) =>
      soilKey == 'auto' ? autoRho : (soilKey == 'custom' ? customRho : (soilRho[soilKey] ?? 60));
  double get rho => rhoFor(data?.rho ?? 50);

  String get soilLabel => soilKey == 'custom'
      ? '${tr('soil_custom')} ${customRho.toStringAsFixed(0)} Ω·m'
      : '${tr('soil_$soilKey')} ${rho.toStringAsFixed(0)} Ω·m';

  Future<void> setSoil(String key, {double? custom}) async {
    soilKey = key;
    if (custom != null) customRho = custom;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('soil', key);
    await p.setDouble('rho', customRho);
  }

  void refresh() => notifyListeners();

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('lang');
    appLang = saved ?? 'ar';
    langNotifier.value = appLang;
    final s = p.getString('soil') ?? 'auto';
    soilKey = (s == 'auto' || s == 'custom' || soilRho.containsKey(s)) ? s : 'auto';
    customRho = p.getDouble('rho') ?? 100;
  }

  Future<void> setLang(String l) async {
    appLang = l;
    langNotifier.value = l;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
  }

  Future<String?> connect(BluetoothDevice d) async {
    try {
      await ble.connect(d);
      notifyListeners();
      return null;
    } catch (e) {
      return errText(e);
    }
  }

  Future<String?> refreshFiles() async {
    loadingList = true;
    notifyListeners();
    try {
      files = await ble.listFiles();
      return files.isEmpty ? tr('no_list') : null;
    } catch (e) {
      return errText(e);
    } finally {
      loadingList = false;
      notifyListeners();
    }
  }

  Future<String?> download(String name) async {
    busyFile = name;
    progress = 0;
    notifyListeners();
    try {
      final f = await ble.download(name, (n) {
        progress = n;
        notifyListeners();
      });
      downloaded[name] = f;
      currentFile = f;
      data = null;
      return null;
    } catch (e) {
      return errText(e);
    } finally {
      busyFile = null;
      notifyListeners();
    }
  }

  Future<void> loadLocalFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    localFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.csv'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    notifyListeners();
  }

  /// Pick a CSV from phone storage and copy it into the app folder.
  Future<String?> importCsv() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res == null) return null;
      final pf = res.files.single;
      if (!pf.name.toLowerCase().endsWith('.csv')) return tr('need_csv');
      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/${pf.name}');
      if (pf.path != null) {
        await File(pf.path!).copy(dest.path);
      } else if (pf.bytes != null) {
        await dest.writeAsBytes(pf.bytes!);
      } else {
        return tr('read_fail');
      }
      currentFile = dest;
      data = null;
      await loadLocalFiles();
      return tr('imported').replaceAll('{n}', pf.name);
    } catch (e) {
      return errText(e);
    }
  }

  void selectLocal(File f) {
    currentFile = f;
    data = null;
    notifyListeners();
  }

  Future<void> deleteLocal(File f) async {
    try {
      await f.delete();
    } catch (_) {}
    downloaded.removeWhere((k, v) => v.path == f.path);
    selected3d.remove(f.path);
    if (currentFile?.path == f.path) {
      currentFile = null;
      data = null;
    }
    await loadLocalFiles();
  }

  // ---- multi-file / 3D volume
  final selected3d = <String>{};
  Volume3D? volume;

  void toggle3d(String path, bool on) {
    if (on) {
      selected3d.add(path);
    } else {
      selected3d.remove(path);
    }
    notifyListeners();
  }

  Future<String?> importMany() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
      if (res == null) return null;
      final dir = await getApplicationDocumentsDirectory();
      var n = 0;
      for (final pf in res.files) {
        if (!pf.name.toLowerCase().endsWith('.csv')) continue;
        final dest = File('${dir.path}/${pf.name}');
        if (pf.path != null) {
          await File(pf.path!).copy(dest.path);
        } else if (pf.bytes != null) {
          await dest.writeAsBytes(pf.bytes!);
        } else {
          continue;
        }
        selected3d.add(dest.path);
        n++;
      }
      await loadLocalFiles();
      return n == 0 ? tr('need_csv') : tr('imported_n').replaceAll('{n}', '$n');
    } catch (e) {
      return errText(e);
    }
  }

  Future<ui.Image> _toImage(Uint8List px, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  String friendlyErr(Object e) => e.toString().contains('no_rows') ? tr('no_rows') : errText(e);

  /// Parsing, resistivity estimate, LTTB and pixel interpolation all run in a background isolate.
  Future<String?> buildVolume() async {
    if (selected3d.isEmpty) return tr('need_files');
    loadingVol = true;
    notifyListeners();
    try {
      final paths = selected3d.toList();
      final r = await runVolumeInIsolate(paths);
      volume = r.vol;
      volumeGrid = r.grid;
      return paths.length == 1 ? tr('one_line_warn') : null;
    } catch (e) {
      return friendlyErr(e);
    } finally {
      loadingVol = false;
      notifyListeners();
    }
  }

  Future<String?> generateMap() async {
    final f = currentFile;
    if (f == null) return null;
    loadingMap = true;
    notifyListeners();
    try {
      final path = f.path;
      final r = await runParseInIsolate(path);
      final a = await _toImage(r.heat.smooth, r.heat.w, r.heat.h);
      final b = await _toImage(r.heat.nearest, r.heat.w, r.heat.h);
      heatSmooth?.dispose();
      heatNearest?.dispose();
      heatSmooth = a;
      heatNearest = b;
      data = r.data; // new file -> new estimated resistivity -> new depth labels
      return null;
    } catch (e) {
      return friendlyErr(e);
    } finally {
      loadingMap = false;
      notifyListeners();
    }
  }
}

// ───────────────────────── UI ─────────────────────────
class GeoPulseApp extends StatelessWidget {
  final AppState app;
  const GeoPulseApp(this.app, {super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: app.langNotifier,
      builder: (context, lang, _) => MaterialApp(
        title: 'GeoPulse',
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(colorSchemeSeed: const Color(0xFF00796B), useMaterial3: true),
        home: Shell(app: app),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  final AppState app;
  const Shell({super.key, required this.app});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  AppState get app => widget.app;

  void toast(String? msg) {
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConnectPage(app: app, toast: toast, onConnected: () => setState(() => tab = 1)),
      FilesPage(app: app, toast: toast, onDownloaded: () => setState(() => tab = 2)),
      MapPage(app: app, toast: toast),
      VolumePage(app: app, toast: toast),
      SettingsPage(app: app, toast: toast),
    ];
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/icon/logo.png', height: 32),
          const SizedBox(width: 8),
          const Text('GeoPulse'),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.translate),
            tooltip: 'العربية / English',
            onPressed: () => app.setLang(app.lang == 'ar' ? 'en' : 'ar'),
          ),
        ],
      ),
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.bluetooth), label: tr('connect')),
          NavigationDestination(icon: const Icon(Icons.folder_open), label: tr('files')),
          NavigationDestination(icon: const Icon(Icons.map), label: tr('map')),
          NavigationDestination(icon: const Icon(Icons.view_in_ar), label: tr('tab3d')),
          NavigationDestination(icon: const Icon(Icons.settings), label: tr('settings')),
        ],
      ),
    );
  }
}

class ConnectPage extends StatelessWidget {
  final AppState app;
  final void Function(String?) toast;
  final VoidCallback onConnected;
  const ConnectPage({super.key, required this.app, required this.toast, required this.onConnected});

  Future<void> _scan() async {
    final st = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse
    ].request();
    if (st[Permission.bluetoothScan]?.isDenied == true) {
      toast(tr('bt_perm'));
      return;
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 64,
            child: FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.bluetooth_searching, size: 28),
              label: Text(tr('scan_connect'), style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(height: 12),
          if (app.ble.connected)
            Card(
              color: Colors.green.shade50,
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(app.ble.device?.platformName ?? tr('connected')),
                trailing: TextButton(
                    onPressed: () async {
                      await app.ble.disconnect();
                      app.refresh();
                    },
                    child: Text(tr('disconnect'))),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<ScanResult>>(
              stream: FlutterBluePlus.scanResults,
              initialData: const [],
              builder: (context, snap) {
                final list = (snap.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList()
                  ..sort((a, b) =>
                      (b.device.platformName.contains('TEFSM') ? 1 : 0) -
                      (a.device.platformName.contains('TEFSM') ? 1 : 0));
                return ListView(
                  children: [
                    for (final r in list)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.sensors),
                          title: Text(r.device.platformName),
                          subtitle: Text('${r.device.remoteId}  •  ${r.rssi} dBm'),
                          trailing: const Icon(Icons.link),
                          onTap: () async {
                            final err = await app.connect(r.device);
                            toast(err ?? tr('connect_ok'));
                            if (err == null) onConnected();
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class FilesPage extends StatelessWidget {
  final AppState app;
  final void Function(String?) toast;
  final VoidCallback onDownloaded;
  const FilesPage({super.key, required this.app, required this.toast, required this.onDownloaded});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.tonalIcon(
              onPressed: !app.ble.connected || app.loadingList
                  ? null
                  : () async => toast(await app.refreshFiles()),
              icon: app.loadingList
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(tr('get_files')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () async {
                final before = app.currentFile?.path;
                final msg = await app.importCsv();
                toast(msg);
                if (app.currentFile != null && app.currentFile!.path != before) onDownloaded();
              },
              icon: const Icon(Icons.upload_file),
              label: Text(tr('import_csv')),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: app.files.isEmpty
                ? Center(child: Text(tr('no_files')))
                : ListView(children: [
                    for (final f in app.files)
                      Card(
                        child: ListTile(
                          leading: Icon(
                              app.downloaded.containsKey(f) ? Icons.check_circle : Icons.description,
                              color: app.downloaded.containsKey(f) ? Colors.green : null),
                          title: Text(f),
                          subtitle: app.busyFile == f
                              ? Text(tr('lines_recv').replaceAll('{n}', '${app.progress}'))
                              : null,
                          trailing: app.busyFile == f
                              ? const SizedBox(
                                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : FilledButton(
                                  onPressed: app.busyFile != null
                                      ? null
                                      : () async {
                                          final err = await app.download(f);
                                          toast(err ?? tr('downloaded').replaceAll('{n}', f));
                                          if (err == null) onDownloaded();
                                        },
                                  child: Text(tr('download'))),
                        ),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  final AppState app;
  final void Function(String?) toast;
  const MapPage({super.key, required this.app, required this.toast});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _boundaryKey = GlobalKey();
  final _tc = TransformationController();
  bool smooth = true;
  bool mapView = false;
  int? selSi, selFi;
  int _pointers = 0;
  bool _lock = false;

  @override
  void initState() {
    super.initState();
    widget.app.loadLocalFiles();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  // While two fingers are down (or the view is zoomed) the page must not scroll.
  void _setLock(bool v) {
    if (_lock != v && mounted) setState(() => _lock = v);
  }

  void _down() {
    _pointers++;
    if (_pointers >= 2 || _tc.value.getMaxScaleOnAxis() > 1.01) _setLock(true);
  }

  void _up() {
    _pointers = math.max(0, _pointers - 1);
    if (_pointers == 0) _setLock(false);
  }

  void _resetSel() {
    selSi = null;
    selFi = null;
    _tc.value = Matrix4.identity();
  }

  void _pick(SurveyData d, Offset pos, Size size) {
    final plot = HeatmapPainter.plotRect(size);
    if (!plot.inflate(4).contains(pos)) return;
    final cols = d.sites.length, rows = d.freqs.length;
    final gx = cols == 1 ? 0.0 : (pos.dx - plot.left) / plot.width * (cols - 1);
    final gy = rows == 1 ? 0.0 : (plot.bottom - pos.dy) / plot.height * (rows - 1);
    setState(() {
      selSi = gx.round().clamp(0, cols - 1);
      selFi = gy.round().clamp(0, rows - 1);
    });
  }

  Future<void> _pickSoil(String key) async {
    if (key != 'custom') {
      await widget.app.setSoil(key);
      return;
    }
    final ctrl = TextEditingController(text: widget.app.customRho.toStringAsFixed(0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('rho_title')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('ok'))),
        ],
      ),
    );
    if (ok == true) {
      final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (v != null && v > 0) await widget.app.setSoil('custom', custom: v);
    }
  }

  Future<void> _share() async {
    try {
      final ro = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (ro == null) return;
      final img = await ro.toImage(pixelRatio: 3);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bd == null) return;
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/geopulse_map.png');
      await f.writeAsBytes(bd.buffer.asUint8List());
      await Share.shareXFiles([XFile(f.path)], text: 'GeoPulse');
    } catch (e) {
      widget.toast(errText(e));
    }
  }

  Future<void> _confirmDelete(File f) async {
    final name = f.path.split('/').last;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('delete_q').replaceAll('{n}', name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('delete'))),
        ],
      ),
    );
    if (ok == true) {
      await widget.app.deleteLocal(f);
      setState(_resetSel);
    }
  }

  /// OpenStreetMap view (no API key). Markers: blue = low voltage (water), red = high (dry).
  Widget _osmWidget(SurveyData d) {
    final range = (d.max - d.min).abs() < 1e-9 ? 1.0 : d.max - d.min;
    final pts = <LatLng>[];
    final markers = <Marker>[];
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (var si = 0; si < d.sites.length; si++) {
      final g = d.gps[d.sites[si]];
      if (g == null) continue;
      final z = d.siteMin(si);
      final t = ((z.v - d.min) / range).clamp(0.0, 1.0).toDouble();
      final pos = LatLng(g[0], g[1]);
      pts.add(pos);
      minLat = math.min(minLat, g[0]);
      maxLat = math.max(maxLat, g[0]);
      minLon = math.min(minLon, g[1]);
      maxLon = math.max(maxLon, g[1]);
      final depth = postickDepth(widget.app.rho, d.freqs[z.fi]).toStringAsFixed(0);
      final info =
          '${tr('site')} ${d.sites[si]} • ${z.v.toStringAsFixed(1)} mV • ${d.freqs[z.fi].toStringAsFixed(0)} Hz • ~$depth ${tr('m_unit')}';
      markers.add(Marker(
        point: pos,
        width: 34,
        height: 34,
        child: GestureDetector(
          onTap: () => widget.toast(info),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: coolwarm(t),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
            ),
            child: Text('${d.sites[si]}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        ),
      ));
    }
    if (pts.isEmpty) return Center(child: Text(tr('no_maps_data')));
    final span = math.max(maxLat - minLat, (maxLon - minLon) * math.cos(((minLat + maxLat) / 2) * math.pi / 180));
    final zoom = span < 1e-6 ? 18.0 : (math.log(360 / span) / math.ln2 - 1).clamp(2.0, 19.0).toDouble();
    return Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCenter: LatLng((minLat + maxLat) / 2, (minLon + maxLon) / 2),
          initialZoom: zoom,
          minZoom: 2,
          maxZoom: 19,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.geopulse.geopulse',
          ),
          PolylineLayer(polylines: [Polyline(points: pts, strokeWidth: 3, color: Colors.black54)]),
          MarkerLayer(markers: markers),
        ],
      ),
      Positioned(
        right: 4,
        bottom: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          color: Colors.white70,
          child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 9, color: Colors.black87)),
        ),
      ),
    ]);
  }

  List<Widget> _mapSection(SurveyData d, String name) {
    final app = widget.app;
    final zones = d.bestZones();
    final target = zones.isEmpty ? null : zones.first;
    final showMap = mapView && d.hasGps;
    final mapH = d.freqs.length <= 12 ? 340.0 : math.min(d.freqs.length * 14.0, 560.0);
    final heatImage = smooth ? app.heatSmooth : app.heatNearest;
    String zoneText(Zone z) => tr('zone_item')
        .replaceAll('{s}', '${d.sites[z.si]}')
        .replaceAll('{f}', d.freqs[z.fi].toStringAsFixed(0))
        .replaceAll('{d}', postickDepth(app.rho, d.freqs[z.fi]).toStringAsFixed(0))
        .replaceAll('{u}', tr('m_unit'))
        .replaceAll('{v}', z.v.toStringAsFixed(1));

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.landscape, color: Color(0xFF8D5A1B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('est_soil').replaceAll('{r}', d.rho.toStringAsFixed(0)),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ]),
            if (app.soilKey != 'auto')
              Text(tr('manual_used').replaceAll('{r}', app.rho.toStringAsFixed(0)),
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(tr('soil'), style: Theme.of(context).textTheme.titleSmall),
            DropdownButton<String>(
              isExpanded: true,
              value: app.soilKey,
              items: [
                DropdownMenuItem(value: 'auto', child: Text(tr('soil_auto'))),
                for (final e in soilRho.entries)
                  DropdownMenuItem(
                      value: e.key,
                      child: Text('${tr('soil_${e.key}')} • ${e.value.toStringAsFixed(0)} Ω·m')),
                DropdownMenuItem(
                    value: 'custom',
                    child: Text('${tr('soil_custom')} • ${app.customRho.toStringAsFixed(0)} Ω·m')),
              ],
              onChanged: (v) {
                if (v != null) _pickSoil(v);
              },
            ),
            Text(tr('depth_note'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
      if (d.hasGps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(tr('view_heat')), icon: const Icon(Icons.grid_on)),
              ButtonSegment(value: true, label: Text(tr('view_gps')), icon: const Icon(Icons.map)),
            ],
            selected: {mapView},
            onSelectionChanged: (s) => setState(() => mapView = s.first),
          ),
        ),
      if (showMap) ...[
        SizedBox(
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Listener(
              onPointerDown: (_) => _setLock(true),
              onPointerUp: (_) => _setLock(false),
              onPointerCancel: (_) => _setLock(false),
              child: _osmWidget(d),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ColorBarLegend(min: d.min, max: d.max),
      ] else ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('smooth')),
          value: smooth,
          onChanged: (v) => setState(() => smooth = v),
        ),
        Row(children: [
          Expanded(child: Text(tr('zoom_hint'), style: Theme.of(context).textTheme.bodySmall)),
          IconButton(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: tr('reset_zoom'),
            onPressed: () => _tc.value = Matrix4.identity(),
          ),
        ]),
        RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Text('$name • ${app.soilLabel}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 6),
              Listener(
                onPointerDown: (_) => _down(),
                onPointerUp: (_) => _up(),
                onPointerCancel: (_) => _up(),
                child: SizedBox(
                  height: mapH,
                  child: LayoutBuilder(builder: (ctx, cons) {
                    final size = Size(cons.maxWidth, cons.maxHeight);
                    return ClipRect(
                      child: InteractiveViewer(
                        transformationController: _tc,
                        minScale: 1,
                        maxScale: 8,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (t) => _pick(d, t.localPosition, size),
                          // own layer: pan/zoom only moves the cached picture, no repaint
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: size,
                              painter: HeatmapPainter(d, heatImage, smooth, selSi, selFi, app.rho, target: target),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              ColorBarLegend(min: d.min, max: d.max),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 8),
      if (target != null)
        Card(
          color: Colors.cyan.shade50,
          child: ListTile(
            leading: const Icon(Icons.water_drop, color: Color(0xFF0D47A1)),
            title: Text(tr('target_title')),
            subtitle: Text(zoneText(target)),
          ),
        ),
      if (!showMap)
        Card(
          child: ListTile(
            leading: const Icon(Icons.touch_app),
            title: Text(selSi == null
                ? tr('tap_hint')
                : tr('picked')
                    .replaceAll('{s}', '${d.sites[selSi!]}')
                    .replaceAll('{f}', d.freqs[selFi!].toStringAsFixed(0))
                    .replaceAll('{d}', postickDepth(app.rho, d.freqs[selFi!]).toStringAsFixed(0))
                    .replaceAll('{u}', tr('m_unit'))
                    .replaceAll('{v}', d.matrix[selFi!][selSi!].toStringAsFixed(1))),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('stats'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text('${tr('min')}: ${d.min.toStringAsFixed(1)} mV'),
            Text('${tr('max')}: ${d.max.toStringAsFixed(1)} mV'),
            Text('${tr('mean')}: ${d.mean.toStringAsFixed(1)} mV'),
          ]),
        ),
      ),
      Card(
        color: Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('analysis'), style: Theme.of(context).textTheme.titleSmall),
            Text(tr('analysis_sub'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            for (var i = 0; i < zones.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('${i + 1}. ${zoneText(zones[i])}'),
              ),
            const SizedBox(height: 6),
            Text(tr('analysis_note'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ]),
        ),
      ),
      if (!showMap) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: FilledButton.tonalIcon(
            onPressed: _share,
            icon: const Icon(Icons.share),
            label: Text(tr('share_map')),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final file = app.currentFile;
        return ListView(
          physics: _lock ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final msg = await app.importCsv();
                  setState(_resetSel);
                  widget.toast(msg);
                },
                icon: const Icon(Icons.upload_file),
                label: Text(tr('import_csv')),
              ),
            ),
            if (app.localFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr('saved_files'), style: Theme.of(context).textTheme.titleSmall),
              for (final f in app.localFiles)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(f.path == file?.path ? Icons.radio_button_checked : Icons.radio_button_off),
                    title: Text(f.path.split('/').last),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: tr('delete'),
                      onPressed: () => _confirmDelete(f),
                    ),
                    onTap: () {
                      app.selectLocal(f);
                      setState(_resetSel);
                    },
                  ),
                ),
            ],
            const SizedBox(height: 12),
            if (file == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(tr('import_or_dl'))),
              )
            else ...[
              Text(file.path.split('/').last, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: app.loadingMap
                      ? null
                      : () async {
                          final err = await app.generateMap();
                          setState(_resetSel);
                          widget.toast(err);
                        },
                  icon: app.loadingMap
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.grid_on),
                  label: Text(app.loadingMap ? tr('processing') : tr('generate_map'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 8),
              if (app.data != null) ..._mapSection(app.data!, file.path.split('/').last),
            ],
          ],
        );
      },
    );
  }
}

// ───────────────────────── 3D PAGE ─────────────────────────
class VolumePage extends StatefulWidget {
  final AppState app;
  final void Function(String?) toast;
  const VolumePage({super.key, required this.app, required this.toast});
  @override
  State<VolumePage> createState() => _VolumePageState();
}

class _VolumePageState extends State<VolumePage> {
  double yaw = 0.6, pitch = 0.5, zoom = 1.0, baseZoom = 1.0, cutoff = 1.0, opacity = 0.9;
  bool _lock = false;

  @override
  void initState() {
    super.initState();
    widget.app.loadLocalFiles();
  }

  void _setLock(bool v) {
    if (_lock != v && mounted) setState(() => _lock = v);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final vol = app.volume, grid = app.volumeGrid;
        final rho = vol == null ? 50.0 : app.rhoFor(vol.rho);
        String pocket = '';
        if (vol != null) {
          final c = vol.lowestCell();
          pocket = tr('pocket')
              .replaceAll('{l}', '${vol.lines[c[0]]}')
              .replaceAll('{s}', '${vol.sites[c[2]]}')
              .replaceAll('{f}', vol.freqs[c[1]].toStringAsFixed(0))
              .replaceAll('{d}', postickDepth(rho, vol.freqs[c[1]]).toStringAsFixed(0))
              .replaceAll('{u}', tr('m_unit'));
        }
        return ListView(
          physics: _lock ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async => widget.toast(await app.importMany()),
                icon: const Icon(Icons.library_add),
                label: Text(tr('import_many')),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('select_lines'), style: Theme.of(context).textTheme.titleSmall),
            for (final f in app.localFiles)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: app.selected3d.contains(f.path),
                title: Text(f.path.split('/').last),
                onChanged: (v) => app.toggle3d(f.path, v == true),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: app.loadingVol ? null : () async => widget.toast(await app.buildVolume()),
                icon: app.loadingVol
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.view_in_ar),
                label: Text(app.loadingVol ? tr('processing') : tr('build_3d'),
                    style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 12),
            if (vol != null && grid != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.landscape, color: Color(0xFF8D5A1B)),
                  title: Text(tr('est_soil').replaceAll('{r}', vol.rho.toStringAsFixed(0))),
                  subtitle: app.soilKey == 'auto'
                      ? null
                      : Text(tr('manual_used').replaceAll('{r}', rho.toStringAsFixed(0))),
                ),
              ),
              Listener(
                onPointerDown: (_) => _setLock(true),
                onPointerUp: (_) => _setLock(false),
                onPointerCancel: (_) => _setLock(false),
                child: Container(
                  height: 380,
                  decoration: BoxDecoration(color: const Color(0xFF0E1621), borderRadius: BorderRadius.circular(8)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onScaleStart: (_) => baseZoom = zoom,
                      onScaleUpdate: (d) => setState(() {
                        zoom = (baseZoom * d.scale).clamp(0.5, 4.0).toDouble();
                        yaw += d.focalPointDelta.dx * 0.01;
                        pitch = (pitch - d.focalPointDelta.dy * 0.01).clamp(-1.4, 1.4).toDouble();
                      }),
                      // own layer: the page around it is not repainted while rotating
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: Volume3DPainter(grid, vol, yaw, pitch, zoom, cutoff, opacity, rho),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(children: [
                Expanded(child: Text(tr('hint3d'), style: Theme.of(context).textTheme.bodySmall)),
                IconButton(
                  icon: const Icon(Icons.zoom_out_map),
                  tooltip: tr('reset_zoom'),
                  onPressed: () => setState(() {
                    yaw = 0.6;
                    pitch = 0.5;
                    zoom = 1.0;
                  }),
                ),
              ]),
              Text(tr('cutoff')),
              Slider(value: cutoff, min: 0.05, max: 1.0, onChanged: (v) => setState(() => cutoff = v)),
              Text(tr('opacity')),
              Slider(value: opacity, min: 0.1, max: 1.0, onChanged: (v) => setState(() => opacity = v)),
              ColorBarLegend(min: vol.min, max: vol.max),
              const SizedBox(height: 8),
              Card(
                color: Colors.cyan.shade50,
                child: ListTile(
                  leading: const Icon(Icons.water_drop, color: Color(0xFF0D47A1)),
                  title: Text(pocket),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(tr('analysis_note'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              ),
            ],
          ],
        );
      },
    );
  }
}

class SettingsPage extends StatefulWidget {
  final AppState app;
  final void Function(String?) toast;
  const SettingsPage({super.key, required this.app, required this.toast});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool busy = false;

  // ESP32 replies with ONE line, e.g. "OTA:UP_TO_DATE v1.0.3" or "OTA:UPDATING v1.0.4"
  Future<void> _checkOta() async {
    if (!widget.app.ble.connected) return widget.toast(tr('connect_first'));
    setState(() => busy = true);
    try {
      final r = await widget.app.ble.request('OTA_CHECK\n');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('fw_title')),
          content: Text(r),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('ok')))],
        ),
      );
    } catch (e) {
      widget.toast(tr('no_reply'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('language'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ar', label: Text('العربية')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.lang},
              onSelectionChanged: (s) => app.setLang(s.first),
            ),
          ]),
        ),
      ),
      Card(
        child: ListTile(
          leading: busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update),
          title: Text(tr('firmware')),
          subtitle: Text(tr('firmware_sub')),
          onTap: busy ? null : _checkOta,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('GeoPulse'),
          subtitle: Text('${tr('version')} 1.1.0'),
        ),
      ),
    ]);
  }
}
