import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

void main() {
  late FanTable table;

  setUpAll(() {
    // Repo layout: mj_core/ and data/ are siblings under mj-game/.
    table =
        FanTable.fromJsonString(File('../data/fan_table.json').readAsStringSync());
  });

  test('loads all 153 entries with valid references', () {
    expect(table.entries.length, 153);
  });

  test('spot-check values against 總例 p.18 (300dpi verified 2026-07-07)', () {
    int v(String id) => table.byId[id]!.value;
    expect(v('ting'), 5);
    expect(v('mun_ting'), 15);
    expect(v('thirteen_orphans'), 120); // 十三么
    expect(v('pure_terminals'), 420); // 清么
    expect(v('all_concealed_triplets'), 240); // 坎坎糊
    expect(v('big_four_winds'), 180); // 大四喜
    expect(v('all_honors'), 240); // 字一色
    expect(v('pure_one_suit'), 120); // 清一色
    expect(v('open_pure_triple_seq'), 30); // 明一色三同順 (the zoomed cell)
    expect(v('eight_immortals'), 40); // 八仙過海
    expect(v('seven_rob_one'), 30); // 七搶一 = 6底 = 30分
    expect(table.settlement.diBase * 6, v('seven_rob_one')); // 1底=5分 cross-check
  });

  test('formula entries evaluate per 總例', () {
    final laZhuang = table.byId['dealer_repeat']!.formula!; // 拉莊 2n
    expect(laZhuang.evaluate(1), 2);
    expect(laZhuang.evaluate(3), 6);
    // 尾牌連摸 5×2^(n-1), n = chain length (Python reference convention;
    // the engine awards it with n = tail_chain ≥ 2)
    final tail = table.byId['tail_chain_draw']!.formula!;
    expect(tail.evaluate(1), 5);
    expect(tail.evaluate(2), 10);
    expect(tail.evaluate(3), 20);
  });

  test('settlement block carries locked decisions', () {
    expect(table.settlement.payment, '全銃制');
    expect(table.settlement.selfDrawMultiplier, 3);
    expect(table.settlement.cap, isNull);
    expect(table.settlement.diBase, 5);
    expect(table.settlement.laLedger.matchEndPolicy, 'wipe'); // 2026-07-07
    expect(table.settlement.laLedger.compound, 1.5);
  });

  test('requires-chain: disabling 十六不搭 deactivates its dependents', () {
    expect(table.isActive('disjoint_mixed_dragon'), isTrue);
    table.byId['sixteen_disjoint']!.enabled = false;
    expect(table.isActive('disjoint_mixed_dragon'), isFalse);
    expect(table.isActive('sixteen_gates_disjoint'), isFalse);
    table.byId['sixteen_disjoint']!.enabled = true; // restore
  });

  test('corrupt table fails fast', () {
    expect(() => FanTable.fromJsonString('{"schema":"fan_table/v2"}'),
        throwsFormatException);
  });
}
