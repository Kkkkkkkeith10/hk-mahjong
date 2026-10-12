Drop-in mahjong tile PNGs.

Generated source size: 256x352, transparent outside the rounded tile body.
App target: scales down from this source for opponent hands, rivers, melds, and own hand.

Required filenames:

萬子:
W1.png W2.png W3.png W4.png W5.png W6.png W7.png W8.png W9.png

筒子:
T1.png T2.png T3.png T4.png T5.png T6.png T7.png T8.png T9.png

索子:
S1.png S2.png S3.png S4.png S5.png S6.png S7.png S8.png S9.png

風牌:
FE.png = 東
FS.png = 南
FW.png = 西
FN.png = 北

三元:
DC.png = 中
DF.png = 發
DB.png = 白

Special:
J0.png = 百搭

花牌:
X1.png = 梅
X2.png = 蘭
X3.png = 菊
X4.png = 竹
X5.png = 春
X6.png = 夏
X7.png = 秋
X8.png = 冬

Back:
back.png = opponent hands / face-down tiles / 暗槓

Notes:
- Tile faces were generated from real mahjong tile references, then cropped and normalized.
- Keep this folder in sync with ../../../assets/tiles before rebuilding the Flutter app.
