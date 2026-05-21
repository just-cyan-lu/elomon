extends Node

# 单位阵营
enum UnitType {
	PLAYER,          # 玩家训练师
	PLAYER_POKEMON,  # 玩家的宝可梦
	ALLY,            # 我方盟友训练师
	ALLY_POKEMON,    # 我方盟友训练师的宝可梦
	ENEMY,           # 敌方
	ENEMY_POKEMON,   # 敌方宝可梦
	NEUTRAL,         # 中立训练师
	NEUTRAL_POKEMON, # 中立训练师的宝可梦
	WILD_POKEMON     # 野生宝可梦
}

# 元素属性，MVP 先保留最小集合
enum ElementType {
	NONE,
	FIRE,
	WATER,
	GRASS,
	ICE,
	ELECTRIC,
	FLYING,
	GROUND
}

# 地形类型，MVP 用于验证站位与技能互动
enum TerrainType {
	NORMAL,
	GRASS
}

# 战斗整体状态（Battle.gd 用）
enum BattleState {
	WAITING,       # CTB 跑条推进中，等待下一个单位行动力满
	PLAYER_TURN,   # 等待玩家输入
	ENEMY_TURN,    # 敌方 AI 执行中
	NEUTRAL_TURN,  # 中立 AI 执行中
	BATTLE_OVER    # 战斗结束
}

# 玩家当前操作状态
enum ActionState {
	IDLE,              # 无操作，显示行动菜单
	SELECTING_MOVE,    # 已选"移动"，等待点击目标格
	SELECTING_SKILL,   # 已选"技能"，等待点击目标格
	CONFIRMING_SKILL,  # 已选技能目标，等待确认攻击
	SELECTING_CARD,    # 已选指令卡，等待点击目标格
	SELECTING_SUMMON   # 已选召唤，等待点击目标格
}

# 格子常量
const GRID_COLS: int = 20
const GRID_ROWS: int = 20
const CELL_SIZE: int = 32    # 像素，640÷20=32

# CTB 常量
const MAX_AP: float = 100.0
