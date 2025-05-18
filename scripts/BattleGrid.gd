# ./scripts/BattleGrid.gd
extends Node2D
class_name BattleGrid

# Signals
signal cell_occupied(grid_pos: Vector2i, creature: Creature)
signal cell_vacated(grid_pos: Vector2i, creature_that_left: Creature) # creature can be null if simply cleared

# --- CONFIGURATION ---
const CELL_SIZE: int = 128  # Visual size of a cell in pixels
const GRID_COLUMNS: int = 8
const GRID_ROWS_PER_FACTION: int = 3
const TOTAL_GRID_ROWS: int = GRID_ROWS_PER_FACTION * 2

# --- STATE ---
# 2D array storing references to Creature nodes. null means empty.
# Access via grid_cells[column][row]
var grid_cells: Array = []

# For drawing grid lines (optional, mainly for debug/visuals)
var visual_lines_container: Node2D # A child Node2D to hold Line2D nodes

# --- REFERENCES ---
# This will be assigned by GameManager or a parent node.
var game_manager


func _ready():
	# Create a container for visual lines if it doesn't exist
	visual_lines_container = Node2D.new()
	visual_lines_container.name = "VisualLinesContainer"
	add_child(visual_lines_container)

	initialize_grid_data()
	draw_grid_lines() # Initial draw

# --- INITIALIZATION ---
func initialize_grid_data():
	grid_cells = []
	for _col in range(GRID_COLUMNS):
		var column_array: Array = []
		column_array.resize(TOTAL_GRID_ROWS) # Pre-size with nulls
		for r in range(TOTAL_GRID_ROWS):
			column_array[r] = null
		grid_cells.append(column_array)
	# print_debug("BattleGrid: Grid data initialized (%d cols x %d rows)." % [GRID_COLUMNS, TOTAL_GRID_ROWS])

func draw_grid_lines():
	# Clear previous lines
	for child in visual_lines_container.get_children():
		child.queue_free()

	var line_color = Color(0.3, 0.3, 0.3, 0.5) # A subdued color for grid lines

	# Vertical lines
	for x in range(GRID_COLUMNS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(x * CELL_SIZE, 0))
		line.add_point(Vector2(x * CELL_SIZE, TOTAL_GRID_ROWS * CELL_SIZE))
		line.width = 1.0
		line.default_color = line_color
		visual_lines_container.add_child(line)

	# Horizontal lines
	for y in range(TOTAL_GRID_ROWS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(0, y * CELL_SIZE))
		line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, y * CELL_SIZE))
		line.width = 1.0
		line.default_color = line_color
		visual_lines_container.add_child(line)
	
	# Optional: A thicker line to divide player and alien sides
	var mid_line = Line2D.new()
	var mid_y = GRID_ROWS_PER_FACTION * CELL_SIZE # This calculation remains correct for the visual middle
	mid_line.add_point(Vector2(0, mid_y))
	mid_line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, mid_y))
	mid_line.width = 2.0 # Thicker
	mid_line.default_color = Color(0.5, 0.2, 0.2, 0.7) # A different color
	visual_lines_container.add_child(mid_line)


# --- GRID VALIDATION & COORDINATE UTILITIES ---
func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return (grid_pos.x >= 0 and grid_pos.x < GRID_COLUMNS and \
			grid_pos.y >= 0 and grid_pos.y < TOTAL_GRID_ROWS)

func get_world_position_for_grid_cell_center(grid_pos: Vector2i) -> Vector2:
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot get world position for invalid grid_pos: %s" % str(grid_pos))
		return Vector2.ZERO # Or some other indicator of error

	# Assumes this BattleGrid Node2D's origin is the top-left of the grid.
	# Creature.gd will use this to set its local position.
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0, \
				   grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0)

func get_grid_position_from_world_position(world_pos: Vector2) -> Vector2i:
	# This converts a world position (e.g., mouse click relative to BattleGrid's origin) to a grid cell.
	var grid_x = floor(world_pos.x / CELL_SIZE)
	var grid_y = floor(world_pos.y / CELL_SIZE)
	return Vector2i(int(grid_x), int(grid_y))

# --- CREATURE PLACEMENT & QUERYING ---
func place_creature_at(creature: Creature, grid_pos: Vector2i) -> bool:
	if not is_instance_valid(creature):
		printerr("BattleGrid: Attempted to place an invalid creature instance.")
		return false
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot place creature. Invalid grid_pos: %s" % str(grid_pos))
		return false
	if grid_cells[grid_pos.x][grid_pos.y] != null:
		printerr("BattleGrid: Cannot place creature. Cell %s is already occupied by %s." % [str(grid_pos), grid_cells[grid_pos.x][grid_pos.y].creature_name])
		return false

	grid_cells[grid_pos.x][grid_pos.y] = creature
	creature.grid_pos = grid_pos # Update creature's own knowledge of its position
	
	emit_signal("cell_occupied", grid_pos, creature)
	# print_debug("BattleGrid: Placed %s at %s" % [creature.creature_name, str(grid_pos)])
	return true

func get_creature_at(grid_pos: Vector2i) -> Creature:
	if not is_valid_grid_position(grid_pos):
		return null
	return grid_cells[grid_pos.x][grid_pos.y] # Can be null if empty

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	if not is_valid_grid_position(grid_pos):
		return true # Treat out-of-bounds as "occupied" to prevent placement
	return grid_cells[grid_pos.x][grid_pos.y] != null

func remove_creature_from(grid_pos: Vector2i) -> Creature:
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot remove creature. Invalid grid_pos: %s" % str(grid_pos))
		return null
	
	var creature_that_was_there: Creature = grid_cells[grid_pos.x][grid_pos.y]
	if is_instance_valid(creature_that_was_there):
		grid_cells[grid_pos.x][grid_pos.y] = null
		# creature_that_was_there.grid_pos = Vector2i(-1, -1) # Invalidate creature's old pos, Creature.gd setter handles this
		emit_signal("cell_vacated", grid_pos, creature_that_was_there)
		# print_debug("BattleGrid: Removed %s from %s" % [creature_that_was_there.creature_name, str(grid_pos)])
		return creature_that_was_there
	else:
		# print_debug("BattleGrid: No creature to remove at %s (cell was already empty)." % str(grid_pos))
		grid_cells[grid_pos.x][grid_pos.y] = null # Ensure it's null
		emit_signal("cell_vacated", grid_pos, null) # Signal that cell is clear
		return null

func clear_cell(grid_pos: Vector2i):
	"""Ensures a cell is marked as empty, without returning the creature."""
	if is_valid_grid_position(grid_pos):
		if grid_cells[grid_pos.x][grid_pos.y] != null:
			var creature_ref = grid_cells[grid_pos.x][grid_pos.y]
			grid_cells[grid_pos.x][grid_pos.y] = null
			emit_signal("cell_vacated", grid_pos, creature_ref) # Pass ref if it existed
		else: # If already null, still signal it's clear if that's useful
			emit_signal("cell_vacated", grid_pos, null)


# --- ROW/COLUMN UTILITIES ---
# MODIFIED: Player rows are now at the bottom of the grid.
func get_player_rows_indices() -> Array[int]:
	# Player rows are now 3, 4, 5 (bottom half of a 0-5 grid)
	var player_rows: Array[int] = []
	for i in range(GRID_ROWS_PER_FACTION):
		player_rows.append(GRID_ROWS_PER_FACTION + i) # Rows 3, 4, 5
	return player_rows

# MODIFIED: Alien rows are now at the top of the grid.
func get_alien_rows_indices() -> Array[int]:
	# Alien rows are now 0, 1, 2 (top half of a 0-5 grid)
	var alien_rows: Array[int] = []
	for i in range(GRID_ROWS_PER_FACTION):
		alien_rows.append(i) # Rows 0, 1, 2
	return alien_rows


func get_creatures_in_row(row_index: int) -> Array[Creature]:
	var creatures_in_row: Array[Creature] = []
	if row_index < 0 or row_index >= TOTAL_GRID_ROWS:
		printerr("BattleGrid: Invalid row_index %d for get_creatures_in_row." % row_index)
		return creatures_in_row
		
	for col_index in range(GRID_COLUMNS):
		var creature = grid_cells[col_index][row_index]
		if is_instance_valid(creature):
			creatures_in_row.append(creature)
	return creatures_in_row

func get_creatures_in_column(col_index: int) -> Array[Creature]:
	var creatures_in_col: Array[Creature] = []
	if col_index < 0 or col_index >= GRID_COLUMNS:
		printerr("BattleGrid: Invalid col_index %d for get_creatures_in_column." % col_index)
		return creatures_in_col

	for row_index in range(TOTAL_GRID_ROWS):
		var creature = grid_cells[col_index][row_index]
		if is_instance_valid(creature):
			creatures_in_col.append(creature)
	return creatures_in_col

func find_first_empty_cell_in_row(row_index: int, start_col: int = 0, end_col: int = -1, step: int = 1) -> Vector2i:
	""" Finds the first empty cell in a specified row, searching columns left-to-right by default. """
	if row_index < 0 or row_index >= TOTAL_GRID_ROWS:
		return Vector2i(-1, -1) # Invalid row

	if end_col == -1: # Default to last column
		end_col = GRID_COLUMNS -1

	# Ensure start_col and end_col are within bounds
	start_col = clamp(start_col, 0, GRID_COLUMNS - 1)
	end_col = clamp(end_col, 0, GRID_COLUMNS - 1)

	if step > 0: # Searching left to right (or increasing index)
		for c in range(start_col, end_col + 1, step):
			if not is_cell_occupied(Vector2i(c, row_index)):
				return Vector2i(c, row_index)
	elif step < 0: # Searching right to left (or decreasing index)
		# Adjust range for negative step to include end_col
		for c in range(start_col, end_col - 1, step): # end_col -1 because range goes up to but not including
			if not is_cell_occupied(Vector2i(c, row_index)):
				return Vector2i(c, row_index)
	
	return Vector2i(-1, -1) # No empty cell found

# --- FACTION-SPECIFIC ROW UTILITIES ---
# Player rows are now the bottom three (y=3, y=4, y=5).
# Alien rows are now the top three (y=0, y=1, y=2).
# Faction Row 1 is considered the row closest to their side of the screen (their "back line").
# Faction Row 3 is considered the row closest to the center line (their "front line").

func get_player_row_y_by_faction_row_num(player_row_num: int) -> int:
	"""
	Converts player's perspective row number (1, 2, or 3) to actual grid y-coordinate.
	Player's "Row 1" (their back line) is at the bottom of the screen (y=5).
	Player's "Row 3" (their front line) is closest to the middle (y=3).
	"""
	match player_row_num:
		1: return TOTAL_GRID_ROWS - 1                     # Player's "Row 1" (y=5, bottom-most on screen)
		2: return TOTAL_GRID_ROWS - 2                     # Player's "Row 2" (y=4)
		3: return TOTAL_GRID_ROWS - GRID_ROWS_PER_FACTION # Player's "Row 3" (y=3, front-most for player)
		_:
			printerr("BattleGrid: Invalid player_row_num %d" % player_row_num)
			return -1

func get_alien_row_y_by_faction_row_num(alien_row_num: int) -> int:
	"""
	Converts alien's perspective row number (1, 2, or 3) to actual grid y-coordinate.
	Alien's "Row 1" (their back line) is at the top of the screen (y=0).
	Alien's "Row 3" (their front line) is closest to the middle (y=2).
	"""
	match alien_row_num:
		1: return 0                                     # Alien's "Row 1" (y=0, top-most on screen)
		2: return 1                                     # Alien's "Row 2" (y=1)
		3: return GRID_ROWS_PER_FACTION - 1             # Alien's "Row 3" (y=2, front-most for alien)
		_:
			printerr("BattleGrid: Invalid alien_row_num %d" % alien_row_num)
			return -1

# Call this to assign essential references if not done via @onready or scene setup.
func assign_runtime_references(gm: Node):
	game_manager = gm
