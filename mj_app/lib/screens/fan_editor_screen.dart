/// 番表管理 — per reference 07-fan-editor.png, adapted to landscape:
/// left category rail (with counts + 全部), right pane of fan rows with
/// enable switch and value stepper (flat values only; formula fans show
/// their formula and are not steppable). Bottom bar shows the live
/// 與官方差異 badge and the 還原官方 button. Edits mutate the working
/// FanTable copy used by new rooms and persist immediately.
library;

import 'package:flutter/material.dart';
import 'package:mj_core/mj_core.dart';

import '../main.dart';
import '../model/app_settings.dart';
import '../theme.dart';

const _categoryNames = <String, String>{
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

class FanEditorScreen extends StatefulWidget {
  const FanEditorScreen({super.key});

  @override
  State<FanEditorScreen> createState() => _FanEditorScreenState();
}

class _FanEditorScreenState extends State<FanEditorScreen> {
  String _query = '';
  String? _selCat; // null = 全部

  /// Persist current working-vs-official diff (called after every edit).
  void _persist() {
    final store = FanTableStore.of(context);
    AppSettings.instance.saveFanOverrides(store.working, store.official);
  }

  void _edit(VoidCallback change) {
    setState(change);
    _persist();
  }

  void _restore(BuildContext context) {
    final store = FanTableStore.of(context);
    for (final e in store.working.entries) {
      final o = store.official.byId[e.id]!;
      e.enabled = o.enabled;
      e.value = o.value;
    }
    setState(() {});
    _persist();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已還原官方番表（總例 2025-07-28）')));
  }

  int _diffCount(FanTableStore store) {
    var n = 0;
    for (final e in store.working.entries) {
      final o = store.official.byId[e.id]!;
      if (e.enabled != o.enabled || e.value != o.value) n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    final store = FanTableStore.of(context);
    final table = store.working;

    // category → entries (respecting search)
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
    final shown = _selCat == null
        ? [for (final v in cats.values) ...v]
        : (cats[_selCat] ?? const <FanEntry>[]);
    final diff = _diffCount(store);

    return Scaffold(
      appBar: AppBar(title: const Text('番表管理')),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── left category rail (reference 07 / 08 sidebar) ──
          SizedBox(
            width: 168,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              children: [
                _railItem(null, '全部', total),
                for (final entry in cats.entries)
                  _railItem(entry.key, _categoryNames[entry.key] ?? entry.key,
                      entry.value.length),
              ],
            ),
          ),
          // ── right pane: search + rows ──
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      hintText: '搜尋番種（例如：清一色）',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: MjColors.ivory,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: MjColors.outline),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(
                          child: Text('冇符合嘅番種',
                              style: TextStyle(
                                  color: MjColors.charcoalSoft)))
                      : ListView(
                          padding:
                              const EdgeInsets.fromLTRB(6, 4, 16, 12),
                          children: [
                            for (final e in shown)
                              _fanRow(e, store.official.byId[e.id]!),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      // ── bottom bar: diff badge + 還原官方 (reference 07 footer) ──
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: MjColors.cream,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: arcadeCard(
                    color: diff == 0 ? MjColors.mint : MjColors.ivory,
                    border:
                        diff == 0 ? MjColors.jade : MjColors.brassDark,
                    radius: 12),
                child: Text(
                    diff == 0 ? '與官方一致' : '與官方差異 $diff 項',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: diff == 0
                            ? MjColors.jadeDark
                            : MjColors.brassDark)),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: diff == 0
                    ? null
                    : () => showDialog<void>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            backgroundColor: MjColors.ivory,
                            title: const Text('還原官方番表？'),
                            content:
                                const Text('所有自訂番值同開關都會被重設。'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dctx),
                                  child: const Text('取消')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: MjColors.coral),
                                onPressed: () {
                                  Navigator.pop(dctx);
                                  _restore(context);
                                },
                                child: const Text('還原'),
                              ),
                            ],
                          ),
                        ),
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('還原官方'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railItem(String? cat, String name, int count) {
    final selected = _selCat == cat;
    return GestureDetector(
      onTap: () => setState(() => _selCat = cat),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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

  Widget _fanRow(FanEntry e, FanEntry official) {
    final f = e.formula;
    final changed =
        e.enabled != official.enabled || e.value != official.value;
    final valueLabel = f == null
        ? '${e.value}番'
        : f.type == 'linear'
            ? '每次 ${f.coef}番'
            : '${f.base}番 ×${f.ratio} 遞增';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: arcadeCard(
          color: MjColors.ivory,
          border: changed ? MjColors.brassDark : MjColors.outline,
          radius: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: e.enabled
                                ? MjColors.charcoal
                                : MjColors.stone)),
                  ),
                  if (changed)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: MjColors.brass.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('已修改',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: MjColors.brassDark)),
                    ),
                ]),
                if (e.notes.isNotEmpty)
                  Text(e.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: MjColors.charcoalSoft)),
              ],
            ),
          ),
          if (f == null && e.editable && e.enabled) ...[
            _stepBtn(
                Icons.remove, e.value > 0, () => _edit(() => e.value -= 1)),
            SizedBox(
              width: 52,
              child: Text(valueLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w900)),
            ),
            _stepBtn(
                Icons.add, e.value < 999, () => _edit(() => e.value += 1)),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(valueLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: e.enabled
                          ? MjColors.brassDark
                          : MjColors.stone)),
            ),
          if (e.editable)
            Switch(
              value: e.enabled,
              onChanged: (v) => _edit(() => e.enabled = v),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Icon(Icons.lock_outline,
                  size: 16, color: MjColors.stone),
            ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, bool on, VoidCallback onTap) =>
      GestureDetector(
        onTap: on ? onTap : null,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: on ? MjColors.mint : MjColors.panel,
            shape: BoxShape.circle,
            border: Border.all(
                color: on ? MjColors.jade : MjColors.outline),
          ),
          child: Icon(icon,
              size: 16, color: on ? MjColors.jadeDark : MjColors.stone),
        ),
      );
}
