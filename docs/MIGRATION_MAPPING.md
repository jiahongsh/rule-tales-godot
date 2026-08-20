# Qt → Godot 迁移映射

## 1. 文档目的

本文件记录 Qt 6 Widgets 版本与 `game_godot` 的职责对应、必须保持的不变量、数据目录边界和当前尚未完成的发布工作。它不是“文件名翻译表”：Qt 的单体 `MainWindow` 在 Godot 中被拆成场景、服务和按需窗口，一些原本分散的生成/局循环类也被合并为更小的 GDScript 服务。

核对基线：

- Qt 源码：仓库根目录的 `src/`、`resources/`、`generator/`、`examples/` 与 `tests/`。
- Godot 工程：`game_godot/`。
- 引擎：Godot `4.7.1.stable`，Compatibility 渲染器。
- 迁移原则：客户端权威逻辑优先于逐像素复刻；AI 不获得存档、规则真假或异常裁判的最终控制权。

## 2. 运行时结构

```text
Qt QApplication + MainWindow                 Godot SceneTree
└─ MainWindow（UI 与编排入口）                ├─ main.gd（页面/窗口协调）
   ├─ GameSession / TurnOrchestrator         ├─ GameSession Autoload
   ├─ AiClient                               │  ├─ TurnPromptAssembler
   ├─ RuleDocument / GameState               │  ├─ AiGateway / HTTPRequest
   ├─ MemoryIndex / FactStore / RuleIndex    │  ├─ RuleTalesGameState
   ├─ RuleGuard                              │  ├─ StructuredFactStore
   ├─ SaveRepository / SaveCatalog           │  └─ RuleFragmentIndex
   └─ QWidgets / QSS / QSoundEffect          ├─ lobby_view / game_view / dialogs
                                             └─ save、seed、audio 等服务
```

Godot 中 `AppSettings` 和 `GameSession` 是 `project.godot` 注册的 Autoload。窗口只提交用户意图；权威状态、存档和 AI 请求不会归属于某个临时 UI 节点。

## 3. 核心模块对应

| Qt 版本 | Godot 版本 | 状态与说明 |
|---|---|---|
| `src/core/GameSession.*` | `scripts/core/game_session.gd` | 已重建为 Autoload 会话门面，负责启封、回合、离线流程、时间线、结局、存档和限时局事件。 |
| `src/core/GameState.*` | `scripts/core/game_state.gd` | 已迁移。严格整数、Qt 值域、公开补丁键、背包/地图/终局语义已对齐；仍采用候选副本校验后一次提交，非法补丁不污染权威状态。 |
| `src/core/RuleDocument.*` | `scripts/core/rule_document.gd` | 已迁移。保留 `<章节>`、无章节“全文”、UTF-8 和 512 KiB 上限。 |
| `src/core/BbCode.*` | `scripts/core/bbcode_util.gd`、`scripts/ui/effects/*.gd` | 已迁移为白名单清洗和 `RichTextEffect`。不执行 HTML。 |
| `src/core/MemoryIndex.*`、`src/ai/ContextPolicy.*` | `scripts/core/memory_search.gd` | 已迁移最近窗口与较早历史相关检索；实现语言调整为本地字符/bigram 风格评分。 |
| `src/memory/RuleIndex.*` | `scripts/core/rule_index.gd` | 已迁移规则切片、稳定 ID、相关/全局片段选择和字符预算轨迹。 |
| `src/memory/FactStore.*` | `scripts/core/fact_store.gd` | 已迁移线索、人物、地点、已触发规则和未解决事件；批次失败整体回滚。 |
| `src/engine/RuleGuard.*` | `scripts/engine/rule_guard.gd` | 已迁移模型输出白名单、规则引用、本地硬约束与地图/物品保守裁判。 |
| `src/engine/TurnOrchestrator.*` | `scripts/core/game_session.gd` | 生命周期折叠进会话：busy、请求 ID、完成/失败、解析、裁判和提交仍按阶段执行。 |
| `src/core/TurnDiagnostics.*` | `GameSession.diagnostics` 与 `game_view` 调试页 | 已迁移为内存诊断快照；不写入普通存档或 API Key。 |
| `src/ai/PromptAssembler.*` | `scripts/ai/prompt_assembler.gd` | 已迁移系统约束、规则检索、状态、事实和历史分层消息。 |
| `src/net/AiClient.*` | `scripts/net/ai_gateway.gd` | 已迁移到 `HTTPRequest` 信号回调；保留 HTTPS/localhost 边界、响应码与 8 MiB 上限，Bearer 请求禁用自动重定向。`ai_gateway_smoke.tscn` 覆盖地址欺骗、2xx 与 401。 |

## 4. 规则种子与局循环

| Qt 版本 | Godot 版本 | 状态与说明 |
|---|---|---|
| `SeedRng.h` | `scripts/generator/seed_rng.gd` | 已迁移 MT19937 兼容随机序列；核心测试固定首个输出。 |
| `FragmentLibrary.*`、`SeedFragment.*` | `rule_forge.gd::_load_pack` 与 JSON 字典 | 已迁移为数据驱动主题包；加载时检查必需字段、重复 ID 和冲突引用。 |
| `RuleForge.*` | `scripts/generator/rule_forge.gd` | 已迁移确定性抽取、槽位、真假分配、出口依赖和篡改计划。 |
| `SolvabilityChecker.*` | `rule_forge.gd::_check_solvability` | 合并迁移。生成结果在返回前检查连续出口链、能力供给、禁令冲突和篡改可用性。 |
| `RunManager.*`、`RouteMap.*` | `scripts/engine/run_systems.gd` + `GameSession` | 合并迁移期限、失踪兜底、日终路线和结算。 |
| `AnomalyDirector.*` | `run_systems.gd::anomaly_for_night` + `GameSession.resolve_pending_anomaly` | 已迁移为 seed/夜数确定性观察与客户端裁判。 |
| Qt 开局 `QDialog` | `scripts/ui/seed_run_dialog.gd` | 已迁移 uint32 种子、3–14 天、真实生成预检和摘要。 |
| `src/meta/MetaProfile.*` | `scripts/persistence/meta_profile.gd` | 已迁移认知点、图鉴、异常和阈值天赋。 |

同一主题包、种子和生成器版本应得到逐字一致的规则文档。`tests/generator_fuzz_test.gd` 对 0–999 种子执行生成与结构回归；这只是自动门禁，不替代内容盲审。

## 5. UI 与视听对应

| Qt 版本 | Godot 版本 | 状态与说明 |
|---|---|---|
| `src/main.cpp` | `project.godot`、`scenes/main.tscn`、`scripts/main.gd` | 已迁移程序入口、主题挂载、页面协调与全局快捷键。 |
| `MainWindow` 大厅/档案选择 | `lobby_view.tscn` + `lobby_view.gd` | 已拆分为主菜单、调查选择与 AI 引导。 |
| `MainWindow` 局内工作台 | `game_view.tscn` + `game_view.gd` | 已迁移常驻状态、叙事、选择、输入、资料页、结局和限时局对话。 |
| Qt 开始设置/设置页 | `settings_dialog.gd` | 已迁移预设、接口、上下文、声音、窗口化/无边框全屏、五档窗口尺寸、五档帧率上限、显示、无障碍和实时预览；窗口尺寸仅通过设置调整，联网模式可独立测试 Endpoint、模型、凭据与 JSON 响应。 |
| Qt 档案管理 | `save_manager_dialog.gd` | 手动槽位、自动存档、两类缩略图、关键节点重开及便携 JSON 导入/导出已迁移。导入先校验并确认替换当前调查。 |
| Qt 规则工坊 | `rule_workshop.gd` | 已迁移章节编辑、模板、搜索、质量检查、草稿、导入/导出和直接启封。 |
| `resources/style.qss` | `ui_factory.gd` + 各窗口 Theme override | 重写为 Godot `Theme`、`StyleBoxFlat` 和 Container；不追求 Qt 像素坐标复刻。 |
| `resources.qrc` | `res://assets`、`res://content` | 资源改由 Godot 导入管线和 `FileAccess` 读取。普通 TXT/JSON 需要导出过滤器。 |
| `InteractionSound.*`、`AmbienceDirector.*` | `sound_manager.gd` | 已迁移到两个 `AudioStreamPlayer`，分别处理多声部交互音效和循环环境声。 |

Godot 窗口使用 `Control`、`Container`、锚点和 stretch 设置适配尺寸；Qt 的固定 widget geometry 不是迁移目标。SystemFont 只引用操作系统字体名称，没有随包分发字体文件。

## 6. 持久化映射与路径边界

| 数据 | Qt | Godot | 兼容性 |
|---|---|---|---|
| 设置 | `QSettings` | `user://settings.cfg` / `ConfigFile` | 键名、默认值和编码不同，不自动导入。 |
| 工坊草稿 | `QSettings ruleWorkshop/*` | `user://rule_workshop_draft.cfg` | 不兼容，需以后编写显式转换。 |
| 手动/自动存档 | `SaveRepository`、`SaveCatalog` JSON | `user://saves/*.json` | 核心调查文档同为 `save_schema=1`；Godot 已严格兼容读取 Qt 字段，但不会自动扫描 Qt 数据目录。 |
| 缩略图 | 手动与自动 PNG | `manual_*.png`、`auto_*.png` | 已迁移；自动存档提交后于渲染帧结束写入对应预览。 |
| 元成长 | Qt `MetaProfile` | `user://meta.json` | 语义相近，未声明 schema 兼容。 |
| 便携存档 | Qt UI 支持导入/导出 | Godot 档案管理 JSON 导入/导出 | 已迁移；文件对话框只筛选 JSON，导入复用会话完整校验并在替换前确认。 |

Godot 三代自动存档在每次成功写入前分配单调递增的 `_autosave_sequence`，恢复时优先按该序号从新到旧排序；没有序号的旧存档才回退到文件修改时间与轮换环位置。这避免同一秒内连续写入时仅凭文件时间误判新旧。

兼容读取覆盖 Qt `save_schema=1` 的规则、状态、结构化事实、历史、选项、已发现规则、关键选择、时间线、限时局配置、篡改状态、异常记录和元奖励字段。再次由 Godot 保存时，事实记录会规范化为 Qt 的 `first_seen_turn` / `last_updated_turn` 字段；早期 Godot 原型的 `updated_turn` 仍可读取。`tests/save_compat_test.gd` 以 `SAVE_COMPAT_OK` 回归这条边界。Godot 自动存档列表还识别早期 `autosave.cursor` 与单文件 `autosave.json`。

Godot 版固定使用 `application/config/custom_user_dir_name="RuleTales/RuleTalesGodot"`：

- Windows：`%APPDATA%\RuleTales\RuleTalesGodot`
- Qt 旧版实测目录：`%APPDATA%\RuleTales\异闻夜谈`

分离目录是刻意的安全边界，而不是核心调查文档不兼容：当前没有自动发现、备份和复制 Qt 数据目录的迁移器，共用 `manual_1.json` 等槽位文件名会让两版互相覆盖。兼容读取只在用户明确选择某个文档后发生，不会静默搬动旧数据。

未来的目录级迁移器应遵守：

1. 只读打开 Qt 原文件，先复制备份，绝不就地改写。
2. 检查来源 schema、文件大小和 JSON 类型。
3. 复用 `GameSession.load_document` 的严格兼容校验，不另写一套宽松的字段转换。
4. 使用新的临时文件写入、回读校验，再原子替换 Godot 目标；保留 Qt 原文件。
5. 保留未知字段报告；不能静默丢失时中止整次迁移。
6. 加入真实 Qt 数据目录 fixture、槽位冲突和失败回滚测试后，才允许暴露“自动迁移整个目录”；当前便携 JSON 入口始终由用户显式选文件。

## 7. 必须保持的不变量

- AI 回复不是权威状态。只有成功解析、规则引用合法、事实批次合法、规则裁判通过且 `GameState.apply_patch` 成功后才能提交回合。
- 状态补丁和事实更新必须作为一个回合事务；任一失败时都不得保留半个结果。
- 地图初始为空；没有叙事探索依据时不能凭空发现节点。
- 物品数量不得变负，未知物品不能被无依据扣除。
- 当前状态优先于历史召回；相关旧记录只能提供上下文。
- 真假图谱、异常答案和篡改目标保留在客户端私有数据中，不进入玩家可见正文或模型自由裁决面。
- API Key 不写 `ConfigFile`、存档、诊断或日志。
- 终局只能由通过裁判的明确 `ending` 成立，随后冻结后续行动；健康/理智归零本身不应暗中合成另一种结局。
- `user://` 只保存可写数据；内置规则和主题包只从只读 `res://content` 加载。

## 8. 验证门禁

从 `game_godot` 运行：

```powershell
godot --headless --editor --path . --import
godot --headless --path . --script res://tests/core_smoke_test.gd
godot --headless --path . --scene res://tests/offline_end_to_end.tscn
godot --headless --path . --scene res://tests/save_compat_test.tscn
godot --headless --path . --scene res://tests/save_transfer_smoke.tscn
godot --headless --path . --script res://tests/thumbnail_smoke.gd
godot --headless --path . --scene res://tests/ai_gateway_smoke.tscn
godot --headless --path . --script res://tests/generator_fuzz_test.gd
godot --headless --path . --scene res://tests/ui_runtime_smoke.tscn
```

需要人工补充的检查：

- 1120×680 最小窗口、1440×810 常用窗口和高 DPI 缩放。
- 中文字体回退、键盘焦点、ESC、F1、F12 和原生文件对话框。
- 血字在完整动态/降低动态下的差异，以及长文本滚动性能。
- 离线六幕在真实图形环境复核音效、转场与结局卡；联网超时、取消、非 2xx、畸形 JSON 和超大响应。
- 手动槽位覆盖、三代自动轮换、关键节点重开和写入失败恢复。
- 导出物在无源码、无编辑器的干净设备上读取全部 `res://content` 文件。

## 9. 尚未完成或有意不宣称的事项

- 没有平台 `export_presets.cfg`，尚未验证导出模板、代码签名、安装包、沙盒权限或商店元数据。
- 没有 Qt → Godot 设置或数据目录自动迁移器；核心 `save_schema=1` 文档已可兼容读取，但仍不会自动发现旧目录。
- 大厅背景已替换为本项目原创生成版本；发布前仍需把工作站上的 ImageGen 原始输出与提示记录归入团队发行档案。
- 项目自身 LICENSE、隐私政策发布地址和支持渠道仍需发行负责人确认；Godot 正文已整理在 `THIRD_PARTY_NOTICES.md`，但仍需在最终包中实际随附并补同版本引擎第三方清单。
- 当前验证以 Windows 开发机和 headless 回归为主，不代表 macOS、Linux 或移动平台已验收。

这些差距必须保持可见；“Godot 中能运行”与“可公开上线”是两个不同的完成条件。
