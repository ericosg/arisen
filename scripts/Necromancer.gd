# ./scripts/Necromancer.gd
extends Node
class_name Necromancer

# Signals
signal de_changed(current_de: int, max_de: int)
signal level_changed(new_level: int)
signal spell_learned(spell_data: SpellData)
signal spell_upgraded(spell_data: SpellData)
signal spell_cast_failed(spell_name: String, reason: String)
signal spell_cast_succeeded(spell_name: String)

# --- CORE ATTRIBUTES ---
@export var level: int = 1 : set = _set_level
@export var current_de: int = 50 : set = _set_current_de
@export var max_de: int = 50 : set = _set_max_de

# --- SPELLBOOK ---
# An array to store instances of SpellData resources that the Necromancer knows.
var known_spells: Array[SpellData] = []

# --- REFERENCES (Assign in _ready or via direct assignment from GameManager) ---
# GameManager will likely create/manage the Necromancer instance.
var game_manager # GameManager instance
var battle_grid  # BattleGrid instance
# @onready var game_manager = get_tree().get_root().find_child("GameManagerNodeName", true, false) # Example


func _ready():
	# Initial signal emissions if values are set via @export
	emit_signal("level_changed", level)
	emit_signal("de_changed", current_de, max_de)
	
	# TODO: Load known spells if implementing a save/load system.
	# For now, spells can be added programmatically.
	# Example: learn_spell(load("res://scripts/spells/SpellReanimateData.tres").duplicate())
	# Ensure to .duplicate() if loading from .tres to avoid modifying the base resource directly
	# if multiple Necromancers could exist or if spells are modified per instance.

# --- SETTERS ---
func _set_level(value: int):
	var old_level = level
	level = max(1, value) # Level cannot be less than 1
	if old_level != level:
		# GDD: Leveling up only changes max stats. Current DE remains.
		# Max DE scaling and other benefits of leveling up should be handled here or by GameManager.
		# Example: _set_max_de(calculate_max_de_for_level(level))
		emit_signal("level_changed", level)
		# print_debug("Necromancer leveled up to %d" % level)

func _set_current_de(value: int):
	var old_de = current_de
	current_de = clamp(value, 0, max_de)
	if old_de != current_de:
		emit_signal("de_changed", current_de, max_de)

func _set_max_de(value: int):
	var old_max_de = max_de
	max_de = max(0, value) # Max DE shouldn't be negative
	if old_max_de != max_de:
		# If current DE exceeds new max DE (e.g., max DE reduced), clamp current DE.
		if current_de > max_de:
			_set_current_de(max_de) # Use setter to emit signal
		else: # Only emit de_changed if current_de wasn't adjusted by the above line
			emit_signal("de_changed", current_de, max_de)

# --- DE MANAGEMENT ---
func spend_de(amount: int) -> bool:
	if amount <= 0:
		return true # Spending 0 or negative DE is always "successful" without change
	if current_de >= amount:
		_set_current_de(current_de - amount)
		return true
	# print_debug("Necromancer: Not enough DE to spend %d. Has: %d" % [amount, current_de])
	return false

func restore_de(amount: int):
	if amount <= 0:
		return
	_set_current_de(current_de + amount)
	# print_debug("Necromancer restored %d DE. Current DE: %d/%d" % [amount, current_de, max_de])

func replenish_de_to_max():
	# print_debug("Necromancer DE replenished to max.")
	_set_current_de(max_de)

# --- SPELL MANAGEMENT ---
func learn_spell(spell_resource: SpellData):
	if not spell_resource is SpellData:
		printerr("Necromancer: Attempted to learn an invalid spell resource.")
		return
		
	# Prevent learning the exact same resource instance multiple times.
	# If spells are identified by name and level, more complex logic is needed
	# to handle learning a spell that's already known (e.g., for upgrading).
	if not known_spells.has(spell_resource):
		# IMPORTANT: Set runtime references on the spell resource instance
		# This Necromancer instance is the caster.
		spell_resource.set_runtime_references(self, game_manager, battle_grid)
		
		known_spells.append(spell_resource)
		emit_signal("spell_learned", spell_resource)
		# print_debug("Necromancer learned spell: %s (Lvl %d)" % [spell_resource.spell_name, spell_resource.spell_level])
	else:
		# print_debug("Necromancer already knows spell: %s" % spell_resource.spell_name)
		pass

func get_spell_by_name(spell_name_to_find: String) -> SpellData:
	for spell in known_spells:
		if spell.spell_name == spell_name_to_find:
			return spell
	return null

func upgrade_spell_by_name(spell_name_to_upgrade: String) -> bool:
	var spell_to_upgrade: SpellData = get_spell_by_name(spell_name_to_upgrade)
	if is_instance_valid(spell_to_upgrade):
		if spell_to_upgrade.upgrade_spell():
			emit_signal("spell_upgraded", spell_to_upgrade)
			# print_debug("Necromancer upgraded spell: %s to Lvl %d" % [spell_to_upgrade.spell_name, spell_to_upgrade.spell_level])
			return true
		else:
			# print_debug("Necromancer: Spell %s is already at max level or upgrade failed." % spell_to_upgrade.spell_name)
			return false
	# print_debug("Necromancer: Cannot upgrade. Spell '%s' not found." % spell_name_to_upgrade)
	return false

# --- SPELL CASTING ---
# This is the primary interface for the player/UI to cast a known spell.
# `spell_to_cast` should be one of the SpellData instances from `known_spells`.
# `target_data` can be a Creature, CorpseData, Vector2i, or null depending on the spell.
func attempt_cast_spell(spell_to_cast: SpellData, target_data = null) -> bool:
	if not is_instance_valid(spell_to_cast):
		printerr("Necromancer: Invalid spell resource provided for casting.")
		emit_signal("spell_cast_failed", "Unknown Spell", "Invalid spell resource.")
		return false

	if not known_spells.has(spell_to_cast):
		printerr("Necromancer: Attempted to cast an unknown spell '%s'." % spell_to_cast.spell_name)
		emit_signal("spell_cast_failed", spell_to_cast.spell_name, "Spell not known.")
		return false

	# Ensure runtime references are set on the spell (should be done when learned, but good to double check)
	# This is critical because the SpellData resource itself doesn't know its caster context.
	spell_to_cast.set_runtime_references(self, game_manager, battle_grid)

	# Delegate actual casting logic to the spell resource itself
	# The spell's can_cast method will check DE via caster.current_de (passed as argument)
	# The spell's cast method will call caster.spend_de()
	if spell_to_cast.cast(self, target_data): # Pass self as caster_node
		emit_signal("spell_cast_succeeded", spell_to_cast.spell_name)
		return true
	else:
		# The spell's can_cast or cast method should have printed/signaled specific failure reasons.
		# print_debug("Necromancer: Failed to cast spell '%s'." % spell_to_cast.spell_name)
		# Emitting a generic fail signal here, specific reasons might come from the spell itself if needed.
		emit_signal("spell_cast_failed", spell_to_cast.spell_name, "Spell execution failed or conditions not met.")
		return false

# --- UTILITY ---
# Example: How Max DE might scale with level.
# func calculate_max_de_for_level(current_level: int) -> int:
#    return 40 + (current_level * 10) # Base 50 at level 1, +10 per level

# Call this to assign essential references if not done via @onready or scene setup.
func assign_runtime_references(gm: Node, bg: Node):
	game_manager = gm
	battle_grid = bg
	# After setting these, re-initialize runtime references for already known spells
	for spell_res in known_spells:
		spell_res.set_runtime_references(self, game_manager, battle_grid)
