/// FanTable — the editable 番種 registry loaded from fan_table.json.
///
/// The JSON asset (schema fan_table/v1, 153 entries transcribed from the
/// 總例 p.18 番種簡表) lives at data/fan_table.json in the repo and is
/// embedded/copied by each consumer. This loader validates it on load so a
/// corrupt or hand-edited table fails fast, not mid-hand.
library;

import 'dart:convert';

class FanFormula {
  final String type; // 'linear' | 'geometric'
  final int coef; // linear: value = coef * n
  final int base; // geometric: value = base * ratio^n
  final int ratio;

  const FanFormula._(this.type, this.coef, this.base, this.ratio);

  factory FanFormula.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String;
    return switch (type) {
      'linear' => FanFormula._(type, j['coef'] as int, 0, 0),
      'geometric' =>
        FanFormula._(type, 0, j['base'] as int, j['ratio'] as int),
      _ => throw FormatException('unknown formula type: $type'),
    };
  }

  /// linear: coef*n. geometric: base*ratio^(n-1) — n=1 pays the base
  /// (e.g. tail_chain_draw 5/10/20…). Matches the Python reference
  /// (fans.FanTable.value); fixture-tested.
  int evaluate(int n) => switch (type) {
        'linear' => coef * n,
        'geometric' => base * _pow(ratio, n - 1),
        _ => throw StateError('unreachable'),
      };

  static int _pow(int b, int e) {
    var r = 1;
    for (var i = 0; i < e; i++) {
      r *= b;
    }
    return r;
  }
}

class FanEntry {
  final String id;
  final String name;
  final String category;
  int value; // mutable: the 番表 editor adjusts flat values on a working copy
  final FanFormula? formula;
  final bool editable;
  bool enabled;
  final List<String> suppresses;
  final List<String> requires;
  final List<String> stacksWith;
  final String detector;
  final String notes;

  FanEntry.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String,
        category = j['category'] as String,
        value = j['value'] as int,
        formula = j['formula'] == null
            ? null
            : FanFormula.fromJson(j['formula'] as Map<String, dynamic>),
        editable = j['editable'] as bool,
        enabled = j['enabled'] as bool,
        suppresses = (j['suppresses'] as List).cast<String>(),
        requires = (j['requires'] as List).cast<String>(),
        stacksWith = (j['stacksWith'] as List).cast<String>(),
        detector = j['detector'] as String,
        notes = (j['notes'] as String?) ?? '';
}

class LaLedgerConfig {
  final double compound; // 1.5
  final bool roundUpOnWin;
  final bool kickHalfRoundDown;
  final String matchEndPolicy; // 'wipe' | 'full' | 'half'  (DECIDED: wipe)

  const LaLedgerConfig(this.compound, this.roundUpOnWin,
      this.kickHalfRoundDown, this.matchEndPolicy);
}

class MidwayRewards {
  final int concealedKongDiPerPlayer; // 暗槓: 1底/家, instant
  final int sevenRobOneDi; // 七搶一: 6底 from the victim
  final int twoTaiFlowerDiPerPlayer; // 八仙過海: 8底/家

  const MidwayRewards(this.concealedKongDiPerPlayer, this.sevenRobOneDi,
      this.twoTaiFlowerDiPerPlayer);
}

class SettlementConfig {
  final String payment; // 全銃制
  final int selfDrawMultiplier; // 3
  final int? cap; // null = 不設上限
  final int diBase; // 1底 = 5分
  final int dealerBonusFan; // 莊家 1
  final int laZhuangFanPerN; // 拉N莊 2N
  final LaLedgerConfig laLedger;
  final bool flowerWinLa; // 花糊該得點拉落下一鋪 (總例 p.9)
  final MidwayRewards midwayRewards;

  const SettlementConfig(
      this.payment,
      this.selfDrawMultiplier,
      this.cap,
      this.diBase,
      this.dealerBonusFan,
      this.laZhuangFanPerN,
      this.laLedger,
      this.flowerWinLa,
      this.midwayRewards);

  factory SettlementConfig.fromJson(Map<String, dynamic> j) {
    final la = j['laLedger'] as Map<String, dynamic>;
    final mw = j['midwayRewards'] as Map<String, dynamic>;
    return SettlementConfig(
      j['payment'] as String,
      j['selfDrawMultiplier'] as int,
      j['cap'] as int?,
      j['diBase'] as int,
      j['dealerBonusFan'] as int,
      j['laZhuangFanPerN'] as int,
      LaLedgerConfig(
        (la['compound'] as num).toDouble(),
        la['roundUpOnWin'] as bool,
        la['kickHalfRoundDown'] as bool,
        la['matchEndPolicy'] as String,
      ),
      j['flowerWinLa'] as bool,
      MidwayRewards(
        mw['concealedKongDiPerPlayer'] as int,
        mw['sevenRobOneDi'] as int,
        mw['twoTaiFlowerDiPerPlayer'] as int,
      ),
    );
  }
}

class FanTable {
  final String schema;
  final SettlementConfig settlement;
  final List<FanEntry> entries;
  final Map<String, FanEntry> byId;
  late final Map<String, Set<String>> _sup; // transitive suppresses closure

  FanTable._(this.schema, this.settlement, this.entries)
      : byId = {for (final e in entries) e.id: e} {
    _sup = {};
    for (final e in entries) {
      final seen = <String>{};
      final stack = [...e.suppresses];
      while (stack.isNotEmpty) {
        final s = stack.removeLast();
        if (!seen.add(s)) continue;
        stack.addAll(byId[s]!.suppresses);
      }
      _sup[e.id] = seen;
    }
  }

  /// Point value of [id] awarded [n] times (mirrors Python
  /// fans.FanTable.value): formula entries evaluate the formula, flat
  /// entries return the single value — the caller multiplies flat values
  /// by n (see _points in fans.dart).
  int value(String id, [int n = 1]) {
    final e = byId[id]!;
    final f = e.formula;
    if (f != null) return f.evaluate(n);
    return e.value;
  }

  bool enabled(String id) => byId[id]!.enabled;

  /// All fan ids transitively suppressed by [id] (不複合 alternatives).
  Set<String> suppressedBy(String id) => _sup[id]!;

  /// Parse + validate. Throws [FormatException] on any integrity problem.
  factory FanTable.fromJsonString(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final schema = root['schema'] as String;
    if (schema != 'fan_table/v1') {
      throw FormatException('unsupported schema: $schema');
    }
    final settlement =
        SettlementConfig.fromJson(root['settlement'] as Map<String, dynamic>);
    final entries = [
      for (final e in root['entries'] as List)
        FanEntry.fromJson(e as Map<String, dynamic>)
    ];
    final table = FanTable._(schema, settlement, entries);
    table._validate();
    return table;
  }

  void _validate() {
    final ids = <String>{};
    for (final e in entries) {
      if (!ids.add(e.id)) throw FormatException('duplicate id: ${e.id}');
      if (e.value < 0) throw FormatException('${e.id}: negative value');
      if (e.detector != e.id) {
        throw FormatException('${e.id}: detector mismatch');
      }
    }
    for (final e in entries) {
      for (final ref in [...e.suppresses, ...e.requires, ...e.stacksWith]) {
        if (!ids.contains(ref)) {
          throw FormatException('${e.id}: unknown reference $ref');
        }
      }
    }
    if (!const ['wipe', 'full', 'half']
        .contains(settlement.laLedger.matchEndPolicy)) {
      throw FormatException(
          'bad matchEndPolicy: ${settlement.laLedger.matchEndPolicy}');
    }
  }

  /// Entries visible in the editor given current enables (requires-chain:
  /// an entry whose requirement is disabled is hidden and inert).
  bool isActive(String id) {
    final e = byId[id];
    if (e == null || !e.enabled) return false;
    return e.requires.every(isActive);
  }
}
