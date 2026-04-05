# CardData.gd
# Định nghĩa tất cả 20 lá bài cho game Nexus Clash
# Mỗi lá bài là một Dictionary với các trường:
#   id, name, type, cost, attack, health, keyword, spell_type, spell_value, spell_target, effect

extends Node

enum CardType { UNIT, SPELL, CHAMPION }
enum Keyword { NONE, GUARD, QUICK_STRIKE, OVERWHELM, SHIELD }
enum SpellType { NONE, DAMAGE, BUFF_ATK, BUFF_STAT, SHIELD_ALLY, HEAL_NEXUS, DAMAGE_NEXUS, COMPLETE }

# Trả về toàn bộ 20 lá bài dưới dạng mảng Dictionary
func get_all_cards() -> Array:
	return [
		# ===== A. UNIT CARDS (10 lá) =====
		{
			"id": 1,
			"name": "Vanguard Squire",
			"type": CardType.UNIT,
			"cost": 1,
			"attack": 1,
			"health": 2,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Unit mở đầu"
		},
		{
			"id": 2,
			"name": "Iron Recruit",
			"type": CardType.UNIT,
			"cost": 2,
			"attack": 2,
			"health": 2,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Unit cơ bản"
		},
		{
			"id": 3,
			"name": "Shield Bearer",
			"type": CardType.UNIT,
			"cost": 2,
			"attack": 1,
			"health": 4,
			"keyword": Keyword.GUARD,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Tanker thủ nhà"
		},
		{
			"id": 4,
			"name": "Swift Duelist",
			"type": CardType.UNIT,
			"cost": 3,
			"attack": 3,
			"health": 2,
			"keyword": Keyword.QUICK_STRIKE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Combat lời"
		},
		{
			"id": 5,
			"name": "War Hound",
			"type": CardType.UNIT,
			"cost": 3,
			"attack": 3,
			"health": 3,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Mid-game ổn định"
		},
		{
			"id": 6,
			"name": "Arc Archer",
			"type": CardType.UNIT,
			"cost": 3,
			"attack": 2,
			"health": 3,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "on_summon_damage_1_enemy",
			"description": "Khi summon: gây 1 damage lên enemy unit ngẫu nhiên"
		},
		{
			"id": 7,
			"name": "Stone Guardian",
			"type": CardType.UNIT,
			"cost": 4,
			"attack": 2,
			"health": 5,
			"keyword": Keyword.GUARD,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Chặn late game"
		},
		{
			"id": 8,
			"name": "Rampage Brute",
			"type": CardType.UNIT,
			"cost": 4,
			"attack": 5,
			"health": 3,
			"keyword": Keyword.OVERWHELM,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "none",
			"description": "Ép máu Nexus"
		},
		{
			"id": 9,
			"name": "Battle Priest",
			"type": CardType.UNIT,
			"cost": 4,
			"attack": 2,
			"health": 4,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "on_summon_heal_nexus_2",
			"description": "Khi summon: hồi 2 HP cho Nexus đồng minh"
		},
		{
			"id": 10,
			"name": "Skybreaker",
			"type": CardType.UNIT,
			"cost": 5,
			"attack": 4,
			"health": 4,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "on_attack_gain_1_atk",
			"description": "Khi attack: nhận +1 attack trong turn đó"
		},
		# ===== B. SPELL CARDS (6 lá) =====
		{
			"id": 11,
			"name": "Fire Bolt",
			"type": CardType.SPELL,
			"cost": 2,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.DAMAGE,
			"spell_value": 2,
			"effect": "damage_unit_or_nexus",
			"description": "Gây 2 damage lên 1 target unit hoặc Nexus"
		},
		{
			"id": 12,
			"name": "Battle Cry",
			"type": CardType.SPELL,
			"cost": 2,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.BUFF_ATK,
			"spell_value": 2,
			"effect": "buff_ally_atk_2_this_round",
			"description": "1 ally unit nhận +2 attack trong round này"
		},
		{
			"id": 13,
			"name": "Barrier Sigil",
			"type": CardType.SPELL,
			"cost": 2,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.SHIELD_ALLY,
			"spell_value": 0,
			"effect": "give_shield_to_ally",
			"description": "Cho 1 ally unit keyword Shield"
		},
		{
			"id": 14,
			"name": "Tactical Shot",
			"type": CardType.SPELL,
			"cost": 3,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.DAMAGE,
			"spell_value": 3,
			"effect": "damage_damaged_enemy_unit",
			"description": "Gây 3 damage lên 1 enemy unit đã bị damage"
		},
		{
			"id": 15,
			"name": "Reinforce",
			"type": CardType.SPELL,
			"cost": 3,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.BUFF_STAT,
			"spell_value": 0,
			"effect": "buff_ally_1_atk_2_hp_permanent",
			"description": "Cho 1 ally unit +1 attack / +2 health vĩnh viễn"
		},
		{
			"id": 16,
			"name": "Nexus Surge",
			"type": CardType.SPELL,
			"cost": 4,
			"attack": 0,
			"health": 0,
			"keyword": Keyword.NONE,
			"spell_type": SpellType.COMPLETE,
			"spell_value": 3,
			"effect": "heal_own_nexus_or_damage_enemy_nexus",
			"description": "Hồi 3 HP cho Nexus mình hoặc gây 3 damage Nexus địch"
		},
		# ===== C. CHAMPION CARDS (4 lá) =====
		{
			"id": 17,
			"name": "Blade Master Kael",
			"type": CardType.CHAMPION,
			"cost": 4,
			"attack": 3,
			"health": 4,
			"keyword": Keyword.QUICK_STRIKE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "level_up_after_2_attacks",
			"level_up_atk": 4,
			"level_up_hp": 5,
			"level_up_effect": "on_attack_gain_1_atk",
			"level_up_condition": "declare_attack_2_times",
			"description": "Level up sau 2 lần declare attack. Sau level up: 4/5, mỗi khi attack nhận +1 atk"
		},
		{
			"id": 18,
			"name": "Blade Master Kael",
			"type": CardType.CHAMPION,
			"cost": 4,
			"attack": 3,
			"health": 4,
			"keyword": Keyword.QUICK_STRIKE,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "level_up_after_2_attacks",
			"level_up_atk": 4,
			"level_up_hp": 5,
			"level_up_effect": "on_attack_gain_1_atk",
			"level_up_condition": "declare_attack_2_times",
			"description": "Level up sau 2 lần declare attack. Sau level up: 4/5, mỗi khi attack nhận +1 atk"
		},
		{
			"id": 19,
			"name": "Aegis Captain Lyra",
			"type": CardType.CHAMPION,
			"cost": 5,
			"attack": 3,
			"health": 5,
			"keyword": Keyword.GUARD,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "level_up_after_5_block_damage",
			"level_up_atk": 4,
			"level_up_hp": 6,
			"level_up_effect": "on_levelup_buff_guard_allies_1hp",
			"level_up_condition": "blocked_or_received_5_damage",
			"description": "Level up sau khi block/nhận 5 damage. Sau level up: 4/6, cho Guard ally +1 HP"
		},
		{
			"id": 20,
			"name": "Aegis Captain Lyra",
			"type": CardType.CHAMPION,
			"cost": 5,
			"attack": 3,
			"health": 5,
			"keyword": Keyword.GUARD,
			"spell_type": SpellType.NONE,
			"spell_value": 0,
			"effect": "level_up_after_5_block_damage",
			"level_up_atk": 4,
			"level_up_hp": 6,
			"level_up_effect": "on_levelup_buff_guard_allies_1hp",
			"level_up_condition": "blocked_or_received_5_damage",
			"description": "Level up sau khi block/nhận 5 damage. Sau level up: 4/6, cho Guard ally +1 HP"
		},
	]

# Lấy lá bài theo id
func get_card(id: int) -> Dictionary:
	for card in get_all_cards():
		if card["id"] == id:
			return card
	return {}

# Tạo deck mặc định (danh sách 20 card id)
func get_default_deck() -> Array:
	return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
			11, 12, 13, 14, 15, 16,
			17, 18, 19, 20]

# Tên keyword để hiển thị
func keyword_name(kw: int) -> String:
	match kw:
		Keyword.GUARD: return "Guard"
		Keyword.QUICK_STRIKE: return "Quick Strike"
		Keyword.OVERWHELM: return "Overwhelm"
		Keyword.SHIELD: return "Shield"
	return ""

# Tên type để hiển thị
func type_name(t: int) -> String:
	match t:
		CardType.UNIT: return "Unit"
		CardType.SPELL: return "Spell"
		CardType.CHAMPION: return "Champion"
	return "Unknown"
