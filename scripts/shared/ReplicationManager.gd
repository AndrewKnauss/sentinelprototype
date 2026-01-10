extends Node

# =============================================================================
# ReplicationManager.gd (AUTOLOAD as "Replication")
# =============================================================================
# Central registry for all networked entities.
# Automatically builds snapshots and applies them.
# =============================================================================

# All registered entities
var _entities: Dictionary = {}  # net_id -> NetworkedEntity

# Next ID for server-spawned entities (players use peer_id)
var _next_id: int = 10000


func register(entity: NetworkedEntity) -> void:
	"""Register an entity for replication."""
	if entity.net_id == 0:
		push_error("Entity registered with net_id 0!")
		return
	
	_entities[entity.net_id] = entity


func unregister(net_id: int) -> void:
	"""Unregister an entity."""
	_entities.erase(net_id)


func get_entity(net_id: int) -> NetworkedEntity:
	"""Get entity by net_id."""
	return _entities.get(net_id)


func get_all_entities() -> Array:
	"""Get all registered entities."""
	return _entities.values()


func generate_id() -> int:
	"""Generate unique ID for server-spawned entities."""
	var id = _next_id
	_next_id += 1
	return id


# SERVER: Build snapshot of all entities
func build_snapshot() -> Dictionary:
	var states = {}
	for id in _entities:
		var entity = _entities[id]
		# Only replicate server-authoritative entities
		if entity.authority == 1:
			states[id] = entity.get_replicated_state()
	return states


# CLIENT: Apply snapshot to entities
func apply_snapshot(states: Dictionary) -> void:
	for id_str in states:
		var id = int(id_str)
		if _entities.has(id):
			var entity = _entities[id]
			# Don't overwrite client-predicted entities
			if not entity.is_authority():
				entity.apply_replicated_state(states[id_str])
