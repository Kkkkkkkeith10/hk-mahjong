import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mj_core/mj_core.dart';

import 'model/app_settings.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // the whole app is landscape — home, setup and table share one orientation
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const MjApp());
}

/// Loads the official 番表 once; screens read/clone it from here. The
/// working copy has any saved editor overrides re-applied at boot
/// (AppSettings.applyFanOverrides) and is persisted on every editor change.
class FanTableStore extends InheritedWidget {
  final FanTable official;
  final FanTable working; // editable copy used by new rooms

  const FanTableStore(
      {super.key,
      required this.official,
      required this.working,
      required super.child});

  static FanTableStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FanTableStore>()!;

  @override
  bool updateShouldNotify(FanTableStore oldWidget) =>
      working != oldWidget.working;
}

/// Root widget. IMPORTANT: FanTableStore must wrap MaterialApp (not sit
/// below it) — pushed routes are children of the Navigator inside
/// MaterialApp, so an InheritedWidget placed under `home:` is invisible
/// to them and FanTableStore.of(context) would blow up on every screen
/// reached via Navigator.push.
class MjApp extends StatefulWidget {
  const MjApp({super.key});

  @override
  State<MjApp> createState() => _MjAppState();
}

class _MjAppState extends State<MjApp> {
  FanTable? _official;
  FanTable? _working;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await AppSettings.instance.load();
      final json = await rootBundle.loadString('assets/fan_table.json');
      final official = FanTable.fromJsonString(json);
      final working = FanTable.fromJsonString(json);
      AppSettings.instance.applyFanOverrides(working);
      setState(() {
        _official = official;
        _working = working;
      });
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Widget _app(Widget home) => MaterialApp(
        title: '香港十六張麻雀',
        debugShowCheckedModeBanner: false,
        theme: mjTheme(),
        home: home,
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _app(Scaffold(
        body: Center(child: Text('番表載入失敗：$_error')),
      ));
    }
    if (_official == null) {
      return _app(const Scaffold(
        body: Center(child: CircularProgressIndicator(color: MjColors.jade)),
      ));
    }
    return FanTableStore(
      official: _official!,
      working: _working!,
      child: _app(const HomeScreen()),
    );
  }
}
