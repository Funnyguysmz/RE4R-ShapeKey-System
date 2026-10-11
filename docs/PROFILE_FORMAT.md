# Profile format: `RE4R_ShapeKeySystem_profile.json`

[English](#english) | [中文](#中文)

---

## English

This is the contract between a character mod and the ShapeKey System panel. The mod ships the file at

```
<game>/reframework/data/RE4R_ShapeKeySystem_profile.json
```

(UTF-8 JSON, loaded with REFramework's `json.load_file`). It describes which blend-shape channels the mod's meshes carry, how to label and group them, and how ARKit values (from native animation or face capture) drive them. This document describes what panel **0.4.4** actually reads (`load_profile` and the code that uses its result). The desktop Studio reads the same keys through the panel's bridge.

> Writing shape keys into an RE4 `.mesh` file currently needs tooling that is **not yet public**. This document only specifies the profile that must accompany such a mesh.

### 1. Top-level fields

| Field | Required | Type | Used by | Meaning |
|---|---|---|---|---|
| `keys` | **required** | array | panel | The list of keys (section 2). If the file is missing or `keys` is not an array, the panel shows "profile not found" and stays idle. |
| `regions` | optional (recommended) | array of `{id, label}` | panel | Regions that get a strength slider on the expression page, in this order. `id` and `label` must be strings. Keys whose `region` is not declared still work (gain 1.0) but get no slider. |
| `native_taps` | optional | array of `{name, hash}` | panel | Zero-delta channels already present in the head mesh (Leon's original `Face__geo__p000_cbs.crct_*` names). They are only **read** (to show native activity and for tap-based conversion rules), never written. `hash` is the hash of `name` (section 3). Only looked up on the head mesh. Omit if your mesh has none. |
| `title` | optional | string | panel | Shown in the panel header and status line. Falls back to `model`, then `?`. |
| `model` | optional | string | panel | Short model id; fallback for `title`. |
| `format` | optional | number | nobody (informational) | Profile layout version. The reference generator writes `2`. Not validated. |
| `mesh` | optional | string | nobody (informational) | Path of the head mesh the keys were written into. Not read; the mesh is found at runtime by hash. |
| `retarget_note` | optional | string | nobody (informational) | Free text for humans, e.g. how left/right was determined. |

Unknown fields are ignored, so you may add your own metadata.

### 2. Key fields

Each element of `keys` is an object:

| Field | Required | Type | Meaning |
|---|---|---|---|
| `id` | **required** | string, unique | The **blend-shape channel name written into the mesh** (e.g. `SK__demo.eye_close_L`). Also the key for saved slider values and presets, so do not rename it between versions. |
| `hash` | **required** | integer 0..4294967295 | The engine's hash of `id` (section 3). This is what binds the key to a mesh channel. |
| `label` | **required** | string | Text on the slider (any language). Also searched by the filter box. |
| `name` | **required** | string | Short technical name, shown in brackets and searched by the filter. For ARKit-library keys it must be the exact ARKit name (section 5). |
| `library` | **required** | string | Source convention. `"ARKit"` means the key is driven 1:1 by the ARKit coefficient named by `name`. Any other string (e.g. `"MMD"`, `"VRC"`, `"custom"`) means the key is driven through `arkit` (below) and/or manually. The panel's library filter only has "all / ARKit / MMD" entries, so other libraries are visible under "all". |
| `group` | **required** | string | Sub-heading on the keys page and in Studio. |
| `region` | **required** | string | Region id (section 4). Decides the strength slider it belongs to and the Studio tab. An empty string puts it on Studio's "other" tab. |
| `arkit` | optional | array of `[arkitName, gain]` | Retarget list for non-ARKit keys: see section 5. `gain` defaults to 1 when omitted. Ignored for `library: "ARKit"` keys. |
| `max_cm` | optional | number | Largest vertex displacement of the key in cm; documentation by the generator. Not read by the panel. |
| `source` | optional | string | Name of the key in the source model; documentation by the generator. Not read by the panel. |

Notes:

- `label`, `name`, `library`, `group` are concatenated or lower-cased by the panel UI. **A missing or non-string value raises a Lua error while drawing the panel.** Treat all of them as required.
- There is **no mesh-index field**. Which mesh carries a key is discovered at runtime: the panel first matches keys against the player's head mesh, then attaches body/hair meshes that contain still-unbound keys (searched under the player body object). One profile can therefore span head, body and hair meshes. Keys whose hash is found on no mesh stay unbound (their sliders are disabled, e.g. an optional add-on is not enabled).
- Slider range is 0..1; the final weight is clamped to 0..1. Bake the largest deformation you want into weight 1.

### 3. `id` and `hash`: how they must match the mesh

At runtime the panel reads `get_ChannelNameHash` of each candidate mesh and builds `hash -> channel index`. A key is bound if `key.hash` is in that table. **Channels are never matched by index or by plain name.** Therefore:

1. The channel name stored in the mesh (the name you hash when writing the mesh) must be exactly the profile's `id`, character for character.
2. `hash` must be that name's hash, computed as **MurmurHash3 x86 32-bit over the UTF-16LE bytes of the name, seed `0xFFFFFFFF`**, as an unsigned 32-bit integer.
3. Hashes must be unique inside the mesh.

Reference implementation (Python):

```python
import struct

def murmur3_utf16(text, seed=0xFFFFFFFF):
    data = text.encode('utf-16-le')
    c1, c2 = 0xcc9e2d51, 0x1b873593
    h = seed
    n = len(data) // 4
    rotl = lambda x, r: ((x << r) | (x >> (32 - r))) & 0xFFFFFFFF
    for i in range(n):
        k = struct.unpack_from('<I', data, i * 4)[0]
        k = (rotl((k * c1) & 0xFFFFFFFF, 15) * c2) & 0xFFFFFFFF
        h = (rotl(h ^ k, 13) * 5 + 0xe6546b64) & 0xFFFFFFFF
    tail = data[n * 4:]
    k = 0
    for i, b in enumerate(tail):
        k |= b << (8 * i)
    if tail:
        k = (rotl((k * c1) & 0xFFFFFFFF, 15) * c2) & 0xFFFFFFFF
        h ^= k
    h ^= len(data)
    h ^= h >> 16; h = (h * 0x85ebca6b) & 0xFFFFFFFF
    h ^= h >> 13; h = (h * 0xc2b2ae35) & 0xFFFFFFFF
    h ^= h >> 16
    return h
```

Test vectors: `murmur3_utf16("Face__geo__p000_cbs.crct_brow_lateral_L") == 3678951475` (a native Leon channel), `murmur3_utf16("SK__demo.eye_close_L") == 3231110021`.

Naming conventions (not enforced by the panel, but recommended): ASCII only; prefix `SK__` so custom channels can never collide with Leon's native `Face__geo__...` channels; then `<modtag>.<name>`, e.g. `SK__arkit.jawOpen` for ARKit-library keys and `SK__mytag.mouth_a` for others. Channel names containing non-ASCII characters hash correctly (UTF-16), but ASCII ids are safer for tooling.

Weight array: for a bound mesh the engine must hold a weight array at least as long as the highest channel the panel writes to. Leon's head allocates it by itself; **body and hair meshes do not** (WeightCount stays 0), so the panel (0.4.3+) sizes them to the channel count when the engine's managed weight list already holds every channel. Writes beyond the array are blocked by the panel (an unprotected out-of-range write crashed the game in an early test). See [API.md](API.md).

Mesh-side facts that affect game behaviour (the tooling that writes them is not public):

- Shape keys only work on LOD0; the panel forces `LodLevel = 0` while driving.
- For meshes that carry shape keys the engine recomputes normals, so toon (cylindrical) normals are lost unless the mod uses a workaround (tiny "fin" triangles per vertex was accepted in game on one mod; it costs mesh size).
- A head mesh in the reference layout keeps Leon's 91 original channel names as zero-delta "taps" at indices 0..90 and appends the custom keys after them. The panel does not require this layout; it binds by hash.

### 4. Regions and GUI tabs

`region` groups keys for the strength sliders in the in-game panel (only regions listed in the top-level `regions` array get a slider). The in-game panel does not split pages by region.

The desktop Studio (0.4) builds its left navigation from the keys. Built-in regions map to four fixed pages, `REGION_PAGE` in Studio's `src/ui/app.js`:

| Region id | Studio page |
|---|---|
| `eye`, `gaze`, `mouth`, `brow`, `effect` | Expression (face) |
| `shape` | Face shaping |
| `body`, `outfit` | Body and outfit |
| `hair`, `ear`, `hairstyle` | Hair and ears |

**Any other region id automatically becomes its own tab**, placed after the built-in pages and before presets / capture / diagnostics. The tab title comes from Studio's translation table when the id is known (pre-registered: `outfit_variant`, `nail`, `eye_detail`, `mouth_detail`) and is otherwise the raw region id, so choose readable ids. A page with no keys is hidden. Keys with an empty `region` go to an "other" tab. (This tab logic is in Studio 0.4; "0.4 source sync pending" in the Studio repository.)

### 5. Two-layer retarget (ARKit as the common currency)

```
 native Leon facial animation --(native_leon.json rules)-->\
                                                            >  ARKit 52 coefficients  -->  character keys
 RhyLive phone capture (52 values, x gain, EMA smoothing)-->/
```

1. **Layer 1, source to ARKit 52.** Native Leon animation is converted by `RE4R_ShapeKeySystem_native_leon.json` (rules of the form `{key: <ARKit name>, joint | taps, lo, hi, gain}`; the signal is normalized between `lo` and `hi`, multiplied by `gain`, summed per ARKit name and clamped to 0..1). Face capture supplies the 52 ARKit values directly (times per-channel gain, times capture strength, smoothed). This layer is model independent.
2. **Layer 2, ARKit to character keys** (this profile). For a key with `library: "ARKit"` the value of the ARKit coefficient called `name` is used 1:1. For any other key the value is
   `sum( arkitValue(name_i) * gain_i )` over its `arkit` list `[[name_1, gain_1], [name_2, gain_2], ...]`.

Final weight of a key:

```
weight = clamp( ( manual_slider + arkit_contribution ) * global_strength * region_strength , 0 , 1 )
```

(`manual_slider` is excluded when the source is "native animation" only; `arkit_contribution` is 0 when the source is "manual".)

The 52 ARKit names (use these exact spellings, case sensitive):

```
browDownLeft browDownRight browInnerUp browOuterUpLeft browOuterUpRight
cheekPuff cheekSquintLeft cheekSquintRight
eyeBlinkLeft eyeBlinkRight eyeLookDownLeft eyeLookDownRight eyeLookInLeft eyeLookInRight
eyeLookOutLeft eyeLookOutRight eyeLookUpLeft eyeLookUpRight
eyeSquintLeft eyeSquintRight eyeWideLeft eyeWideRight
jawForward jawLeft jawOpen jawRight
mouthClose mouthDimpleLeft mouthDimpleRight mouthFrownLeft mouthFrownRight mouthFunnel mouthLeft
mouthLowerDownLeft mouthLowerDownRight mouthPressLeft mouthPressRight mouthPucker mouthRight
mouthRollLower mouthRollUpper mouthShrugLower mouthShrugUpper mouthSmileLeft mouthSmileRight
mouthStretchLeft mouthStretchRight mouthUpperUpLeft mouthUpperUpRight
noseSneerLeft noseSneerRight tongueOut
```

Left/right: ARKit "Left" is the subject's (character's) left. Do not guess sides from key names; measure the side from the key's deformation (the reference generator uses the sign of the delta centroid x: `+x` = character's left) and record it.

#### Mapping guide for common source conventions

The gains below are the starting values used by the author's reference generator (`RET` table), which were tuned for a small set of example characters. **Treat them as starting points, not as numbers to copy**: tune them in game for your own model. Rows marked "(untested guess)" are not in the reference table.

| Source convention / key | `library` | ARKit contribution (`arkit` list) | Notes |
|---|---|---|---|
| ARKit / Perfect-Sync (52 names) | `ARKit` | none (1:1 by `name`) | Key `name` must equal the ARKit name; id such as `SK__arkit.jawOpen`. |
| VRChat / VRM blink (L / R) | any non-ARKit | L: `[["eyeBlinkLeft",1.0]]`, R: `[["eyeBlinkRight",1.0]]` | Single "blink both" key: `[["eyeBlinkLeft",0.5],["eyeBlinkRight",0.5]]`. |
| VRChat visemes `aa` / VRM `A`, MMD `あ` | non-ARKit | `[["jawOpen",0.9]]` | |
| viseme `ou` / VRM `O`, MMD `お` | non-ARKit | `[["mouthFunnel",0.9]]` | |
| viseme `U` / `uu`, MMD `う` | non-ARKit | `[["mouthPucker",1.0]]` | |
| viseme `ih` / VRM `I`, MMD `い` | non-ARKit | `[["mouthStretchLeft",0.7],["mouthStretchRight",0.7]]` | (untested guess) |
| viseme `E` / VRM `E`, MMD `え` | non-ARKit | `[["jawOpen",0.5],["mouthStretchLeft",0.4],["mouthStretchRight",0.4]]` | (untested guess) |
| MMD `まばたき` (blink, both) | non-ARKit | `[["eyeBlinkLeft",0.5],["eyeBlinkRight",0.5]]` | |
| MMD `ウィンク` / `ウィンク右` (wink) | non-ARKit | `[["eyeBlinkLeft",1.0]]` / `[["eyeBlinkRight",1.0]]` | Check which side the deformation is on. |
| MMD `笑い` / happy eyes (L/R) | non-ARKit | `[["eyeSquintLeft",0.5]]` / `[["eyeSquintRight",0.5]]` | |
| surprised / wide eyes | non-ARKit | `[["eyeWideLeft",0.5],["eyeWideRight",0.5]]` | |
| smile / mouth corner up (L/R) | non-ARKit | `[["mouthSmileLeft",1.0]]` / `[["mouthSmileRight",1.0]]` | |
| frown / mouth corner down (L/R) | non-ARKit | `[["mouthFrownLeft",1.0]]` / `[["mouthFrownRight",1.0]]` | |
| wide mouth / stretch (L/R) | non-ARKit | `[["mouthStretchLeft",0.7]]` / `[["mouthStretchRight",0.7]]` | |
| angry brow (L/R), MMD `怒り` | non-ARKit | `[["browDownLeft",1.0]]` / `[["browDownRight",1.0]]` | |
| troubled / sad brow (L/R), MMD `困る` | non-ARKit | `[["browInnerUp",0.6]]` on each side | |
| raised brow (L/R) | non-ARKit | `[["browOuterUpLeft",1.0]]` / `[["browOuterUpRight",1.0]]` | |
| cheek puff (L/R) | non-ARKit | `[["cheekPuff",0.8]]` on each side | |
| tongue out, MMD `ぺろっ` | non-ARKit | `[["tongueOut",1.0]]` | |
| eye look left / right / up / down | non-ARKit | left: `[["eyeLookOutLeft",G],["eyeLookInRight",G]]`, right: `[["eyeLookInLeft",G],["eyeLookOutRight",G]]`, up: `[["eyeLookUpLeft",G],["eyeLookUpRight",G]]`, down: `[["eyeLookDownLeft",G],["eyeLookDownRight",G]]` | Reference value `G = 0.35`: Leon's full eye rotation drove the iris too far at 1.0. Source models without gaze keys need synthetic translation keys. |
| Keys with no ARKit equivalent (hair, outfit, body shape, special-effect eyes, etc.) | any | omit `arkit` | Manual sliders only. |

### 6. Minimal valid example

Three keys: one ARKit-library key (1:1), one retargeted key, one manual-only body key. The hashes are real values for these ids.

```json
{
  "format": 2,
  "model": "demo",
  "title": "Demo character",
  "regions": [
    { "id": "eye",  "label": "Eyes" },
    { "id": "mouth", "label": "Mouth" },
    { "id": "body", "label": "Body" }
  ],
  "native_taps": [
    { "name": "Face__geo__p000_cbs.crct_brow_lateral_L", "hash": 3678951475 }
  ],
  "keys": [
    { "id": "SK__arkit.jawOpen", "hash": 2743593822, "label": "Jaw open",
      "name": "jawOpen", "library": "ARKit", "group": "Mouth", "region": "mouth" },
    { "id": "SK__demo.eye_close_L", "hash": 3231110021, "label": "Eye close L",
      "name": "eye_close_L", "library": "VRC", "group": "Eyes", "region": "eye",
      "max_cm": 2.9, "source": "eye_close_L",
      "arkit": [["eyeBlinkLeft", 1.0]] },
    { "id": "SK__demo.breast_big", "hash": 1200267882, "label": "Bust bigger",
      "name": "breast_big", "library": "VRC", "group": "Body", "region": "body" }
  ]
}
```

`native_taps` can be left out entirely if your head mesh does not keep Leon's native channels.

### 7. Checklist for mod authors

- [ ] File is at `reframework/data/RE4R_ShapeKeySystem_profile.json`, valid UTF-8 JSON, top-level `keys` array.
- [ ] Every key has `id`, `hash`, `label`, `name`, `library`, `group`, `region` as strings (`hash` an integer).
- [ ] Every `id` is unique and is the exact channel name in the mesh; every `hash` equals `murmur3_utf16(id)` (UTF-16LE, seed `0xFFFFFFFF`), unique within the mesh.
- [ ] ARKit-library keys have `name` equal to a valid ARKit name (case sensitive).
- [ ] `arkit` entries use valid ARKit names; left/right sides were measured, not guessed.
- [ ] Every region used by a key is declared in `regions` (or you accept no strength slider) and has a readable id (it becomes a Studio tab title if it is not a built-in region).
- [ ] The shipped meshes have shape-key data that the engine accepts (LOD0 present, weight arrays: head allocates itself; body/hair rely on the panel's allocation, which is 0.4.3+).
- [ ] You also ship `RE4R_ShapeKeySystem_native_leon.json` if you want native-animation conversion (it is model independent and shared).
- [ ] In game: panel shows the meshes bound and weight arrays at full length; run the sweep page over every key; for face capture also check the debug page that native animation never writes your custom keys.
- [ ] Do not ship third-party models or assets you have no right to redistribute.

---

## 中文

本文是角色 MOD 与形态键面板之间的约定。MOD 需要把下面这个文件放在

```
<游戏目录>/reframework/data/RE4R_ShapeKeySystem_profile.json
```

（UTF-8 JSON，由 REFramework 的 `json.load_file` 读取）。它描述 MOD 网格里有哪些 blend shape 通道、如何命名和分组，以及 ARKit 数值（来自原生动画或面捕）如何驱动它们。下文以面板 **0.4.4** 实际读取的内容为准；桌面 Studio 通过面板的桥接读取同一批键。

> 把形态键写进 RE4 `.mesh` 目前需要**尚未公开**的工具。本文只规定必须随网格一起提供的配置文件。

### 1. 顶层字段

| 字段 | 是否必须 | 类型 | 谁使用 | 含义 |
|---|---|---|---|---|
| `keys` | **必须** | 数组 | 面板 | 键列表（第 2 节）。文件不存在或 `keys` 不是数组时，面板提示未找到配置并保持空闲。 |
| `regions` | 可选（建议提供） | `{id, label}` 数组 | 面板 | 在表情页各得到一个强度滑条的区域，按此顺序显示。`id`、`label` 必须是字符串。键的 `region` 未在此声明时仍然有效（增益 1.0），只是没有滑条。 |
| `native_taps` | 可选 | `{name, hash}` 数组 | 面板 | 头部网格里已有的零位移通道（里昂原版 `Face__geo__p000_cbs.crct_*`）。只**读取**（显示原生活动、供基于 tap 的换算规则使用），从不写入。`hash` 是 `name` 的哈希（第 3 节）。只在头部网格查找。网格里没有就省略。 |
| `title` | 可选 | 字符串 | 面板 | 显示在面板标题和状态栏；缺省取 `model`，再缺省为 `?`。 |
| `model` | 可选 | 字符串 | 面板 | 模型短名；`title` 的后备。 |
| `format` | 可选 | 数字 | 无（仅说明） | 配置版式版本。参考生成器写 `2`，不校验。 |
| `mesh` | 可选 | 字符串 | 无（仅说明） | 键写入的头部网格路径。不读取；运行时按哈希找网格。 |
| `retarget_note` | 可选 | 字符串 | 无（仅说明） | 给人看的备注，例如左右是怎么判定的。 |

未知字段会被忽略，可以放自己的元数据。

### 2. 键字段

`keys` 的每个元素是一个对象：

| 字段 | 是否必须 | 类型 | 含义 |
|---|---|---|---|
| `id` | **必须** | 字符串，唯一 | **写进网格的 blend shape 通道名**（如 `SK__demo.eye_close_L`）。也是保存滑条值和预设的键，版本之间不要改名。 |
| `hash` | **必须** | 整数 0..4294967295 | 引擎对 `id` 的哈希（第 3 节），这是把键绑定到网格通道的依据。 |
| `label` | **必须** | 字符串 | 滑条上的文字（任意语言），也会被搜索框检索。 |
| `name` | **必须** | 字符串 | 技术短名，显示在括号里并参与搜索。ARKit 库的键必须是准确的 ARKit 名（第 5 节）。 |
| `library` | **必须** | 字符串 | 来源约定。`"ARKit"` 表示该键由名为 `name` 的 ARKit 系数 1:1 驱动；其他任意字符串（`"MMD"`、`"VRC"`、`"custom"` 等）表示通过 `arkit` 列表和/或手动驱动。面板的库筛选只有“全部 / ARKit / MMD”，其他库在“全部”下可见。 |
| `group` | **必须** | 字符串 | 形态键页和 Studio 里的小标题。 |
| `region` | **必须** | 字符串 | 区域 id（第 4 节），决定所属强度滑条和 Studio 标签页。空字符串会进入 Studio 的“other”页。 |
| `arkit` | 可选 | `[ARKit名, 增益]` 数组 | 非 ARKit 键的换算列表，见第 5 节。省略 `gain` 时按 1。`library: "ARKit"` 的键忽略此字段。 |
| `max_cm` | 可选 | 数字 | 该键最大顶点位移（厘米），生成器写的说明信息，面板不读。 |
| `source` | 可选 | 字符串 | 源模型里该键的名字，生成器写的说明信息，面板不读。 |

注意：

- 面板 UI 会对 `label`、`name`、`library`、`group` 做字符串拼接或转小写，**缺失或非字符串会在绘制面板时触发 Lua 错误**，请视为必须。
- 配置里**没有网格序号字段**。哪个网格带有某个键是运行时发现的：面板先用玩家头部网格匹配，再把含有未绑定键的身体/头发网格（在玩家身体对象的层级下查找）附加进来。所以一份配置可以横跨头、身体、头发多个网格。哈希在任何网格都找不到的键保持未绑定（滑条禁用，例如可选 add-on 没启用）。
- 滑条范围 0..1，最终权重限幅到 0..1；请把想要的最大形变做进权重 1。

### 3. `id` 与 `hash`：必须与网格怎样对应

运行时面板读取候选网格的 `get_ChannelNameHash`，建立 `哈希 -> 通道序号` 表，`key.hash` 在表里就绑定。**从不按序号或明文名字匹配。** 因此：

1. 写入网格的通道名（写网格时对它求哈希的那个字符串）必须与配置里的 `id` 逐字符一致。
2. `hash` 必须是该名字的哈希：对名字的 **UTF-16LE 字节**做 **MurmurHash3 x86 32 位，种子 `0xFFFFFFFF`**，结果为无符号 32 位整数。
3. 同一个网格内哈希不能重复。

参考实现（Python）见上方英文部分的 `murmur3_utf16`。测试向量：`murmur3_utf16("Face__geo__p000_cbs.crct_brow_lateral_L") == 3678951475`（里昂原生通道），`murmur3_utf16("SK__demo.eye_close_L") == 3231110021`。

命名约定（面板不强制，建议遵守）：只用 ASCII；加前缀 `SK__`，保证自定义通道永远不会和里昂原生的 `Face__geo__...` 通道冲突；之后是 `<模型标记>.<名字>`，例如 ARKit 库的键 `SK__arkit.jawOpen`，其他键 `SK__mytag.mouth_a`。含非 ASCII 字符的名字按 UTF-16 也能正确求哈希，但 ASCII 对工具更稳妥。

权重数组：被绑定的网格，引擎持有的权重数组长度必须不小于面板要写的最大通道号。里昂头部会自己分配；**身体和头发网格不会**（WeightCount 保持 0），所以面板（0.4.3 起）会在引擎的托管权重列表已装满全部通道时把数量设成通道数。越界写入会被面板拦下（早期测试中无保护的越界写入曾让游戏崩溃）。见 [API.md](API.md)。

影响游戏表现的网格侧事实（写入这些数据的工具尚未公开）：

- 形态键只在 LOD0 生效，面板驱动时会强制 `LodLevel = 0`。
- 带形态键的网格，引擎会重算法线，三渲二（柱面）法线会丢失，除非 MOD 采用变通办法（给每个顶点加极小“鳍片”三角形的做法已在一个 MOD 上实机通过，代价是网格体积变大）。
- 参考版式的头部网格把里昂原版 91 个通道名作为零位移 tap 放在 0..90 号，自定义键追加在其后。面板并不要求这一版式，只按哈希绑定。

### 4. 区域与 GUI 标签页

`region` 在游戏内面板里用于分组强度滑条（只有顶层 `regions` 数组里列出的区域才有滑条），游戏内面板不按区域分页。

桌面 Studio（0.4）根据键生成左侧导航。内置区域映射到四个固定页面，即 Studio `src/ui/app.js` 里的 `REGION_PAGE`：

| 区域 id | Studio 页面 |
|---|---|
| `eye`、`gaze`、`mouth`、`brow`、`effect` | 表情（face） |
| `shape` | 捏脸 |
| `body`、`outfit` | 身体与服装 |
| `hair`、`ear`、`hairstyle` | 头发与耳朵 |

**其他任何区域 id 会自动各成一个标签页**，排在内置页之后、预设 / 面捕 / 诊断之前。已知 id 的标题来自 Studio 的翻译表（已预注册：`outfit_variant`、`nail`、`eye_detail`、`mouth_detail`），否则显示 region 原文，所以请取可读的 id。没有键的页面会隐藏；`region` 为空的键进入“other”页。（该标签页逻辑在 Studio 0.4 中；Studio 仓库标注“0.4 源码同步待办”。）

### 5. 两层换算（以 ARKit 为通用中间量）

```
 游戏原生里昂面部动画 --(native_leon.json 规则)-->\
                                                   >  ARKit 52 系数  -->  角色自己的键
 RhyLive 手机面捕（52 值，×增益，EMA 平滑）------>/
```

1. **第一层：来源 → ARKit 52。** 原生里昂动画由 `RE4R_ShapeKeySystem_native_leon.json` 换算（规则形如 `{key: <ARKit名>, joint | taps, lo, hi, gain}`：信号在 `lo`、`hi` 之间归一化，乘 `gain`，按 ARKit 名累加并限幅到 0..1）。面捕直接提供 52 个 ARKit 值（乘单通道增益、面捕强度，再平滑）。这一层与模型无关。
2. **第二层：ARKit → 角色的键**（即本配置）。`library: "ARKit"` 的键直接使用名为 `name` 的 ARKit 系数（1:1）。其他键取其 `arkit` 列表 `[[名1, 增益1], [名2, 增益2], ...]` 的 `sum( ARKit值(名i) × 增益i )`。

键的最终权重：

```
权重 = clamp( ( 手动滑条 + ARKit贡献 ) × 全局强度 × 区域强度 , 0 , 1 )
```

（来源为“原生动画”时不含手动滑条；来源为“手动”时 ARKit 贡献为 0。）

52 个 ARKit 名称见上方英文部分的列表（区分大小写，必须按此拼写）。

左右：ARKit 的 “Left” 指对象（角色）自己的左边。不要凭键名猜左右，应按形变实测（参考生成器用形变重心 x 的符号，`+x` = 角色左），并记录下来。

#### 常见来源约定的映射指南

下表增益是作者参考生成器（`RET` 表）的起始值，针对少数示例角色调过。**请当作起点而不是照抄的数字**，在游戏里按自己的模型调整。标注“（未验证的猜测）”的行不在参考表中。

| 来源约定 / 键 | `library` | ARKit 贡献（`arkit` 列表） | 备注 |
|---|---|---|---|
| ARKit / Perfect-Sync（52 个名字） | `ARKit` | 无（按 `name` 1:1） | `name` 必须等于 ARKit 名；id 例如 `SK__arkit.jawOpen`。 |
| VRChat / VRM 眨眼（左 / 右） | 非 ARKit | 左 `[["eyeBlinkLeft",1.0]]`，右 `[["eyeBlinkRight",1.0]]` | 只有一个“双眼眨眼”键时：`[["eyeBlinkLeft",0.5],["eyeBlinkRight",0.5]]`。 |
| viseme `aa` / VRM `A`，MMD `あ` | 非 ARKit | `[["jawOpen",0.9]]` | |
| viseme `ou` / VRM `O`，MMD `お` | 非 ARKit | `[["mouthFunnel",0.9]]` | |
| viseme `U` / `uu`，MMD `う` | 非 ARKit | `[["mouthPucker",1.0]]` | |
| viseme `ih` / VRM `I`，MMD `い` | 非 ARKit | `[["mouthStretchLeft",0.7],["mouthStretchRight",0.7]]` | （未验证的猜测） |
| viseme `E` / VRM `E`，MMD `え` | 非 ARKit | `[["jawOpen",0.5],["mouthStretchLeft",0.4],["mouthStretchRight",0.4]]` | （未验证的猜测） |
| MMD `まばたき`（双眼眨眼） | 非 ARKit | `[["eyeBlinkLeft",0.5],["eyeBlinkRight",0.5]]` | |
| MMD `ウィンク` / `ウィンク右`（单眼眨） | 非 ARKit | `[["eyeBlinkLeft",1.0]]` / `[["eyeBlinkRight",1.0]]` | 先确认形变在哪一侧。 |
| MMD `笑い` / 笑眼（左 / 右） | 非 ARKit | `[["eyeSquintLeft",0.5]]` / `[["eyeSquintRight",0.5]]` | |
| 惊讶 / 睁大眼 | 非 ARKit | `[["eyeWideLeft",0.5],["eyeWideRight",0.5]]` | |
| 微笑 / 嘴角上扬（左 / 右） | 非 ARKit | `[["mouthSmileLeft",1.0]]` / `[["mouthSmileRight",1.0]]` | |
| 嘴角下垂（左 / 右） | 非 ARKit | `[["mouthFrownLeft",1.0]]` / `[["mouthFrownRight",1.0]]` | |
| 嘴横拉（左 / 右） | 非 ARKit | `[["mouthStretchLeft",0.7]]` / `[["mouthStretchRight",0.7]]` | |
| 生气眉（左 / 右），MMD `怒り` | 非 ARKit | `[["browDownLeft",1.0]]` / `[["browDownRight",1.0]]` | |
| 困扰 / 伤心眉（左 / 右），MMD `困る` | 非 ARKit | 两侧各 `[["browInnerUp",0.6]]` | |
| 抬眉（左 / 右） | 非 ARKit | `[["browOuterUpLeft",1.0]]` / `[["browOuterUpRight",1.0]]` | |
| 鼓腮（左 / 右） | 非 ARKit | 两侧各 `[["cheekPuff",0.8]]` | |
| 吐舌，MMD `ぺろっ` | 非 ARKit | `[["tongueOut",1.0]]` | |
| 视线 左 / 右 / 上 / 下 | 非 ARKit | 左 `[["eyeLookOutLeft",G],["eyeLookInRight",G]]`，右 `[["eyeLookInLeft",G],["eyeLookOutRight",G]]`，上 `[["eyeLookUpLeft",G],["eyeLookUpRight",G]]`，下 `[["eyeLookDownLeft",G],["eyeLookDownRight",G]]` | 参考值 `G = 0.35`：1.0 时里昂完整的眼球转动会让虹膜移动过大。源模型没有视线键时需要合成平移键。 |
| 没有 ARKit 对应的键（头发、服装、身体形状、特效眼等） | 任意 | 省略 `arkit` | 只能手动滑条。 |

### 6. 最小有效示例

三个键：一个 ARKit 库键（1:1）、一个换算键、一个仅手动的身体键。哈希是这些 id 的真实值。

```json
{
  "format": 2,
  "model": "demo",
  "title": "示例角色",
  "regions": [
    { "id": "eye",  "label": "眼" },
    { "id": "mouth", "label": "嘴" },
    { "id": "body", "label": "身体" }
  ],
  "native_taps": [
    { "name": "Face__geo__p000_cbs.crct_brow_lateral_L", "hash": 3678951475 }
  ],
  "keys": [
    { "id": "SK__arkit.jawOpen", "hash": 2743593822, "label": "张嘴",
      "name": "jawOpen", "library": "ARKit", "group": "嘴", "region": "mouth" },
    { "id": "SK__demo.eye_close_L", "hash": 3231110021, "label": "闭眼 左",
      "name": "eye_close_L", "library": "VRC", "group": "目", "region": "eye",
      "max_cm": 2.9, "source": "eye_close_L",
      "arkit": [["eyeBlinkLeft", 1.0]] },
    { "id": "SK__demo.breast_big", "hash": 1200267882, "label": "胸部放大",
      "name": "breast_big", "library": "VRC", "group": "身体", "region": "body" }
  ]
}
```

头部网格没有保留里昂原生通道时，`native_taps` 可以整段省略。

### 7. MOD 作者检查清单

- [ ] 文件位于 `reframework/data/RE4R_ShapeKeySystem_profile.json`，是合法的 UTF-8 JSON，顶层有 `keys` 数组。
- [ ] 每个键都有字符串类型的 `id`、`label`、`name`、`library`、`group`、`region` 和整数 `hash`。
- [ ] 每个 `id` 唯一，且就是网格里的准确通道名；每个 `hash` 等于 `murmur3_utf16(id)`（UTF-16LE，种子 `0xFFFFFFFF`），网格内不重复。
- [ ] ARKit 库的键，`name` 是合法 ARKit 名（区分大小写）。
- [ ] `arkit` 里用的是合法 ARKit 名；左右是实测的，不是猜的。
- [ ] 键用到的每个区域都在 `regions` 里声明（或者接受没有强度滑条），并且 id 可读（不是内置区域时它会成为 Studio 标签页标题）。
- [ ] 随包网格里的形态键数据能被引擎接受（有 LOD0；权重数组：头部自己分配，身体/头发依赖面板 0.4.3 起的自动分配）。
- [ ] 想要原生动画换算，就同时提供 `RE4R_ShapeKeySystem_native_leon.json`（与模型无关，可共用）。
- [ ] 进游戏：面板显示网格已绑定且权重数组达到满长；在巡检页过一遍所有键；用面捕时还要在调试页确认原生动画没有写你的自定义键。
- [ ] 不要随包发布你无权再分发的第三方模型或素材。
