# GameState.gd
# Quản lý toàn bộ trạng thái game Nexus Clash

class_name GameState

const MAX_HAND_SIZE = 8
const MAX_BOARD_SIZE = 5
const MAX_MANA = 10
const MAX_SPELL_MANA = 2
const START_NEXUS_HP = 20
const START_HAND_SIZE = 4

# ----------- Player State -----------
class PlayerState:
	var nexus_hp: int = START_NEXUS_HP
	var mana: int = 0
	var max_mana: int = 0
	var spell_mana: int = 0
	var deck: Array = []        # Array of card_id (int)
	var hand: Array = []        # Array of card_id (int)
	var board: Array = []       # Array of UnitInstance
	
	# Thống kê champion level up
	var attack_declares: int = 0     # Kael level up condition
	var total_block_damage: int = 0  # Lyra level up condition

# ----------- Game State -----------
var players: Array = []  # [PlayerState x2]  0=Player, 1=AI
var round_num: int = 0
var priority_player: int = 0       # ai đang hành động
var attack_token_owner: int = 0    # ai có attack token
var consecutive_passes: int = 0    # đếm pass liên tiếp để kết thúc round
var uid_counter: int = 0           # tạo uid duy nhất cho unit

# Trạng thái combat trong round
var attackers: Array = []          # uid các unit đang attack
var block_assignments: Dictionary = {}  # {attacker_uid: blocker_uid}
var in_combat: bool = false

# Giai đoạn game
enum Phase { MENU, MULLIGAN, PLAYER_TURN, AI_TURN, COMBAT_DECLARE, COMBAT_BLOCK, COMBAT_RESOLVE, ROUND_END, GAME_OVER }
var phase: int = Phase.MENU
var winner: int = -1  # -1 = chưa xong, 0 = Player, 1 = AI

# --------------------------------------------------------
func _init():
	players = [PlayerState.new(), PlayerState.new()]

# Tạo uid mới
func next_uid() -> int:
	uid_counter += 1
	return uid_counter

# Lấy PlayerState
func get_player(pid: int) -> PlayerState:
	return players[pid]

# Lấy opponent id
static func opponent(pid: int) -> int:
	return 1 - pid

# ---- Mana ----
func spend_mana(pid: int, amount: int):
	var p = get_player(pid)
	if amount <= p.mana:
		p.mana -= amount
	else:
		var from_spell = amount - p.mana
		p.mana = 0
		p.spell_mana -= from_spell

# Kiểm tra đủ mana (thường hoặc spell)
func can_afford(pid: int, cost: int) -> bool:
	var p = get_player(pid)
	return p.mana >= cost

# Kiểm tra đủ mana kể cả spell mana (cho spell)
func can_afford_with_spell_mana(pid: int, cost: int) -> bool:
	var p = get_player(pid)
	return p.mana + p.spell_mana >= cost

# ---- Board ----
func board_full(pid: int) -> bool:
	return get_player(pid).board.size() >= MAX_BOARD_SIZE

func get_board(pid: int) -> Array:
	return get_player(pid).board

func add_to_board(pid: int, unit: UnitInstance):
	get_player(pid).board.append(unit)

func remove_dead_units():
	for p in players:
		var alive = []
		for u in p.board:
			if u.is_alive():
				alive.append(u)
		p.board = alive

func get_unit_by_uid(uid: int) -> UnitInstance:
	for p in players:
		for u in p.board:
			if u.uid == uid:
				return u
	return null

# ---- Round Management ----
func start_new_round():
	round_num += 1
	for pid in range(2):
		var p = get_player(pid)
		# Tăng max mana
		p.max_mana = min(p.max_mana + 1, MAX_MANA)
		# Refill mana, lưu dư vào spell mana
		var leftover = p.mana  # mana còn lại từ round trước
		p.spell_mana = min(p.spell_mana + leftover, MAX_SPELL_MANA)
		p.mana = p.max_mana
		# Reset temp buff của unit
		for u in p.board:
			u.reset_temp_buffs()
			u.exhausted = false
	# Đổi attack token
	if round_num > 1:
		attack_token_owner = opponent(attack_token_owner)
	consecutive_passes = 0

# ---- Hand / Deck ----
func draw_card(pid: int) -> bool:
	var p = get_player(pid)
	if p.deck.is_empty():
		return false
	if p.hand.size() >= MAX_HAND_SIZE:
		# Burn card
		p.deck.remove_at(0)
		return false
	var card_id = p.deck.pop_front()
	p.hand.append(card_id)
	return true

# ---- Win condition ----
func check_win_condition():
	for pid in range(2):
		if get_player(pid).nexus_hp <= 0:
			winner = opponent(pid)
			phase = Phase.GAME_OVER
			return
	winner = -1

# ---- Summon unit lên sân ----
func summon_unit(pid: int, card: Dictionary) -> UnitInstance:
	var unit = UnitInstance.from_card(card, pid, next_uid())
	add_to_board(pid, unit)
	return unit

# Debug dump
func debug_state() -> String:
	var s = "=== Round %d | Token: P%d | Phase: %d ===\n" % [round_num, attack_token_owner, phase]
	for pid in range(2):
		var p = get_player(pid)
		var label = "Player" if pid == 0 else "AI"
		s += "[%s] Nexus:%d Mana:%d/%d SpellMana:%d Hand:%d Deck:%d\n" % [
			label, p.nexus_hp, p.mana, p.max_mana, p.spell_mana, p.hand.size(), p.deck.size()
		]
		s += "  Board: "
		for u in p.board:
			s += u.to_string() + " | "
		s += "\n"
	return s
