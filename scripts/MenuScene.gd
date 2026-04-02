# MenuScene.gd
# Script cho màn hình Menu chính

extends Control

@onready var btn_new_game = $VBox/BtnNewGame
@onready var btn_about    = $VBox/BtnAbout
@onready var btn_exit     = $VBox/BtnExit
@onready var popup_about  = $PopupAbout
@onready var difficulty_option = $VBox/DifficultyOption

func _ready():
	btn_new_game.pressed.connect(_on_new_game)
	btn_about.pressed.connect(_on_about)
	btn_exit.pressed.connect(_on_exit)
	
	if popup_about:
		popup_about.hide()
	
	# Difficulty dropdown
	if difficulty_option:
		difficulty_option.clear()
		difficulty_option.add_item("Easy (Random AI)")
		difficulty_option.add_item("Normal (Heuristic AI)")
		difficulty_option.selected = 1

func _on_new_game():
	var diff = 0  # default easy
	if difficulty_option:
		diff = difficulty_option.selected  # 0=Easy, 1=Normal
	
	var gm = get_node("/root/GameManager")
	gm.ai_difficulty = diff
	
	get_tree().change_scene_to_file("res://scenes/BattleScene.tscn")

func _on_about():
	if popup_about:
		popup_about.show()

func _on_exit():
	get_tree().quit()

func _on_popup_close():
	if popup_about:
		popup_about.hide()
