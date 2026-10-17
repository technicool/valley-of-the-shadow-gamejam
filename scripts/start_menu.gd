extends Control

const GAME_SCENE_PATH := "res://scenes/main.tscn"
const EDITOR_SCENE_PATH := "res://scenes/editor.tscn"

@onready var start_button: Button = $Menu/Buttons/StartButton
@onready var editor_button: Button = $Menu/Buttons/EditorButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	editor_button.pressed.connect(_on_editor_pressed)
	start_button.grab_focus()


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_editor_pressed() -> void:
	get_tree().change_scene_to_file(EDITOR_SCENE_PATH)
