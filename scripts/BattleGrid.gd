# BattleGrid.gd
extends Node2D

const CELL_SIZE = 64
const GRID_WIDTH = 10  # Columns/lanes
const GRID_HEIGHT = 6  # Rows

var grid_cells = []  # 2D array to track grid occupancy
var visual_grid = []  # For debugging

func _ready() -> void:
	# Initialize grid
	grid_cells = []
	for x in range(GRID_WIDTH):
		var column = []
		for y in range(GRID_HEIGHT):
			column.append(null)  # null means empty cell
		grid_cells.append(column)
	
	# Draw grid lines for debugging
	draw_grid_lines()

func draw_grid_lines() -> void:
	for x in range(GRID_WIDTH + 1):
		var line = Line2D.new()
		line.add_point(Vector2(x * CELL_SIZE, 0))
		line.add_point(Vector2(x * CELL_SIZE, GRID_HEIGHT * CELL_SIZE))
		line.width = 1.0
		line.default_color = Color(0.5, 0.5, 0.5, 0.5)
		add_child(line)
		visual_grid.append(line)
	
	for y in range(GRID_HEIGHT + 1):
		var line = Line2D.new()
		line.add_point(Vector2(0, y * CELL_SIZE))
		line.add_point(Vector2(GRID_WIDTH * CELL_SIZE, y * CELL_SIZE))
		line.width = 1.0
		line.default_color = Color(0.5, 0.5, 0.5, 0.5)
		add_child(line)
		visual_grid.append(line)

func world_to_grid(world_pos: Vector2) -> Vector2:
	var grid_x = int(world_pos.x / CELL_SIZE)
	var grid_y = int(world_pos.y / CELL_SIZE)
	return Vector2(grid_x, grid_y)

func grid_to_world(grid_pos: Vector2) -> Vector2:
	var world_x = grid_pos.x * CELL_SIZE + CELL_SIZE / 2
	var world_y = grid_pos.y * CELL_SIZE + CELL_SIZE / 2
	return Vector2(world_x, world_y)

func place_creature(creature, grid_pos: Vector2) -> bool:
	if grid_pos.x < 0 or grid_pos.x >= GRID_WIDTH or grid_pos.y < 0 or grid_pos.y >= GRID_HEIGHT:
		return false  # Out of bounds
	
	if grid_cells[grid_pos.x][grid_pos.y] != null:
		return false  # Cell already occupied
	
	# Place creature in grid
	grid_cells[grid_pos.x][grid_pos.y] = creature
	
	# Position creature in world
	var world_pos = grid_to_world(grid_pos)
	creature.position = world_pos
	
	# Update creature's internal position
	creature.lane = grid_pos.x
	creature.row = grid_pos.y
	
	return true

func remove_creature(grid_pos: Vector2) -> void:
	if grid_pos.x < 0 or grid_pos.x >= GRID_WIDTH or grid_pos.y < 0 or grid_pos.y >= GRID_HEIGHT:
		return
	
	grid_cells[grid_pos.x][grid_pos.y] = null

func get_creatures_at_position(grid_pos: Vector2):
	if grid_pos.x < 0 or grid_pos.x >= GRID_WIDTH or grid_pos.y < 0 or grid_pos.y >= GRID_HEIGHT:
		return null
	
	return grid_cells[grid_pos.x][grid_pos.y]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos = world_to_grid(event.position)
		if grid_pos.x >= 0 and grid_pos.x < GRID_WIDTH and grid_pos.y >= 0 and grid_pos.y < GRID_HEIGHT:
			var game_manager = get_node_or_null("/root/GameManager")
			if game_manager:
				game_manager.emit_signal("request_reanimate", grid_pos, "skeleton")
