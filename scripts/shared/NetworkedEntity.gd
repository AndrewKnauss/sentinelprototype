# =============================================================================
# NetworkedEntity.gd - REFACTORED TO COMPONENT PATTERN
# =============================================================================
# Component that provides networking/replication functionality to entities.
# Entities extend their proper physics body type (CharacterBody2D, StaticBody2D, etc.)
# and hold this as a component for network sync.
# =============================================================================

class_name NetworkedEntity
extends RefCounted

# Unique network ID (peer_id for players, generated for others)
var net_id: int = 0

# Who has authority (1 = server, peer_id = client for prediction)
var authority: int = 1

# Entity type for spawn/despawn messages
var entity_type: String = "unknown"

# Reference to the actual entity node
var owner_node: Node2D = null


func _init(node: Node2D, id: int, auth: int = 1, ent_type: String = "unknown") -> void:
	owner_node = node
	net_id = id
	authority = auth
	entity_type = ent_type
	
	# Register with replication system
	register()


func register() -> void:
	"""Register this entity with the replication manager."""
	if Engine.has_singleton("Replication"):
		return  # Autoload singletons use different access
	
	var replication = owner_node.get_node_or_null("/root/Replication")
	if replication:
		replication.register_entity(self)


func unregister() -> void:
	"""Unregister this entity from the replication manager."""
	var replication = owner_node.get_node_or_null("/root/Replication")
	if replication:
		replication.unregister_entity(net_id)


func get_replicated_state() -> Dictionary:
	"""Get state to replicate. Delegates to owner node if it has the method."""
	if owner_node.has_method("get_replicated_state"):
		return owner_node.get_replicated_state()
	
	# Default: just position and rotation
	return {
		"p": owner_node.global_position,
		"r": owner_node.rotation
	}


func apply_replicated_state(state: Dictionary) -> void:
	"""Apply replicated state. Delegates to owner node if it has the method."""
	if owner_node.has_method("apply_replicated_state"):
		owner_node.apply_replicated_state(state)
	else:
		# Default: apply position and rotation
		owner_node.global_position = state.get("p", owner_node.global_position)
		owner_node.rotation = state.get("r", owner_node.rotation)


func is_authority() -> bool:
	"""Check if this peer has authority over this entity."""
	var net = owner_node.get_node_or_null("/root/Net")
	if not net:
		return false
	
	if net.is_server():
		return authority == 1
	else:
		return authority == net.get_unique_id()
