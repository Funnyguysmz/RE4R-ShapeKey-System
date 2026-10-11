# RE4R_ShapeKeySystem 公开接口（0.4.3 起）

给其他 REFramework 脚本用，例如独立 GUI 的桥接段。面板加载完后会定义一个全局表：

```lua
local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
```

| 函数 | 说明 |
|---|---|
| `api.version` | 面板版本字符串 |
| `api.mesh_status()` | 返回已绑定网格的列表 `{index, name, channels, weight_count, weight_list, limit, ready}`。`index` 为 1 的是头部，2 及以后是身体、头发。`ready` 表示权重数组已经覆盖全部通道 |
| `api.allocate_weights(i)` | 把身体/头发网格的权重数组设成通道数（也就是调试页“手动：设置 WeightCount”按钮做的事）。`i` 是网格序号，`nil` 表示所有额外网格。返回这次设好的网格数。头部（1）不处理，因为里昂的面部控制器会自己分配 |
| `api.get_auto_allocate()` / `api.set_auto_allocate(bool)` | 自动分配开关，默认开启，会写进设置文件 |

背景：只有里昂头部带 `chainsaw.FacialController_cha0`，所以引擎只给头部分配权重数组；身体和头发的 WeightCount 一直是 0。Shinano 实机验证过，手动设成通道数是安全的。0.4.3 的自动分配会每秒重试一次，直到成功；它会先确认引擎的权重列表已经填满全部通道，然后才去设置数量。
