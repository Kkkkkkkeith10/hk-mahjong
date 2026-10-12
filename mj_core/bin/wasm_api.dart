/// WASM entry point for the multiplayer edge function.
///
/// Compiled with `dart compile wasm` (build_wasm.bat) and loaded by the
/// Supabase Deno edge function. dart2wasm preserves native 64-bit int
/// semantics, so SplitMix64 replays are bit-for-bit identical to the
/// golden-fixture-tested VM engine (dart2js would NOT be — do not switch
/// compilers without regenerating and re-verifying every fixture).
///
/// Protocol: main() attaches `globalThis.mjHandle(reqJson) -> Promise<string>`.
/// Request (all ops):
///   { op, fan_table?, rules, human_seats, actions, seat? }
/// - fan_table: full fan_table.json text; cached, so only the first call
///   after a cold start must include it.
/// - rules: MatchRules JSON (seed/total_hands/jokers/swap/la_on).
/// - actions: ordered SeatAction log [{seat,type,value}, ...].
/// Ops:
/// - 'state'    -> { ok, ...meta, view } redacted clientView for `seat`.
/// - 'validate' -> { ok, ...meta }; a ReplayException (bad/illegal action)
///                 comes back as { ok:false, error:'replay', message }.
/// - 'bot'      -> { ok, ...meta, bot_action } L1 answer for the pending
///                 prompt (turn-timer expiry / grace AI takeover).
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe'; // JSObject.setProperty

import 'package:mj_core/mj_core.dart';

FanTable? _table;
String? _tableSrc;

void main() {
  globalContext.setProperty(
      'mjHandle'.toJS,
      ((JSString req) => _run(req.toDart).toJS).toJS);
}

Future<JSString> _run(String reqJson) async {
  try {
    final req = jsonDecode(reqJson) as Map<String, dynamic>;
    return jsonEncode(await _dispatch(req)).toJS;
  } on ReplayException catch (e) {
    return jsonEncode(
        {'ok': false, 'error': 'replay', 'message': '$e'}).toJS;
  } catch (e) {
    return jsonEncode(
        {'ok': false, 'error': 'internal', 'message': '$e'}).toJS;
  }
}

Future<Map<String, dynamic>> _dispatch(Map<String, dynamic> req) async {
  final ft = req['fan_table'] as String?;
  if (ft != null && ft != _tableSrc) {
    _table = FanTable.fromJsonString(ft);
    _tableSrc = ft;
  }
  final table = _table;
  if (table == null) {
    throw StateError('fan_table not loaded (cold start needs fan_table)');
  }
  final rules = MatchRules.fromJson(
      (req['rules'] as Map).cast<String, dynamic>());
  final humans = (req['human_seats'] as List).cast<int>().toSet();
  final actions = [
    for (final a in req['actions'] as List)
      SeatAction.fromJson((a as Map).cast<String, dynamic>())
  ];
  final snap = await MatchDriver(table, rules, humans).run(actions);
  final meta = <String, dynamic>{
    'ok': true,
    'match_over': snap.matchOver,
    'pending_seat': snap.pending?.seat,
    'pending_type': snap.pending?.type,
    'scores': snap.scores,
    'hand_no': snap.handNo,
  };
  switch (req['op'] as String) {
    case 'state':
      return {...meta, 'view': clientView(snap, req['seat'] as int)};
    case 'validate':
      return meta;
    case 'bot':
      final p = snap.pending;
      if (p == null) return {...meta, 'bot_action': null};
      return {
        ...meta,
        'bot_action':
            SeatAction(p.seat, p.type, botAnswerFor(snap, p)).toJson(),
      };
    default:
      throw ArgumentError("unknown op '${req['op']}'");
  }
}
