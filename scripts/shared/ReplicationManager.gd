extends Node

# =============================================================================
# ReplicationManager.gd (AUTOLOAD as "Replication")
# =============================================================================
# Central registry for all networked entities.
# Automatically builds snapshots and applies them.
# =============================================================================

# All registered entities (component-based)
var _entities: Dictionary = {}  # net_id -> NetworkedEntity component

# Next ID for server-spawned entities (players use peer_id)
var _next_id: int = 10000


func register_entity(entity: NetworkedEntity) -> void:
	"""Register a NetworkedEntity component for replication."""
	if entity.net_id == 0:
		push_error("Entity registered with net_id 0!")
		return
	
	_entities[entity.net_id] = entity


func unregister_entity(net_id: int) -> void:
	"""Unregister an entity component."""
	_entities.erase(net_id)


func get_entity(net_id: int) -> Node2D:
	"""Get entity node by net_id."""
	var component = _entities.get(net_id)
	if component:
		return component.owner_node
	return null


func get_all_entities() -> Array:
	"""Get all registered entity nodes."""
	var nodes = []
	for component in _entities.values():
		nodes.append(component.owner_node)
	return nodes


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
