# RE4R ShapeKey System

用于生化危机4重制版 REFramework 的游戏内形态键面板，当前版本 **0.4.3**。

支持手动滑条、区域分组、预设、撤销/重做、逐键测试、原生动画换算、RhyLive 面捕和断流回落，提供多网格权重数组分配与脚本 API。身体、服装、头发的控制范围取决于 MOD 实际写入的形态键。

## 安装
1. 安装 REFramework 和带自定义形态键的角色 MOD。
2. 把 src/RE4R_ShapeKeySystem.lua 放入游戏 reframework/autorun/。
3. MOD 必须提供 reframework/data/RE4R_ShapeKeySystem_profile.json，通道哈希要对应实际 MESH。
4. 原生动画换算还需要匹配的 RE4R_ShapeKeySystem_native_leon.json 和 profile 映射。
5. 打开 Script Generated UI → 形态键系统，扫描绑定，先以手动模式测试单键。

面捕需安装 [RhyLive 接收插件](https://github.com/Funnyguysmz/RE4R-RhyLive-Face)，启动接收器。本面板从 rhylive_native 读取快照，无需同时开启骨骼 Drive face。

本仓库不包含模型、原生游戏 MESH、用户设置或模型专用配置。**单独安装脚本不会为普通 MOD 自动添加形态键。**

## 桌面 GUI 和 API
[Studio](https://github.com/Funnyguysmz/RE4R-ShapeKey-Studio) 维护独立 GUI、桥接 DLL 和适配层；本仓库维护基础游戏内脚本。[API 文档](docs/API.md)。

Studio 使用适配后的同名运行脚本，避免用本仓库基础脚本覆盖 GUI 适配层。

## 打包与测试
~~~powershell
.\Package.ps1
lua tests/test_panel.lua src/RE4R_ShapeKeySystem.lua tests/fixture.lua
~~~
输出 build/package/reframework/autorun。fixture 仅作回归测试；无游戏桩测试不代表实机表情、法线、材质与物理验证。

项目自有代码尚未另行声明开源许可。
