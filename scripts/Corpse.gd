# ./scripts/Corpse.gd
extends Resource
class_name CorpseData

# This script defines a data container for a corpse.
# It's not a Node, but a Resource, meaning it holds data and can be passed around easily.
# It will be created by the GameManager when a creature dies.

# --- DATA FROM THE ORIGINAL CREATURE ---
# These are populated from the dying creature's get_data_for_corpse_creation() method.
@export var original_creature_name: String = "Unknown"
@export var original_max_health: int = 1
@export var original_attack_power: int = 0
@export var original_was_flying: bool = false
@export var original_had_reach: bool = false
@export var original_faction: Creature.Faction = Creature.Faction.NONE # From Creature.gd's Faction enum

# --- REANIMATION-SPECIFIC DATA ---
# The finality counter of this specific corpse.
# - If the corpse was from a living Human/Alien, this is set to a starting value by GameManager/ReanimateSpell.
# - If the corpse was from an Undead, this is its finality_counter at the time of its death.
@export var finality_counter: int = 0

# The grid position where the creature died. Useful if you want to spawn
# a visual marker or for spells that target corpses in specific locations.
@export var grid_pos_on_death: Vector2i = Vector2i(-1,-1)

# Timestamp or turn number of death, for decay mechanic (corpses removed at end of turn).
@export var turn_of_death: int = 0


# --- METHODS ---
func _init(data: Dictionary = {}):
	if not data.is_empty():
		original_creature_name = data.get("original_creature_name", "Unknown")
		original_max_health = data.get("original_max_health", 1)
		original_attack_power = data.get("original_attack_power", 0)
		original_was_flying = data.get("original_was_flying", false)
		original_had_reach = data.get("original_had_reach", false)
		
		# Ensure faction is correctly assigned from enum value if data provides an int
		var fact_val_from_data = data.get("original_faction", Creature.Faction.NONE) # This will be an int

		# Validate if the integer fact_val_from_data corresponds to a defined member of Creature.Faction
		var is_valid_enum_int = false
		if fact_val_from_data is int: # Ensure it's an integer before checking against enum values
			for known_enum_value in Creature.Faction.values(): # Creature.Faction.values() returns an array like [0, 1, 2, 3]
				if fact_val_from_data == known_enum_value:
					is_valid_enum_int = true
					break
		
		if is_valid_enum_int:
			# If valid, assign the integer. The variable original_faction is typed as Creature.Faction,
			# and GDScript handles this assignment correctly.
			original_faction = fact_val_from_data 
		else:
			# If fact_val_from_data was not an int, or was an int not in Creature.Faction.values()
			original_faction = Creature.Faction.NONE 
			if not (fact_val_from_data is int and fact_val_from_data == Creature.Faction.NONE): # Avoid error if it was already the default valid int
				printerr("CorpseData: Invalid value '%s' (type: %s) provided for Faction enum. Defaulting to NONE." % [str(fact_val_from_data), typeof(fact_val_from_data)])
				

		# For finality:
		# If the dying creature was Undead, its 'current_finality_counter_on_death' is passed.
		# If it was a Human/Alien, the ReanimateSpell or GameManager will assign a starting finality.
		# This constructor will take what's given.
		finality_counter = data.get("finality_counter", 0) 
		
		grid_pos_on_death = data.get("grid_pos_on_death", Vector2i(-1,-1))
		turn_of_death = data.get("turn_of_death", 0) # GameManager should set this

func can_be_reanimated() -> bool:
	# A corpse can be reanimated if its finality counter is greater than 0.
	# Additional game rules could be added here (e.g., specific corpse types).
	return finality_counter > 0

func get_info_for_ui() -> String:
	var reanim_status = "Reanimatable" if can_be_reanimated() else "Spent"
	# Ensure original_faction is an int before using it as an index for .keys()
	var faction_key_index = int(original_faction)
	var faction_name_str = "UNKNOWN_FACTION"
	if faction_key_index >= 0 and faction_key_index < Creature.Faction.keys().size():
		faction_name_str = Creature.Faction.keys()[faction_key_index]

	return "Corpse of %s (Faction: %s, Finality: %d - %s)" % [
		original_creature_name,
		faction_name_str,
		finality_counter,
		reanim_status
	]

# When a corpse is reanimated, the ReanimateSpell will:
# 1. Check can_be_reanimated().
# 2. If true, it will effectively consume this corpse.
# 3. It will then create a new Undead creature instance.
# 4. The new Undead's finality_counter will be this corpse.finality_counter - 1.
#    (This logic is in the spell, not here. This object just holds the data).
