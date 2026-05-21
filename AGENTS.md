# AGENTS.md

本文件为 Codex (Codex.ai/code) 提供在此仓库中工作时的指导。

## 重要说明
使用中文回复我
当编辑或者添加新功能后需要更新本文件，以及其关联的子文件

## 项目概述

**elomon**（代号：cardmon / 宝可梦战棋）是一个用 Godot 4.6 开发的宝可梦风格战棋 RPG 原型。战斗在 20×20 网格上进行，采用 CTB（Charge Time Battle）系统——每个单位根据自身速度持续积累行动力（AP），达到 100 时轮到该单位行动。

## 运行游戏

用 Godot 4.6 编辑器打开项目，按 F5（运行项目）。主场景为 `battle/Battle.tscn`。当前项目视口为 `640×360`，20×20 网格会超出首屏，后续通过相机滚动查看完整战场。

`addons/godot_mcp` 是编辑器自动化插件，与游戏逻辑无关。

## 设计文档来源

Notion 的「程序设计 / 战棋原型开发文档 v1.0」是早期原型计划，仍保留了 10×10、1280×720、`BattleManager.gd`、`GridManager.gd` 等旧约定。当前仓库实现以本文件和 `.claude/` 下的文档为准。

## 核心系统一览

| 系统 | 入口文件 | 职责 |
|------|----------|------|
| 战斗循环 | `battle/Battle.gd` | 协调所有子系统，驱动回合状态机、同步率与后备能力提取 |
| 资源事件 | `battle/Battle.gd` | 统一记录 AP/同步率增减事件，供临时反馈、日志和未来正式 UI 复用 |
| 属性倍率 | `core/TypeChart.gd` | 管理属性克制表，按单位属性列表连乘伤害倍率 |
| CTB 计时 | `battle/ctb/CTBSystem.gd` | 每帧累加 AP，AP 满时暂停并通知 |
| CTB 显示 | `battle/ctb/CTBBar.gd` | 跑条/行动轴双视图，显示 READY、NEXT 和未来行动顺序 |
| 网格 | `grid/Grid.gd` | 管理单位位置、移动/攻击范围计算、点击事件、敌方威胁覆盖层 |
| 单位运行时 | `units/Unit.gd` | HP、AP、格子位置等动态状态 |
| 单位静态数据 | `units/data/UnitData.gd` | 属性、技能列表、稳定度与蓄力攻击配置（`.tres` 实例） |
| 技能静态数据 | `skills/SkillData.gd` | 伤害/治疗、射程、稳定度伤害、控制标记与范围半径 |
| 敌方 AI | `units/UnitAI.gd` | 无状态静态类，优先反击上次攻击者，否则攻击最近对立单位；厚血大怪可低频蓄力预警攻击 |
| 行动菜单 | `ui/ActionMenu.gd` | 显示真实技能名、卡牌消耗、提取形态和待机/结束状态，并通过悬停说明暴露效果 |
| 战斗日志 | `battle/Battle.gd` | 结构化记录已结算行动，并在右下 HUD 临时滚动展示 |
| 全局枚举/常量 | `core/Enums.gd` | `UnitType`、`BattleState`、`ActionState`、网格常量 |

## 详细文档

- [架构详解](.claude/architecture.md) — 各系统的实现细节与数据流
- [关键约定](.claude/conventions.md) — 坐标系、AP 经济、节点命名等开发约定
- [MVP 设计稿](.claude/mvp_design.md) — 第一场可玩战斗的系统收束、单位、卡牌与验证标准
- [MVP 复盘](.claude/mvp_retrospective.md) — 当前试玩结论、风险点与下一轮优先级
- [7 属性克制设计稿](.claude/type_chart_7.md) — 水火草冰雷飞地的克制关系与战术定位
