// End-to-end smoke test for the deployed `mj` Supabase edge function.
// Run on a machine with network access (dev PC): test_mp.bat.
//
// Flow: anonymous sign-in -> create_room (1 hand, 3 bots) -> start ->
// [state -> answer prompt via act] loop until finished, plus two negative
// checks (illegal act -> 400, premature timeout -> 409).
//
// Exit code 0 + final line "SMOKE OK" means the whole multiplayer stack
// (auth, edge function, wasm engine bootstrap, DB log, validation) works.
import 'dart:convert';
import 'dart:io';

/// Reads KEY=VALUE pairs from mj_core/.env (git-ignored), then the environment.
Map<String, String> _loadEnv() {
  final values = <String, String>{};
  final file = File('.env');
  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
      final i = t.indexOf('=');
      values[t.substring(0, i).trim()] = t.substring(i + 1).trim();
    }
  }
  values.addAll(Platform.environment);
  return values;
}

final _env = _loadEnv();
final base = _env['MP_BASE_URL'] ?? '';
final anonKey = _env['MP_ANON_KEY'] ?? '';

final http = HttpClient();

Future<(int, Map<String, dynamic>)> post(
    String path, Map<String, dynamic> body,
    {String? bearer}) async {
  final req = await http.postUrl(Uri.parse('$base$path'));
  req.headers.set('apikey', anonKey);
  req.headers.set('Authorization', 'Bearer ${bearer ?? anonKey}');
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  Map<String, dynamic> data;
  try {
    data = jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    data = {'raw': text};
  }
  return (res.statusCode, data);
}

Never fail(String why, [Object? detail]) {
  print('SMOKE FAIL: $why');
  if (detail != null) print(detail);
  exit(1);
}

/// The same trivial answers the server bot would give — enough to finish
/// a hand legally. counts is the 34-kind multiset of the own hand.
Object? answerFor(Map<String, dynamic> prompt, List<dynamic> counts) {
  final c = counts.map((e) => e as int).toList();
  switch (prompt['type']) {
    case 'swap':
      final n = prompt['args']['n'] as int;
      final picks = <int>[];
      for (var k = 0; k < c.length && picks.length < n; k++) {
        while (c[k] > 0 && picks.length < n) {
          c[k] -= 1;
          picks.add(k);
        }
      }
      return picks;
    case 'discard':
      for (var k = 0; k < c.length; k++) {
        if (c[k] > 0) return k;
      }
      fail('discard prompt but empty hand');
    case 'win':
      return true;
    case 'ting':
    case 'kong':
    case 'claim':
    case 'chow':
      return null; // decline / pass
    default:
      fail('unknown prompt type ${prompt['type']}');
  }
}

Future<void> main() async {
  // 1. anonymous sign-in (Guest + nickname model)
  final (aCode, auth) = await post('/auth/v1/signup', {});
  if (aCode != 200 || auth['access_token'] == null) {
    fail(
        'anonymous sign-in failed ($aCode) — is Anonymous provider enabled '
        'in Authentication > Sign In / Up?',
        auth);
  }
  final token = auth['access_token'] as String;
  print('auth ok: user ${auth['user']?['id']}');

  Future<(int, Map<String, dynamic>)> fn(Map<String, dynamic> body) =>
      post('/functions/v1/mj', body, bearer: token);

  // 2. create a quick 1-hand room, 15s timer
  final (cCode, created) = await fn({
    'op': 'create_room',
    'nickname': 'smoke',
    'rules': {'total_hands': 1, 'turn_seconds': 15},
  });
  if (cCode != 200) fail('create_room -> $cCode', created);
  final roomId = created['room_id'] as String;
  print('room $roomId seat ${created['seat']}');

  // 3. premature timeout must be rejected (game not in play yet)
  final (t0Code, t0) = await fn({'op': 'timeout', 'room_id': roomId});
  if (t0Code != 409) fail('timeout before start should be 409, got $t0Code', t0);
  print('timeout-before-start correctly rejected (409)');

  // 4. start with 3 bot seats
  final (sCode, started) = await fn({'op': 'start', 'room_id': roomId});
  if (sCode != 200) fail('start -> $sCode', started);
  print('started');

  // 5. one deliberately illegal action -> 400
  final (badCode, bad) = await fn(
      {'op': 'act', 'room_id': roomId, 'type': 'discard', 'value': -1});
  if (badCode != 400) fail('illegal act should be 400, got $badCode', bad);
  print('illegal act correctly rejected (400): ${bad['error']}');

  // 6. play the hand to completion
  var acts = 0;
  for (var i = 0; i < 400; i++) {
    final (vCode, st) = await fn({'op': 'state', 'room_id': roomId});
    if (vCode != 200) fail('state -> $vCode', st);
    final room = st['room'] as Map<String, dynamic>;
    if (room['status'] == 'finished') {
      final view = st['view'] as Map<String, dynamic>;
      print('match finished after $acts human actions; '
          'scores ${view['scores']}');
      print('SMOKE OK');
      exit(0);
    }
    final view = st['view'] as Map<String, dynamic>?;
    final prompt = view?['prompt'] as Map<String, dynamic>?;
    if (prompt == null) {
      fail('playing but no prompt for me (waiting_on '
          '${view?['waiting_on']}) — unexpected for a 1-human room', st);
    }
    if (room['turn_deadline'] == null) {
      fail('pending prompt but no turn_deadline set', room);
    }
    final value = answerFor(prompt, view!['counts'] as List<dynamic>);
    final (aCode2, ack) = await fn({
      'op': 'act',
      'room_id': roomId,
      'type': prompt['type'],
      'value': value,
    });
    if (aCode2 != 200) {
      fail('act #$acts ${prompt['type']}=$value -> $aCode2', ack);
    }
    acts += 1;
    if (acts % 10 == 0) print('...$acts actions (last: ${prompt['type']})');
  }
  fail('hand did not finish within 400 actions');
}
