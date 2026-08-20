# 素材来源与发行许可台账

## 1. 使用范围

本台账覆盖 `game_godot` 当前运行时会读取的图像、SVG、声音和内置内容，并区分“技术上能加载”与“法律上可公开发行”。没有来源记录的文件不得因为已经进入仓库或 Godot 导入缓存，就被自动视为拥有发行权。

审计日期：2026-08-12。

## 2. 发行结论摘要

| 资产族 | 运行时用途 | 当前证据 | 发行状态 |
|---|---|---|---|
| `assets/audio/**/*.wav` | 交互音效与环境声 | 由仓库 `scripts/generate_sfx.py` 确定性合成；与 Qt `resources/audio` 文件逐项同哈希 | 来源明确；仍需项目自身 LICENSE 覆盖代码与生成输出 |
| `assets/app_icon.svg` | 项目图标 | 与 Qt `resources/app_icon.svg` 同哈希；源 SVG 可读，已进入历史提交 | 项目来源候选；项目 LICENSE 尚缺失，发布前确认权利归属 |
| `assets/backgrounds/archive_lobby_v1.png` | 大厅与规则种子主题背景 | 2026-08-12 通过 Codex ImageGen 为本项目原创生成；提示摘要、会话 ID、原始输出与哈希已记录 | 来源已明确，不再是许可阻断项；发布前把工作站生成记录复制进团队发行档案 |
| `content/rules/**/*.txt` | 内置规则档案 | 雾栖公寓、白槐中学、夜间档案室与 Qt `examples` 对应文件同哈希 | 项目内容；仍需项目 LICENSE/发行授权 |
| `content/rule_packs/**/*.json` | 规则种子碎片与异常池 | 与 Qt `generator/fragments/apartment.json` 同哈希 | 项目内容；仍需项目 LICENSE/发行授权 |
| `content/demos/**/*.json` | 离线体验固定流程 | Godot 迁移工程内的文本数据，无外部来源旁证 | 项目内容候选；需纳入项目 LICENSE 与内容审核 |
| `artifacts/*.png` | 开发截图与视觉回归证据 | 由运行态捕获形成，可能包含上述背景和 UI | 不是运行时素材；默认不导出，转作商店或营销素材前仍需单独审核画面和版本 |

当前没有发现从网络素材站下载的运行时资产。大厅背景有独立的生成记录；音频有可复现脚本；图标和文本仍需由项目权利人纳入项目 LICENSE/发行授权。来源结论只覆盖本次审计到的文件，不能用来替代以后新增素材的逐项登记。

## 3. 程序化音频

仓库根目录的 `scripts/generate_sfx.py` 使用 Python 标准库 `math`、`random`、`struct`、`wave` 合成单声道 44.1 kHz PCM WAV。随机噪声由文件名派生的固定种子驱动，因此生成结果可复现，不依赖在线服务或外部采样包。

生成项：

- 交互：`click`、`page`、`commit`、`reveal`、`danger`、`denied`。
- 状态与工具：`item`、`map`、`damage`、`recover`。
- 结局：`ending_escape`、`ending_lost`。
- 环境循环：`ambient_drone`、`ambient_rain`、`ambient_wind`、`ambient_pulse`。

Godot 文件是 Qt 资源的字节级副本：

```text
resources/audio/click.wav
  == game_godot/assets/audio/sfx/click.wav

resources/audio/ambient_drone.wav
  == game_godot/assets/audio/ambience/ambient_drone.wav
```

审计时已对全部 16 个 WAV 执行 SHA-256 比较，均一致。重新生成命令应从仓库根目录运行：

```powershell
python scripts/generate_sfx.py
```

脚本输出到 Qt 的 `resources/audio`；若重新生成，必须再显式同步到 Godot 的 `assets/audio/sfx` 和 `assets/audio/ambience`，并重新做逐文件哈希比较。不要直接在 Godot 副本上手工修改，否则会破坏来源链。

## 4. 图像与 SVG 哈希证据

### 大厅背景：本项目原创生成

```text
0EECA3F8512A67D91BD253DFA3D98D0E5A82A49FA5A7B5A728315DABA70C1DE9
  game_godot/assets/backgrounds/archive_lobby_v1.png
  1672 × 941 px
```

生成记录：

- 日期：2026-08-12。
- 方式：Codex 内置 ImageGen；没有输入参考图片。
- 会话/记录 ID：`019f6dd9-84cc-75c1-8837-0925a844d4aa`。
- 与工程文件同哈希的原始输出：`exec-3ab09c0b-444e-41b9-ba97-669518716562.png`。
- 工作站原始记录：`%USERPROFILE%\.codex\generated_images\019f6dd9-84cc-75c1-8837-0925a844d4aa`。
- 提示核心：原创 16:9 中式超自然档案馆；左侧约 32% 深色菜单留白；中央至右侧为档案柜墙、楼梯和封禁门；暗金与克制深红；无文字、人物、Logo、水印或血腥画面；不模仿现有作品。

工作站缓存不是团队级长期凭证。发布负责人应把上述原始输出、完整生成记录、生成日期、提示文本和本节哈希复制到版本化的发行档案，并记录最终裁切/调色（如有）。Godot 新背景与 Qt 旧背景已不相同；Qt `resources/images/archive_lobby_v1.png` 不进入 Godot 运行时或本次 Godot 发行清单。

### 应用图标：Qt 来源副本

以下 SHA-256 在审计时一致：

```text
C07CA7802EF0DE8AE1F692AC7DBEF1AE1647DCEDED3C22A5C83C12B814A01496
  resources/app_icon.svg
  game_godot/assets/app_icon.svg
```

图标哈希只能证明 Godot 文件与 Qt 仓库文件相同，不能单独证明著作权或许可。项目权利人仍需确认其创作来源，并在项目 LICENSE/发行授权中明确覆盖。此前未使用的重复品牌图标和来源不明的备用下拉箭头已经从 Godot 工程删除，不进入“导出所有资源”的候选集合；Qt 旧工程文件没有被修改。

## 5. 内置规则与主题数据

Godot 内置规则和 Qt 工作树的对应副本经 SHA-256 比较一致：

- `content/rules/mist_apartment/rules.txt` ↔ `examples/雾栖公寓规则.txt`
- `content/rules/white_locust_school/rules.txt` ↔ `examples/白槐中学校园守则.txt`
- `content/rules/night_archive/rules.txt` ↔ `examples/夜间档案室体验规则.txt`
- `content/rule_packs/apartment/fragments.json` ↔ `generator/fragments/apartment.json`

这些文本包含虚构地点、规则、异常观察和结局流程。发布前仍需：

- 由项目权利人确认原创/授权，并明确项目 LICENSE 是否覆盖文本内容。
- 做商标、真实机构名称、个人信息和不当内容复核。
- 保留内容版本，因为同一 seed 的确定性依赖主题包与生成器版本。
- 将 `.txt` 与 `.json` 加入 Godot 导出非资源过滤器；存在源码目录不等于进入 PCK。

## 6. 字体与引擎

### 系统字体

`UIFactory` 使用 `SystemFont` 按名称请求 `Noto Sans SC`、`Microsoft YaHei UI`、`Microsoft YaHei`、`SimSun`、`Noto Serif SC`、`STSong` 等系统字体。工程没有复制或分发这些字体文件；最终字形由用户操作系统提供，缺失时由 Godot/系统回退。

因此当前没有“字体文件随包再分发”的素材项，但需要在 Windows/macOS/Linux 实机检查中文字形和排版。若以后把字体文件放入 `assets/`，必须单独记录字体许可、版本、来源 URL 和随包声明。

### Godot Engine

导出物包含 Godot Engine。Godot 采用 MIT 许可，发行负责人必须根据实际使用的 4.7.1 官方引擎许可文本提供版权与许可声明，并补齐该引擎自带第三方组件的版权清单。具体正文和发行门禁见 [第三方许可声明](../THIRD_PARTY_NOTICES.md)。不要沿用 Qt 版的第三方清单来替代 Godot 清单；Qt/FFmpeg/MinGW 仅属于旧发行链，是否随 Godot 包出现应以最终二进制审计为准。

本工程尚无项目根 LICENSE。没有项目 LICENSE 时，即使素材由项目成员创作，也缺少对外发行、修改和再分发的明确授权边界。

### Godot MCP Native 编辑器插件

`res://addons/godot_mcp/` 来自 <https://github.com/yurineko73/Godot-MCP-Native>，版本 `1.0.8`，固定上游提交 `eef4807190e7765e69d59c9e707d0ba170f6770d`，获取日期为 2026-08-18，许可为 MIT。完整许可和本地修改记录分别保存在 `addons/godot_mcp/LICENSE` 与 `addons/godot_mcp/UPSTREAM.md`。

该目录是开发期工具，不是美术素材或游戏内容。插件启用时，上游会注册 `MCPRuntimeProbe` Autoload 以支持运行时调试，因此开发运行中会加载该探针。本地仅允许 `127.0.0.1` 访问 MCP 服务，不在工程、设置或日志中保存认证令牌。正式导出预设建立后，必须验证插件目录和运行时探针未进入最终 PCK/发行包；如果选择分发，则需要按 MIT 要求保留版权与许可正文。

## 7. Godot 导入文件不是来源记录

`*.import` 和 `.godot/imported/*` 记录 Godot 的导入参数、缓存路径与源文件哈希，它们由编辑器生成：

- 可以帮助确认运行时依赖哪个源文件。
- 不能替代作者、下载地址、许可或购买凭证。
- `.godot/` 应排除版本控制与发行素材清单。
- 修改源素材后必须由匹配版本的 Godot 重新导入。

## 8. 新增素材的最低记录

以后每个新增素材至少记录：

| 字段 | 要求 |
|---|---|
| 工程路径 | `res://` 路径与用途 |
| 类型 | 自绘、程序生成、委托、购买、开放许可或第三方组件 |
| 作者/来源 | 姓名或组织；外部素材必须有原始页面 URL |
| 获取日期 | 下载、生成或交付日期 |
| 许可 | 名称、版本、商业使用/修改/署名限制 |
| 原始哈希 | 未修改源文件 SHA-256 |
| 修改记录 | 裁切、调色、转码、循环点等 |
| 证明位置 | 原工程、订单、许可快照或生成记录的保存位置 |
| 发布决定 | 允许、需署名、仅内部、阻断 |

没有这些字段时，默认状态应是“仅内部测试”，而不是“可以上线”。

## 9. 发布前素材门禁

- [ ] 为项目源码与原创内容确定 LICENSE/发行授权。
- [ ] 把大厅背景的 ImageGen 原始输出、完整提示和会话记录从工作站缓存复制到团队发行档案。
- [ ] 由项目权利人确认 `assets/app_icon.svg` 的创作来源及发行权。
- [ ] 对最终 PCK/可执行文件做实际文件与第三方组件清单，而非只审源码目录。
- [ ] 确认开发期 `addons/godot_mcp/` 与 `MCPRuntimeProbe` Autoload 未进入最终游戏发行物；若分发则附带其 MIT 许可。
- [ ] 随发行物提供 Godot Engine 4.7.1 的完整 MIT 正文及同版本引擎第三方版权清单。
- [ ] 在目标平台验证系统字体回退；若捆绑字体，先补字体许可。
- [ ] 排除 `artifacts/`、测试输出、`.godot/`、日志、临时文件和导出凭据。
- [ ] 对商店截图、预告片和宣传图单独做素材清权复核。
