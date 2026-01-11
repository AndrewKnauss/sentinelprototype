extends Node2D

# =============================================================================
# Bootstrap.gd
# =============================================================================
# LONG DESCRIPTION:
# This is the "entrypoint glue" attached to your main scene.
#
# Its job is to:
#   - Look at command-line arguments (user args after `--`)
#   - Decide whether we run as server or client in THIS process
#   - Instantiate the correct gameplay controller node:
#       ServerMain or ClientMain
#   - Start the network transport via the Net AutoLoad singleton
#
# This file intentionally contains almost NO gameplay logic.
# It's purely startup orchestration.
# =============================================================================

const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 24567

# -----------------------------------------------------------------------------
# _ready()
# -----------------------------------------------------------------------------
# PURPOSE:
# - Read args, choose server/client mode, spawn the correct controller node,
#   and start networking.
#
# WHERE CALLED:
# - Godot calls _ready() once when the node enters the scene tree.
#
# RETURNS:
# - Nothing.
# -----------------------------------------------------------------------------
func _ready() -> void:
	# User args are what you pass after `--`.
	# Example (server):
	#   godot4 --headless --path . -- --server --port=24567
	# Example (client):
	#   godot4 --path . -- --client --host=127.0.0.1 --port=24567
	var args: PackedStringArray = OS.get_cmdline_user_args()

	var host: String = _arg_value("--host=", DEFAULT_HOST)
	var port: int = int(_arg_value("--port=", str(DEFAULT_PORT)))

	if "--server" in args:
		# Add server controller node
		var server_node: Node = (load("res://scripts/server/ServerMain.gd") as Script).new()
		add_child(server_node)

		# Read port from Railway environment or use default
		var port_env = OS.get_environment("PORT")
		var server_port = int(port_env) if port_env else port
		
		# Start transport in server mode
		Net.start_server(server_port)
	else:
		# Add client controller node
		var client_node: Node = (load("res://scripts/client/ClientMain.gd") as Script).new()
		add_child(client_node)

		# Start transport in client mode
		Net.connect_client(host, port)

# -----------------------------------------------------------------------------
# _arg_value(prefix, default_val)
# -----------------------------------------------------------------------------
# PURPOSE:
# - Helper to parse args like "--port=24567" or "--host=127.0.0.1".
#
# WHERE CALLED:
# - _ready()
#
# RETURNS:
# - String: argument value if found, otherwise default_val.
# -----------------------------------------------------------------------------
func _arg_value(prefix: String, default_val: String) -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return default_val
