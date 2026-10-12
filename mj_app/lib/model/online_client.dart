/// Minimal Supabase client for online play — no extra packages.
///
/// Talks to the `mj` edge function (see mj_core/bin/wasm_api.dart and the
/// deployed index.ts): guest (anonymous) auth, persisted session, and the
/// six ops (create_room / join_room / start / state / act / timeout).
/// Clients learn "something changed" by polling `state` (version bumps);
/// realtime push can replace polling later without touching callers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Supabase project for online play. Pass at build time, e.g.
///   flutter run --dart-define=MP_BASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=MP_ANON_KEY=...
const mpBaseUrl = String.fromEnvironment('MP_BASE_URL');

/// Publishable anon key (protected by row-level security on the server).
const mpAnonKey = String.fromEnvironment('MP_ANON_KEY');

class OnlineException implements Exception {
  final int status;
  final String message;
  OnlineException(this.status, this.message);
  @override
  String toString() => 'OnlineException($status): $message';
}

/// Anonymous-session Supabase client. [ensureSignedIn] gives every device a
/// stable guest identity (stored refresh token); ops go through [op].
class OnlineClient {
  static final OnlineClient instance = OnlineClient._();
  OnlineClient._();

  final HttpClient _http = HttpClient();
  String? _accessToken;
  String? _refreshToken;
  String? userId;

  static const _kAccess = 'mp_access_token';
  static const _kRefresh = 'mp_refresh_token';
  static const _kUser = 'mp_user_id';

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    bool authed = false,
  }) async {
    final req = await _http.postUrl(Uri.parse('$mpBaseUrl$path'));
    req.headers.set('apikey', mpAnonKey);
    req.headers.contentType = ContentType.json;
    if (authed) {
      req.headers.set('Authorization', 'Bearer $_accessToken');
    }
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    Map<String, dynamic> json;
    try {
      json = text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw OnlineException(res.statusCode, text);
    }
    if (res.statusCode >= 400) {
      final msg = (json['error'] ?? json['msg'] ?? json['error_description'] ??
              text)
          .toString();
      throw OnlineException(res.statusCode, msg);
    }
    return json;
  }

  /// Sign in as a guest, restoring the persisted session when possible so
  /// the same device keeps its identity (needed for room rejoin).
  Future<void> ensureSignedIn() async {
    if (_accessToken != null) return;
    final prefs = await SharedPreferences.getInstance();
    _refreshToken ??= prefs.getString(_kRefresh);
    userId ??= prefs.getString(_kUser);

    if (_refreshToken != null) {
      try {
        final j = await _post('/auth/v1/token?grant_type=refresh_token',
            {'refresh_token': _refreshToken});
        await _storeSession(prefs, j);
        return;
      } on OnlineException {
        // refresh token expired/revoked — fall through to a fresh guest
        _refreshToken = null;
      }
    }
    final j = await _post('/auth/v1/signup', {}); // anonymous sign-in
    await _storeSession(prefs, j);
  }

  Future<void> _storeSession(
      SharedPreferences prefs, Map<String, dynamic> j) async {
    _accessToken = j['access_token'] as String?;
    _refreshToken = (j['refresh_token'] as String?) ?? _refreshToken;
    userId = ((j['user'] as Map?)?['id'] as String?) ?? userId;
    if (_accessToken == null) {
      throw OnlineException(500, 'auth response missing access_token');
    }
    await prefs.setString(_kAccess, _accessToken!);
    if (_refreshToken != null) await prefs.setString(_kRefresh, _refreshToken!);
    if (userId != null) await prefs.setString(_kUser, userId!);
  }

  /// Call one edge-function op. Transparently re-authenticates once on 401
  /// (expired access token mid-session).
  Future<Map<String, dynamic>> op(Map<String, dynamic> body) async {
    await ensureSignedIn();
    try {
      return await _post('/functions/v1/mj', body, authed: true);
    } on OnlineException catch (e) {
      if (e.status != 401) rethrow;
      _accessToken = null; // force refresh and retry once
      await ensureSignedIn();
      return _post('/functions/v1/mj', body, authed: true);
    }
  }

  // ── ops ───────────────────────────────────────────────────────────────
  Future<({String roomId, int seat})> createRoom(
      {required String nickname, required Map<String, dynamic> rules}) async {
    final j = await op({'op': 'create_room', 'nickname': nickname, 'rules': rules});
    return (roomId: j['room_id'] as String, seat: j['seat'] as int);
  }

  Future<int> joinRoom(
      {required String roomId, required String nickname}) async {
    final j = await op({'op': 'join_room', 'room_id': roomId, 'nickname': nickname});
    return j['seat'] as int;
  }

  Future<void> start(String roomId) async {
    await op({'op': 'start', 'room_id': roomId});
  }

  Future<Map<String, dynamic>> state(String roomId) =>
      op({'op': 'state', 'room_id': roomId});

  Future<void> act(String roomId, String type, Object? value) async {
    await op({'op': 'act', 'room_id': roomId, 'type': type, 'value': value});
  }

  Future<void> timeout(String roomId) async {
    await op({'op': 'timeout', 'room_id': roomId});
  }
}
