/// 規則書 — per reference 08-rules-encyclopedia.png: two tabs —
/// 玩法概要 (rules digest written in our own words, not the 總例 text) and
/// 番種圖鑑 (searchable fan cards driven by the official FanTable).
library;

import 'package:flutter/material.dart';
import 'package:mj_core/mj_core.dart';

import '../main.dart';
import '../theme.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('規則書'),
          bottom: const TabBar(
            labelColor: MjColors.jadeDark,
            indicatorColor: MjColors.jade,
            tabs: [Tab(text: '玩法概要'), Tab(text: '番種圖鑑')],
          ),
        ),
        body: const TabBarView(
          children: [_Digest(), _Encyclopedia()],
        ),
      ),
    );
  }
}

// ── 玩法概要 ─────────────────────────────────────────────────────────────
class _Digest extends StatelessWidget {
  const _Digest();

  static const _sections = <(String, IconData, String)>[
    (
      '基本玩法',
      Icons.grid_view_rounded,
      '四人對戰，每人十六張牌。輪流摸打，砌出五副面子（順子或刻子）加一對眼即可食糊。'
          '可以上（食上家順子）、碰、槓。花牌摸到即擺出補牌。'
    ),
    (
      '叮',
      Icons.notifications_active_outlined,
      '聽牌時打出一隻牌並宣告「叮」，之後手牌唔可以再變（摸咩打咩），'
          '食糊多5番；門清落叮就係門叮15番。叮咗之後如果放棄食糊，成局都唔可以再食（叮過水）。'
    ),
    (
      '找數（全銃制）',
      Icons.payments_outlined,
      '出銃者一個人找足全部。自摸就三家都要畀，每家照計。'
          '莊家食糊或者出銃都加1番；連莊再拉N，每連一莊加2番。1底 = 5分。'
    ),
    (
      '拉 · 踢半',
      Icons.receipt_long_outlined,
      '開咗「拉」嘅房：出銃唔即刻找數，記落拉數簿。下次同一對玩家再有數，'
          '舊數×1.5覆利（踢半）疊上去。找清就一筆勾銷。完場仲未清嘅拉數作廢，唔使找。'
    ),
    (
      '花糊',
      Icons.local_florist_outlined,
      '集齊八隻花即時食糊（八仙過海）。摸到第七隻花嘅時候，'
          '其他人有第八隻花可以搶（七搶一）。'
    ),
    (
      '百搭（房間選項）',
      Icons.auto_awesome,
      '開房可以揀加入4隻或者8隻百搭。百搭可以代替任何一隻牌砌糊，'
          '但係唔可以打出、唔可以換出。'
    ),
    (
      '開局換牌（房間選項）',
      Icons.swap_horiz,
      '發牌之後每人揀幾隻牌傳畀下家：可以固定換三張，'
          '或者擲骰決定換幾多張（1至6）。'
    ),
    (
      '流局',
      Icons.hourglass_empty,
      '摸完成幅牌都冇人食糊就係流局，唔使找數，莊家繼續做莊（連莊）。'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (title, icon, body) in _sections)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: arcadeCard(radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: MjColors.jade),
                    const SizedBox(width: 8),
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body,
                    style: const TextStyle(fontSize: 13.5, height: 1.6)),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          '依照香港麻雀協會《港式台牌總例》（2025-07-28 修訂版）整理，'
          '以官方番表為準。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: MjColors.charcoalSoft),
        ),
      ],
    );
  }
}

// ── 番種圖鑑 ─────────────────────────────────────────────────────────────
const _catNames = <String, String>{
  'action': '動作番',
  'hand_state': '手牌狀態',
  'win_method': '食糊方式',
  'situational': '際遇番',
  'composition': '組合番',
  'flower': '花牌',
  'wait_shape': '叫糊形狀',
  'hand_pattern': '手牌形態',
  'sequence': '順子系',
  'triplet': '刻子系',
  'honor': '番子系',
  'suit': '花色系',
  'terminal': '么九系',
  'quad_group': '槓系',
  'special_form': '特殊糊',
  'pair_form': '對子糊',
};

class _Encyclopedia extends StatefulWidget {
  const _Encyclopedia();

  @override
  State<_Encyclopedia> createState() => _EncyclopediaState();
}

class _EncyclopediaState extends State<_Encyclopedia> {
  String _query = '';
  String? _selCat; // null = 全部

  @override
  Widget build(BuildContext context) {
    final table = FanTableStore.of(context).official;

    // per-category counts (respecting search) — reference 08 left sidebar
    final cats = <String, List<FanEntry>>{};
    for (final e in table.entries) {
      if (_query.isNotEmpty &&
          !e.name.contains(_query) &&
          !e.id.contains(_query)) {
        continue;
      }
      cats.putIfAbsent(e.category, () => []).add(e);
    }
    final total = cats.values.fold<int>(0, (a, b) => a + b.length);
    final entries = (_selCat == null
        ? [for (final v in cats.values) ...v]
        : List.of(cats[_selCat] ?? const <FanEntry>[]))
      ..sort((a, b) {
        final va = a.formula == null ? a.value : a.formula!.evaluate(1);
        final vb = b.formula == null ? b.value : b.formula!.evaluate(1);
        final cmp = vb.compareTo(va);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── left category rail (reference 08) ──
        SizedBox(
          width: 168,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            children: [
              _railItem(null, '全部', total),
              for (final entry in cats.entries)
                _railItem(entry.key, _catNames[entry.key] ?? entry.key,
                    entry.value.length),
            ],
          ),
        ),
        // ── right pane: search + fan cards ──
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    hintText: '搜尋番種',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: MjColors.ivory,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: MjColors.outline),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text('冇符合嘅番種',
                            style:
                                TextStyle(color: MjColors.charcoalSoft)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(6, 4, 16, 16),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _fanCard(entries[i]),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _railItem(String? cat, String name, int count) {
    final selected = _selCat == cat;
    return GestureDetector(
      onTap: () => setState(() => _selCat = cat),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: arcadeCard(
            color: selected ? MjColors.jade : MjColors.ivory,
            border: selected ? MjColors.jadeDark : MjColors.outline,
            radius: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : MjColors.charcoal)),
            ),
            Text('$count',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white70
                        : MjColors.charcoalSoft)),
          ],
        ),
      ),
    );
  }

  Widget _fanCard(FanEntry e) {
    final f = e.formula;
    final valueLabel = f == null
        ? '${e.value}番'
        : f.type == 'linear'
            ? '每次${f.coef}番'
            : '${f.base}番起 ×${f.ratio}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: arcadeCard(radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900)),
                if (e.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(e.notes,
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: MjColors.charcoalSoft)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: MjColors.brass.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MjColors.brass),
            ),
            child: Text(valueLabel,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: MjColors.brassDark)),
          ),
        ],
      ),
    );
  }
}
