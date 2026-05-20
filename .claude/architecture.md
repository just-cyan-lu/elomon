# 架构详解

## 全局与核心工具（`core/`）
- `Enums.gd` — 所有共享枚举（`UnitType`、`ElementType`、`TerrainType`、`BattleState`、`ActionState`）以及网格/CTB 常量（`GRID_COLS=20`、`GRID_ROWS=20`、`CELL_SIZE=32`、`MAX_AP=100`）。全局以 `Enums.*` 引用。
- `TypeChart.gd` — 属性倍率表与工具函数，通过 `preload("res://core/TypeChart.gd")` 使用。当前 MVP 使用火 > 草 > 水 > 火，克制 2 倍，抵抗 0.5 倍；单位属性列表逐项连乘，未来双属性可自然得到 4 倍克制伤害。
- `GameManager.gd` — 目前是空壳，未来的全局状态放这里。

## 战斗流程（`battle/`）
`Battle.gd` 掌控整个战斗循环，是 `Battle.tscn` 的根节点脚本，负责协调所有子系统：

1. **生成单位** — MVP 版本在 `_spawn_units()` 中动态创建 `UnitData` / `SkillData`，实例化 `Unit.tscn`，并将单位注册到 `GridManager`、`CTBSystem` 和 `CTBBar`。旧 `.tres` 数据仍保留，但当前样板战斗不依赖它们。
2. **CTB 推进** — `CTBSystem._process()` 每帧为各单位累加 AP。某单位 AP 达到 100 时发出 `unit_ready` 信号，`CTBSystem` 自身暂停，`Battle.gd` 的 `_on_unit_ready()` 响应。恢复跑条时如果已有单位满 AP，会立刻触发该单位行动，避免被卡牌加满 AP 的单位被跳过。
3. **玩家回合** — `Battle.gd` 显示 `ActionMenu`。玩家选择移动 / 技能 / 指令卡 / 召唤 / 回收 / 等待，驱动 `ActionState` 状态机。格子点击通过 `GridManager` 的 `cell_clicked` 信号路由。空闲时点击敌人会预览敌方移动范围和最远攻击威胁；选择移动时会同时预览移动后最远技能覆盖范围。移动后若尚未使用技能或支援操作，可按 `Esc` 撤回到回合开始位置。选择技能后第一次点目标只显示伤害预览，确认后才结算攻击并自动结束回合。
4. **敌方回合** — `UnitAI.run()`（`RefCounted` 类上的静态方法）通过 `await` 延迟执行，便于玩家观察，结束后调用 `_end_turn()`。
5. **结束回合** — `_end_turn()` 从当前单位 AP 中扣除 `MAX_AP`，清除高亮和状态，调用 `CTBSystem.resume()` 重启计时。MVP 中 AP 只负责行动顺序，不再参与移动和技能成本。

## MVP 战斗系统
当前分支实现了 `.claude/mvp_design.md` 的第一版样板战：
- 训练师、火狐兽开场在场，藤藤兽、水跃兽、电花鼠位于后备名单；藤藤兽当前可被召唤，水跃兽和电花鼠先作为提取能力来源。
- 敌方包含火属性近战、草属性近战、水属性远程和草属性可捕捉厚血大怪。
- 训练师回合可消耗同步率使用固定指令卡：高速组件、小型护盾、火力插件、空白封印卡；也可召唤或回收藤藤兽。高速组件提供宝可梦下一次移动 +2，而不是补 AP。
- 后备能力提取由 `Battle.gd` 的 `_reserve_units` 和 `_trainer_extract_id` 管理。提取需要对应宝可梦仍在后备中，不消耗后备宝可梦本体；提取后训练师会切换属性，并把技能列表替换为对应宝可梦技能，直到下一次提取。
- 同步率显示在战斗 UI 上，会随行动自然回复，也会因训练师/宝可梦攻击、稳定度归零、捕捉而增加；HUD 常驻显示主要获得规则，每次实际获得同步率时，HUD 附近会显示短暂的 `+同步率` 反馈。
- 可捕捉厚血大怪拥有稳定度。克制或控制技能削减稳定度；稳定度为 0 且低血时可被训练师封印。稳定度归零不会让敌人跳过行动，也不设置捕捉倒计时。
- 厚血大怪有低频蓄力攻击。蓄力时会在地图上显示预警格，下一次大怪行动时对预警格内的己方单位造成较低伤害。
- 训练师倒下不会直接失败，而是进入指挥离线状态：不能再刷卡、召唤、回收或封印，只能继续操作已在场的宝可梦。己方全部单位倒下才失败。

## 网格（`grid/`）
`Grid.gd` 声明 `class_name GridManager`，维护一个 20×20 的二维数组（`_grid`），将 `Vector2i` 坐标映射到 `Unit` 引用（或 `null`）。另有 `_terrain` 数组记录普通地面和草地。当前原型直接用动态创建的 `ColorRect` 绘制格子，有美术或 TileMap 方案后再替换表现层。核心方法：
- `get_move_range(origin, move_range)` — BFS，跳过已有单位的格子
- `get_attack_range(origin, attack_range)` — 曼哈顿距离，含有单位的格子也包括在内
- `highlight_cells()` / `clear_highlights()` — 修改 `ColorRect` 节点颜色；`highlight_cells()` 可选择不清除已有高亮，用于同时显示移动范围和攻击威胁
- `set_threat_cells()` / `clear_threat_cells()` — 显示敌方全体威胁覆盖层；普通高亮清除后要恢复该覆盖层
- `setup_mvp_terrain()` / `set_terrain()` / `get_terrain()` — 初始化与读写 MVP 地形
- `_input()` — 将鼠标点击转换为 `cell_clicked(grid_pos)` 信号

网格坐标约定：`_grid[row][col]`，即 `_grid[y][x]`。

项目视口为 `640×360`。由于 20×20 网格按 `CELL_SIZE=32` 计算为 `640×640`，当前首屏无法显示完整战场；后续计划通过相机滚动查看完整地图。

## 单位（`units/`）
- `Unit.gd`（`class_name Unit`）— 运行时状态：`current_hp`、`current_ap`、`grid_pos`、`has_acted`、`has_moved`、护盾、稳定度、可封印提示、下次攻击强化、下次移动加成、上一次攻击者、蓄力预警格。提供 `take_damage()`、`heal()`、护盾、属性伤害倍率与稳定度变更等战斗接口。视觉表现由代码动态创建的 `ColorRect`、血条和 `Label` 节点充当（美术资源到位前的占位符）。阵营色固定为我方柔和蓝、敌方柔和红、中立/野生柔和黄，受伤时会闪白并显示短暂伤害数字。
- `UnitData.gd`（`class_name UnitData`，继承 `Resource`）— 静态数据：属性、颜色、技能列表、主元素属性、元素属性列表、最大稳定度。`element_type` 保留为主属性兼容字段，`element_types` 用于未来双属性；为空时回退到主属性。旧实例位于 `units/data/tres/`，MVP 样板战当前由 `Battle.gd` 动态生成。
- `UnitAI.gd`（`class_name UnitAI`，继承 `RefCounted`）— 无状态静态 AI。`run()` 优先反击上一次攻击自己的我方单位；没有可用仇恨目标时，寻找最近我方单位，移动靠近后若在攻击范围内则发动攻击。厚血大怪每隔数次行动可能进入蓄力状态，下一次行动结算预警格伤害。

## 技能（`skills/`）
- `SkillData.gd`（`class_name SkillData`，继承 `Resource`）— 字段：`skill_name`、`damage`、`atk_range`、预留的 `ap_cost`、元素属性、稳定度伤害、是否控制技能、`area_radius`、`effect_type`。MVP 中技能不消耗 AP，`ap_cost` 暂不参与战斗结算。`effect_type=DAMAGE` 表示攻击敌人，`HEAL` 表示治疗友方。`area_radius=0` 表示单体，`>0` 表示目标格周围菱形范围。旧实例位于 `skills/tres/`，MVP 样板战当前由 `Battle.gd` 动态生成。
- 伤害公式：先计算 `max(skill.damage + unit.attack - target.defense, 1)`，再通过 `TypeChart` 按目标属性列表逐项连乘。克制为 2 倍，抵抗为 0.5 倍；未来双属性若同时被克制会得到 4 倍。稳定度使用同一属性倍率的克制部分，再叠加控制加成。
- 玩家单位可通过行动菜单使用技能 1 或技能 2；敌方 AI 仍使用单位技能列表中的第一个技能。

## UI（`ui/`）
- `ActionMenu.gd` — 悬浮在当前行动单位旁，发出移动、技能、指令卡、提取、召唤、回收、等待等信号。MVP 中按钮由脚本补充创建；菜单会压缩按钮高度并限制在视口内，避免长菜单超出屏幕。菜单按钮会根据当前单位显示真实技能名、卡牌消耗、冷却、当前提取形态或后备离场状态，鼠标悬停时通过 `option_hovered(description)` 让 `Battle.gd` 更新顶部说明。
- `Battle.gd` 动态创建轻量伤害预览面板。预览面板显示技能名、命中目标、HP 变化、伤害、稳定度变化和总伤害；范围技能会列出所有受影响敌人，并在地图上显示预览数字。
- `CTBBar.gd` — 提供两种可切换视图：速度跑条视图和行动轴视图。速度跑条视图中每个单位对应一组标签+进度条，每帧从 `unit.current_ap` 更新显示；CTB 暂停时会显示 `WAIT`，当前可行动单位显示 `READY` 并高亮进度条，下一位行动单位显示 `NEXT`。行动轴视图会预测未来数次行动顺序，速度快的单位允许重复出现。
- `DamageNumber.gd` / `DamageNumber.tscn` — 目前仍是占位脚本和场景，尚未接入伤害表现。

## 与 Notion v1.0 的差异
Notion「程序设计 / 战棋原型开发文档 v1.0」是早期实现蓝图，当前仓库已有几处不同：
- 地图从 10×10 / 64px 格子演进为 20×20 / 32px 格子。
- 视口从文档中的 1280×720 改为项目当前的 640×360。
- 根战斗脚本文件从 `BattleManager.gd` 改为 `Battle.gd`。
- 网格脚本文件从 `GridManager.gd` 改为 `Grid.gd`，但仍保留 `class_name GridManager` 作为类型名。
- 当前网格表现使用 `ColorRect` 动态绘制，而不是 Notion v1.0 中设想的 TileMap。
