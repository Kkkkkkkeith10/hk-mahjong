/// Tile *kinds* — the compact int encoding the engine/recognizer work in.
/// Mirrors ref_engine/tiles.py exactly (fixture contract).
///
/// Kind indices (34 playing kinds + joker sentinel):
///   0-8   W1-W9 萬
///   9-17  T1-T9 筒
///   18-26 S1-S9 索
///   27-30 FE FS FW FN 東南西北
///   31-33 DC DF DB 中發白
///   34    J0 百搭 (joker)
/// Flowers (X1-X8) are not hand tiles; they live in a separate flower zone.
library;

const int kindWind = 27;
const int kindDragon = 31;
const int kJoker = 34;
const int numKinds = 34; // playing kinds excluding joker

const List<String> _winds = ['FE', 'FS', 'FW', 'FN'];
const List<String> _dragons = ['DC', 'DF', 'DB'];

String kindToId(int k) {
  if (k < 9) return 'W${k + 1}';
  if (k < 18) return 'T${k - 8}';
  if (k < 27) return 'S${k - 17}';
  if (k < 31) return _winds[k - 27];
  if (k < 34) return _dragons[k - 31];
  return 'J0';
}

int idToKind(String tid) {
  switch (tid[0]) {
    case 'W':
      return int.parse(tid.substring(1)) - 1;
    case 'T':
      return 9 + int.parse(tid.substring(1)) - 1;
    case 'S':
      return 18 + int.parse(tid.substring(1)) - 1;
    case 'F':
      return 27 + _winds.indexOf(tid);
    case 'D':
      return 31 + _dragons.indexOf(tid);
    case 'J':
      return kJoker;
  }
  throw ArgumentError.value(tid, 'tid', 'unknown tile id');
}

/// 0=W 1=T 2=S 3=wind 4=dragon.
int suitOf(int k) {
  if (k < 27) return k ~/ 9;
  return k < 31 ? 3 : 4;
}

/// 1-9 for suited; 1-4 winds; 1-3 dragons.
int rankOf(int k) {
  if (k < 27) return k % 9 + 1;
  return k < 31 ? k - 26 : k - 30;
}

bool isSuitedKind(int k) => k < 27;
bool isHonorKind(int k) => 27 <= k && k < 34;
bool isTerminalKind(int k) => k < 27 && (k % 9 == 0 || k % 9 == 8);

/// 么九+字: the 13 orphan kinds.
bool isOrphanKind(int k) => isTerminalKind(k) || isHonorKind(k);

final List<int> orphanKinds = [
  for (var k = 0; k < numKinds; k++)
    if (isOrphanKind(k)) k
];
