/// App-wide persisted settings + custom 番表 overrides.
///
/// Backed by shared_preferences. Two stores:
/// - simple prefs: bot pacing, sound toggle
/// - fan overrides: JSON map of id → [enabled, value] diffs vs the official
///   table, re-applied to the working FanTable at boot and saved on every
///   editor change. 還原官方 clears the diff.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mj_core/mj_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kBotDelay = 'botDelayMs';
  static const _kSound = 'soundOn';
  static const _kFanOverrides = 'fanOverrides/v1';

  SharedPreferences? _prefs;

  int botDelayMs = 550; // 快300 / 中550 / 慢900
  bool soundOn = true; // sound pack lands later; toggle persists now

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    botDelayMs = p.getInt(_kBotDelay) ?? 550;
    soundOn = p.getBool(_kSound) ?? true;
  }

  Future<void> setBotDelayMs(int v) async {
    botDelayMs = v;
    notifyListeners();
    await _prefs?.setInt(_kBotDelay, v);
  }

  Future<void> setSoundOn(bool v) async {
    soundOn = v;
    notifyListeners();
    await _prefs?.setBool(_kSound, v);
  }

  // ── 番表 overrides ────────────────────────────────────────────────────
  /// Re-apply saved diffs onto [working]. Unknown ids (from an older app
  /// version whose table had different entries) are ignored.
  void applyFanOverrides(FanTable working) {
    final raw = _prefs?.getString(_kFanOverrides);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in m.entries) {
        final e = working.byId[entry.key];
        if (e == null) continue;
        final v = entry.value as List;
        e.enabled = v[0] as bool;
        e.value = v[1] as int;
      }
    } catch (_) {
      // corrupt blob → drop it rather than crash the boot
      _prefs?.remove(_kFanOverrides);
    }
  }

  /// Persist the diff of [working] vs [official] (empty diff = remove key).
  Future<void> saveFanOverrides(FanTable working, FanTable official) async {
    final diff = <String, List<Object>>{};
    for (final e in working.entries) {
      final o = official.byId[e.id]!;
      if (e.enabled != o.enabled || e.value != o.value) {
        diff[e.id] = [e.enabled, e.value];
      }
    }
    if (diff.isEmpty) {
      await _prefs?.remove(_kFanOverrides);
    } else {
      await _prefs?.setString(_kFanOverrides, jsonEncode(diff));
    }
  }
}
