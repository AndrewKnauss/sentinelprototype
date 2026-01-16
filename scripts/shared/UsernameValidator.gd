# Username validation utilities
class_name UsernameValidator extends RefCounted

const MIN_LENGTH = 3
const MAX_LENGTH = 16
const RESERVED_NAMES = ["admin", "server", "moderator", "system", "bot"]

static func validate(username: String) -> String:
	"""
	Validates a username.
	Returns empty string if valid, error message if invalid.
	"""
	if username.is_empty():
		return "Username cannot be empty"
	
	if username.length() < MIN_LENGTH:
		return "Username must be at least %d characters" % MIN_LENGTH
	
	if username.length() > MAX_LENGTH:
		return "Username must be at most %d characters" % MAX_LENGTH
	
	# Check for valid characters (alphanumeric + underscore)
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	if not regex.search(username):
		return "Username can only contain letters, numbers, and underscores"
	
	# Check reserved names
	if username.to_lower() in RESERVED_NAMES:
		return "Username is reserved"
	
	return ""  # Valid

static func sanitize(username: String) -> String:
	"""
	Sanitizes username to lowercase for storage.
	"""
	return username.to_lower().strip_edges()
