/// Settlement + 拉/踢半 ledger — line-for-line port of ref_engine/settle.py.
///
/// Money model (03-SCORING-SETTLEMENT.md + fan_table.json settlement):
///  * 全銃制: 出銃 pays the winner's full total; 自摸 = each of the other
///    three pays the full total.
///  * 1番 = 1分 for win totals; 底 (=5分) is the unit for 中途獎勵.
///  * 莊家 adjustment is PER PAIR: any payment line involving the dealer
///    gains (dealerBonusFan + laZhuangFanPerN × repeatN) 番. The engine
///    must NOT set ctx.dealer/dealerRepeatN on the recognizer — the
///    fan-table `dealer`/`dealer_repeat` entries are display aliases of
///    this same adjustment, never double-counted.
///  * 拉 ledger (toggle ON): 出銃 amounts are recorded, not paid.
///    Compounds ×1.5 (ceil) when the same creditor wins off the same
///    debtor again; debtor escaping (win off creditor / 自摸) pays half,
///    floor (踢半); creditor winning elsewhere / debtor 出銃 elsewhere ⇒
///    collect in full.
///  * 斬拉 (kou ≥ 3, debtor's option between 局): settle full, clear.
///  * Match end: unresolved ledgers are WIPED (Keith 2026-07-07).
///  * 花糊 (七搶一/兩台花) 該得點拉落下一鋪 when flowerWinLa; 暗槓 reward
///    is instant.
library;

import 'fan_table.dart';

class Delta {
  final int frm; // seat paying
  final int to; // seat receiving
  final int amount; // 分
  final String reason;
  final bool la; // true = record to LaLedger instead of paying

  const Delta(this.frm, this.to, this.amount, this.reason, {this.la = false});

  Map<String, dynamic> toJson() =>
      {'frm': frm, 'to': to, 'amount': amount, 'reason': reason, 'la': la};

  @override
  String toString() => '$frm→$to $amount ($reason${la ? ", la" : ""})';
}

int _dealerAdj(SettlementConfig cfg, int dealer, int repeatN, int a, int b) {
  if (dealer == a || dealer == b) {
    return cfg.dealerBonusFan + cfg.laZhuangFanPerN * repeatN;
  }
  return 0;
}

/// Payment lines for one win. [discarder] null ⇒ 自摸 (3 payers).
/// With [laOn], 出銃 lines are marked la=true (recorded, not paid).
List<Delta> winDeltas(int totalFan, int winner, int? discarder, int dealer,
    int repeatN, SettlementConfig cfg,
    {bool laOn = false}) {
  final deltas = <Delta>[];
  if (discarder == null) {
    for (var p = 0; p < 4; p++) {
      if (p == winner) continue;
      final amt = totalFan + _dealerAdj(cfg, dealer, repeatN, winner, p);
      deltas.add(Delta(p, winner, amt, 'self_draw'));
    }
  } else {
    final amt =
        totalFan + _dealerAdj(cfg, dealer, repeatN, winner, discarder);
    deltas.add(Delta(discarder, winner, amt, 'discard_win', la: laOn));
  }
  return deltas;
}

/// 中途獎勵. [kind]: concealed_kong | seven_rob_one | two_tai_flower.
/// 七搶一 comes from the flower-drawer ([source]); the other two from
/// every other player. 花糊 rewards are 拉'd when flowerWinLa.
List<Delta> midwayDeltas(String kind, int seat, SettlementConfig cfg,
    {int? source}) {
  final di = cfg.diBase;
  final mw = cfg.midwayRewards;
  final la = cfg.flowerWinLa;
  switch (kind) {
    case 'concealed_kong':
      final amt = mw.concealedKongDiPerPlayer * di;
      return [
        for (var p = 0; p < 4; p++)
          if (p != seat) Delta(p, seat, amt, kind)
      ];
    case 'seven_rob_one':
      return [Delta(source!, seat, mw.sevenRobOneDi * di, kind, la: la)];
    case 'two_tai_flower':
      final amt = mw.twoTaiFlowerDiPerPlayer * di;
      return [
        for (var p = 0; p < 4; p++)
          if (p != seat) Delta(p, seat, amt, kind, la: la)
      ];
  }
  throw ArgumentError.value(kind);
}

class LedgerEntry {
  int amount;
  int kou;
  LedgerEntry(this.amount, this.kou);
}

/// 拉/踢半 ledger. Keys are (creditor, debtor) ordered pairs.
/// Iteration order = insertion order (matches the Python dict reference).
class LaLedger {
  final LaLedgerConfig cfg;
  final Map<(int, int), LedgerEntry> led = {};

  LaLedger(this.cfg);

  void record(int creditor, int debtor, int amount) {
    final key = (creditor, debtor);
    final cur = led[key];
    if (cur == null) {
      led[key] = LedgerEntry(amount, 1);
    } else {
      final compRaw = cur.amount * cfg.compound;
      final comp = cfg.roundUpOnWin ? compRaw.ceil() : compRaw.floor();
      cur.amount = comp + amount;
      cur.kou += 1;
    }
  }

  /// Apply the resolution table for one win event. Returns instant Deltas.
  /// The NEW win amount itself is handled by the caller (record() for
  /// 出銃, instant for 自摸).
  List<Delta> resolveOnWin(int winner, int? discarder) {
    final out = <Delta>[];
    for (final key in led.keys.toList()) {
      final (c, d) = key;
      final amt = led[key]!.amount;
      if (winner == c && discarder == d) {
        continue; // compounding via record()
      }
      if (winner == c) {
        // creditor wins elsewhere / 自摸
        out.add(Delta(d, c, amt, 'la_collect'));
        led.remove(key);
      } else if (winner == d && (discarder == c || discarder == null)) {
        // 踢半
        final half = cfg.kickHalfRoundDown ? amt ~/ 2 : (amt + 1) ~/ 2;
        out.add(Delta(d, c, half, 'la_kick_half'));
        led.remove(key);
      } else if (discarder == d) {
        // debtor 出銃 elsewhere
        out.add(Delta(d, c, amt, 'la_collect'));
        led.remove(key);
      }
    }
    return out;
  }

  /// 斬拉: debtor settles the full recorded amount (kou≥3 gate is
  /// UI-side). Returns the instant Delta.
  Delta zhanLa(int creditor, int debtor) {
    final rec = led.remove((creditor, debtor))!;
    return Delta(debtor, creditor, rec.amount, 'la_zhan');
  }

  bool canZhan(int creditor, int debtor) {
    final rec = led[(creditor, debtor)];
    return rec != null && rec.kou >= 3;
  }

  /// matchEndPolicy 'wipe': cancel everything, return the wiped entries
  /// for the struck-through UI panel: (creditor, debtor, amount, kou).
  List<(int, int, int, int)> matchEnd() {
    final wiped = [
      for (final e in led.entries)
        (e.key.$1, e.key.$2, e.value.amount, e.value.kou)
    ];
    led.clear();
    return wiped;
  }
}

/// Full settlement of one win: returns the instant Deltas.
/// If [ledger] is provided (拉 ON), 出銃 amounts are recorded there
/// instead of paid, and existing ledgers resolve per the table.
/// Multi-winner: call once per winner, in seat order from the
/// discarder's 下家 (R2).
List<Delta> settleWin(int totalFan, int winner, int? discarder, int dealer,
    int repeatN, LaLedger? ledger, SettlementConfig cfg) {
  final laOn = ledger != null;
  final instant = <Delta>[];
  if (laOn) instant.addAll(ledger.resolveOnWin(winner, discarder));
  for (final dl in winDeltas(totalFan, winner, discarder, dealer, repeatN,
      cfg,
      laOn: laOn)) {
    if (dl.la) {
      ledger!.record(dl.to, dl.frm, dl.amount);
    } else {
      instant.add(dl);
    }
  }
  return instant;
}
