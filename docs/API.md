# RE4R_ShapeKeySystem public API (0.4.4)

[English](#english) | [中文](#中文)

## English

For other REFramework scripts, for example the bridge section of the desktop Studio. After the panel loads it defines one global table:

```lua
local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
if not api then return end        -- panel not loaded (yet)
```

| Member | Since | Description |
|---|---|---|
| `api.version` | 0.4.3 | Panel version string. |
| `api.mesh_status()` | 0.4.3 | List of bound meshes: `{index, name, channels, weight_count, weight_list, limit, ready}`. `index` 1 is the head; 2 and up are body / hair meshes. `weight_count` is the engine's `BlendShapeChannelWeightCount`, `weight_list` the length of the engine weight list, `limit` the highest writable channel count the panel allows, `ready` is true when the weight count already covers every channel. Empty list when nothing is bound. |
| `api.allocate_weights(i)` | 0.4.3 | Sizes a body/hair mesh's weight array to its channel count (what the debug page's manual "set WeightCount" button does). `i` is the mesh index; `nil` means all extra meshes. Returns the number of meshes sized by this call. The head (index 1) is never touched, because Leon's facial controller allocates it. It only acts when the engine's managed weight list already holds every channel. |
| `api.get_auto_allocate()` / `api.set_auto_allocate(bool)` | 0.4.3 | Automatic allocation switch, on by default, saved in the settings file. |
| `api.get_cap_smooth()` / `api.set_cap_smooth(v)` | 0.4.4 | Face-capture follow speed: the EMA factor applied for each received RhyLive sample. Range 0.05 to 1, default 0.5; larger follows faster, smaller is smoother. `set` clamps into the range, accepts values convertible by `tonumber`, returns `false` for invalid values, NaN or infinity, returns `true` on success, saves to the settings file, and is the same value as the panel's slider. |

### Background

Only Leon's head carries `chainsaw.FacialController_cha0`, so the engine allocates a weight array for the head only; the WeightCount of body and hair meshes stays 0 and writing past it can crash the game. Setting it by hand to the channel count was verified safe in game on one example mod. Automatic allocation (0.4.3 and later) retries about once per second until it succeeds; it first confirms the engine's weight list already holds every channel and only then sets the count. Automatic allocation itself has been stub-tested; in-game confirmation is pending.

### Example

```lua
local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
if api then
    for _, m in ipairs(api.mesh_status()) do
        log.info(('%d %s %d/%d ready=%s'):format(m.index, m.name, m.weight_count or -1, m.channels, tostring(m.ready)))
    end
    api.set_cap_smooth(0.35)          -- smoother capture (0.4.4+)
end
```

Wrap calls in `pcall` and check for the function with `api.set_cap_smooth ~= nil` if you must also support 0.4.3.

## 中文

给其他 REFramework 脚本用，例如桌面 Studio 的桥接段。面板加载后会定义一个全局表：

```lua
local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
if not api then return end        -- 面板还没加载
```

| 成员 | 起始版本 | 说明 |
|---|---|---|
| `api.version` | 0.4.3 | 面板版本字符串。 |
| `api.mesh_status()` | 0.4.3 | 已绑定网格的列表 `{index, name, channels, weight_count, weight_list, limit, ready}`。`index` 为 1 的是头部，2 及以后是身体、头发。`weight_count` 是引擎的 `BlendShapeChannelWeightCount`，`weight_list` 是引擎权重列表长度，`limit` 是面板允许写入的通道上限，`ready` 表示权重数量已覆盖全部通道。未绑定时返回空表。 |
| `api.allocate_weights(i)` | 0.4.3 | 把身体/头发网格的权重数组设成通道数（等同调试页“手动：设置 WeightCount”按钮）。`i` 是网格序号，`nil` 表示所有额外网格。返回这次设好的网格数。头部（1）不处理，因为里昂的面部控制器会自己分配。仅在引擎的托管权重列表已经装满全部通道时才会执行。 |
| `api.get_auto_allocate()` / `api.set_auto_allocate(bool)` | 0.4.3 | 自动分配开关，默认开启，写进设置文件。 |
| `api.get_cap_smooth()` / `api.set_cap_smooth(v)` | 0.4.4 | 面捕跟随速度，即每收到一个 RhyLive 采样的 EMA 系数。范围 0.05–1，默认 0.5；越大越跟手，越小越平滑。`set` 会限幅到范围内，接受可由 `tonumber` 转换的值，无效值 / NaN / 无穷返回 `false`，成功返回 `true`，写进设置文件，与面板里的滑条是同一个值。 |

### 背景

只有里昂头部带 `chainsaw.FacialController_cha0`，所以引擎只给头部分配权重数组；身体和头发的 WeightCount 一直是 0，越界写入会让游戏崩溃。手动设成通道数已在一个示例 MOD 上实机验证安全。自动分配（0.4.3 起）每秒重试一次直到成功，会先确认引擎的权重列表已装满全部通道，然后才设置数量。自动分配本身仅经过桩测试，实机确认待做。

### 示例

```lua
local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
if api then
    for _, m in ipairs(api.mesh_status()) do
        log.info(('%d %s %d/%d ready=%s'):format(m.index, m.name, m.weight_count or -1, m.channels, tostring(m.ready)))
    end
    api.set_cap_smooth(0.35)          -- 更平滑（0.4.4 起）
end
```

调用请包在 `pcall` 里；若还要兼容 0.4.3，先判断 `api.set_cap_smooth ~= nil`。
