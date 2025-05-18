# ./scripts/Necromancer.gd
extends Node
class_name Necromancer

# Signals
signal de_changed(current_de: int, max_de: int)
signal level_changed(new_level: int) # Emitted when Necromancer's main level changes
signal mastery_points_changed(new_mastery_points: int) # Emitted when MP changes
signal spell_learned(spell_data: SpellData)
signal spell_upgraded(spell_data: SpellData) # Emitted when a spell's level increases
signal spell_cast_failed(spell_name: String, reason: String) # For UI feedback
signal spell_cast_succeeded(spell_name: String) # For UI feedback

# --- CORE ATTRIBUTES ---
@export var level: int = 1 : set = _set_level # Necromancer's main level
@export var current_de: int = 50 : set = _set_current_de
@export var max_de: int = 50 : set = _set_max_de
# Mastery Points are gained with levels and spent on upgrades.
@export var mastery_points: int = 0 : set = _set_mastery_points 

# --- SPELLBOOK ---
var known_spells: Array[SpellData] = [] # Stores instances of learned spells

# --- RUNTIME REFERENCES (Set by Game.gd) ---
var game_manager: GameManager 
var battle_grid: BattleGrid  


func _ready():
	# Initial signal emissions
	# Set level first, which then sets initial mastery points via its setter logic
	_set_level(level) 
	emit_signal("de_changed", current_de, max_de) # Emit initial DE state


# --- SETTERS ---
func _set_level(value: int):
	var old_level = level
	level = max(1, value) 
	if old_level != level:
		emit_signal("level_changed", level)
		# Gain 1 MP per level up (if level increased)
		# This assumes leveling up always grants MP.
		if level > old_level:
			_set_mastery_points(mastery_points + (level - old_level))
		# If level is set directly (e.g. game start), ensure MP is correct:
		elif old_level == 1 and level == 1 and mastery_points == 0: # Initial setup at level 1
			_set_mastery_points(0) # MP is 0 at level 1
		# else, if level is set downwards or to same value, MP isn't auto-adjusted here.
		# The logic is: MP = (level - 1) accumulated, minus spent.
		# Simpler: _ready sets initial MP. Leveling up adds to it.

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
		if current_de > max_de:
			_set_current_de(max_de) 
		else: 
			emit_signal("de_changed", current_de, max_de)

# --- DE MANAGEMENT ---
func spend_de(amount: int) -> bool:
	if amount <= 0: return true 
	if current_de >= amount:
		_set_current_de(current_de - amount)
		return true
	# Failure to spend DE is caught by spell's can_cast, which emits spell_cast_failed.
	return false

func restore_de(amount: int):
	if amount <= 0: return
	_set_current_de(current_de + amount)

func replenish_de_to_max():
	_set_current_de(max_de)

# --- SPELL MANAGEMENT ---
func learn_spell(spell_instance: SpellData): # Expects an instance, not a resource path
	if not is_instance_valid(spell_instance) or not spell_instance is SpellData:
		printerr("Necromancer: Attempted to learn an invalid spell instance.")
		return
		
	# Prevent learning the exact same instance multiple times.
	# If spells are identified by name, ensure no duplicate names if that's a rule.
	var already_known = false
	for sp in known_spells:
		if sp.spell_name == spell_instance.spell_name: # Assuming unique spell names
			already_known = true
			# print_debug("Necromancer already knows spell: %s" % spell_instance.spell_name)
			break
	
	if not already_known:
		# Set runtime references on the spell instance
		spell_instance.set_runtime_references(self, game_manager, battle_grid)
		known_spells.append(spell_instance)
		emit_signal("spell_learned", spell_instance)
		# print_debug("Necromancer learned spell: %s (Lvl %d)" % [spell_instance.spell_name, spell_instance.spell_level])


func get_spell_by_name(spell_name_to_find: String) -> SpellData:
	for spell in known_spells:
		if spell.spell_name == spell_name_to_find:
			return spell
	return null

func upgrade_spell_by_name(spell_name_to_upgrade: String) -> bool:
	var spell_to_upgrade: SpellData = get_spell_by_name(spell_name_to_upgrade)
	
	if not is_instance_valid(spell_to_upgrade):
		# print_debug("Necromancer: Cannot upgrade. Spell '%s' not found." % spell_name_to_upgrade)
		return false
		
	if spell_to_upgrade.spell_level >= spell_to_upgrade.max_spell_level:
		# print_debug("Necromancer: Spell %s is already at max level." % spell_to_upgrade.spell_name)
		return false # UI should disable button

	var mp_cost = spell_to_upgrade.get_mastery_cost_for_next_upgrade()

	if mp_cost == -1: 
		# print_debug("Necromancer: No mastery cost defined for upgrading %s from L%d." % [spell_to_upgrade.spell_name, spell_to_upgrade.spell_level])
		return false

	if mastery_points >= mp_cost:
		_set_mastery_points(mastery_points - mp_cost) 
		
		if spell_to_upgrade.upgrade_spell(): # This increments spell_level in the spell
			emit_signal("spell_upgraded", spell_to_upgrade)
			# print_debug("Necromancer upgraded spell: %s to Lvl %d. MP Remaining: %d" % [spell_to_upgrade.spell_name, spell_to_upgrade.spell_level, mastery_points])
			return true
		else: # Should not happen if max_level check passed
			_set_mastery_points(mastery_points + mp_cost) # Refund MP
			# print_debug("Necromancer: Spell %s upgrade failed internally. MP refunded." % spell_to_upgrade.spell_name)
			return false 
	else:
		# print_debug("Necromancer: Not enough MP to upgrade %s. Has: %d, Needs: %d" % [spell_to_upgrade.spell_name, mastery_points, mp_cost])
		return false # UI should disable


# --- SPELL CASTING ---
func attempt_cast_spell(spell_to_cast: SpellData, target_data = null) -> bool:
	if not is_instance_valid(spell_to_cast):
		printerr("Necromancer: Invalid spell instance provided for casting.")
		emit_signal("spell_cast_failed", "Unknown Spell", "Invalid spell instance.")
		return false

	# Ensure runtime references are set (should be done when learned, but good safety check)
	spell_to_cast.set_runtime_references(self, game_manager, battle_grid)

	# Delegate actual casting logic to the spell resource itself
	if spell_to_cast.cast(self, target_data): # Pass self as caster_node
		emit_signal("spell_cast_succeeded", spell_to_cast.spell_name)
		return true
	else:
		# The spell's can_cast or cast method should have emitted specific failure reasons
		# via the spell_cast_failed signal on this Necromancer node.
		return false

# --- UTILITY ---
func assign_runtime_references(gm: GameManager, bg: BattleGrid): 
	game_manager = gm
	battle_grid = bg
	# After setting these, re-initialize runtime references for already known spells
	# This is important if spells were learned before GM/BG were fully ready.
	for spell_inst in known_spells:
		if is_instance_valid(spell_inst): 
			spell_inst.set_runtime_references(self, game_manager, battle_grid)
