# BattleGrid.gd
extends Node2D

@onready var game_manager: GameManager = $"../GameManager"

const CELL_SIZE = 64  # Adjust as needed for your visuals
const GRID_COLUMNS = 8
const GRID_ROWS = 6 # Total rows (3 for attackers, 3 for defenders)

var grid_cells = []  # 2D array to track grid occupancy by creature nodes
var visual_lines = [] # To store Line2D nodes for easy clearing/redrawing if needed

func _ready() -> void:
	initialize_grid()
	draw_grid_lines()

func initialize_grid() -> void:
	grid_cells = []
	for _x in range(GRID_COLUMNS):
		var column = []
		for _y in range(GRID_ROWS):
			column.append(null)  # null means empty cell
		grid_cells.append(column)

func draw_grid_lines() -> void:
	# Clear previous lines if any
	for line_node in visual_lines:
		line_node.queue_free()
	visual_lines.clear()

	for x in range(GRID_COLUMNS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(x * CELL_SIZE, 0))
		line.add_point(Vector2(x * CELL_SIZE, GRID_ROWS * CELL_SIZE))
		line.width = 1.0
		line.default_color = Color(0.3, 0.3, 0.3, 0.5) # Darker for less distraction
		add_child(line)
		visual_lines.append(line)
	
	for y in range(GRID_ROWS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(0, y * CELL_SIZE))
		line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, y * CELL_SIZE))
		line.width = 1.0
		line.default_color = Color(0.3, 0.3, 0.3, 0.5)
		add_child(line)
		visual_lines.append(line)

	# Central dividing line (optional, for visual separation)
	var mid_line = Line2D.new()
	var mid_y = (GRID_ROWS / 2.0) * CELL_SIZE
	mid_line.add_point(Vector2(0, mid_y))
	mid_line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, mid_y))
	mid_line.width = 2.0
	mid_line.default_color = Color(0.6, 0.6, 0.6, 0.7)
	add_child(mid_line)
	visual_lines.append(mid_line)


func world_to_grid_coords(world_pos: Vector2) -> Vector2:
	var grid_x = floor(world_pos.x / CELL_SIZE)
	var grid_y = floor(world_pos.y / CELL_SIZE)
	return Vector2(grid_x, grid_y)

func grid_coords_to_world_center(grid_coords: Vector2) -> Vector2:
	var world_x = grid_coords.x * CELL_SIZE + CELL_SIZE / 2.0
	var world_y = grid_coords.y * CELL_SIZE + CELL_SIZE / 2.0
	return Vector2(world_x, world_y)

func is_valid_grid_coords(grid_coords: Vector2) -> bool:
	return (grid_coords.x >= 0 and grid_coords.x < GRID_COLUMNS and
			grid_coords.y >= 0 and grid_coords.y < GRID_ROWS)

func place_creature_at_coords(creature: Creature, grid_coords: Vector2) -> bool:
	if not is_valid_grid_coords(grid_coords):
		printerr("Attempted to place creature out of bounds: ", grid_coords)
		return false
	
	if grid_cells[int(grid_coords.x)][int(grid_coords.y)] != null:
		printerr("Attempted to place creature in occupied cell: ", grid_coords)
		return false # Cell already occupied
	
	grid_cells[int(grid_coords.x)][int(grid_coords.y)] = creature
	creature.position = grid_coords_to_world_center(grid_coords)
	creature.lane = int(grid_coords.x)
	creature.row = int(grid_coords.y)
	
	# Ensure the creature is a child of a scene that can render it (e.g., GameManager or a specific layer)
	# If creature is not already in scene, you might need: add_child(creature) or get_parent().add_child(creature)
	# This script (BattleGrid) is likely for logic, visual nodes are added elsewhere.
	return true

func remove_creature_from_coords(grid_coords: Vector2) -> Creature:
	if not is_valid_grid_coords(grid_coords):
		printerr("Attempted to remove creature from out-of-bounds coords: ", grid_coords)
		return null
	
	var creature = grid_cells[int(grid_coords.x)][int(grid_coords.y)]
	grid_cells[int(grid_coords.x)][int(grid_coords.y)] = null
	return creature

func get_creature_at_coords(grid_coords: Vector2) -> Creature:
	if not is_valid_grid_coords(grid_coords):
		return null
	return grid_cells[int(grid_coords.x)][int(grid_coords.y)]

func is_cell_empty(grid_coords: Vector2) -> bool:
	if not is_valid_grid_coords(grid_coords):
		return false # Out of bounds cells are effectively not empty for placement
	return grid_cells[int(grid_coords.x)][int(grid_coords.y)] == null

# This input function needs to be adapted for selecting a specific dead creature body
# For now, it still uses grid position as a placeholder for targeting reanimation.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos = world_to_grid_coords(event.position) # Use event.global_position if this node is scaled/rotated
		if is_valid_grid_coords(grid_pos):
			if game_manager:
				# IDEALLY: Find a dead creature visual node at event.position
				# and pass its associated data.
				# PLACEHOLDER: Using grid_pos to find a dead creature in GameManager
				var dead_creature_found_at_pos = false
				for dead_info in game_manager.dead_creatures_for_reanimation:
					if dead_info.position == grid_pos:
						game_manager.emit_signal("request_reanimate", dead_info) # Pass the whole dead_info
						dead_creature_found_at_pos = true
						break
				if not dead_creature_found_at_pos:
					print_debug("No reanimatable body selected at: ", grid_pos)
