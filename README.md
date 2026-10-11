# RE4R ShapeKey System

[English](#english) | [中文](#中文)

---

## English

### What it is

An in-game REFramework Lua panel for Resident Evil 4 Remake that drives **custom blend-shape (shape-key) channels** that a character mod has written into its player meshes. It provides:

- manual sliders, region grouping, presets, undo/redo, per-key sweep test, "compare with neutral";
- conversion of the game's **native Leon facial animation** into ARKit-52 coefficients, so a custom face can blink and talk with the game's own animation;
- **RhyLive / ARKit face capture** (read from the receiver DLL) with a fall-back to native animation when the stream drops;
- multi-mesh support (head, body, hair) with weight-array protection and automatic weight-array allocation for body/hair meshes;
- a small Lua API for other REFramework scripts ([docs/API.md](docs/API.md)).

Keys are bound by **engine channel-name hash, never by index**. What can be controlled (face, body, outfit, hair) depends entirely on the keys the character mod actually contains. **Installing this script alone adds no shape keys to an ordinary mod.** Writing shape keys into an RE4 `.mesh` currently needs tooling that is not yet public; see [docs/PROFILE_FORMAT.md](docs/PROFILE_FORMAT.md) for the profile contract a mod must ship.

### How the three repositories fit together

```
 phone (RhyLive app, ARKit 52, UDP)
        |
        v
 RE4R-RhyLive-Face      receiver DLL (rhylive_native) + face-bone Lua panel
        |  rhylive_native.poll()  (read-only snapshot)
        v
 RE4R-ShapeKey-System   <- THIS REPO: in-game panel, writes shape-key weights
        ^
        |  named pipe + RE4R_ShapeKeySystem_api
 RE4R-ShapeKey-Studio   desktop app (WebView2 UI) + bridge DLL + installer
```

| Repository | Role |
|---|---|
| [RE4R-ShapeKey-System](https://github.com/Funnyguysmz/RE4R-ShapeKey-System) | the in-game panel (this repo) |
| [RE4R-RhyLive-Face](https://github.com/Funnyguysmz/RE4R-RhyLive-Face) | UDP receiver DLL and bone-driven face panel |
| [RE4R-ShapeKey-Studio](https://github.com/Funnyguysmz/RE4R-ShapeKey-Studio) | desktop GUI, bridge DLL, installer |

Players can use this repo alone (manual sliders and native animation) or add the other two for face capture and a desktop GUI.

### Requirements

- Resident Evil 4 Remake with [REFramework](https://github.com/praydog/REFramework).
- A character mod that ships custom shape keys **and** a matching `reframework/data/RE4R_ShapeKeySystem_profile.json`.
- For native-animation conversion: `reframework/data/RE4R_ShapeKeySystem_native_leon.json` (Leon facial rig to ARKit conversion table; it depends only on Leon's skeleton, so one file serves every model). Without it the "native animation" sources are unavailable.
- For face capture: the RhyLive-Face receiver (see the other repo) and a phone running RhyLive.

### Install (players)

1. Install REFramework and the character mod with shape keys.
2. Copy `src/RE4R_ShapeKeySystem.lua` to `<game>/reframework/autorun/` (or use the output of `Package.ps1`).
3. Make sure the mod provides `reframework/data/RE4R_ShapeKeySystem_profile.json` and the native map file above.
4. Start the game, open REFramework's menu, **Script Generated UI -> ShapeKey System**. Wait until the status line shows the mesh as bound and the weight array reaches the channel count, tick "enable driving", and test single keys in manual mode first (sweep page).

If you use the desktop Studio, let its installer manage the script; Studio appends an adaptation block to the same-named script, so do not overwrite it with this repo's base script (see the Studio README).

### Usage

- **Expression source**: manual / native animation / native + manual offsets / face capture + manual offsets / face capture with fall-back to native animation when the stream is lost (> 0.5 s).
- **Face-capture strength** and **follow speed** (EMA factor 0.05-1; larger = more responsive) are on the expression page; per-channel gains are shared with the RhyLive panel. Only "Start receiver" is needed in the RhyLive panel; do not also enable its bone "Drive face".
- **Regions** declared in the profile get a strength slider each.
- **Keys page**: library filter, search, presets, undo/redo, reset. **Sweep page**: pushes every key 0 -> 1 -> 0 in turn. **Debug / signal pages**: mesh state, weight arrays, optional mesh diagnostics dump, native-signal recording.
- Settings, presets and diagnostics are written next to the profile under `reframework/data/` (`RE4R_ShapeKeySystem_settings.json`, `..._presets.json`, `..._diag.json`).

### Build / package from source

```powershell
.\Package.ps1
```

Output: `build/package/reframework/autorun/RE4R_ShapeKeySystem.lua` plus a copy of this README. There is nothing to compile.

### Testing

```powershell
lua tests/test_panel.lua src/RE4R_ShapeKeySystem.lua tests/fixture.lua
```

Requires a Lua 5.4 interpreter. The test is a stub-based regression (the fixture fakes the REFramework API). **It does not prove expressions, normals, materials or physics in the real game.**

### Verified status and limitations

| Item | Status |
|---|---|
| Lua stub regression (`tests/`) | 0.4.4: 60 checks passed, 0 failed |
| Head keys by hash (ARKit 52 and a 77-key MMD set), native-animation conversion, RhyLive capture 1:1 | verified in game by the author on two character mods (2026-10-11) |
| Manually setting WeightCount on body/hair meshes | verified in game on one example mod |
| Automatic weight allocation (0.4.3 / 0.4.4) and the capture-smoothing API | stub-tested only; in-game confirmation pending |
| Toon (cylindrical) normals on meshes that carry shape keys | **not preserved**: the engine recomputes normals for such meshes. A "fin" workaround was accepted in game on one mod, but it needs mod-side tooling that is not public |
| Writing shape keys into `.mesh` files | needs non-public tooling; this repo does not contain it |

Only the engine's `via.render.Mesh` blend-shape functions are used. Writing a channel beyond the engine's weight array crashed the game in an early test, so the panel re-reads the array size every frame and refuses to write outside it.

This repository contains no models, original game meshes, user settings or mod-specific profiles.

### License

License: MIT. See [LICENSE](LICENSE). Applies to project-owned code; third-party files retain their original licenses.

### Third-party notices

Uses the REFramework Lua API (praydog/REFramework, MIT) at runtime; no third-party code is bundled in this repository.

---

## 中文

### 这是什么

生化危机4重制版的游戏内 REFramework Lua 面板，用来驱动角色 MOD 写进玩家网格里的**自定义形态键（blend shape）通道**。功能：

- 手动滑条、分区、预设、撤销/重做、逐键巡检、“对比初始”；
- 把游戏**原生里昂面部动画**换算成 ARKit 52 系数，让自定义脸用游戏原生动画眨眼说话；
- **RhyLive / ARKit 面捕**（读取接收 DLL 的快照），断流时可回落原生动画；
- 多网格（头、身体、头发），带权重数组保护，身体/头发网格可自动分配权重数组；
- 供其他 REFramework 脚本调用的 Lua 接口（[docs/API.md](docs/API.md)）。

形态键按**引擎通道名哈希**绑定，不按序号。能控制什么（脸、身体、服装、头发）完全取决于角色 MOD 实际含有的键。**单独安装本脚本不会给普通 MOD 添加形态键。** 把形态键写进 RE4 `.mesh` 目前需要尚未公开的工具；MOD 必须附带的配置文件格式见 [docs/PROFILE_FORMAT.md](docs/PROFILE_FORMAT.md)。

### 三个仓库如何配合

```
 手机（RhyLive，ARKit 52，UDP）
        |
        v
 RE4R-RhyLive-Face      接收 DLL（rhylive_native）+ 面部骨骼 Lua 面板
        |  rhylive_native.poll()（只读快照）
        v
 RE4R-ShapeKey-System   <- 本仓库：游戏内面板，写入形态键权重
        ^
        |  命名管道 + RE4R_ShapeKeySystem_api
 RE4R-ShapeKey-Studio   桌面程序（WebView2 界面）+ 桥接 DLL + 安装器
```

玩家可以只用本仓库（手动滑条和原生动画），也可以再加另外两个获得面捕和桌面 GUI。

### 需求

- 安装了 [REFramework](https://github.com/praydog/REFramework) 的生化危机4重制版。
- 带自定义形态键、并附带匹配的 `reframework/data/RE4R_ShapeKeySystem_profile.json` 的角色 MOD。
- 原生动画换算还需要 `reframework/data/RE4R_ShapeKeySystem_native_leon.json`（里昂面部骨架到 ARKit 的换算表，只与里昂骨架有关，所有模型共用）。没有它则“原生动画”类来源不可用。
- 面捕需要 RhyLive-Face 接收插件（见另一个仓库）和运行 RhyLive 的手机。

### 玩家安装

1. 安装 REFramework 和带形态键的角色 MOD。
2. 把 `src/RE4R_ShapeKeySystem.lua` 放入 `<游戏目录>/reframework/autorun/`（或使用 `Package.ps1` 的输出）。
3. 确认 MOD 提供了 `reframework/data/RE4R_ShapeKeySystem_profile.json` 和上面的原生换算表。
4. 进入游戏，打开 REFramework 菜单 → **Script Generated UI → 形态键系统**。等状态栏显示网格已绑定、权重数组达到通道数后，勾选“启用驱动”，先用手动模式（巡检页）逐键测试。

如果使用桌面 Studio，请让它的安装器管理脚本：Studio 会在同名脚本末尾追加适配段，不要用本仓库的基础脚本覆盖（见 Studio 的 README）。

### 使用

- **表情来源**：手动 / 原生动画 / 原生动画 + 手动微调 / 面捕 + 手动微调 / 面捕（断流超过 0.5 秒回落原生动画）。
- 表情页有**面捕强度**和**跟随速度**（EMA 系数 0.05–1，越大越跟手）；单通道增益沿用 RhyLive 面板里的设置。RhyLive 面板里只需“启动接收”，不要同时开它的骨骼 Drive face。
- 配置里声明的**区域**各有一个强度滑条。
- **形态键页**：库筛选、搜索、预设、撤销/重做、重置。**巡检页**：依次把每个键 0→1→0。**调试 / 信号页**：网格状态、权重数组、可选的网格诊断导出、原生信号录制。
- 设置、预设、诊断文件写在 `reframework/data/` 下（`RE4R_ShapeKeySystem_settings.json`、`..._presets.json`、`..._diag.json`）。

### 从源码打包

```powershell
.\Package.ps1
```

输出 `build/package/reframework/autorun/RE4R_ShapeKeySystem.lua` 和本 README 的副本。没有需要编译的内容。

### 测试

```powershell
lua tests/test_panel.lua src/RE4R_ShapeKeySystem.lua tests/fixture.lua
```

需要 Lua 5.4 解释器。这是基于桩的回归测试（fixture 伪造 REFramework API），**不能证明游戏里的表情、法线、材质和物理。**

### 验证状态与限制

| 项目 | 状态 |
|---|---|
| Lua 桩回归（`tests/`） | 0.4.4：60 项通过，0 失败 |
| 按哈希绑定头部键（ARKit 52 与 77 键 MMD 集）、原生动画换算、RhyLive 面捕 1:1 | 作者已在两个角色 MOD 上实机验证（2026-10-11） |
| 手动给身体/头发网格设置 WeightCount | 已在一个示例 MOD 上实机验证 |
| 自动权重分配（0.4.3 / 0.4.4）与面捕平滑接口 | 仅桩测试；实机确认待做 |
| 带形态键网格上的三渲二（柱面）法线 | **无法保留**：引擎会为这类网格重算法线。“鳍片”变通方案已在一个 MOD 上实机通过，但需要未公开的 MOD 侧工具 |
| 把形态键写入 `.mesh` | 需要未公开工具，本仓库不含 |

只使用引擎 `via.render.Mesh` 的 blend shape 函数。早期测试中写入超出权重数组的通道会让游戏崩溃，所以面板每帧重新读取数组大小，拒绝越界写入。

本仓库不含模型、原版游戏网格、用户设置或模型专用配置。

### 许可

License: MIT。详见 [LICENSE](LICENSE)。适用于项目自有代码；第三方文件保持原许可。

### 第三方声明

运行时使用 REFramework 的 Lua API（praydog/REFramework，MIT）；本仓库不捆绑第三方代码。
