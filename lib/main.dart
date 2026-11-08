// GeoPulse v1.1 - TEFSM groundwater survey viewer (ESP32 over BLE)
// Arabic / English, CSV import, tap-to-inspect heatmap, zone analysis, share image
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
    'zone_item': 'الموقع {s} عند {f} هرتز: {v} mV',
    'analysis_note': 'نتيجة استرشادية فقط، ولا تغني عن الخبرة الميدانية أو الحفر التجريبي.',
    'tap_hint': 'المس الخريطة لعرض قيمة أي نقطة',
    'picked': 'الموقع {s} • {f} هرتز • {v} mV',
    'no_rows': 'لا توجد بيانات صالحة في الملف',
    'no_uart': 'لم يتم العثور على خدمة UART في الجهاز',
    'no_list': 'لم يرجع الجهاز أي ملفات',
    'timeout': 'انتهت مهلة النقل',
    'version': 'الإصدار',
    'mv_unit': 'mV',
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
    'zone_item': 'Site {s} at {f} Hz: {v} mV',
    'analysis_note': 'Indicative only. It does not replace field experience or test drilling.',
    'tap_hint': 'Tap the map to read any point',
    'picked': 'Site {s} • {f} Hz • {v} mV',
    'no_rows': 'No valid data rows in file',
    'no_uart': 'UART service not found on device',
    'no_list': 'The device returned no files',
    'timeout': 'Transfer timed out',
    'version': 'Version',
    'mv_unit': 'mV',
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

class SurveyData {
  final List<int> sites; // X axis
  final List<double> freqs; // Y axis ascending (row 0 = lowest freq = deepest)
  final List<List<double>> matrix; // matrix[freqIndex][siteIndex] = mV
  final double min, max, mean;
  SurveyData(this.sites, this.freqs, this.matrix, this.min, this.max, this.mean);

  static SurveyData parse(String csvText) {
    final rows = const CsvToListConverter(eol: '\n', shouldParseNumbers: true)
        .convert(csvText.replaceAll('\r', ''));
    final vals = <String, double>{};
    final siteSet = <int>{};
    final freqSet = <double>{};
    for (final r in rows) {
      if (r.length < 4) continue;
      final site = num.tryParse(r[1].toString());
      final freq = num.tryParse(r[2].toString());
      final v = num.tryParse(r[3].toString());
      if (site == null || freq == null || v == null) continue; // header / junk
      siteSet.add(site.toInt());
      freqSet.add(freq.toDouble());
      vals['${site.toInt()}|${freq.toDouble()}'] = v.toDouble();
    }
    if (vals.isEmpty) throw Exception(tr('no_rows'));
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
    return SurveyData(sites, freqs, m, all.reduce(math.min), all.reduce(math.max), mean);
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
}

// ───────────────────────── COLOR + INTERPOLATION ─────────────────────────
Color coolwarm(double t) {
  t = t.clamp(0.0, 1.0);
  const c0 = Color(0xFF3B4CC0), c1 = Color(0xFFDDDDDD), c2 = Color(0xFFB40426);
  return t < 0.5 ? Color.lerp(c0, c1, t * 2)! : Color.lerp(c1, c2, (t - 0.5) * 2)!;
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
class HeatmapPainter extends CustomPainter {
  final SurveyData data;
  final bool smooth;
  final int? selSi, selFi;
  final String lang = appLang;
  HeatmapPainter(this.data, this.smooth, this.selSi, this.selFi);

  static Rect plotRect(Size s) => Rect.fromLTRB(46, 8, s.width - 8, s.height - 30);

  void _text(Canvas c, String s, Offset o,
      {bool centerX = false, bool right = false, bool centerY = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(fontSize: 10, color: Colors.black87)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = o.dx, dy = o.dy;
    if (centerX) dx -= tp.width / 2;
    if (right) dx -= tp.width;
    if (centerY) dy -= tp.height / 2;
    tp.paint(c, Offset(dx, dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const step = 3.0;
    final plot = plotRect(size);
    final rows = data.freqs.length, cols = data.sites.length;
    final range = (data.max - data.min).abs() < 1e-9 ? 1.0 : data.max - data.min;
    final p = Paint();

    for (double py = 0; py < plot.height; py += step) {
      for (double px = 0; px < plot.width; px += step) {
        var gx = cols == 1 ? 0.0 : (px + step / 2) / plot.width * (cols - 1);
        // Y inverted: top of the plot = highest frequency, row 0 (lowest freq) at the bottom
        var gy = rows == 1 ? 0.0 : (plot.height - py - step / 2) / plot.height * (rows - 1);
        if (!smooth) {
          gx = gx.roundToDouble();
          gy = gy.roundToDouble();
        }
        final v = bilinear(data.matrix, gx, gy);
        p.color = coolwarm((v - data.min) / range);
        canvas.drawRect(
            Rect.fromLTWH(plot.left + px, plot.top + py, math.min(step, plot.width - px) + 0.5,
                math.min(step, plot.height - py) + 0.5),
            p);
      }
    }
    canvas.drawRect(plot, Paint()..style = PaintingStyle.stroke..color = Colors.black54);

    final xTicks = math.min(cols, 8);
    for (var i = 0; i < xTicks; i++) {
      final idx = xTicks == 1 ? 0 : (i * (cols - 1) / (xTicks - 1)).round();
      final x = cols == 1 ? plot.center.dx : plot.left + idx / (cols - 1) * plot.width;
      _text(canvas, '${data.sites[idx]}', Offset(x, plot.bottom + 3), centerX: true);
    }
    _text(canvas, tr('site'), Offset(plot.center.dx, plot.bottom + 15), centerX: true);

    final yTicks = math.min(rows, 10);
    for (var i = 0; i < yTicks; i++) {
      final idx = yTicks == 1 ? 0 : (i * (rows - 1) / (yTicks - 1)).round();
      final y = rows == 1 ? plot.center.dy : plot.bottom - idx / (rows - 1) * plot.height;
      _text(canvas, '${data.freqs[idx].toStringAsFixed(0)} Hz', Offset(plot.left - 4, y),
          right: true, centerY: true);
    }

    if (selSi != null && selFi != null) {
      final x = cols == 1 ? plot.center.dx : plot.left + selSi! / (cols - 1) * plot.width;
      final y = rows == 1 ? plot.center.dy : plot.bottom - selFi! / (rows - 1) * plot.height;
      canvas.drawCircle(Offset(x, y), 7, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 7,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.black);
    }
  }

  @override
  bool shouldRepaint(covariant HeatmapPainter old) =>
      old.data != data ||
      old.smooth != smooth ||
      old.selSi != selSi ||
      old.selFi != selFi ||
      old.lang != lang;
}

class ColorBarLegend extends StatelessWidget {
  final SurveyData data;
  const ColorBarLegend({super.key, required this.data});
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
          Text('${data.min.toStringAsFixed(1)} mV', style: const TextStyle(color: Colors.black87)),
          Text('${data.max.toStringAsFixed(1)} mV', style: const TextStyle(color: Colors.black87)),
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

  void refresh() => notifyListeners();

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('lang');
    appLang = saved ?? 'ar';
    langNotifier.value = appLang;
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
    if (currentFile?.path == f.path) {
      currentFile = null;
      data = null;
    }
    await loadLocalFiles();
  }

  Future<String?> generateMap() async {
    try {
      data = SurveyData.parse(await currentFile!.readAsString());
      notifyListeners();
      return null;
    } catch (e) {
      return errText(e);
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
  bool smooth = true;
  int? selSi, selFi;

  @override
  void initState() {
    super.initState();
    widget.app.loadLocalFiles();
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
      setState(() {
        selSi = null;
        selFi = null;
      });
    }
  }

  List<Widget> _mapSection(SurveyData d, String name) {
    final zones = d.bestZones();
    String zoneText(Zone z) => tr('zone_item')
        .replaceAll('{s}', '${d.sites[z.si]}')
        .replaceAll('{f}', d.freqs[z.fi].toStringAsFixed(0))
        .replaceAll('{v}', z.v.toStringAsFixed(1));

    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('smooth')),
        value: smooth,
        onChanged: (v) => setState(() => smooth = v),
      ),
      RepaintBoundary(
        key: _boundaryKey,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 6),
            SizedBox(
              height: 340,
              child: LayoutBuilder(builder: (ctx, cons) {
                final size = Size(cons.maxWidth, cons.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (t) => _pick(d, t.localPosition, size),
                  child: CustomPaint(size: size, painter: HeatmapPainter(d, smooth, selSi, selFi)),
                );
              }),
            ),
            const SizedBox(height: 8),
            ColorBarLegend(data: d),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          leading: const Icon(Icons.touch_app),
          title: Text(selSi == null
              ? tr('tap_hint')
              : tr('picked')
                  .replaceAll('{s}', '${d.sites[selSi!]}')
                  .replaceAll('{f}', d.freqs[selFi!].toStringAsFixed(0))
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
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        child: FilledButton.tonalIcon(
          onPressed: _share,
          icon: const Icon(Icons.share),
          label: Text(tr('share_map')),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final file = app.currentFile;
        return ListView(padding: const EdgeInsets.all(16), children: [
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                final msg = await app.importCsv();
                setState(() {
                  selSi = null;
                  selFi = null;
                });
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
                  leading: Icon(
                      f.path == file?.path ? Icons.radio_button_checked : Icons.radio_button_off),
                  title: Text(f.path.split('/').last),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tr('delete'),
                    onPressed: () => _confirmDelete(f),
                  ),
                  onTap: () {
                    app.selectLocal(f);
                    setState(() {
                      selSi = null;
                      selFi = null;
                    });
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
                onPressed: () async {
                  final err = await app.generateMap();
                  setState(() {
                    selSi = null;
                    selFi = null;
                  });
                  widget.toast(err);
                },
                icon: const Icon(Icons.grid_on),
                label: Text(tr('generate_map'), style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 8),
            if (app.data != null) ..._mapSection(app.data!, file.path.split('/').last),
          ],
        ]);
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
