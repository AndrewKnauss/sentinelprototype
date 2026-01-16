# Username input dialog for client
extends Control
class_name UsernameDialog

signal username_submitted(username: String)

var _input: LineEdit
var _button: Button
var _label: Label
var _error_label: Label


func _ready() -> void:
	# Full-screen background for centering
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Center panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.size = Vector2(400, 200)
	panel.offset_left = -200
	panel.offset_top = -100
	panel.offset_right = 200
	panel.offset_bottom = 100
	add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	
	# Title
	_label = Label.new()
	_label.text = "Enter Username (3-16 characters)"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_label)
	
	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer1)
	
	# Input field
	_input = LineEdit.new()
	_input.placeholder_text = "Username"
	_input.max_length = 16
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.text_submitted.connect(_on_submit)
	vbox.add_child(_input)
	
	# Error label
	_error_label = Label.new()
	_error_label.text = ""
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_color_override("font_color", Color.RED)
	vbox.add_child(_error_label)
	
	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# Submit button
	_button = Button.new()
	_button.text = "Join Game"
	_button.pressed.connect(_on_submit_button)
	vbox.add_child(_button)
	
	# Focus input
	_input.grab_focus()


func _on_submit_button() -> void:
	_on_submit(_input.text)


func _on_submit(text: String) -> void:
	# Client-side validation (server will validate again)
	var error = UsernameValidator.validate(text)
	if not error.is_empty():
		show_error(error)
		return
	
	# Disable input while waiting
	_input.editable = false
	_button.disabled = true
	_label.text = "Connecting..."
	
	username_submitted.emit(text)


func show_error(message: String) -> void:
	_error_label.text = message
	_input.editable = true
	_button.disabled = false


func show_result(success: bool, message: String) -> void:
	if success:
		_label.text = message
		# Dialog will be hidden by ClientMain
	else:
		show_error(message)
		_label.text = "Enter Username (3-16 characters)"
