/// Online play entry — 開房 (create) / 入房 (join by 6-char code), then the
/// waiting room (roster + owner's 開始). When the room flips to `playing`
/// the waiting room swaps itself for [OnlineGameScreen].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model/online_client.dart';
import '../model/online_controller.dart';
import '../theme.dart';
import 'online_game_screen.dart';

class OnlineLobbyScreen extends StatefulWidget {
  final bool createMode; // true = 開房, false = 入房
  const OnlineLobbyScreen({super.key, required this.createMode});

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  final _nick = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  // 開房 options (mirror SetupScreen's vocabulary)
  int _totalHands = 8;
  int _jokers = 0;
  String _swap = 'off';
  bool _laOn = true;
  int _turnSeconds = 30;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = p.getString('mp_nickname') ?? '';
      if (saved.isNotEmpty && mounted) setState(() => _nick.text = saved);
    });
  }

  @override
  void dispose() {
    _nick.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final nickname = _nick.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = '請輸入暱稱');
      return;
    }
    final code = _code.text.trim().toUpperCase();
    if (!widget.createMode && code.length != 6) {
      setState(() => _error = '房號係 6 個字');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mp_nickname', nickname);
      final client = OnlineClient.instance;
      String roomId;
      int seat;
      if (widget.createMode) {
        final r = await client.createRoom(nickname: nickname, rules: {
          'total_hands': _totalHands,
          'jokers': _jokers,
          'swap': _swap,
          'la_on': _laOn,
          'turn_seconds': _turnSeconds,
        });
        roomId = r.roomId;
        seat = r.seat;
      } else {
        roomId = code;
        seat = await client.joinRoom(roomId: code, nickname: nickname);
      }
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => OnlineRoomScreen(
                  roomId: roomId, mySeat: seat, isOwner: widget.createMode)));
    } on OnlineException catch (e) {
      setState(() => _error = switch (e.status) {
            404 => '搵唔到呢間房，睇下房號啱唔啱',
            409 => e.message.contains('full') ? '房間滿咗喇' : '遊戲已經開始咗',
            _ => '連線失敗（${e.status}）：${e.message}',
          });
    } catch (e) {
      setState(() => _error = '連線失敗，請檢查網絡再試');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.createMode ? '開房' : '入房')),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.all(16),
            decoration: arcadeCard(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('暱稱',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                TextField(
                  controller: _nick,
                  maxLength: 12,
                  decoration: const InputDecoration(
                      counterText: '',
                      hintText: '譬如：燒賣仔',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                if (widget.createMode) ..._createOptions() else ..._joinField(),
                const SizedBox(height: 14),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: MjColors.coral,
                            fontWeight: FontWeight.w700)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: MjColors.jade,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : _go,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : Text(widget.createMode ? '開房' : '入房',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _joinField() => [
        const Text('房號', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        TextField(
          controller: _code,
          maxLength: 6,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          ],
          style: const TextStyle(
              fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(
              counterText: '',
              hintText: 'ABC123',
              isDense: true,
              border: OutlineInputBorder()),
        ),
      ];

  List<Widget> _createOptions() => [
        _optRow<int>('局數', _totalHands, const [4, 8, 16],
            (v) => '$v 局', (v) => setState(() => _totalHands = v)),
        _optRow<int>('百搭', _jokers, const [0, 4, 8],
            (v) => v == 0 ? '冇' : '$v 隻', (v) => setState(() => _jokers = v)),
        _optRow<String>('換牌', _swap, const ['off', 'fixed3', 'dice'],
            (v) => switch (v) {
                  'fixed3' => '換三隻',
                  'dice' => '骰仔決定',
                  _ => '唔換',
                },
            (v) => setState(() => _swap = v)),
        _optRow<bool>('拉銃', _laOn, const [true, false],
            (v) => v ? '開' : '關', (v) => setState(() => _laOn = v)),
        _optRow<int>('出牌時限', _turnSeconds, const [15, 30, 60],
            (v) => '$v 秒', (v) => setState(() => _turnSeconds = v)),
      ];

  Widget _optRow<T>(String label, T current, List<T> options,
      String Function(T) name, void Function(T) onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
              width: 86,
              child:
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                for (final o in options)
                  ChoiceChip(
                    label: Text(name(o)),
                    selected: o == current,
                    selectedColor: MjColors.mint,
                    onSelected: (_) => onPick(o),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Waiting room + in-game host. Owns the [OnlineGameController]; renders
/// the roster while `waiting`, [OnlineGameScreen] once `playing`.
class OnlineRoomScreen extends StatefulWidget {
  final String roomId;
  final int mySeat;
  final bool isOwner;
  const OnlineRoomScreen(
      {super.key,
      required this.roomId,
      required this.mySeat,
      required this.isOwner});

  @override
  State<OnlineRoomScreen> createState() => _OnlineRoomScreenState();
}

class _OnlineRoomScreenState extends State<OnlineRoomScreen> {
  late final OnlineGameController c;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    c = OnlineGameController(roomId: widget.roomId, mySeat: widget.mySeat);
    c.addListener(_onChange);
    c.startPolling();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await OnlineClient.instance.start(widget.roomId);
      await c.refresh();
    } on OnlineException catch (e) {
      setState(() => _error = '開始失敗（${e.status}）：${e.message}');
    } catch (_) {
      setState(() => _error = '連線失敗，請再試');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (c.phase) {
      case OnlinePhase.playing:
      case OnlinePhase.finished:
        return OnlineGameScreen(controller: c);
      case OnlinePhase.error:
        return Scaffold(
          appBar: AppBar(title: const Text('房間')),
          body: Center(
              child: Text(c.errorText ?? '出錯喇',
                  style: const TextStyle(color: MjColors.coral))),
        );
      case OnlinePhase.connecting:
      case OnlinePhase.waiting:
        return _waitingRoom(context);
    }
  }

  Widget _waitingRoom(BuildContext context) {
    final full = c.roster.where((p) => !p.isBot).length;
    return Scaffold(
      appBar: AppBar(title: const Text('等緊人齊')),
      body: Center(
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(16),
          decoration: arcadeCard(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('房號', style: TextStyle(color: MjColors.charcoalSoft)),
              const SizedBox(height: 4),
              SelectableText(widget.roomId,
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: MjColors.jadeDark)),
              const SizedBox(height: 4),
              const Text('叫朋友入呢個房號',
                  style: TextStyle(color: MjColors.charcoalSoft, fontSize: 12)),
              const SizedBox(height: 14),
              for (var s = 0; s < 4; s++) _seatRow(s),
              const SizedBox(height: 14),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: MjColors.coral, fontWeight: FontWeight.w700)),
                ),
              if (widget.isOwner)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: MjColors.coral,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _starting || c.phase == OnlinePhase.connecting
                        ? null
                        : _start,
                    child: Text(
                        full >= 4 ? '開始' : '開始（空位由電腦頂上）',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                )
              else
                const Text('等房主開始…',
                    style: TextStyle(color: MjColors.charcoalSoft)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seatRow(int seat) {
    OnlinePlayer? p;
    for (final r in c.roster) {
      if (r.seat == seat) p = r;
    }
    final me = seat == widget.mySeat;
    final label = p == null
        ? '空位 · 電腦頂上'
        : p.isBot
            ? '電腦'
            : (p.nickname.isEmpty ? '玩家 ${seat + 1}' : p.nickname);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: me ? MjColors.mint : MjColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: me ? MjColors.jade : MjColors.outline),
      ),
      child: Row(
        children: [
          Icon(p == null ? Icons.smart_toy_outlined : Icons.person,
              size: 18,
              color: p == null ? MjColors.stone : MjColors.charcoal),
          const SizedBox(width: 8),
          Text('${seat + 1} 號位',
              style: const TextStyle(
                  color: MjColors.charcoalSoft, fontSize: 12)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          if (me)
            const Text('你',
                style: TextStyle(
                    color: MjColors.jadeDark, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
