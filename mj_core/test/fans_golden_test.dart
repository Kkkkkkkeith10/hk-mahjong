/// Replays fixtures/fans_golden.json (contract fans/v1, 414 cases:
/// 總例 p.11 worked examples + special forms + self-play harvested wins)
/// through the Dart scorer and demands identical (total, form, fans).
import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

Ctx ctxFromJson(Map<String, dynamic> j) => Ctx(
      counts: List<int>.from(j['counts'] as List),
      jokers: j['jokers'] as int,
      exposed: [
        for (final e in j['exposed'] as List)
          ((e as List)[0] as int, e[1] as String)
      ],
      winKind: j['win_kind'] as int,
      winMethod: j['win_method'] as String,
      flowers: List<int>.from(j['flowers'] as List),
      seat: j['seat'] as int,
      dealer: j['dealer'] as bool,
      dealerRepeatN: j['dealer_repeat_n'] as int,
      ting: j['ting'] as bool,
      tingClass: j['ting_class'] as String,
      instantEat: j['instant_eat'] as bool,
      lastTile: j['last_tile'] as bool,
      flowerDraw: j['flower_draw'] as bool,
      kongDraw: j['kong_draw'] as bool,
      tailChainN: j['tail_chain_n'] as int,
      multiWin: j['multi_win'] as int,
      winClass: j['win_class'] as String,
      sevenRobOne: j['seven_rob_one'] as bool,
      jokerInEye: j['joker_in_eye'] as bool,
    );

void main() {
  late FanTable table;
  late Map<String, dynamic> golden;

  setUpAll(() {
    table = FanTable.fromJsonString(
        File('../data/fan_table.json').readAsStringSync());
    golden = loadFixture('fans_golden.json');
    expect(golden['contract'], 'fans/v1');
  });

  test('all cases match the Python reference scorer', () {
    final cases = golden['cases'] as List;
    expect(cases.length, greaterThanOrEqualTo(400));
    for (var i = 0; i < cases.length; i++) {
      final c = cases[i] as Map<String, dynamic>;
      final expectMap = c['expect'] as Map<String, dynamic>;
      final r = scoreWin(ctxFromJson(c['ctx'] as Map<String, dynamic>), table);
      expect(r.notAWin, isFalse, reason: 'case $i: scored not-a-win');
      final got = {
        'total': r.total,
        'form': r.form,
        'fans': sortedFans([
          for (final (f, n, p) in r.fans) [f, n, p]
        ]),
      };
      final want = {
        'total': expectMap['total'],
        'form': expectMap['form'],
        'fans': sortedFans([for (final f in expectMap['fans'] as List) f as List]),
      };
      expect(deepEq(got, want), isTrue,
          reason: 'case $i mismatch\nwant ${pretty(want)}\ngot  ${pretty(got)}'
              '\nctx  ${pretty(c['ctx'])}');
    }
  });
}
