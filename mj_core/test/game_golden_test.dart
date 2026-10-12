/// Replays fixtures/game_golden.json (contract game/l1policy/v1): 24 full
/// self-play games (seeds 5000.., jokers 0/4/8 × swap off/fixed3/dice,
/// rotating dealer and repeat_n) with four L1Policy bots, and demands the
/// entire event log plus the final result (winners, deltas, ledger,
/// dealer_repeats) match the Python reference engine bit-for-bit.
///
/// Fan lists inside win events / winner results are order-normalized
/// (Python's sorted-triples convention) on both sides before comparing.
import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

/// Normalize an event for comparison: sort 'fans' on win events.
Map<String, dynamic> normEvent(Map<String, dynamic> e) {
  if (e['type'] == 'win' && e['fans'] is List) {
    return {
      ...e,
      'fans': sortedFans([for (final f in e['fans'] as List) f as List]),
    };
  }
  return e;
}

void main() {
  late FanTable table;
  late Map<String, dynamic> golden;

  setUpAll(() {
    table = FanTable.fromJsonString(
        File('../data/fan_table.json').readAsStringSync());
    golden = loadFixture('game_golden.json');
    expect(golden['contract'], 'game/l1policy/v1');
  });

  test('all self-play games match the Python reference engine', () async {
    for (final caseJson in golden['cases'] as List) {
      final c = caseJson as Map<String, dynamic>;
      final seed = c['seed'] as int;
      final label = 'seed=$seed jokers=${c['jokers']} swap=${c['swap']}';
      final led = LaLedger(table.settlement.laLedger);
      final eng = Engine(seed, table,
          opts: EngineOptions(
              jokers: c['jokers'] as int, swap: c['swap'] as String),
          dealer: c['dealer'] as int,
          repeatN: c['repeat_n'] as int,
          ledger: led);
      final res = await eng.play([for (var i = 0; i < 4; i++) L1Policy()]);

      // ── event log ────────────────────────────────────────────────────
      final wantEvents = c['events'] as List;
      expect(eng.events.length, wantEvents.length,
          reason: '$label: event count '
              '(got ${eng.events.length}, want ${wantEvents.length})\n'
              'first got  ${pretty(eng.events.take(6).toList())}\n'
              'first want ${pretty(wantEvents.take(6).toList())}');
      for (var i = 0; i < wantEvents.length; i++) {
        final got = normEvent(eng.events[i]);
        final want = normEvent(
            Map<String, dynamic>.from(wantEvents[i] as Map));
        expect(deepEq(got, want), isTrue,
            reason: '$label event $i\nwant ${pretty(want)}\ngot  ${pretty(got)}');
      }

      // ── result ───────────────────────────────────────────────────────
      final wantRes = c['result'] as Map<String, dynamic>;
      final ledKeys = led.led.keys.toList()
        ..sort((a, b) =>
            a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
      final gotRes = <String, dynamic>{
        'kind': res.kind,
        'deltas': [for (final d in eng.deltas) d.toJson()],
        'ledger': {
          for (final k in ledKeys)
            '${k.$1},${k.$2}': {
              'amount': led.led[k]!.amount,
              'kou': led.led[k]!.kou
            }
        },
        'dealer_repeats': res.dealerRepeats,
      };
      if (res.kind == 'win') {
        gotRes['winners'] = [
          for (final (w, r) in res.winners)
            [
              w,
              {
                'total': r.total,
                'form': r.form,
                'fans': sortedFans([
                  for (final (f, n, p) in r.fans) [f, n, p]
                ]),
              }
            ]
        ];
        gotRes['discarder'] = res.discarder;
      }
      expect(deepEq(gotRes, wantRes), isTrue,
          reason: '$label result\nwant ${pretty(wantRes)}\ngot  ${pretty(gotRes)}');
    }
  });
}
