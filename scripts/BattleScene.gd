# BattleScene.gd
# Script cho màn hình chiến đấu chính của Nexus Clash
# Kết nối với GameManager để nhận state và player input

extends Control

# ── Node refs (sẽ được gán trong .tscn) ──────────────────────
@onready var lbl_round      = $VBox/Header/LblRound
@onready var lbl_ai_nexus   = $VBox/Header/LblAINexus
@onready var lbl_player_nexus = $VBox/Header/LblPlayerNexus
@onready var lbl_ai_mana    = $VBox/Header/LblAIMana
@onready var lbl_player_mana = $VBox/Footer/LblPlayerMana
@onready var lbl_log        = $VBox/LogBox/LblLog
@onready var ai_board_hbox  = $VBox/BoardArea/AIBoard
@onready var player_board_hbox = $VBox/BoardArea/PlayerBoard
@onready var hand_hbox      = $VBox/Footer/HandArea
@onready var btn_end_turn   = $VBox/Footer/BtnEndTurn
@onready var btn_attack     = $VBox/Footer/BtnAttack
@onready var popup_gameover = $PopupGameOver
@onready var lbl_gameover   = $PopupGameOver/LblResult

# ── Internal state ────────────────────────────────────────────
var selected_hand_index: int = -1
var selected_hand_card_id: int = -1
var expecting_target: bool = false   # True khi spell cần chọn target
var pending_spell_index: int = -1

var attack_selecting: bool = false   # True khi player đang chọn unit attack
var selected_attackers: Array = []

var block_mode: bool = false         # True khi player đang chọn block
var block_assignments: Dictionary = {}
var current_attacker_uid: int = -1   # uid đang cần assign blocker

var gm: Node  # GameManager singleton ref

# ── Colors ───────────────────────────────────────────────────
const COLOR_SELECTED   = Color(1, 0.9, 0.2)
const COLOR_NORMAL     = Color(1, 1, 1)
const COLOR_ENEMY      = Color(1, 0.4, 0.4)
const COLOR_ALLY       = Color(0.4, 0.8, 1)
const COLOR_EXHAUSTED  = Color(0.5, 0.5, 0.5)

# ─────────────────────────────────────────────────────────────
func _ready():
	gm = get_node("/root/GameManager")
	gm.state_updated.connect(_on_state_updated)
	gm.log_message.connect(_on_log)
	gm.game_over.connect(_on_game_over)
	gm.combat_started.connect(_on_combat_started)
	
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	btn_attack.pressed.connect(_on_attack_pressed)
	
	popup_gameover.hide()
	await get_tree().process_frame
	gm.start_new_game()

# ── State Update ─────────────────────────────────────────────
func _on_state_updated(state: GameState):
	_refresh_ui(state)

func _refresh_ui(state: GameState):
	if state == null: return
	var gm_state = state
	
	# Header info
	lbl_round.text = "Round %d" % gm_state.round_num
	var p0 = gm_state.get_player(0)
	var p1 = gm_state.get_player(1)
	lbl_player_nexus.text = "❤ %d" % p0.nexus_hp
	lbl_ai_nexus.text    = "❤ %d" % p1.nexus_hp
	lbl_player_mana.text = "💧 %d/%d  ✨%d" % [p0.mana, p0.max_mana, p0.spell_mana]
	lbl_ai_mana.text     = "AI 💧 %d/%d" % [p1.mana, p1.max_mana]
	
	# Board
	_rebuild_board(ai_board_hbox, gm_state, 1)
	_rebuild_board(player_board_hbox, gm_state, 0)
	
	# Hand
	_rebuild_hand(hand_hbox, gm_state)
	
	# Buttons
	var is_player_turn = (gm_state.phase == GameState.Phase.PLAYER_TURN)
	btn_end_turn.disabled = not is_player_turn or block_mode or attack_selecting
	btn_attack.disabled = (not is_player_turn) or (gm_state.attack_token_owner != 0) or attack_selecting
	btn_attack.text = "⚔ Declare Attack" if not attack_selecting else "✔ Confirm Attack"

func _rebuild_board(hbox: HBoxContainer, state: GameState, pid: int):
	for child in hbox.get_children():
		child.queue_free()
	
	for unit in state.get_board(pid):
		var card_ui = _make_unit_card(unit, pid)
		hbox.add_child(card_ui)
	
	# Empty slots
	var empty = GameState.MAX_BOARD_SIZE - state.get_board(pid).size()
	for _i in range(empty):
		var slot = _make_empty_slot()
		hbox.add_child(slot)

func _rebuild_hand(hbox: HBoxContainer, state: GameState):
	for child in hbox.get_children():
		child.queue_free()
	
	var p = state.get_player(0)
	for i in range(p.hand.size()):
		var card_id = p.hand[i]
		var card = CardData.get_card(card_id)
		var card_ui = _make_hand_card(card, i, p.mana + p.spell_mana)
		hbox.add_child(card_ui)

# ── Unit card UI ─────────────────────────────────────────────
func _make_unit_card(unit: UnitInstance, pid: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 110)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = ("★ " if unit.leveled_up else "") + unit.unit_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)
	
	var stat_lbl = Label.new()
	stat_lbl.text = "%d / %d" % [unit.get_effective_attack(), unit.health]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.add_theme_font_size_override("font_size", 14)
	vbox.add_child(stat_lbl)
	
	var kw_lbl = Label.new()
	var kw = CardData.keyword_name(unit.keyword)
	kw_lbl.text = kw + (" 🛡" if unit.has_shield else "")
	kw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kw_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(kw_lbl)
	
	# Color
	var style = StyleBoxFlat.new()
	if unit.exhausted:
		style.bg_color = Color(0.3, 0.3, 0.3, 0.9)
	elif pid == 0:
		style.bg_color = Color(0.1, 0.3, 0.5, 0.9)
	else:
		style.bg_color = Color(0.5, 0.1, 0.1, 0.9)
	style.border_width_all = 2
	style.border_color = Color(1, 0.8, 0.2) if unit.is_champion else Color(0.6, 0.6, 0.6)
	style.corner_radius_all = 6
	panel.add_theme_stylebox_override("panel", style)
	
	# Click handler
	var btn = Button.new()
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_unit_clicked.bind(unit.uid, pid))
	panel.add_child(btn)
	
	return panel

func _make_hand_card(card: Dictionary, index: int, available_mana: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(90, 120)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	# Cost
	var cost_lbl = Label.new()
	cost_lbl.text = "💧%d" % card.get("cost", 0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)
	
	# Name
	var name_lbl = Label.new()
	name_lbl.text = card.get("name", "?")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_lbl)
	
	# Type / stat
	var t = card.get("type", 0)
	var stat_lbl = Label.new()
	if t == CardData.CardType.SPELL:
		stat_lbl.text = "[Spell]"
	else:
		stat_lbl.text = "%d/%d" % [card.get("attack", 0), card.get("health", 0)]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stat_lbl)
	
	# Keyword
	var kw_lbl = Label.new()
	kw_lbl.text = CardData.keyword_name(card.get("keyword", 0))
	kw_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kw_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(kw_lbl)
	
	var can_afford = available_mana >= card.get("cost", 99)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.4, 0.15, 0.95) if can_afford else Color(0.2, 0.2, 0.2, 0.8)
	if index == selected_hand_index:
		style.bg_color = Color(0.5, 0.4, 0.0, 0.95)
		style.border_width_all = 3
		style.border_color = COLOR_SELECTED
	style.corner_radius_all = 8
	panel.add_theme_stylebox_override("panel", style)
	
	if can_afford:
		var btn = Button.new()
		btn.flat = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_hand_card_clicked.bind(index, card))
		panel.add_child(btn)
	
	return panel

func _make_empty_slot() -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 110)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.5)
	style.border_width_all = 1
	style.border_color = Color(0.3, 0.3, 0.3)
	style.corner_radius_all = 6
	panel.add_theme_stylebox_override("panel", style)
	return panel

# ── Input Handlers ───────────────────────────────────────────
func _on_hand_card_clicked(index: int, card: Dictionary):
	if gm.state.phase != GameState.Phase.PLAYER_TURN:
		return
	var t = card.get("type", 0)
	
	if t in [CardData.CardType.UNIT, CardData.CardType.CHAMPION]:
		# Summon trực tiếp
		gm.player_summon(index)
		selected_hand_index = -1
	elif t == CardData.CardType.SPELL:
		if selected_hand_index == index:
			# Deselect
			selected_hand_index = -1
			expecting_target = false
		else:
			selected_hand_index = index
			pending_spell_index = index
			var effect = card.get("effect", "")
			# Spell không cần target → cast luôn
			if effect in ["heal_own_nexus_or_damage_enemy_nexus"]:
				# Dual-target: chọn heal nexus mình
				gm.player_cast_spell(index, 0)
				selected_hand_index = -1
			else:
				expecting_target = true
				_on_log("Chọn target cho %s..." % card["name"])
		_refresh_ui(gm.state)

func _on_unit_clicked(uid: int, pid: int):
	var state = gm.state
	
	# Block mode
	if block_mode:
		if pid == 0 and current_attacker_uid != -1:
			block_assignments[current_attacker_uid] = uid
			_on_log("Block assigned!")
			current_attacker_uid = -1
			_check_block_complete(state)
		return
	
	# Target mode (spell)
	if expecting_target and selected_hand_index != -1:
		if pid == 1:  # Chỉ target enemy
			gm.player_cast_spell(selected_hand_index, uid)
			selected_hand_index = -1
			expecting_target = false
			pending_spell_index = -1
		return
	
	# Attack select mode
	if attack_selecting and pid == 0:
		var unit = state.get_unit_by_uid(uid)
		if unit and not unit.exhausted:
			if uid in selected_attackers:
				selected_attackers.erase(uid)
			else:
				selected_attackers.append(uid)
			_on_log("Đã chọn %d unit tấn công" % selected_attackers.size())
			_refresh_ui(state)

func _on_attack_pressed():
	if attack_selecting:
		# Confirm attack
		if not selected_attackers.is_empty():
			attack_selecting = false
			gm.player_declare_attack(selected_attackers)
			selected_attackers = []
		else:
			attack_selecting = false
		_refresh_ui(gm.state)
	else:
		attack_selecting = true
		selected_attackers = []
		_on_log("Chọn unit để tấn công (click vào unit của bạn), rồi bấm Confirm Attack")
		_refresh_ui(gm.state)

func _on_end_turn_pressed():
	expecting_target = false
	attack_selecting = false
	selected_hand_index = -1
	selected_attackers = []
	gm.player_pass()

func _on_combat_started(attackers: Array):
	if not gm.waiting_for_player_block:
		return
	block_mode = true
	block_assignments = {}
	_on_log("AI attack! Chọn unit để block (click unit bạn, sau đó click attacker của AI)")
	_refresh_ui(gm.state)

func _on_unit_clicked_attacker(atk_uid: int):
	if block_mode:
		current_attacker_uid = atk_uid
		_on_log("Chọn unit của bạn để block attacker này...")

func _check_block_complete(state: GameState):
	_on_log("Block xong! Nhấn 'Confirm Block' hoặc đợi auto")
	block_mode = false
	gm.player_submit_blocks(block_assignments)
	block_assignments = {}
	_refresh_ui(state)

# ── Log ─────────────────────────────────────────────────────
func _on_log(msg: String):
	if lbl_log:
		lbl_log.text = msg

# ── Game Over ────────────────────────────────────────────────
func _on_game_over(winner_id: int):
	popup_gameover.show()
	if winner_id == 0:
		lbl_gameover.text = "🎉 BẠN THẮNG! 🎉\nNexus địch đã bị phá hủy!"
		lbl_gameover.add_theme_color_override("font_color", Color(0.2, 1, 0.2))
	else:
		lbl_gameover.text = "💀 BẠN THUA! 💀\nNexus của bạn đã bị phá hủy!"
		lbl_gameover.add_theme_color_override("font_color", Color(1, 0.2, 0.2))

func _on_btn_menu_pressed():
	get_tree().change_scene_to_file("res://scenes/MenuScene.tscn")

func _on_btn_restart_pressed():
	get_tree().reload_current_scene()
