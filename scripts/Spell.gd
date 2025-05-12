extends Resource

class_name Spell

enum SpellType {
	REANIMATE,
	SOUL_DRAIN,
}

@export var cost_by_level: Array[int] = []

func get_cost(level: int) -> int:
	var idx = clamp(level - 1, 0, cost_by_level.size() - 1)
	return cost_by_level[idx]
