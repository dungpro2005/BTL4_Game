# HOW TO RUN - Nexus Clash (Godot 4)

## Yêu cầu
- **Godot Engine 4.x** (tải miễn phí tại https://godotengine.org/)
- Không cần cài thêm gì khác

---

## Cách import project vào Godot

### Bước 1: Tải Godot 4
1. Vào https://godotengine.org/download
2. Tải bản **Godot Engine 4.x** (Standard) cho Linux
3. Giải nén → chạy file `Godot_v4.x-stable_linux.x86_64`

### Bước 2: Import Project
1. Mở Godot → màn hình **Project Manager**
2. Click **"Import"** (hoặc "Scan")
3. Chọn thư mục: `/home/dungpto3103/Downloads/BTL_Game/`
4. Chọn file `project.godot` → click **"Import & Edit"**

### Bước 3: Chạy game
- Nhấn **F5** hoặc click nút **▶ Play** (góc trên phải)
- Godot sẽ tự mở màn hình Menu

---

## Cấu trúc thư mục

```
BTL_Game/
├── project.godot          ← File config Godot (quan trọng!)
├── scripts/
│   ├── CardData.gd        ← Định nghĩa 20 lá bài
│   ├── UnitInstance.gd    ← Unit trên sân
│   ├── GameState.gd       ← Toàn bộ trạng thái game
│   ├── DeckManager.gd     ← Shuffle deck, deal bài
│   ├── CombatManager.gd   ← Xử lý combat & spell
│   ├── AIPlayer.gd        ← AI (Easy random + Normal heuristic)
│   ├── GameManager.gd     ← AutoLoad: điều phối game flow
│   ├── BattleScene.gd     ← UI logic màn hình chiến đấu
│   └── MenuScene.gd       ← UI logic màn hình menu
├── scenes/
│   ├── MenuScene.tscn     ← Scene menu chính
│   └── BattleScene.tscn   ← Scene chiến đấu chính
└── yeucau.txt             ← File yêu cầu gốc
```

---

## Cách chơi

| Hành động | Cách làm |
|-----------|----------|
| Triệu hồi unit | Click vào lá bài trong tay (màu xanh = đủ mana) |
| Dùng spell | Click lá spell → click target (unit địch hoặc Nexus) |
| Tấn công | Click **⚔ Declare Attack** → click unit của mình → click **✔ Confirm** |
| Block (khi AI attack) | Click unit của mình để block |
| Kết thúc lượt | Click **⏩ End Turn / Pass** |
| Thắng | Giảm Nexus địch về 0 |

---

## Luật game tóm tắt

- **Nexus HP**: 20 mỗi bên
- **Deck**: 20 lá (10 Unit + 6 Spell + 4 Champion)
- **Hand đầu**: 4 lá, mỗi round rút thêm 1 (tối đa 8)
- **Mana**: bắt đầu 1, tăng 1 mỗi round (tối đa 10)
- **Spell Mana**: mana thừa từ round trước (tối đa 2)
- **Board**: tối đa 5 unit mỗi bên
- **Attack Token**: đổi bên sau mỗi round
- **Summon Sickness**: unit mới không attack ngay

### Keyword
| Keyword | Hiệu ứng |
|---------|----------|
| **Guard** | Phải bị block trước |
| **Quick Strike** | Đánh trước trong combat |
| **Overwhelm** | Damage dư xuyên vào Nexus |
| **Shield** | Hút 1 lần damage đầu tiên |

### Champion Level Up
| Champion | Điều kiện | Sau level up |
|----------|-----------|--------------|
| **Blade Master Kael** (4/4, QS) | Declare attack 2 lần | 4/5, mỗi khi attack +1 ATK |
| **Aegis Captain Lyra** (3/5, Guard) | Block/nhận 5 damage | 4/6, cho Guard ally +1 HP |

---

## AI

| Độ khó | Chiến lược |
|--------|------------|
| **Easy** | Chọn action ngẫu nhiên trong danh sách hợp lệ |
| **Normal** | Heuristic rule-based: ưu tiên lethal → trade → summon → pass |

### Heuristic score (Normal AI):
```
score = (AI_Nexus - Player_Nexus) * 50
	  + (AI_board_attack - Player_board_attack) * 8
	  + (AI_board_health - Player_board_health) * 6
	  + (AI_hand - Player_hand) * 4
	  + (AI_mana + AI_spell_mana) * 2
	  + (leveled_champion_AI - leveled_champion_Player) * 20
	  + (guard_AI - guard_Player) * 5
```

---

## Lưu ý khi nhập vào Godot

> Godot 4 có thể báo lỗi nếu AutoLoad `GameManager` không tìm thấy scene.
> Hãy vào **Project → Project Settings → AutoLoad** và xác nhận:
> - Name: `GameManager`
> - Path: `res://scripts/GameManager.gd`
> - Enable: ✓

Nếu gặp lỗi về `@onready` node path, hãy mở `BattleScene.tscn` trong Godot Editor
và điều chỉnh node paths trong `BattleScene.gd` cho khớp với hierarchy thực tế.
