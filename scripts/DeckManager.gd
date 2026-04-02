# DeckManager.gd
# Quản lý deck: shuffle, deal, và khởi tạo game

extends Node

# Shuffle deck (Fisher-Yates)
static func shuffle_deck(deck: Array) -> Array:
	var d = deck.duplicate()
	for i in range(d.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = d[i]
		d[i] = d[j]
		d[j] = tmp
	return d

# Khởi tạo game mới
static func setup_game(state: GameState):
	randomize()
	state.round_num = 0
	state.uid_counter = 0
	state.winner = -1
	state.in_combat = false
	state.attackers = []
	state.block_assignments = {}
	
	# Chọn ai đi trước ngẫu nhiên (attack token)
	state.attack_token_owner = randi() % 2
	state.priority_player = state.attack_token_owner
	
	# Setup từng player
	for pid in range(2):
		var p = state.get_player(pid)
		p.nexus_hp = GameState.START_NEXUS_HP
		p.mana = 0
		p.max_mana = 0
		p.spell_mana = 0
		p.attack_declares = 0
		p.total_block_damage = 0
		
		# Deck mặc định + shuffle
		var base_deck = CardData.get_default_deck()
		p.deck = shuffle_deck(base_deck)
		p.hand = []
		p.board = []
	
	# Rút 4 lá đầu cho mỗi bên
	for _i in range(GameState.START_HAND_SIZE):
		for pid in range(2):
			state.draw_card(pid)

# Bắt đầu round mới (gọi từ GameManager)
static func begin_round(state: GameState):
	state.start_new_round()
	# Rút 1 lá mỗi bên
	for pid in range(2):
		state.draw_card(pid)
