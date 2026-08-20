# 第三方许可声明

本文件记录 `game_godot` 当前已确认的第三方软件许可。核对基线为 Godot Engine `4.7.1.stable.official.a13da4feb`；许可正文同时由该版本运行时的 `Engine.get_license_text()` 与本机 4.7.1 官方离线文档“Complying with licenses”交叉确认。

## Godot Engine 4.7.1

本游戏使用 Godot Engine。Godot Engine 以 MIT License 提供；引擎贡献者分别保留其贡献的权利。MIT 条款要求在软件的所有副本或实质部分中保留版权声明和许可声明。

Godot 官方文档允许通过游戏内许可页、制作人员页、可访问的日志或随安装包提供的文件履行展示义务。桌面发行时，本项目选择随最终安装包提供完整官方许可文件；仅把文字留在源码仓库或 PCK 内但不让最终用户访问，不应视为完成发行检查。

以下为 Godot 4.7.1 引擎返回的完整 MIT 许可正文：

```text
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Godot 自带第三方组件

Godot 引擎还包含并非由上述 MIT 文本单独覆盖的第三方组件。Godot 官方文档建议在最终产品文档中同时提供与所用引擎版本匹配的完整 `COPYRIGHT.txt`，可改名为 `GODOT_COPYRIGHT.txt` 以免与项目自己的版权文件混淆。

正式发行时应从实际用于导出的 Godot 4.7.1 官方版本取得该清单；也可用同一引擎二进制的 `Engine.get_copyright_info()` 与 `Engine.get_license_info()` 生成游戏内许可页。不得拿 Qt 版本根目录中的第三方 notice 代替 Godot 引擎清单，因为 Qt、MinGW、FFmpeg 等旧发行链组件不等于 Godot 导出物实际携带的组件。

## 项目自身许可

本文件只处理第三方软件声明，不决定《异闻夜谈》源码、规则文本、生成音频、图标或其他原创内容采用何种许可。项目自身 LICENSE 仍待维护者/权利人选择；在此之前，不能从 Godot 的 MIT License 推导出项目内容已经获得对外授权。素材记录和剩余门禁见 [素材来源与发行许可台账](docs/ASSET_PROVENANCE.md)。

## Godot MCP Native（编辑器工具）

工程的 `addons/godot_mcp/` 引入 Godot MCP Native `1.0.8`，固定到上游提交 `eef4807190e7765e69d59c9e707d0ba170f6770d`，来源为 <https://github.com/yurineko73/Godot-MCP-Native>。版权归 `yurineko73`，采用 MIT License；完整许可正文保存在 `addons/godot_mcp/LICENSE`。

该组件用于 Godot 开发期自动化，不是游戏内容。启用插件时，上游会把 `MCPRuntimeProbe` 注册为项目 Autoload，以支持运行时调试；因此不能仅凭“EditorPlugin”名称推断它不会进入游戏运行时。当前本地补丁把 HTTP MCP 服务明确绑定到 `127.0.0.1`，避免默认监听全部网卡。更新插件时必须重新审计并保留许可与本地安全补丁；导出配置确定后，还要验证插件目录和运行时探针是否被排除在最终游戏包之外。

## 最终发行门禁

- [ ] 在最终安装目录、应用内许可页或其他用户可访问位置附上完整 Godot MIT 正文；桌面包建议提供 `GODOT_LICENSE.txt`。
- [ ] 随包提供与实际 Godot 4.7.1 导出二进制匹配的完整 `GODOT_COPYRIGHT.txt`，或在应用内等价展示引擎第三方版权与许可信息。
- [ ] 确认安装器、商店包或压缩包不会把许可文件留在 PCK 外的构建临时目录而漏发。
- [ ] 为项目自身选择 LICENSE/发行授权，并完成 [ASSET_PROVENANCE.md](docs/ASSET_PROVENANCE.md) 的素材门禁。
- [ ] 如果更换 Godot 版本或自编译引擎，重新从实际二进制/对应官方源码生成并复核本清单。
- [ ] 确认最终游戏导出物不包含仅供开发使用的 `addons/godot_mcp/` 和 `MCPRuntimeProbe` Autoload；若实际分发该组件，随包保留其 MIT 版权与许可正文。

本仓库尚无平台 `export_presets.cfg`，因此当前没有自动把上述文件放入安装包的未经验证配置；发布负责人必须在目标平台预设确定后做一次成品包内容审计。
