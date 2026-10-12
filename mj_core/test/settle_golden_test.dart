/// Replays fixtures/settle_golden.json (contract settle/v1): 8 scripted
/// LaLedger lifecycles (record / compound / collect / kick-half / 斬拉 /
/// match-end wipe) through the Dart settlement and demands identical
/// instant deltas and ledger snapshots.
///
/// NOTE on ledger snapshots: gen_fixtures.py stores *references* to the
/// live ledger records per step and serializes at the end, so a step's
/// snapshot shows the FINAL state of any entry that survives later
/// compounding (e.g. zhan_and_wipe steps 1-3 all show amount 48, kou 3).
/// We replicate that aliasing exactly by snapshotting LedgerEntry
/// references and reading amount/kou only after the whole script ran.
import 'dart:io';

import 'package:mj_core/mj_core.dart';
import 'package:test/test.dart';

import 'golden_util.dart';

void main() {
  late FanTable table;
  late Map<String, dynamic> golden;

  setUpAll(() {
    table = FanTable.fromJsonString(
        File('../data/fan_table.json').readAsStringSync());
    golden = loadFixture('settle_golden.json');
    expect(golden['contract'], 'settle/v1');
  });

  test('all scripts match the Python reference settlement', () {
    final cfg = table.settlement;
    for (final caseJson in golden['cases'] as List) {
      final name = caseJson['name'] as String;
      final steps = caseJson['steps'] as List;
      final led = LaLedger(cfg.laLedger);
      // Per step: instant deltas / wiped tuples (value snapshots) and the
      // ledger reference snapshot (aliased, read at the end).
      final gotInstant = <int, List<Map<String, dynamic>>>{};
      final gotWiped = <int, List<List<int>>>{};
      final ledgerRefs = <int, Map<String, LedgerEntry>>{};
      for (var i = 0; i < steps.length; i++) {
        final call = (steps[i] as Map)['call'] as Map<String, dynamic>;
        if (call.containsKey('zhan')) {
          final z = call['zhan'] as List;
          final d = led.zhanLa(z[0] as int, z[1] as int);
          gotInstant[i] = [d.toJson()];
        } else if (call.containsKey('wipe')) {
          gotWiped[i] = [
            for (final (c, dd, amt, kou) in led.matchEnd()) [c, dd, amt, kou]
          ];
        } else {
          final inst = settleWin(
              call['fan'] as int,
              call['w'] as int,
              call['d'] as int?,
              call['dealer'] as int,
              call['rep'] as int,
              led,
              cfg);
          gotInstant[i] = [for (final d in inst) d.toJson()];
        }
        final keys = led.led.keys.toList()
          ..sort((a, b) =>
              a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
        ledgerRefs[i] = {
          for (final k in keys) '${k.$1},${k.$2}': led.led[k]!
        };
      }
      // Compare, reading aliased ledger entries only now (post-script).
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i] as Map<String, dynamic>;
        if (step.containsKey('instant')) {
          expect(deepEq(gotInstant[i], step['instant']), isTrue,
              reason: '$name step $i instant\nwant ${pretty(step['instant'])}'
                  '\ngot  ${pretty(gotInstant[i])}');
        }
        if (step.containsKey('wiped')) {
          expect(deepEq(gotWiped[i], step['wiped']), isTrue,
              reason: '$name step $i wiped\nwant ${pretty(step['wiped'])}'
                  '\ngot  ${pretty(gotWiped[i])}');
        }
        final gotLedger = {
          for (final e in ledgerRefs[i]!.entries)
            e.key: {'amount': e.value.amount, 'kou': e.value.kou}
        };
        expect(deepEq(gotLedger, step['ledger']), isTrue,
            reason: '$name step $i ledger\nwant ${pretty(step['ledger'])}'
                '\ngot  ${pretty(gotLedger)}');
      }
    }
  });
}
