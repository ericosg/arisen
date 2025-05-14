# ./scripts/GameManager.gd
extends Node
class_name GameManager

# --- SIGNALS ---
signal turn_started(turn_number: int)
signal wave_started(wave_number: int, turn_number: int)
signal player_phase_started(phase_name: String) # e.g., "PRE_BATTLE", "REANIMATE_AFTER_WAVE"
signal battle_phase_started
signal wave_ended(wave_number: int, turn_number: int)
signal turn_ended(turn_number: int)
signal game_over(reason: String) # "humans_extinct", "player_won"
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData)
signal undead_roster_changed(new_roster: Array[Creature]) # Pass the whole roster or specific changes

# --- GAME STATE ENUMS ---
enum GamePhase {
	NONE,
	OUT_OF_TURN,      # MC leveling, spell upgrades
	TURN_STARTING,    # Replenish DE, add humans
	PLAYER_PRE_BATTLE,# Player places units, casts non-combat spells
	BATTLE_IN_PROGRESS, # Combat resolution
	PLAYER_POST_BATTLE, # Player reanimates new corpses
	WAVE_ENDING,
	TURN_ENDING       # Alien pass-through, corpse decay
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 5 
var waves_with_new_aliens: int = 3 

var human_civilian_population: int = 1000 : set = _set_human_civilian_population
const MAX_HUMAN_POPULATION: int = 1000 
const INITIAL_HUMAN_POPULATION: int = 1000

var current_game_phase: GamePhase = GamePhase.NONE

var necromancer_node: Necromancer 

var living_humans_on_grid: Array[Creature] = []
var living_aliens_on_grid: Array[Creature] = []
var living_undead_on_grid: Array[Creature] = [] 

var player_undead_roster: Array[Creature] = [] 
var available_corpses: Array[CorpseData] = [] 

var battle_grid_node: BattleGrid
var units_container_node: Node2D 

const CREATURE_SCRIPT_PATHS = {
	"Skeleton": "res://scripts/creatures/Skeleton.gd",
	"Zombie": "res://scripts/creatures/Zombie.gd",
	"Spirit": "res://scripts/creatures/Spirit.gd",
	"Human_Civilian": "res://scripts/creatures/Human.gd", 
	"Human_Swordsman": "res://scripts/creatures/Human.gd",
	"Human_Archer": "res://scripts/creatures/Human.gd",
	"Human_Knight": "res://scripts/creatures/Human.gd", # Added Knight
	"Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd",
	"Alien_Spider": "res://scripts/creatures/Alien.gd", 
	"Alien_Scorpion": "res://scripts/creatures/Alien.gd",
	"Alien_Beetle": "res://scripts/creatures/Alien.gd",
}
const INITIAL_FINALITY_FOR_NEW_CORPSES: int = 1 

var combat_log: Array[String] = [] 

func _ready():
	pass

func start_new_game():
	current_turn = 0
	_set_human_civilian_population(INITIAL_HUMAN_POPULATION)
	
	for child in units_container_node.get_children():
		if child is Creature: 
			child.queue_free()

	living_humans_on_grid.clear()
	living_aliens_on_grid.clear()
	living_undead_on_grid.clear()
	player_undead_roster.clear()
	available_corpses.clear()
	
	if is_instance_valid(battle_grid_node): 
		battle_grid_node.initialize_grid_data() 
	
	if not is_instance_valid(necromancer_node): printerr("GM: Necro node missing!"); return
	if not is_instance_valid(battle_grid_node): printerr("GM: BG node missing!"); return
	if not is_instance_valid(units_container_node): printerr("GM: Units container missing!"); return
		
	necromancer_node.assign_runtime_references(self, battle_grid_node) 

	_change_game_phase(GamePhase.OUT_OF_TURN)


func proceed_to_next_turn(): 
	if current_game_phase != GamePhase.OUT_OF_TURN and current_game_phase != GamePhase.TURN_ENDING and current_game_phase != GamePhase.NONE:
		return
	
	current_turn += 1
	current_wave_in_turn = 0
	emit_signal("turn_started", current_turn)
	_change_game_phase(GamePhase.TURN_STARTING)
	
	if is_instance_valid(necromancer_node):
		necromancer_node.replenish_de_to_max()
		
	_spawn_new_human_contingent()
	proceed_to_next_wave()

func proceed_to_next_wave(): 
	if current_game_phase != GamePhase.TURN_STARTING and \
	   current_game_phase != GamePhase.PLAYER_POST_BATTLE and \
	   current_game_phase != GamePhase.WAVE_ENDING: 
		return

	current_wave_in_turn += 1
	if current_wave_in_turn > max_waves_per_turn:
		_end_current_turn()
		return

	emit_signal("wave_started", current_wave_in_turn, current_turn)
	
	if current_wave_in_turn <= waves_with_new_aliens:
		_spawn_new_alien_wave()
		
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE)
	emit_signal("player_phase_started", "PRE_BATTLE")


func player_ends_pre_battle_phase(): 
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started")
	combat_log.clear()
	
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
			
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")


func player_ends_post_battle_phase(): 
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	_end_current_wave()


func _end_current_wave():
	emit_signal("wave_ended", current_wave_in_turn, current_turn)
	_change_game_phase(GamePhase.WAVE_ENDING)

	var aliens_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_spawn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_on_grid and not more_aliens_spawn:
		_end_current_turn()


func _end_current_turn():
	_change_game_phase(GamePhase.TURN_ENDING)
	
	var passed_aliens: Array[Creature] = []
	for alien in living_aliens_on_grid.duplicate(): 
		if not is_instance_valid(alien) or not alien.is_alive: continue
		var clear_path = true
		for p_unit in living_humans_on_grid + living_undead_on_grid:
			if is_instance_valid(p_unit) and p_unit.is_alive and p_unit.grid_pos.x == alien.grid_pos.x:
				clear_path = false; break
		if clear_path: passed_aliens.append(alien)
			
	for alien_p in passed_aliens:
		_handle_alien_pass_through(alien_p, "EndTurn")
		if is_instance_valid(alien_p): _remove_creature_from_game(alien_p)

	for corpse_d in available_corpses.duplicate(): _remove_corpse_from_list(corpse_d) 
	available_corpses.clear() 

	emit_signal("turn_ended", current_turn)
	
	if current_turn >= 20: _set_game_over("player_won", "Survived!"); return
	_change_game_phase(GamePhase.OUT_OF_TURN)

func _set_human_civilian_population(value: int):
	var old = human_civilian_population
	human_civilian_population = max(0, value) 
	if old != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population)
		if human_civilian_population == 0: _set_game_over("humans_extinct", "Population Zero.")

func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase: current_game_phase = new_phase

func _set_game_over(reason: String, msg: String):
	if current_game_phase == GamePhase.NONE and reason != "": return 
	_change_game_phase(GamePhase.NONE); emit_signal("game_over", reason)

func _spawn_new_human_contingent():
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placeholder_human.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placeholder_archer.png"}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_civilian.png"}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN)

func _spawn_new_alien_wave():
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "max_health": 8, "attack_power": 3, "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "max_health": 6, "attack_power": 2, "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png"}},
	]
	if current_wave_in_turn == 2: 
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "max_health": 20, "attack_power": 2, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png"}})
	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN)

func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction):
	var faction_rows_y: Array[int]
	if faction == Creature.Faction.HUMAN: faction_rows_y = [0,1,2] # Player R1,R2,R3 (y=0,1,2)
	elif faction == Creature.Faction.ALIEN: faction_rows_y = [5,4,3] # Alien R1,R2,R3 (y=5,4,3)
	else: return

	for unit_data in units_to_spawn_data:
		var creature_node: Creature = _create_creature_node_from_config(unit_data["type"], unit_data["config"], faction)
		if not is_instance_valid(creature_node): continue
		var placed = false
		for row_y in faction_rows_y: 
			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1):
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					# Creature.gd's _set_grid_pos now handles setting self.position
					placed = true; break 
		if not placed: creature_node.queue_free()


func spawn_reanimated_creature(config_from_spell: Dictionary) -> Creature:
	var script_path = config_from_spell.get("creature_class_script_path", "")
	if script_path == "": return null

	var creature_node = Node2D.new() 
	var script_res = load(script_path)
	if not script_res: creature_node.queue_free(); return null
	
	creature_node.set_script(script_res)
	var actual_creature: Creature = creature_node as Creature 
	if not is_instance_valid(actual_creature): creature_node.queue_free(); return null

	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	# Add sprite_texture_path to reanimation configs if not already there
	var final_config = config_from_spell.duplicate(true)
	var undead_type_name = config_from_spell.get("creature_name", "Undead").to_lower()
	if undead_type_name.contains("skeleton"):
		final_config["sprite_texture_path"] = "res://assets/images/placeholder_skeleton.png"
	elif undead_type_name.contains("zombie"):
		final_config["sprite_texture_path"] = "res://assets/images/placeholder_zombie.png"
	elif undead_type_name.contains("spirit"):
		final_config["sprite_texture_path"] = "res://assets/images/placeholder_spirit.png"
	else: # Default undead sprite
		final_config["sprite_texture_path"] = "res://assets/images/placeholder_undead.png"

	actual_creature.initialize_creature(final_config)
	units_container_node.add_child(actual_creature)
	player_undead_roster.append(actual_creature)
	emit_signal("undead_roster_changed", player_undead_roster)
	return actual_creature


func _create_creature_node_from_config(type_key: String, config: Dictionary, fact_override: Creature.Faction) -> Creature:
	var script_path = CREATURE_SCRIPT_PATHS.get(type_key, "")
	if script_path == "": return null

	var creature_node = Node2D.new()
	var script_res = load(script_path)
	if not script_res: creature_node.queue_free(); return null
	
	creature_node.set_script(script_res)
	var actual_creature: Creature = creature_node as Creature
	if not is_instance_valid(actual_creature): creature_node.queue_free(); return null
		
	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	var final_cfg = config.duplicate(true)
	final_cfg["faction"] = fact_override 
	
	actual_creature.initialize_creature(final_cfg)
	units_container_node.add_child(actual_creature) # Add to scene tree under UnitsContainer
	
	if not actual_creature.died.is_connected(_on_creature_died): 
		actual_creature.died.connect(_on_creature_died.bind(actual_creature))
	return actual_creature

func _add_creature_to_active_lists(creature: Creature):
	if not is_instance_valid(creature): return
	match creature.faction:
		Creature.Faction.HUMAN:
			if not living_humans_on_grid.has(creature): living_humans_on_grid.append(creature)
		Creature.Faction.ALIEN:
			if not living_aliens_on_grid.has(creature): living_aliens_on_grid.append(creature)
		Creature.Faction.UNDEAD:
			if not living_undead_on_grid.has(creature): living_undead_on_grid.append(creature)
			if player_undead_roster.has(creature):
				player_undead_roster.erase(creature)
				emit_signal("undead_roster_changed", player_undead_roster)

func _on_creature_died(creature_died: Creature):
	if not is_instance_valid(creature_died): return
	
	var corpse_payload = creature_died.get_data_for_corpse_creation()
	corpse_payload["grid_pos_on_death"] = creature_died.grid_pos
	corpse_payload["turn_of_death"] = current_turn
	
	if creature_died.faction == Creature.Faction.HUMAN or creature_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: 
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)

	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse); emit_signal("corpse_added", new_corpse)
	_remove_creature_from_game(creature_died)

func _remove_creature_from_game(creature_to_remove: Creature):
	if not is_instance_valid(creature_to_remove): return
	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos)

	match creature_to_remove.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			living_undead_on_grid.erase(creature_to_remove)
			if player_undead_roster.has(creature_to_remove): # Should not happen if dying from grid
				player_undead_roster.erase(creature_to_remove); emit_signal("undead_roster_changed", player_undead_roster)

	if not creature_to_remove.is_queued_for_deletion(): creature_to_remove.queue_free()

func consume_corpse(corpse: CorpseData): 
	if available_corpses.has(corpse):
		available_corpses.erase(corpse); emit_signal("corpse_removed", corpse)

func _remove_corpse_from_list(corpse: CorpseData): 
	if available_corpses.has(corpse):
		available_corpses.erase(corpse); emit_signal("corpse_removed", corpse)

func _resolve_combat_in_lane(col_idx: int) -> bool:
	var combat_occured = false
	while true: 
		var p_unit: Creature = null; var a_unit: Creature = null
		for r_p in range(2, -1, -1): # Player rows 2,1,0 (R3,R2,R1)
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_p))
			if is_instance_valid(c) and c.is_alive and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
				p_unit = c; break
		for r_a in range(3, 6): # Alien rows 3,4,5 (their R3,R2,R1)
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_a))
			if is_instance_valid(c) and c.is_alive and c.faction == Creature.Faction.ALIEN:
				a_unit = c; break
		
		if not is_instance_valid(p_unit) or not is_instance_valid(a_unit): break 
		combat_occured = true
		var log = "L%d: %s vs %s" % [col_idx, p_unit.creature_name, a_unit.creature_name]
		
		var alien_passed = false
		if a_unit.is_flying and not p_unit.is_flying and not p_unit.has_reach:
			log += " - ALIEN PASSES!"; combat_log.append(log)
			_handle_alien_pass_through(a_unit, "MidBattleUnblock")
			_remove_creature_from_game(a_unit); alien_passed = true
		
		if alien_passed: continue 

		var p_hp_old = p_unit.current_health; var a_hp_old = a_unit.current_health
		p_unit.take_damage(a_unit.attack_power); a_unit.take_damage(p_unit.attack_power)
		log += " | P:%d->%d A:%d->%d" % [p_hp_old, p_unit.current_health, a_hp_old, a_unit.current_health]
		combat_log.append(log)
		
		if not p_unit.is_alive and not a_unit.is_alive: break 
	return combat_occured

func _handle_alien_pass_through(alien: Creature, reason: String):
	if not is_instance_valid(alien): return
	_set_human_civilian_population(human_civilian_population - (alien.attack_power * 5))

func get_available_corpses() -> Array[CorpseData]: return available_corpses 
func get_all_living_humans_and_aliens() -> Array[Creature]:
	var all: Array[Creature] = []; all.append_array(living_humans_on_grid); all.append_array(living_aliens_on_grid)
	return all.filter(func(c: Creature): return is_instance_valid(c) and c.is_alive)
func get_player_undead_roster() -> Array[Creature]: return player_undead_roster

func player_deploys_undead_from_roster(undead: Creature, grid_pos: Vector2i) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return false
	if not is_instance_valid(undead) or not player_undead_roster.has(undead): return false
	
	var p_rows_y = [battle_grid_node.get_player_row_y_by_faction_row_num(1),battle_grid_node.get_player_row_y_by_faction_row_num(2),battle_grid_node.get_player_row_y_by_faction_row_num(3)]
	var allowed_rows: Array[int] = []
	match undead.speed_type:
		Creature.SpeedType.SLOW: allowed_rows = [p_rows_y[0]]
		Creature.SpeedType.NORMAL: allowed_rows = [p_rows_y[0], p_rows_y[1]]
		Creature.SpeedType.FAST: allowed_rows = p_rows_y
	if not grid_pos.y in allowed_rows: return false

	if battle_grid_node.place_creature_at(undead, grid_pos):
		_add_creature_to_active_lists(undead) 
		# Creature.gd's _set_grid_pos will update its visual position
		return true
	return false

func player_returns_undead_to_roster(undead: Creature) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return false
	if not is_instance_valid(undead) or not living_undead_on_grid.has(undead): return false
	var old_pos = undead.grid_pos
	if battle_grid_node.remove_creature_from(old_pos) == undead: 
		living_undead_on_grid.erase(undead); player_undead_roster.append(undead)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead.grid_pos = Vector2i(-1,-1) 
		return true
	return false

func late_initialize_references(necro: Necromancer, bg: BattleGrid, units_cont: Node2D):
	necromancer_node = necro; battle_grid_node = bg; units_container_node = units_cont
