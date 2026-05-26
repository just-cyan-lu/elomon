class_name GridManager
extends Node2D

# 信号
signal cell_clicked(grid_pos: Vector2i)

const COLOR_NORMAL  := Color(0.15, 0.15, 0.15)
const COLOR_MOVE    := Color(0.2, 0.5, 1.0, 0.6)
const COLOR_ATTACK  := Color(1.0, 0.2, 0.2, 0.6)
const COLOR_CURSOR  := Color(1.0, 1.0, 0.0, 0.5) # 黄色，鼠标悬停
const COLOR_GRASS   := Color(0.1, 0.38, 0.16)
const COLOR_WARNING := Color(1.0, 0.55, 0.12, 0.85)
const COLOR_THREAT  := Color(0.75, 0.18, 0.18, 0.52)

var _grid: Array = []
var _terrain: Array = []
var _cell_nodes: Array = []   # 存 ColorRect 节点，方便改颜色
var _highlighted: Array = []  # 当前高亮的格子列表
var _warning_cells: Array[Vector2i] = []
var _threat_cells: Array[Vector2i] = []

func _ready() -> void:
	_init_grid()
	_draw_cells()

# 初始化二维数组
func _init_grid() -> void:
	_grid.clear()
	_terrain.clear()
	_cell_nodes.clear()
	for row in Enums.GRID_ROWS:
		var row_arr = []
		var terrain_row = []
		var node_row = []
		for col in Enums.GRID_COLS:
			row_arr.append(null)
			terrain_row.append(Enums.TerrainType.NORMAL)
			node_row.append(null)
		_grid.append(row_arr)
		_terrain.append(terrain_row)
		_cell_nodes.append(node_row)

# 用 ColorRect 绘制格子（有美术后替换为 TileMap）
func _draw_cells() -> void:
	print("开始画格子，CELL_SIZE: ", Enums.CELL_SIZE)
	for row in Enums.GRID_ROWS:
		for col in Enums.GRID_COLS:
			var rect := ColorRect.new()
			rect.size = Vector2(Enums.CELL_SIZE - 1, Enums.CELL_SIZE - 1)
			# -1 留出 1px 间隙作为格线
			rect.position = Vector2(
				col * Enums.CELL_SIZE,
				row * Enums.CELL_SIZE
			)
			rect.color = _get_terrain_color(Vector2i(col, row))
			add_child(rect)
			_cell_nodes[row][col] = rect
	print("格子画完，总数: ", Enums.GRID_ROWS * Enums.GRID_COLS)

# 像素坐标 → 格子坐标（输入是相对于 GridManager 自身的本地坐标）
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / Enums.CELL_SIZE),
		int(world_pos.y / Enums.CELL_SIZE)
	)

# 格子坐标 → 像素中心点
func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * Enums.CELL_SIZE + Enums.CELL_SIZE * 0.5,
		grid_pos.y * Enums.CELL_SIZE + Enums.CELL_SIZE * 0.5
	)

# 判断格子坐标是否在地图内
func is_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < Enums.GRID_COLS \
	   and pos.y >= 0 and pos.y < Enums.GRID_ROWS

# 判断格子是否有单位
func is_occupied(pos: Vector2i) -> bool:
	if not is_valid(pos): return true  # 越界也算"不可通行"
	return _grid[pos.y][pos.x] != null

# 获取格子上的单位（没有返回 null）
func get_unit_at(pos: Vector2i) -> Unit:
	if not is_valid(pos): return null
	return _grid[pos.y][pos.x]

func get_terrain(pos: Vector2i) -> int:
	if not is_valid(pos):
		return Enums.TerrainType.NORMAL
	return _terrain[pos.y][pos.x]

func set_terrain(pos: Vector2i, terrain_type: int) -> void:
	if not is_valid(pos):
		return
	_terrain[pos.y][pos.x] = terrain_type
	_cell_nodes[pos.y][pos.x].color = _get_display_color(pos)

func set_warning_cells(cells: Array[Vector2i]) -> void:
	clear_warning_cells()
	for pos in cells:
		if is_valid(pos) and not _warning_cells.has(pos):
			_warning_cells.append(pos)
			_cell_nodes[pos.y][pos.x].color = COLOR_WARNING

func clear_warning_cells() -> void:
	var old_cells := _warning_cells.duplicate()
	_warning_cells.clear()
	for pos in old_cells:
		if is_valid(pos):
			_cell_nodes[pos.y][pos.x].color = _get_display_color(pos)

func set_threat_cells(cells: Array[Vector2i]) -> void:
	clear_threat_cells()
	for pos in cells:
		if is_valid(pos) and not _threat_cells.has(pos):
			_threat_cells.append(pos)
			if not _highlighted.has(pos):
				_cell_nodes[pos.y][pos.x].color = _get_display_color(pos)

func clear_threat_cells() -> void:
	var old_cells := _threat_cells.duplicate()
	_threat_cells.clear()
	for pos in old_cells:
		if is_valid(pos) and not _highlighted.has(pos):
			_cell_nodes[pos.y][pos.x].color = _get_display_color(pos)

func setup_mvp_terrain(level_id: String = "level1") -> void:
	for y in Enums.GRID_ROWS:
		for x in Enums.GRID_COLS:
			set_terrain(Vector2i(x, y), Enums.TerrainType.NORMAL)
	if level_id == "level2":
		for pos in [Vector2i(7, 7), Vector2i(8, 8), Vector2i(7, 9), Vector2i(10, 8)]:
			set_terrain(pos, Enums.TerrainType.GRASS)
		return
	for y in range(7, 11):
		for x in range(7, 11):
			set_terrain(Vector2i(x, y), Enums.TerrainType.GRASS)

func _get_terrain_color(pos: Vector2i) -> Color:
	if not is_valid(pos):
		return COLOR_NORMAL
	match _terrain[pos.y][pos.x]:
		Enums.TerrainType.GRASS:
			return COLOR_GRASS
		_:
			return COLOR_NORMAL

func _get_display_color(pos: Vector2i) -> Color:
	if _warning_cells.has(pos):
		return COLOR_WARNING
	if _threat_cells.has(pos):
		return COLOR_THREAT
	return _get_terrain_color(pos)

# 放置单位到格子
func place_unit(unit: Node, pos: Vector2i) -> void:
	_grid[pos.y][pos.x] = unit
	unit.position = grid_to_world(pos)

# 移动单位（更新数组 + 更新位置）
func move_unit(unit: Node, from: Vector2i, to: Vector2i) -> void:
	_grid[from.y][from.x] = null
	_grid[to.y][to.x] = unit
	unit.position = grid_to_world(to)

# 移除单位（死亡时调用）
func remove_unit(pos: Vector2i) -> void:
	_grid[pos.y][pos.x] = null

# BFS 计算可移动格子
# 从 origin 出发，不超过 move_range 步，跳过有单位的格子
func get_move_range(origin: Vector2i, move_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited := {}          # 用字典做访问标记，key 是 Vector2i
	var queue: Array = []      # 元素格式：[位置, 已走步数]
	
	visited[origin] = true
	queue.append([origin, 0])
	
	while queue.size() > 0:
		var current = queue.pop_front()
		var pos: Vector2i = current[0]
		var dist: int = current[1]
		
		# origin 本身不加入结果（不能移动到自己脚下）
		if dist > 0:
			result.append(pos)
		
		# 已达最大步数，不继续扩展
		if dist >= move_range:
			continue
		
		# 四个方向扩展
		var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		for dir in dirs:
			var next: Vector2i = pos + dir
			if is_valid(next) and not visited.has(next) and not is_occupied(next):
				visited[next] = true
				queue.append([next, dist + 1])
	
	return result

# 计算攻击范围（曼哈顿距离 <= range 的所有格子，含有敌人的格子）
# 注意：攻击范围不排除有单位的格子（需要能选中敌人）
func get_attack_range(origin: Vector2i, attack_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-attack_range, attack_range + 1):
		for dx in range(-attack_range, attack_range + 1):
			var pos := origin + Vector2i(dx, dy)
			var dist: int = abs(dx) + abs(dy)
			if dist > 0 and dist <= attack_range and is_valid(pos):
				result.append(pos)
	return result

# 高亮指定格子
func highlight_cells(cells: Array[Vector2i], color: Color, clear_existing: bool = true) -> void:
	if clear_existing:
		clear_highlights()
	for pos in cells:
		if is_valid(pos):
			_cell_nodes[pos.y][pos.x].color = color
			_highlighted.append(pos)

# 清除所有高亮
func clear_highlights() -> void:
	for pos in _highlighted:
		if is_valid(pos):
			_cell_nodes[pos.y][pos.x].color = _get_display_color(pos)
	_highlighted.clear()

# 鼠标点击处理
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		# 把屏幕坐标转换为 GridManager 的本地坐标
		var local_pos := to_local(get_viewport().get_mouse_position())
		var grid_pos := world_to_grid(local_pos)
		if is_valid(grid_pos):
			emit_signal("cell_clicked", grid_pos)
