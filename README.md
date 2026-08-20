# 异闻夜谈 · Godot

一款使用 Godot 4 制作的 AI 规则怪谈交互游戏。玩家阅读规则、探索异常地点、管理状态与线索，并在每一轮行动中面对由规则约束的叙事结果。

游戏的核心原则是：AI 负责生成叙事，客户端负责规则检索、权威状态、物品与地图变化、事实记忆、异常裁判、存档和结局判定。

## 游戏内容

- 游戏大厅与内置规则档案选择
- 《夜间档案室》离线体验流程
- OpenAI 兼容接口与 DeepSeek 配置
- 规则文本导入、章节解析与安全 BBCode
- 规则工坊：编辑、预览、检查、导入、导出和启封
- 规则种子限时局：确定性生成、真假层、异常观察和出口链检查
- 横向叙事工作台、行动选项与自由输入
- 规则片段检索、相关历史检索与结构化事实记忆
- 背包、探索地图、天气、人物状态、健康、理智和体力
- 存活、逃脱、失踪、污染和特殊结局
- 六个手动存档槽位与三代自动存档
- 关键节点时间线、调查评级和结局回顾
- 程序化交互音效、环境声和动态效果设置
- 窗口化、无边框全屏、窗口尺寸、帧率和无障碍选项

## 环境要求

- Godot `4.7.1.stable`
- GDScript
- Compatibility 渲染器
- 联网档案需要用户自己的 OpenAI 兼容 API

API Key 只保留在当前进程内，不会写入设置、存档、诊断数据或日志。

## 打开与运行

在本目录执行：

```powershell
godot --editor --path .
```

直接运行游戏：

```powershell
godot --path .
```

也可以在 Godot 编辑器中打开 `project.godot`，然后按 F6 或 F5 运行。第一次打开时需要等待资源导入完成。

不配置 API 时，可以直接游玩内置《夜间档案室》离线体验。其他联网档案需要先在设置窗口配置接口地址、模型和 API Key。

## 规则文档

章节标题必须独占一行，并使用半角尖括号：

```text
<入住须知>
不要替镜子里的人回答点名。

<离开方式>
只有在出口条件可验证时才能离开。
```

没有章节标记的文件会作为“全文”导入。规则文件最大为 512 KiB。正文支持安全白名单 BBCode，包括：

`b`、`i`、`u`、`s`、`color`、`size`、`center`、`quote`、`code`、`spoiler`、`blood`、`shake`、`br`

原始 HTML 会被转义，不会直接执行。规则工坊会检查空章节、重复标题、非法标题、未配对标签、重复规则、疑似冲突、规则数量不足、高危效果过量以及缺少出口或解除条件等问题。

## AI 与客户端裁判

每轮请求会分层组装以下内容：

- 最近对话窗口
- 与当前行动相关的历史记录
- 当前规则片段
- 当前权威游戏状态
- 结构化事实记忆
- 本回合可引用的规则 ID

AI 只能返回结构化状态补丁。客户端会校验补丁、事实更新和规则引用，然后一次性提交本回合结果。非法物品扣除、未知地图节点、无依据的状态变化、损坏 JSON 或未检索到的规则引用不会改变权威状态。

规则裁判还会根据本地完整规则检查明确的数值边界、禁带物品和其他可确定约束。无法从文本中可靠判断的复杂自然语言条件，会交由叙事流程处理，不做武断拦截。

## 规则种子模式

规则种子模式使用主题包、种子和生成器版本产生可复现的限时调查局：

- 每局拥有固定种子和持续夜数
- 规则、地点、出口条件与异常事件由客户端确定性生成
- 生成结果必须通过出口链、能力供给、禁令冲突和异常可用性检查
- 每个夜晚可能出现正常观察或异常观察
- 玩家需要判断是否返回、继续探索或处理当前异常
- 客户端保留真假答案，AI 不掌握最终裁判权

同一主题包、种子和生成器版本应得到一致的规则文档。生成器回归测试覆盖 1000 个种子。

## 数据与隐私

工程使用固定的自定义 `user://` 目录：`RuleTales/RuleTalesGodot`。

桌面平台默认位置：

- Windows：`%APPDATA%\RuleTales\RuleTalesGodot`
- macOS：`~/Library/Application Support/RuleTales/RuleTalesGodot`
- Linux：`~/.local/share/RuleTales/RuleTalesGodot`

主要文件包括：

- `settings.cfg`：窗口、显示、音频、上下文和接口设置，不含 API Key
- `rule_workshop_draft.cfg`：规则工坊草稿
- `meta.json`：认知点、图鉴和天赋
- `saves/manual_1.json` 至 `manual_6.json`：手动存档
- `saves/auto_1.json` 至 `auto_3.json`：轮换自动存档
- `saves/manual_*.png`、`saves/auto_*.png`：存档缩略图

便携 JSON 导入会先进行格式和内容校验，再要求确认替换当前调查。失败的导入不会污染现有存档。

## 自动验证

先完成资源导入：

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

存档验证：

```powershell
godot --headless --path . --scene res://tests/save_compat_test.tscn
```

档案导入、导出和失败隔离：

```powershell
godot --headless --path . --scene res://tests/save_transfer_smoke.tscn
```

缩略图编码与回读：

```powershell
godot --headless --path . --script res://tests/thumbnail_smoke.gd
```

AI 网关地址边界、响应解析与错误诊断：

```powershell
godot --headless --path . --scene res://tests/ai_gateway_smoke.tscn
```

1000 个种子的确定性与可解性回归：

```powershell
godot --headless --path . --script res://tests/generator_fuzz_test.gd
```

大厅、设置、存档、工坊、种子窗口及离线回合运行态：

```powershell
godot --headless --path . --scene res://tests/ui_runtime_smoke.tscn
```

成功标志包括：

- `CORE_SMOKE_OK`
- `OFFLINE_END_TO_END_OK`
- `SAVE_COMPAT_OK`
- `SAVE_TRANSFER_SMOKE_OK`
- `THUMBNAIL_SMOKE_OK`
- `AI_GATEWAY_SMOKE_OK`
- `GENERATOR_FUZZ_OK:1000`
- `UI_RUNTIME_SMOKE_OK`

发布前还需要在真实图形环境检查窗口缩放、中文字体回退、音量、键盘焦点和降低动态模式。

## 导出项目

仓库目前没有 `export_presets.cfg`。正式导出前，需要在 Godot 的“项目 → 导出”中确认目标平台、导出模板、架构、签名、包标识和输出路径。

导出时请注意：

1. 安装与 Godot 4.7.1 匹配的官方导出模板。
2. 确保 `scenes/main.tscn` 的全部依赖都被包含。
3. 将普通文本数据加入导出过滤器：`*.txt, *.json`。
4. 不要提交 `.godot/export_credentials.cfg`。
5. 在干净目录或干净设备上验证离线档案和规则种子模式。
6. 发布前完成素材来源、项目授权和第三方许可审核。

创建并审查导出预设后，命令行格式为：

```powershell
godot --headless --path . --export-release "<已审查的预设名称>" "<平台对应的输出路径>"
```

## 目录结构

```text
game_godot/
├─ assets/       运行时图像、SVG 与程序化 WAV
├─ content/      内置规则、离线流程与规则主题包
├─ docs/         素材来源和工程说明
├─ scenes/       主场景和界面入口
├─ scripts/
│  ├─ ai/        提示词与上下文组装
│  ├─ core/      权威状态、规则、记忆与会话
│  ├─ engine/    规则裁判与限时局系统
│  ├─ generator/ 确定性规则生成器
│  ├─ net/       HTTP AI 网关
│  ├─ persistence/ 存档与元成长
│  └─ ui/        大厅、游戏工作台和窗口
├─ tests/        核心、生成器与 UI 运行态验证
├─ artifacts/    开发期截图和视觉回归证据
└─ THIRD_PARTY_NOTICES.md
```

## 许可与素材

Godot Engine 4.7.1 采用 MIT License。项目使用的 Godot MCP Native 编辑器插件也保留其上游 MIT 许可，相关声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

素材来源、生成记录、哈希证据和发布前审核要求见 [docs/ASSET_PROVENANCE.md](docs/ASSET_PROVENANCE.md)。项目自身的源码、规则文本、音频、图标和其他原创内容许可仍需由权利人单独确认；第三方引擎许可不等于项目内容许可。
