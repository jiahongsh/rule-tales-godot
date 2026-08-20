# 异闻夜谈 · Godot 版

这是《异闻夜谈》从 Qt 6 Widgets 迁移到 Godot 4 的独立工程。它保留规则怪谈跑团的核心约束：玩家导入或选择规则档案，AI 只负责叙事，客户端负责规则检索、权威状态、物品与地图变更、真伪/篡改裁判、存档和结局。

当前工程是可运行、可测试的迁移候选，不是已经签名的正式发行包。Qt 版本仍保留在仓库根目录；模块对应关系见 [迁移映射](docs/MIGRATION_MAPPING.md)，素材来源与发布门禁见 [素材溯源](docs/ASSET_PROVENANCE.md)，引擎许可见 [第三方许可声明](THIRD_PARTY_NOTICES.md)。

## 已迁移能力

- 游戏大厅、档案选择、AI 配置引导与离线体验。
- 横向叙事工作台、常驻状态栏、行动选项、自由输入与上下文资料页。
- `<章节>` 规则解析、安全 BBCode、血字与低频异常文本动态。
- 最近历史窗口、相关历史检索、结构化事实记忆与规则片段检索。
- OpenAI 兼容接口、DeepSeek 模式、设置页连接测试、本机离线流程与客户端状态裁判。
- 背包、ASCII 地图、五类结局、调查评级、关键选择和调试观察器。
- 六个手动槽位、三代自动存档、手动/自动缩略图、便携 JSON 与关键节点时间线。
- 规则工坊、规则种子生成、出口链可解性检查、真假层、篡改与异常指认。
- 程序化界面音效、环境声、窗口化/无边框全屏、五档窗口尺寸、五档帧率上限、文字比例、降低动态和高对比选项。

## 环境要求

- Godot `4.7.1.stable`。`project.godot` 声明了 `4.7` 特性，不应使用较旧版本打开后保存。
- 当前工程使用 GDScript 与 Compatibility 渲染器，不要求 .NET SDK、CMake 或 Qt。
- 联网档案需要用户自己的 OpenAI 兼容 API。API Key 仅驻留当前进程，不写入设置或存档。

## 打开与运行

在 `game_godot` 目录执行：

```powershell
godot --editor --path .
```

直接运行主场景：

```powershell
godot --path .
```

也可以在 Godot 编辑器中打开 `project.godot`，按 F6/F5 运行。第一次打开需等待资源导入完成；`.godot/` 与 `*.import` 生成缓存不应被当作素材来源证明。

不配置 API 时可游玩《夜间档案室》离线体验。白槐中学、雾栖公寓、私人规则和规则种子限时局需要在设置窗口完成联网配置。

## 规则文档

章节标题必须独占一行，并使用半角尖括号：

```text
<入住须知>
不要替镜子里的人回答点名。

<离开方式>
只有在出口条件可验证时才能离开。
```

没有章节标记的文件会作为“全文”导入。规则文件最大 512 KiB。运行时读取的内置内容位于：

- `content/rules/**/*.txt`
- `content/demos/**/*.json`
- `content/rule_packs/**/*.json`

这些是通过 `FileAccess` 从 `res://` 读取的普通文本，不是 Godot 导入资源；发布时必须显式包含，见“导出要求”。

## 数据与隐私

工程启用了固定的自定义 `user://` 目录 `RuleTales/RuleTalesGodot`，避免应用名称调整后路径漂移，也避免与 Qt 版存档发生同名覆盖。

桌面平台默认位置：

- Windows：`%APPDATA%\RuleTales\RuleTalesGodot`
- macOS：`~/Library/Application Support/RuleTales/RuleTalesGodot`
- Linux：`~/.local/share/RuleTales/RuleTalesGodot`

主要文件：

- `settings.cfg`：窗口尺寸、帧率上限、显示、音频、上下文和接口地址；不含 API Key。
- `rule_workshop_draft.cfg`：规则工坊本地草稿。
- `meta.json`：认知点、图鉴和天赋。
- `saves/manual_1.json` 至 `manual_6.json`：手动存档。
- `saves/auto_1.json` 至 `auto_3.json`：轮换自动存档。
- `saves/manual_*.png`、`saves/auto_*.png`：手动与自动存档缩略图。

Qt 旧版位于另一个应用数据目录。两版核心调查文档同为 `save_schema=1`，Godot 已对 Qt 的规则、状态、事实、历史、时间线和局配置等字段进行兼容读取；但当前不会自动扫描或搬运 Qt 数据目录。迁移单个调查时，应在“档案管理”中明确选择“导入 JSON”，由客户端先校验再确认替换当前进度；不要直接用旧文件覆盖 Godot 的同名槽位，也不要让两版共用数据根目录。兼容范围与安全迁移边界见 [MIGRATION_MAPPING.md](docs/MIGRATION_MAPPING.md)。

## 自动验证

先完成导入：

```powershell
godot --headless --editor --path . --import
```

核心状态、规则、事实、裁判与种子生成：

```powershell
godot --headless --path . --script res://tests/core_smoke_test.gd
```

离线体验从启封、行动、六幕推进到结局封存：

```powershell
godot --headless --path . --scene res://tests/offline_end_to_end.tscn
```

Qt `save_schema=1` 文档、旧 Godot 事实字段与自动存档兼容边界：

```powershell
godot --headless --path . --scene res://tests/save_compat_test.tscn
```

档案管理的便携 JSON 导入/导出、替换确认与失败隔离：

```powershell
godot --headless --path . --scene res://tests/save_transfer_smoke.tscn
```

手动/自动存档缩略图的 PNG 编码、提交与 480×270 回读：

```powershell
godot --headless --path . --script res://tests/thumbnail_smoke.gd
```

AI 地址边界、禁止 Bearer 自动重定向、OpenAI 兼容响应与错误诊断：

```powershell
godot --headless --path . --scene res://tests/ai_gateway_smoke.tscn
```

1000 个种子的确定性与可解性回归：

```powershell
godot --headless --path . --script res://tests/generator_fuzz_test.gd
```

大厅、设置、存档、工坊、种子窗口及离线回合运行态测试：

```powershell
godot --headless --path . --scene res://tests/ui_runtime_smoke.tscn
```

成功标志分别为 `CORE_SMOKE_OK`、`OFFLINE_END_TO_END_OK`、`SAVE_COMPAT_OK`、`SAVE_TRANSFER_SMOKE_OK`、`THUMBNAIL_SMOKE_OK`、`AI_GATEWAY_SMOKE_OK`、`GENERATOR_FUZZ_OK:1000` 与 `UI_RUNTIME_SMOKE_OK`。发布前还需要在真实图形环境检查窗口缩放、中文字体回退、音量、键盘焦点和降低动态模式。

## 导出要求

仓库目前没有 `export_presets.cfg`。这是有意保留的发布门禁：目标平台、模板、架构、签名、包标识与输出路径尚未由发布者确认，因此不能凭开发机情况伪造一个“可上线”预设。

创建正式预设时，在 Godot 的“项目 → 导出”中完成以下检查：

1. 安装与 Godot 4.7.1 匹配的官方导出模板，并选择真实目标平台。
2. 资源模式需覆盖 `scenes/main.tscn` 的全部依赖和动态加载的音频、图片。首次发布建议从“导出项目中的所有资源”开始，再按审计结果排除 `artifacts/` 与 `tests/`。
3. 在“导出非资源文件/文件夹的过滤器”中加入 `*.txt, *.json`。Godot 官方文档明确说明 `.txt`、`.json`、`.csv` 等普通文件依赖该过滤器进入包体。
4. 不要把 `.godot/export_credentials.cfg` 提交到版本库；正式生成的 `export_presets.cfg` 可以提交，但必须先审查其中的平台设置。
5. 在干净目录或干净设备运行导出物，至少启动离线档案和规则种子预检，以确认所有 `content/**/*.txt`、`content/**/*.json` 都能从 `res://` 读取。
6. 完成 [ASSET_PROVENANCE.md](docs/ASSET_PROVENANCE.md) 中的许可门禁，把原创大厅背景的生成记录归入团队发行档案，并按 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 随发行物提供 Godot Engine 完整 MIT 正文和对应版本的第三方版权清单。

建立预设后，命令行格式为：

```powershell
godot --headless --path . --export-release "<已审查的预设名称>" "<平台对应的输出路径>"
```

命令行导出仍然依赖现有预设；不要把示例占位符当作真实平台配置。

## 目录结构

```text
game_godot/
├─ assets/       运行时图像、SVG 与程序化 WAV
├─ content/      内置规则、离线流程与规则碎片包
├─ docs/         迁移映射与素材来源台账
├─ scenes/       主场景和屏幕入口
├─ scripts/
│  ├─ ai/        提示词、上下文与检索组装
│  ├─ core/      权威状态、规则、记忆与会话
│  ├─ engine/    规则裁判与限时局系统
│  ├─ generator/ 确定性规则生成器
│  ├─ net/       HTTPRequest AI 网关
│  ├─ persistence/ 存档与元成长
│  └─ ui/        大厅、游戏工作台和各窗口
├─ tests/        核心、生成器与 UI 运行态验证
├─ artifacts/    开发期截图，不属于运行时素材
└─ THIRD_PARTY_NOTICES.md  Godot 引擎许可与发行归属要求
```

## 已核对的 Godot 4.7.1 官方依据

- “Data paths”：`user://` 在导出项目中保证可写；启用自定义用户目录后使用系统标准应用数据位置。
- `ProjectSettings`：`application/config/use_custom_user_dir` 与 `application/config/custom_user_dir_name`。
- “Exporting projects / Resource options”：非资源文件必须通过导出包含过滤器加入。
- “Exporting projects / Configuration files”：`export_presets.cfg` 可纳入版本控制，`.godot/export_credentials.cfg` 通常不得提交。

本次只依据与工程版本匹配的 Godot 4.7.1 官方离线文档；尚未创建或宣称任何未经验证的平台导出预设。
