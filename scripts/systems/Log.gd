extends Node
# =============================================================================
# Log.gd (AUTOLOAD SINGLETON)
# =============================================================================
# Centralized logging system with category-based filtering.
# Usage: Log.network("Connected to server")
#        Log.entity("Spawned player %d" % peer_id)
# =============================================================================

# Log categories
enum Category {
	NETWORK,      # Network events (connect, disconnect, RPC)
	ENTITY,       # Entity spawn/despawn
	SNAPSHOT,     # Snapshot send/receive
	INPUT,        # Input processing
	RECONCILE,    # Client reconciliation
	PHYSICS,      # Physics simulation
	DEBUG,        # General debug info
	WARNING,      # Warnings
	ERROR,        # Errors (always shown)
}

# Global enable/disable per category
var _enabled: Dictionary = {
	Category.NETWORK: false,
	Category.ENTITY: false,
	Category.SNAPSHOT: false,  # Very spammy
	Category.INPUT: false,     # Very spammy
	Category.RECONCILE: true,
	Category.PHYSICS: false,
	Category.DEBUG: true,
	Category.WARNING: true,
	Category.ERROR: true,
}

# Category prefixes for readability
var _prefixes: Dictionary = {
	Category.NETWORK: "[NET]",
	Category.ENTITY: "[ENT]",
	Category.SNAPSHOT: "[SNAP]",
	Category.INPUT: "[INPUT]",
	Category.RECONCILE: "[RECON]",
	Category.PHYSICS: "[PHYS]",
	Category.DEBUG: "[DEBUG]",
	Category.WARNING: "[WARN]",
	Category.ERROR: "[ERROR]",
}

# Generic log function
func _log(category: Category, message: String) -> void:
	if not _enabled.get(category, false):
		return
	
	var prefix = _prefixes.get(category, "[LOG]")
	print(prefix, " ", message)

# Convenience functions
func network(message: String) -> void:
	_log(Category.NETWORK, message)

func entity(message: String) -> void:
	_log(Category.ENTITY, message)

func snapshot(message: String) -> void:
	_log(Category.SNAPSHOT, message)

func input(message: String) -> void:
	_log(Category.INPUT, message)

func reconcile(message: String) -> void:
	_log(Category.RECONCILE, message)

func physics(message: String) -> void:
	_log(Category.PHYSICS, message)

func debug(message: String) -> void:
	_log(Category.DEBUG, message)

func warn(message: String) -> void:
	_log(Category.WARNING, message)

func error(message: String) -> void:
	_log(Category.ERROR, message)

# Enable/disable categories at runtime
func enable(category: Category) -> void:
	_enabled[category] = true

func disable(category: Category) -> void:
	_enabled[category] = false

func set_enabled(category: Category, enabled: bool) -> void:
	_enabled[category] = enabled

func is_enabled(category: Category) -> bool:
	return _enabled.get(category, false)

# Bulk operations
func enable_all() -> void:
	for cat in _enabled:
		_enabled[cat] = true

func disable_all() -> void:
	for cat in _enabled:
		_enabled[cat] = false

func set_verbose(verbose: bool) -> void:
	"""Enable/disable verbose categories (snapshot, input, physics)."""
	_enabled[Category.SNAPSHOT] = verbose
	_enabled[Category.INPUT] = verbose
	_enabled[Category.PHYSICS] = verbose
