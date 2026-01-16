extends Node2D
class_name NetworkedEntity

# =============================================================================
# NetworkedEntity.gd
# =============================================================================
# Base class for all replicated entities (players, enemies, bullets, walls).
# Handles automatic registration with ReplicationManager.
# =============================================================================

# Unique network ID (peer_id for players, generated for others)
var net_id: int = 0

# Who has authority (1 = server, peer_id = client for prediction)
var authority: int = 1

# Entity type for spawn/despawn messages
var entity_type: String = "unknown"


func _ready() -> void:
	# Register with replication system
	if has_node("/root/Replication"):
		get_node("/root/Replication").register(self)


func _exit_tree() -> void:
	# Unregister when removed
	if has_node("/root/Replication"):
		get_node("/root/Replication").unregister(net_id)


# Override in subclasses to define what gets replicated
func get_replicated_state() -> Dictionary:
	return {
		"p": global_position,
		"r": rotation
	}


# Override in subclasses to apply replicated state
func apply_replicated_state(state: Dictionary) -> void:
	global_position = state.get("p", global_position)
	rotation = state.get("r", rotation)


# Check if this peer has authority over this entity
func is_authority() -> bool:
	if not has_node("/root/Net"):
		return false
	
	var net = get_node("/root/Net")
	if net.is_server():
		return authority == 1
	else:
		return authority == net.get_unique_id()
