# Optional native receivers and maps / 接收口与映射（0.4.5-rc.1）

Copy release reframework/ into the game directory. Bundled generic maps:
- data/RE4R_ShapeKeySystem_native_leon.json: default Leon table, 48 rules.
- data/RE4R_ShapeKeySystem_native_leon_mouth9.json: optional subset, 19 rules (16 bone + 3 tap rules), 17 semantic outputs.

The character MOD owns reframework/data/RE4R_ShapeKeySystem_profile.json: keys, names/hashes and declared receivers must match its MESH. The script does not add shape keys to ordinary MODs. examples/profile_mouth9_synthetic.json is inactive synthetic data, not a playable model or universal profile.

native_taps supports 91 receivers, nine selected receivers, or an empty NoTap array. Binding uses current name hashes, not fixed indices. Unselected channels need not exist; selected missing channels are diagnosed.

Optional profile field:
```json
"native_map_file": "RE4R_ShapeKeySystem_native_leon_mouth9.json"
```
The JSON basename is loaded from reframework/data/. Omit the field to retain the default table. Explicitly selected missing/invalid maps report errors and disable native conversion without silent fallback; manual and RhyLive remain available. Selection never forces mouth9 onto all models.

mouth9 includes jaw_openExtreme, four mouth_purse_{L,R}_{U,D} and four mouth_funnel_{L,R}_{U,D}, prefixed Face__geo__p000_cbs.crct_. The 16 bone rules and retained thresholds/gains match the full table. Jaw sums C_Chin, C_LowerLip and jaw_openExtreme, clamps, then applies model profile retargeting; no NoTap 3x multiplier is added. It is not equivalent to the full map: historical recording comparison found 8 pucker frames with loss >0.05, maximum 0.207181. Private recordings/profiles are not distributed.

## Diagnostics and safety

Debug UI and JSON diagnostics list each selected receiver. native_tap_status() returns {name, short, hash, channel, bound, state, value}; states: ok, unbound, bounds_unavailable, out_of_bounds, read_failed. Only ok has a confirmed value; zero is distinct from failure. native_map_status() returns {file, loaded, error}.

Reads/writes respect live ChannelNum, WeightList length, WeightCount and bound channel count. Unavailable bounds block access; write batches recheck all boundaries each frame. Manual allocation requires a complete list and matching ChannelNum. Head initialization stays explicit; extra meshes retain automatic allocation. Native weights are read-only even for accidental profile overlaps. A bound hash and zero value do not prove game signal delivery.

Studio must merge base Lua changes into its adapted runtime, retaining its bridge; do not replace Studio's adapted file with base Lua. Back up installed scripts, profiles/maps and model before testing, retain user settings, and stop competing NoTap/other writers. Roll back the backed-up script/config/model set together. Prior v0.4.4 remains available.

## Validation (2026-10-13)

- Legacy regression 60/60; public synthetic mouth9 regression 29/29; generic-map contract checked.
- Local model check: 85 custom + 9 zero-delta receivers = 94 matching names/hashes, 389 bones. Private assets not distributed.
- Derived exporter 0.70.6 evidence: real Blender export/readback, default unchanged from 0.70.5, no-recalc format import/export for specified base normals.
- User accepted prior standalone 85-channel normal experiment. Integrated 94-channel game signals, blinking, mouth opening and idle closure remain unverified; arbitrary models/per-expression normal mixing are not validated. No additional representative cutscene test was requested.

## 中文

安装包内含旧 Leon 通用表和 mouth9 精简表；MOD 提供与真实 MESH 匹配的 profile。省略 native_map_file 保持旧表，仅匹配模型显式选择精简表。91/9/NoTap均兼容，原生接收口只读。逐口诊断区分缺失、边界不可读/越界、读取失败和确认零值。jaw未叠加NoTap实验3倍；精简pucker存在损失。

已发现RE4原生 no-recalc＋法线记录资源，派生导出器支持指定基础法线方向，鳍片不是唯一路线。独立85通道法线实验获用户认可；新94通道组合、基础信号及眼嘴行为仍待验。详见[公开派生导出器](https://github.com/Funnyguysmz/RE-Mesh-Editor-BlendShape)。导出器GPLv3许可与本仓库MIT独立。


Exporter prerelease / 导出器预发布：[v0.70.6-re4r.1](https://github.com/Funnyguysmz/RE-Mesh-Editor-BlendShape/releases/tag/v0.70.6-re4r.1). Both export switches default off; mouth9 prepends nine zero-delta receivers, nonzero same-name receivers are rejected. Packed/no-recalc uses the final base custom normal for each key; it does not author normals, skinning or remove fins. 两个开关默认关闭；仅增加九个零位移接收口，每键法线来自最终基础自定义法线，不自动造法线、绑权重或删鳍片。