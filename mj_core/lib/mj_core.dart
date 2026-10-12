/// mj_core — pure-Dart rules engine for 港式台牌.
///
/// Design contract (see game-design-doc/08-INTEGRATION.md):
///  * intent in, events out — no UI, no I/O, no Flutter imports
///  * fully deterministic: same seed + same intents ⇒ identical event log
///  * consumed identically by client, server, and AI (FilteredView only)
library mj_core;

export 'src/tile.dart';
export 'src/rng.dart';
export 'src/wall.dart';
export 'src/meld.dart';
export 'src/fan_table.dart';
export 'src/kinds.dart';
export 'src/decompose.dart';
export 'src/fans.dart';
export 'src/settle.dart';
export 'src/engine.dart';
export 'src/ai.dart';
export 'src/replay.dart';
