# ./scripts/BattleGrid.gd
extends Node2D
class_name BattleGrid

# Signals
signal cell_occupied(grid_pos: Vector2i, creature: Creature) # For living creatures
signal cell_vacated(grid_pos: Vector2i, creature_that_left: Creature) # For living creatures
signal corpse_added_to_cell(grid_pos: Vector2i, corpse_node: Creature) # When a creature node becomes a corpse on a cell
signal corpse_removed_from_cell(grid_pos: Vector2i, corpse_node: Creature) # When a corpse node is removed/replaced

# --- CONFIGURATION ---
const CELL_SIZE: int = 128  
const GRID_COLUMNS: int = 8
const GRID_ROWS_PER_FACTION: int = 3 
const TOTAL_GRID_ROWS: int = GRID_ROWS_PER_FACTION * 2 

# --- STATE ---
# grid_cells stores the primary occupant: a living Creature node or a Creature node marked as a corpse.
var grid_cells: Array = [] 

var visual_lines_container: Node2D 
var game_manager: GameManager # Assigned by GameManager


func _ready():
	visual_lines_container = Node2D.new()
	visual_lines_container.name = "VisualLinesContainer"
	add_child(visual_lines_container)
	initialize_grid_data()
	draw_grid_lines() 

func initialize_grid_data():
	grid_cells = [] 
	for _col in range(GRID_COLUMNS):
		var column_array: Array = []
		column_array.resize(TOTAL_GRID_ROWS) 
		for r in range(TOTAL_GRID_ROWS):
			column_array[r] = null 
		grid_cells.append(column_array)

func draw_grid_lines(): # Copied from your provided BattleGrid.gd
	for child in visual_lines_container.get_children(): child.queue_free()
	var line_color = Color(0.3, 0.3, 0.3, 0.5) 
	for x in range(GRID_COLUMNS + 1):
		var line = Line2D.new(); line.add_point(Vector2(x * CELL_SIZE, 0)); line.add_point(Vector2(x * CELL_SIZE, TOTAL_GRID_ROWS * CELL_SIZE))
		line.width = 1.0; line.default_color = line_color; visual_lines_container.add_child(line)
	for y in range(TOTAL_GRID_ROWS + 1):
		var line = Line2D.new(); line.add_point(Vector2(0, y * CELL_SIZE)); line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, y * CELL_SIZE))
		line.width = 1.0; line.default_color = line_color; visual_lines_container.add_child(line)
	var mid_line = Line2D.new(); var mid_y = GRID_ROWS_PER_FACTION * CELL_SIZE 
	mid_line.add_point(Vector2(0, mid_y)); mid_line.add_point(Vector2(GRID_COLUMNS * CELL_SIZE, mid_y))
	mid_line.width = 2.0; mid_line.default_color = Color(0.5, 0.2, 0.2, 0.7); visual_lines_container.add_child(mid_line)

func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return (grid_pos.x >= 0 and grid_pos.x < GRID_COLUMNS and \
			grid_pos.y >= 0 and grid_pos.y < TOTAL_GRID_ROWS)

func get_world_position_for_grid_cell_center(grid_pos: Vector2i) -> Vector2:
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Invalid grid_pos for world_pos: %s" % str(grid_pos)); return Vector2.ZERO 
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2.0, grid_pos.y * CELL_SIZE + CELL_SIZE / 2.0)

func get_grid_position_from_world_position(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / CELL_SIZE)), int(floor(world_pos.y / CELL_SIZE)))

# --- CREATURE PLACEMENT & QUERYING ---
func place_creature_at(creature_node_to_place: Creature, grid_pos: Vector2i) -> bool:
	if not is_instance_valid(creature_node_to_place):
		printerr("BattleGrid: Attempted to place an invalid creature instance.")
		return false
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot place creature. Invalid grid_pos: %s" % str(grid_pos))
		return false

	var current_occupant_node = grid_cells[grid_pos.x][grid_pos.y] # This could be a living unit or a corpse node

	if creature_node_to_place.is_corpse:
		# Placing a corpse node (this happens when a creature dies and its node becomes the corpse visual)
		if is_instance_valid(current_occupant_node) and not current_occupant_node.is_corpse:
			printerr("BattleGrid Error: Trying to place corpse '%s' over living unit '%s' at %s." % [creature_node_to_place.creature_name, current_occupant_node.creature_name, str(grid_pos)])
			return false # Should not happen if logic is correct elsewhere (living unit should die first)
		
		if is_instance_valid(current_occupant_node) and current_occupant_node.is_corpse and current_occupant_node != creature_node_to_place:
			# A different corpse node is already here. The new one (from the recently died unit) replaces it.
			# The old corpse node should be freed by GameManager when its CorpseData is handled.
			emit_signal("corpse_removed_from_cell", grid_pos, current_occupant_node)
		
		grid_cells[grid_pos.x][grid_pos.y] = creature_node_to_place
		creature_node_to_place.grid_pos = grid_pos # Update creature's internal knowledge
		emit_signal("corpse_added_to_cell", grid_pos, creature_node_to_place)
		# print_debug("BattleGrid: Placed corpse visual '%s' at %s" % [creature_node_to_place.creature_name, str(grid_pos)])
		return true
	else: # Placing a living creature
		if is_instance_valid(current_occupant_node) and not current_occupant_node.is_corpse:
			# Cell is occupied by another LIVING unit
			var occupant_name = current_occupant_node.creature_name
			printerr("BattleGrid: Cannot place living '%s'. Cell %s is occupied by living '%s'." % [creature_node_to_place.creature_name, str(grid_pos), occupant_name])
			return false
		
		# If a corpse node is here, the living unit is placed "on top".
		# The corpse node is still technically at this grid_pos in terms of its data,
		# but the grid_cells array now points to the living unit.
		# The CorpseData resource for the underlying corpse is still managed by GameManager.
		if is_instance_valid(current_occupant_node) and current_occupant_node.is_corpse:
			# The corpse visual node (current_occupant_node) is effectively "covered".
			# It might be queue_freed later when its CorpseData is consumed or decays.
			# For BattleGrid's purpose, the living unit is now the primary occupant of the cell.
			emit_signal("corpse_removed_from_cell", grid_pos, current_occupant_node) # Signal that corpse visual is no longer primary
			
		grid_cells[grid_pos.x][grid_pos.y] = creature_node_to_place
		creature_node_to_place.grid_pos = grid_pos
		emit_signal("cell_occupied", grid_pos, creature_node_to_place) # For living creatures
		# print_debug("BattleGrid: Placed living '%s' at %s" % [creature_node_to_place.creature_name, str(grid_pos)])
		return true

func get_creature_at(grid_pos: Vector2i) -> Creature:
	"""Returns the creature node (living or corpse) at a given grid position, or null."""
	if not is_valid_grid_position(grid_pos): return null
	return grid_cells[grid_pos.x][grid_pos.y]

func get_living_creature_at(grid_pos: Vector2i) -> Creature:
	"""Returns a LIVING creature node at a given grid position, or null if empty or only a corpse."""
	var c = get_creature_at(grid_pos)
	if is_instance_valid(c) and not c.is_corpse:
		return c
	return null

func get_corpse_node_at(grid_pos: Vector2i) -> Creature:
	"""Returns a creature node marked as a CORPSE at a given grid position, or null."""
	var c = get_creature_at(grid_pos)
	if is_instance_valid(c) and c.is_corpse:
		return c
	return null

func is_cell_occupied_by_living_unit(grid_pos: Vector2i) -> bool:
	"""Checks if a cell is occupied by a LIVING unit. Out-of-bounds is 'occupied'."""
	if not is_valid_grid_position(grid_pos): return true 
	var creature_node = grid_cells[grid_pos.x][grid_pos.y]
	return is_instance_valid(creature_node) and not creature_node.is_corpse

func remove_creature_from(grid_pos: Vector2i) -> Creature:
	"""
	Removes the creature node (living or corpse) from the specified grid cell in grid_cells.
	Returns the node that was removed.
	"""
	if not is_valid_grid_position(grid_pos):
		printerr("BattleGrid: Cannot remove. Invalid grid_pos: %s" % str(grid_pos))
		return null
	
	var occupant_node: Creature = grid_cells[grid_pos.x][grid_pos.y]
	if is_instance_valid(occupant_node):
		grid_cells[grid_pos.x][grid_pos.y] = null # Clear the cell in the grid array
		# occupant_node.grid_pos = Vector2i(-1, -1) # Creature's setter handles this if called by GameManager
		
		if occupant_node.is_corpse:
			emit_signal("corpse_removed_from_cell", grid_pos, occupant_node)
		else:
			emit_signal("cell_vacated", grid_pos, occupant_node) # For living creatures
		# print_debug("BattleGrid: Removed occupant '%s' from %s" % [occupant_node.creature_name, str(grid_pos)])
		return occupant_node
	else: # Cell was already empty
		grid_cells[grid_pos.x][grid_pos.y] = null 
		emit_signal("cell_vacated", grid_pos, null) # Signal cell is clear
		return null

func clear_cell(grid_pos: Vector2i): # Kept from your version
	if is_valid_grid_position(grid_pos):
		var creature_ref = grid_cells[grid_pos.x][grid_pos.y] 
		grid_cells[grid_pos.x][grid_pos.y] = null
		if is_instance_valid(creature_ref):
			if creature_ref.is_corpse: emit_signal("corpse_removed_from_cell", grid_pos, creature_ref)
			else: emit_signal("cell_vacated", grid_pos, creature_ref)
		else: emit_signal("cell_vacated", grid_pos, null)


# --- ROW/COLUMN UTILITIES (Copied from your BattleGrid.gd) ---
func get_player_rows_indices() -> Array[int]:
	var player_rows: Array[int] = []; for i in range(GRID_ROWS_PER_FACTION): player_rows.append(GRID_ROWS_PER_FACTION + i); 
	return player_rows
func get_alien_rows_indices() -> Array[int]:
	var alien_rows: Array[int] = []; for i in range(GRID_ROWS_PER_FACTION): alien_rows.append(i); 
	return alien_rows
func get_creatures_in_row(row_index: int) -> Array[Creature]: # Consider adding include_corpses flag if needed
	var creatures_in_row: Array[Creature] = []; if row_index < 0 or row_index >= TOTAL_GRID_ROWS: return creatures_in_row
	for col_index in range(GRID_COLUMNS):
		var creature = grid_cells[col_index][row_index]; if is_instance_valid(creature): creatures_in_row.append(creature)
	return creatures_in_row
func get_creatures_in_column(col_index: int) -> Array[Creature]: # Consider adding include_corpses flag
	var creatures_in_col: Array[Creature] = []; if col_index < 0 or col_index >= GRID_COLUMNS: return creatures_in_col
	for row_index in range(TOTAL_GRID_ROWS):
		var creature = grid_cells[col_index][row_index]; if is_instance_valid(creature): creatures_in_col.append(creature)
	return creatures_in_col
func find_first_empty_cell_in_row(row_index: int, start_col: int = 0, end_col: int = -1, step: int = 1) -> Vector2i:
	"""Finds the first cell NOT occupied by a LIVING unit."""
	if row_index < 0 or row_index >= TOTAL_GRID_ROWS: return Vector2i(-1, -1)
	if end_col == -1: end_col = GRID_COLUMNS -1
	start_col = clamp(start_col, 0, GRID_COLUMNS - 1); end_col = clamp(end_col, 0, GRID_COLUMNS - 1)
	if step > 0: 
		for c in range(start_col, end_col + 1, step):
			if not is_cell_occupied_by_living_unit(Vector2i(c, row_index)): return Vector2i(c, row_index)
	elif step < 0: 
		for c in range(start_col, end_col - 1, step): 
			if not is_cell_occupied_by_living_unit(Vector2i(c, row_index)): return Vector2i(c, row_index)
	else: printerr("BattleGrid: find_first_empty_cell_in_row step = 0."); return Vector2i(-1,-1)
	return Vector2i(-1, -1) 
func get_player_row_y_by_faction_row_num(player_row_num: int) -> int:
	match player_row_num: 
		1: return TOTAL_GRID_ROWS - 1; 
		2: return TOTAL_GRID_ROWS - 2; 
		3: return TOTAL_GRID_ROWS - GRID_ROWS_PER_FACTION 
		_: printerr("BattleGrid: Invalid player_row_num %d" % player_row_num); return -1 
func get_alien_row_y_by_faction_row_num(alien_row_num: int) -> int:
	match alien_row_num: 
		1: return 0; 
		2: return 1; 
		3: return GRID_ROWS_PER_FACTION - 1             
		_: printerr("BattleGrid: Invalid alien_row_num %d" % alien_row_num); return -1 
func assign_runtime_references(gm: Node):
	if gm is GameManager: game_manager = gm
	else: printerr("BattleGrid: Invalid GameManager reference.")
