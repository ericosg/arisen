# ./scripts/BattleGrid.gd
extends Node2D
class_name BattleGrid

# Signals
signal cell_occupied(grid_pos: Vector2i, creature: Creature)
signal cell_vacated(grid_pos: Vector2i, creature_that_left: Creature) # creature can be null if simply cleared

# --- CONFIGURATION ---
const CELL_SIZE: int = 128  # Visual size of a cell in pixels
const GRID_COLUMNS: int = 8
const GRID_ROWS_PER_FACTION: int = 3 # Rows for player, and separately for aliens
const TOTAL_GRID_ROWS: int = GRID_ROWS_PER_FACTION * 2 # Total rows on the grid

# --- STATE ---
# 2D array storing references to Creature nodes. null means empty.
# Access via grid_cells[column][row]
var grid_cells: Array = []

# For drawing grid lines (optional, mainly for debug/visuals)
var visual_lines_container: Node2D # A child Node2D to hold Line2D nodes

# --- REFERENCES ---
# This will be assigned by GameManager or a parent node.
var game_manager # Reference to the GameManager


func _ready():
	# Create a container for visual lines if it doesn't exist
	# This helps keep the main BattleGrid node clean.
	visual_lines_container = Node2D.new()
	visual_lines_container.name = "VisualLinesContainer"
	add_child(visual_lines_container)

	initialize_grid_data()
	draw_grid_lines() # Initial draw of the grid visuals

# --- INITIALIZATION ---
func initialize_grid_data():
	"""
	Sets up the internal 2D array (grid_cells) to represent the battle grid.
	Each cell is initially null, indicating it's empty.
	"""
	grid_cells = [] # Clear any existing data
	for _col in range(GRID_COLUMNS):
		var column_array: Array = []
		column_array.resize(TOTAL_GRID_ROWS) # Pre-size with nulls for each row in this column
		for r in range(TOTAL_GRID_ROWS):
			column_array[r] = null # Explicitly set to null
		grid_cells.append(column_array)
	# print_debug("BattleGrid: Grid data initialized (%d cols x %d rows)." % [GRID_COLUMNS, TOTAL_GRID_ROWS])

func draw_grid_lines():
	"""
	Draws the visual grid lines on the screen.
	This is primarily for debugging or visual aid during development.
	"""
	# Clear previous lines to prevent drawing over existing ones
	for child in visual_lines_container.get_children():
		child.queue_free()

	var line_color = Color(0.3, 0.3, 0.3, 0.5) # A subdued color for grid lines

	# Draw Vertical lines
	for x in range(GRID_COLUMNS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(x * CELL_SIZE, 0))
		line.add_point(Vector2(x * CELL_SIZE, TOTAL_GRID_ROWS * CELL_SIZE))
		line.width = 1.0
		line.default_color = line_color
		visual_lines_container.add_child(line)

	# Draw Horizontal lines
	for y in range(TOTAL_GRID_ROWS + 1):
		var line = Line2D.new()
		line.add_point(Vector2(0, y * CELL_SIZE))
		line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, y * CELL_SIZE))
		line.width = 1.0
		line.default_color = line_color
		visual_lines_container.add_child(line)
	
	# Optional: A thicker line to visually divide player and alien sides
	var mid_line = Line2D.new()
	# The middle line is after the alien rows (or before player rows)
	var mid_y = GRID_ROWS_PER_FACTION * CELL_SIZE 
	mid_line.add_point(Vector2(0, mid_y))
	mid_line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, mid_y))
	mid_line.width = 2.0 # Make it thicker
	mid_line.default_color = Color(0.5, 0.2, 0.2, 0.7) # A distinct color
	visual_lines_container.add_child(mid_line)


# --- GRID VALIDATION & COORDINATE UTILITIES ---
func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	"""Checks if a given grid position (column, row) is within the bounds of the grid."""
	return (grid_pos.x >= 0 and grid_pos.x < GRID_COLUMNS and \
			grid_pos.y >= 0 and grid_pos.y < TOTAL_GRID_ROWS)

func get_world_position_for_grid_cell_center(grid_pos: Vector2i) -> Vector2:
	"""
	Converts a grid cell coordinate (Vector2i) to its center world position (Vector2).
	Assumes this BattleGrid Node2D's origin is the top-left of the grid.
	"""
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot get world position for invalid grid_pos: %s" % str(grid_pos))
		return Vector2.ZERO # Return zero vector or handle error as appropriate

	# Calculate the center of the cell
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0, \
				   grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0)

func get_grid_position_from_world_position(world_pos: Vector2) -> Vector2i:
	"""
	Converts a world position (e.g., mouse click relative to BattleGrid's origin) 
	to a grid cell coordinate (Vector2i).
	"""
	var grid_x = floor(world_pos.x / CELL_SIZE)
	var grid_y = floor(world_pos.y / CELL_SIZE)
	return Vector2i(int(grid_x), int(grid_y))

# --- CREATURE PLACEMENT & QUERYING ---
func place_creature_at(creature: Creature, grid_pos: Vector2i) -> bool:
	"""
	Places a creature onto a specified grid cell.
	Returns true if placement was successful, false otherwise.
	"""
	if not is_instance_valid(creature):
		printerr("BattleGrid: Attempted to place an invalid creature instance.")
		return false
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot place creature. Invalid grid_pos: %s" % str(grid_pos))
		return false
	if grid_cells[grid_pos.x][grid_pos.y] != null:
		var occupant_name = grid_cells[grid_pos.x][grid_pos.y].creature_name if is_instance_valid(grid_cells[grid_pos.x][grid_pos.y]) else "Unknown Occupant"
		printerr("BattleGrid: Cannot place creature. Cell %s is already occupied by %s." % [str(grid_pos), occupant_name])
		return false

	grid_cells[grid_pos.x][grid_pos.y] = creature
	creature.grid_pos = grid_pos # Update creature's internal knowledge of its position
	
	emit_signal("cell_occupied", grid_pos, creature)
	# print_debug("BattleGrid: Placed %s at %s" % [creature.creature_name, str(grid_pos)])
	return true

func get_creature_at(grid_pos: Vector2i) -> Creature:
	"""Returns the creature at a given grid position, or null if the cell is empty or invalid."""
	if not is_valid_grid_position(grid_pos):
		return null
	return grid_cells[grid_pos.x][grid_pos.y] # This can be null if the cell is empty

func is_cell_occupied(grid_pos: Vector2i) -> bool:
	"""Checks if a cell is occupied. Treats out-of-bounds as occupied to prevent placement errors."""
	if not is_valid_grid_position(grid_pos):
		return true # Treat out-of-bounds as "occupied"
	return grid_cells[grid_pos.x][grid_pos.y] != null

func remove_creature_from(grid_pos: Vector2i) -> Creature:
	"""
	Removes a creature from a specified grid cell.
	Returns the creature that was removed, or null if no creature was there or pos was invalid.
	"""
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot remove creature. Invalid grid_pos: %s" % str(grid_pos))
		return null
	
	var creature_that_was_there: Creature = grid_cells[grid_pos.x][grid_pos.y]
	if is_instance_valid(creature_that_was_there):
		grid_cells[grid_pos.x][grid_pos.y] = null
		# creature_that_was_there.grid_pos = Vector2i(-1, -1) # Invalidate creature's old pos; Creature.gd setter handles this
		emit_signal("cell_vacated", grid_pos, creature_that_was_there)
		# print_debug("BattleGrid: Removed %s from %s" % [creature_that_was_there.creature_name, str(grid_pos)])
		return creature_that_was_there
	else:
		# Cell was already empty or contained an invalid instance
		grid_cells[grid_pos.x][grid_pos.y] = null # Ensure it's marked null
		emit_signal("cell_vacated", grid_pos, null) # Signal that cell is clear
		return null

func clear_cell(grid_pos: Vector2i):
	"""Ensures a cell is marked as empty, without returning the creature. Emits cell_vacated."""
	if is_valid_grid_position(grid_pos):
		var creature_ref = grid_cells[grid_pos.x][grid_pos.y] # Get ref before nulling
		grid_cells[grid_pos.x][grid_pos.y] = null
		emit_signal("cell_vacated", grid_pos, creature_ref if is_instance_valid(creature_ref) else null)


# --- ROW/COLUMN UTILITIES ---
# Player rows are at the bottom of the grid (higher y-indices).
# Alien rows are at the top of the grid (lower y-indices).

func get_player_rows_indices() -> Array[int]:
	"""Returns an array of y-indices for the player's rows."""
	var player_rows: Array[int] = []
	# Player rows are the bottom GRID_ROWS_PER_FACTION rows.
	# Example: If TOTAL_GRID_ROWS is 6 and GRID_ROWS_PER_FACTION is 3, player rows are 3, 4, 5.
	for i in range(GRID_ROWS_PER_FACTION):
		player_rows.append(GRID_ROWS_PER_FACTION + i) 
	return player_rows

func get_alien_rows_indices() -> Array[int]:
	"""Returns an array of y-indices for the alien's rows."""
	var alien_rows: Array[int] = []
	# Alien rows are the top GRID_ROWS_PER_FACTION rows.
	# Example: If GRID_ROWS_PER_FACTION is 3, alien rows are 0, 1, 2.
	for i in range(GRID_ROWS_PER_FACTION):
		alien_rows.append(i)
	return alien_rows


func get_creatures_in_row(row_index: int) -> Array[Creature]:
	"""Returns an array of all valid creatures currently in a specific row."""
	var creatures_in_row: Array[Creature] = []
	if row_index < 0 or row_index >= TOTAL_GRID_ROWS:
		printerr("BattleGrid: Invalid row_index %d for get_creatures_in_row." % row_index)
		return creatures_in_row # Return empty array
		
	for col_index in range(GRID_COLUMNS):
		var creature = grid_cells[col_index][row_index]
		if is_instance_valid(creature):
			creatures_in_row.append(creature)
	return creatures_in_row

func get_creatures_in_column(col_index: int) -> Array[Creature]:
	"""Returns an array of all valid creatures currently in a specific column."""
	var creatures_in_col: Array[Creature] = []
	if col_index < 0 or col_index >= GRID_COLUMNS:
		printerr("BattleGrid: Invalid col_index %d for get_creatures_in_column." % col_index)
		return creatures_in_col # Return empty array

	for row_index in range(TOTAL_GRID_ROWS):
		var creature = grid_cells[col_index][row_index]
		if is_instance_valid(creature):
			creatures_in_col.append(creature)
	return creatures_in_col

func find_first_empty_cell_in_row(row_index: int, start_col: int = 0, end_col: int = -1, step: int = 1) -> Vector2i:
	""" 
	Finds the first empty cell in a specified row, within a given column range.
	Returns Vector2i(-1, -1) if no empty cell is found or row is invalid.
	"""
	if row_index < 0 or row_index >= TOTAL_GRID_ROWS:
		return Vector2i(-1, -1) # Invalid row

	if end_col == -1: # Default to last column if not specified
		end_col = GRID_COLUMNS -1

	# Ensure start_col and end_col are within bounds
	start_col = clamp(start_col, 0, GRID_COLUMNS - 1)
	end_col = clamp(end_col, 0, GRID_COLUMNS - 1)

	if step > 0: # Searching left to right (or increasing column index)
		for c in range(start_col, end_col + 1, step): # Iterate from start_col to end_col (inclusive)
			if not is_cell_occupied(Vector2i(c, row_index)):
				return Vector2i(c, row_index)
	elif step < 0: # Searching right to left (or decreasing column index)
		# Adjust range for negative step to correctly include end_col if it's the start of search
		for c in range(start_col, end_col - 1, step): # range goes up to but not including the stop value
			if not is_cell_occupied(Vector2i(c, row_index)):
				return Vector2i(c, row_index)
	else: # step is 0, invalid
		printerr("BattleGrid: find_first_empty_cell_in_row called with step = 0.")
		return Vector2i(-1,-1)
	
	return Vector2i(-1, -1) # No empty cell found in the specified range

# --- FACTION-SPECIFIC ROW UTILITIES ---
# These helpers convert a faction's perspective of rows (1st, 2nd, 3rd)
# to actual grid y-coordinates.
# "Row 1" for a faction is their back-most row (furthest from the center line).
# "Row 3" for a faction is their front-most row (closest to the center line).

func get_player_row_y_by_faction_row_num(player_row_num: int) -> int:
	"""
	Converts player's perspective row number (1, 2, or 3) to actual grid y-coordinate.
	Player's "Row 1" (back line) is at y = TOTAL_GRID_ROWS - 1.
	Player's "Row 3" (front line) is at y = GRID_ROWS_PER_FACTION.
	"""
	match player_row_num:
		1: return TOTAL_GRID_ROWS - 1                     # Player's "Row 1" (e.g., y=5 if TOTAL_GRID_ROWS=6)
		2: return TOTAL_GRID_ROWS - 2                     # Player's "Row 2" (e.g., y=4)
		3: return TOTAL_GRID_ROWS - GRID_ROWS_PER_FACTION # Player's "Row 3" (e.g., y=3, if GRID_ROWS_PER_FACTION=3)
		_:
			printerr("BattleGrid: Invalid player_row_num %d" % player_row_num)
			return -1 # Indicate error

func get_alien_row_y_by_faction_row_num(alien_row_num: int) -> int:
	"""
	Converts alien's perspective row number (1, 2, or 3) to actual grid y-coordinate.
	Alien's "Row 1" (back line) is at y = 0.
	Alien's "Row 3" (front line) is at y = GRID_ROWS_PER_FACTION - 1.
	"""
	match alien_row_num:
		1: return 0                                     # Alien's "Row 1" (y=0)
		2: return 1                                     # Alien's "Row 2" (y=1)
		3: return GRID_ROWS_PER_FACTION - 1             # Alien's "Row 3" (y=2, if GRID_ROWS_PER_FACTION=3)
		_:
			printerr("BattleGrid: Invalid alien_row_num %d" % alien_row_num)
			return -1 # Indicate error

# Call this to assign essential references if not done via @onready or scene setup.
func assign_runtime_references(gm: Node):
	"""Assigns runtime references, typically the GameManager."""
	if gm is GameManager:
		game_manager = gm
	else:
		printerr("BattleGrid: Attempted to assign an invalid GameManager reference.")
