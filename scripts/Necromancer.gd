# ./scripts/Necromancer.gd
extends Node
class_name Necromancer

# Signals
signal de_changed(current_de: int, max_de: int)
signal level_changed(new_level: int) 
signal mastery_points_changed(new_mastery_points: int) 
signal spell_learned(spell_data: SpellData)
signal spell_upgraded(spell_data: SpellData) 
signal spell_cast_failed(spell_name: String, reason: String) 
signal spell_cast_succeeded(spell_name: String) 

# --- CORE ATTRIBUTES ---
@export var level: int = 1 : set = _set_level 
@export var current_de: int = 50 : set = _set_current_de
@export var max_de: int = 50 : set = _set_max_de
@export var mastery_points: int = 0 : set = _set_mastery_points 

# --- SPELLBOOK ---
var known_spells: Array[SpellData] = [] 

# --- RUNTIME REFERENCES (Set by Game.gd) ---
var game_manager: GameManager 
var battle_grid: BattleGrid  


func _ready():
	# Initial values are set by @export, signals will be emitted if changed via setters.
	# Ensure initial state is broadcast if setters weren't called by property initialization.
	# However, _set_level is called due to the ': set = _set_level' syntax if level is default 1.
	# If level was loaded as something else, setter would also run.
	# Explicitly emit for clarity if needed, but setters should handle it.
	# emit_signal("level_changed", level) # Potentially redundant if setter always runs
	# emit_signal("mastery_points_changed", mastery_points) # Potentially redundant
	emit_signal("de_changed", current_de, max_de) # Good to have for initial UI sync


# --- SETTERS ---
func _set_level(value: int):
	var old_level = level
	level = max(1, value) 
	if old_level != level:
		emit_signal("level_changed", level)
		# Note: Mastery point gain on level up is now handled by level_up_player()
		# to avoid granting MP if level is set directly for other reasons (e.g. loading game).

func _set_mastery_points(value: int):
	var old_mp = mastery_points
	mastery_points = max(0, value) 
	if old_mp != mastery_points:
		emit_signal("mastery_points_changed", mastery_points)

func _set_current_de(value: int):
	var old_de = current_de
	current_de = clamp(value, 0, max_de)
	if old_de != current_de:
		emit_signal("de_changed", current_de, max_de)

func _set_max_de(value: int):
	var old_max_de = max_de
	max_de = max(0, value) 
	if old_max_de != max_de:
		# If current_de exceeds new max_de, clamp it.
		if current_de > max_de:
			_set_current_de(max_de) # This will emit de_changed
		else: # Otherwise, just emit that max_de changed
			emit_signal("de_changed", current_de, max_de)

# --- DE MANAGEMENT ---
func spend_de(amount: int) -> bool:
	if amount <= 0: return true 
	if current_de >= amount:
		_set_current_de(current_de - amount)
		return true
	return false

func restore_de(amount: int):
	if amount <= 0: return
	_set_current_de(current_de + amount)

func replenish_de_to_max():
	_set_current_de(max_de)

# --- SPELL MANAGEMENT ---
func learn_spell(spell_instance: SpellData): 
	if not is_instance_valid(spell_instance) or not spell_instance is SpellData:
		printerr("Necromancer: Attempted to learn an invalid spell instance.")
		return
		
	var already_known = false
	for sp in known_spells:
		if sp.spell_name == spell_instance.spell_name: 
			already_known = true
			break
	
	if not already_known:
		spell_instance.set_runtime_references(self, game_manager, battle_grid)
		known_spells.append(spell_instance)
		emit_signal("spell_learned", spell_instance)


func get_spell_by_name(spell_name_to_find: String) -> SpellData:
	for spell in known_spells:
		if spell.spell_name == spell_name_to_find:
			return spell
	return null

func upgrade_spell_by_name(spell_name_to_upgrade: String) -> bool:
	var spell_to_upgrade: SpellData = get_spell_by_name(spell_name_to_upgrade)
	
	if not is_instance_valid(spell_to_upgrade):
		emit_signal("spell_cast_failed", spell_name_to_upgrade, "Spell not known.") # Use spell_cast_failed for generic failure feedback
		return false
	if spell_to_upgrade.spell_level >= spell_to_upgrade.max_spell_level:
		emit_signal("spell_cast_failed", spell_name_to_upgrade, "Spell already at max level.")
		return false

	var mp_cost = spell_to_upgrade.get_mastery_cost_for_next_upgrade()
	if mp_cost == -1: # Should not happen if not max level, but good check
		emit_signal("spell_cast_failed", spell_name_to_upgrade, "Cannot determine upgrade cost.")
		return false

	if mastery_points >= mp_cost:
		_set_mastery_points(mastery_points - mp_cost) 
		if spell_to_upgrade.upgrade_spell(): 
			emit_signal("spell_upgraded", spell_to_upgrade) # Game.gd handles success log
			return true
		else: 
			# Should not happen if upgrade_spell() is robust, but refund MP if it failed internally
			_set_mastery_points(mastery_points + mp_cost) 
			emit_signal("spell_cast_failed", spell_name_to_upgrade, "Internal spell upgrade error.")
			return false 
	else:
		emit_signal("spell_cast_failed", spell_name_to_upgrade, "Not enough Mastery Points (needs %d)." % mp_cost)
		return false 

# --- PLAYER LEVEL UP ---
# ADDED: Method for player-initiated level up
func level_up_player():
	# Basic level up: increment level, gain 1 mastery point.
	# Could be expanded with costs or other conditions in the future.
	var old_level = level
	_set_level(level + 1) # Use setter to ensure signal emission
	if level > old_level: # If level actually increased
		_set_mastery_points(mastery_points + 1) # Use setter for signal
		# Game.gd can log the success via its button handler or level_changed signal


# --- SPELL CASTING ---
func attempt_cast_spell(spell_to_cast: SpellData, target_data = null, spell_specific_arg = null) -> bool:
	if not is_instance_valid(spell_to_cast):
		printerr("Necromancer: Invalid spell instance provided for casting.")
		emit_signal("spell_cast_failed", "Unknown Spell", "Invalid spell instance.")
		return false

	# Ensure runtime refs are set, though they should be at learn_spell
	spell_to_cast.set_runtime_references(self, game_manager, battle_grid)

	if spell_to_cast.cast(self, target_data, spell_specific_arg): 
		emit_signal("spell_cast_succeeded", spell_to_cast.spell_name)
		return true
	else:
		# Failure reason should have been emitted by the spell's can_cast or cast method.
		# Necromancer doesn't need to emit another spell_cast_failed here if the spell did it.
		return false

# --- UTILITY ---
func assign_runtime_references(gm: GameManager, bg: BattleGrid): 
	game_manager = gm
	battle_grid = bg
	# Ensure spells also have their references updated if Necromancer's are late-assigned
	for spell_inst in known_spells:
		if is_instance_valid(spell_inst): 
			spell_inst.set_runtime_references(self, game_manager, battle_grid)
