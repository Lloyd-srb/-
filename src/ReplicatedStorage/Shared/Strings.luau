--!strict
--[[
	Strings — source of every player-facing text (English + Thai).

	build/BuildLocalization.luau turns this into the LocalizationTable used in
	game; code only ever refers to the keys. The language follows the player's
	Roblox locale automatically (GDD §1) — there is no language setting.

	`{name}` / `{seconds:int}` are LocalizationTable format parameters.
	Texts quoted in the GDD are used verbatim in English.
	Entries marked DRAFT were written by the developer (the GDD only describes
	them) and are waiting for the owner's approval.
]]

export type Entry = { en: string, th: string }

local Strings: { [string]: Entry } = {
	-- Phase banners (GDD §6)
	["Phase.RoleSelect"] = { en = "Choose 3 roles", th = "เลือก 3 บทบาท" },
	["Phase.Day"] = { en = "Day {day:int}", th = "วันที่ {day:int}" },
	["Phase.Night"] = { en = "Night {night:int}", th = "คืนที่ {night:int}" },
	["Phase.FullMoon"] = { en = "Full moon in {seconds:int} seconds", th = "พระจันทร์เต็มดวงในอีก {seconds:int} วินาที" },
	["Phase.MeetingCalled"] = {
		en = "{name} called a meeting! Starting in {seconds:int} seconds",
		th = "{name} เรียกประชุม! เริ่มในอีก {seconds:int} วินาที",
	},
	["Phase.MeetingForced"] = { en = "Time is up. The village must meet.", th = "หมดเวลาแล้ว ทั้งหมู่บ้านต้องประชุม" },
	["Phase.MeetingUnlocked"] = { en = "The meeting bell can now be rung.", th = "ตอนนี้กดเรียกประชุมที่โต๊ะได้แล้ว" },

	["Phase.MeetingCountdown"] = { en = "Meeting soon", th = "ใกล้ถึงเวลาประชุม" },
	["Phase.Meeting"] = { en = "Village meeting", th = "ประชุมหมู่บ้าน" },
	["Phase.FullMoonWarning"] = { en = "Nightfall", th = "ใกล้ค่ำ" },
	["Phase.GameOver"] = { en = "Game over", th = "จบเกม" },
	["Phase.NotEnough"] = {
		en = "Not enough players arrived (need {min:int}). Back to the lobby...",
		th = "ผู้เล่นมาไม่ถึง {min:int} คน กำลังกลับ Lobby...",
	},
	["Phase.Waiting"] = { en = "Waiting for players {count:int}/{needed:int}", th = "รอผู้เล่น {count:int}/{needed:int}" },

	-- Role-selection screen (GDD §4)
	["RoleSelect.Count"] = { en = "{count:int}/{max:int} chosen", th = "เลือกแล้ว {count:int}/{max:int}" },
	["RoleSelect.Locked"] = { en = "Level {level:int}", th = "ต้องเลเวล {level:int}" },
	["RoleSelect.NotOwned"] = { en = "Not owned", th = "ยังไม่มีบทนี้" },
	["RoleSelect.Waiting"] = { en = "Waiting for the other players...", th = "รอผู้เล่นคนอื่น..." },
	["RoleSelect.Hint"] = {
		en = "You get one of your 3 picks. The wolf is chosen at random.",
		th = "คุณจะได้ 1 ใน 3 บทที่เลือก ส่วนหมาป่าสุ่มจากทุกคน",
	},

	-- Lobby (GDD §3, owner's rules 17 Nov 2026)
	["Lobby.PadTitle"] = { en = "Match {id:int}", th = "ห้อง {id:int}" },
	["Lobby.Waiting"] = { en = "Needs {min:int} to start", th = "ต้องมีอย่างน้อย {min:int} คน" },
	["Lobby.Ready"] = { en = "Host {name} can start", th = "หัวห้อง {name} กดเริ่มได้" },
	["Lobby.Countdown"] = { en = "Starting in {seconds:int}", th = "เริ่มในอีก {seconds:int}" },
	["Lobby.Launching"] = { en = "Going to the village...", th = "กำลังไปหมู่บ้าน..." },
	["Lobby.InQueue"] = { en = "In queue: Match {id:int}  ({count:int}/{max:int})", th = "อยู่ในคิว: ห้อง {id:int}  ({count:int}/{max:int})" },
	["Lobby.YouAreHost"] = { en = "You are the host", th = "คุณคือหัวห้อง" },
	["Lobby.Start"] = { en = "Start", th = "เริ่มเกม" },
	["Lobby.StepOff"] = { en = "Step off the pad to leave the queue", th = "เดินออกจากแท่นเพื่อออกจากคิว" },
	["Lobby.Locked"] = { en = "Full! Nobody can leave now", th = "ครบแล้ว! ออกจากคิวไม่ได้แล้ว" },
	["Lobby.NoTeleport"] = { en = "Teleporting does not work in Studio (or the Match place id is not set).", th = "ใน Studio ส่งไปห้องเกมไม่ได้ (หรือยังไม่ได้ใส่ Place ID ของห้องเกม)" },
	["Lobby.TeleportFailed"] = { en = "Could not reach the village. Please try again.", th = "ไปหมู่บ้านไม่สำเร็จ ลองใหม่อีกครั้ง" },

	-- Lobby menus
	["Menu.Shop"] = { en = "Shop", th = "ร้านค้า" },
	["Menu.Role"] = { en = "Roles", th = "บทบาท" },
	["Menu.Monster"] = { en = "Monster", th = "มอนสเตอร์" },
	["Menu.Settings"] = { en = "Settings", th = "ตั้งค่า" },
	["Menu.News"] = { en = "News", th = "ข่าวสาร" },
	["Menu.Codes"] = { en = "Codes", th = "โค้ด" },
	["Menu.Pass"] = { en = "Pass", th = "Pass" },
	["Menu.Spin"] = { en = "Daily Spin", th = "หมุนรายวัน" },
	["Menu.Close"] = { en = "Close", th = "ปิด" },
	["Menu.Soon"] = { en = "Coming soon.", th = "เร็วๆ นี้" },
	["Menu.Free"] = { en = "Free", th = "ฟรี" },
	["Menu.Price"] = { en = "{coins:int} coins  ·  {robux:int} R$ / Diamonds", th = "{coins:int} coin  ·  {robux:int} R$ / Diamond" },
	["Menu.Level"] = { en = "Level {level:int}+", th = "เลเวล {level:int} ขึ้นไป" },
	["Menu.Werewolf"] = { en = "Werewolf (selected)", th = "หมาป่า (ใช้อยู่)" },
	["Menu.WolfDefault"] = { en = "Plain grey werewolf", th = "หมาป่าสีเทาแบบปกติ" },
	["Menu.MonsterInfo"] = { en = "More monsters will come later.", th = "มอนสเตอร์แบบอื่นจะมาในภายหลัง" },
	["Menu.SettingsInfo"] = {
		en = "The game uses the language of your Roblox account automatically.",
		th = "ภาษาในเกมเปลี่ยนตามภาษาของบัญชี Roblox อัตโนมัติ",
	},
	["News.Body"] = {
		en = "Welcome to Wolf Village! Step on a glowing pad to join a match. 8 players can start; 12 starts by itself.",
		th = "ยินดีต้อนรับสู่ Wolf Village! เดินขึ้นแท่นเรืองแสงเพื่อเข้าคิว ครบ 8 คนเริ่มได้ ครบ 12 คนเริ่มเอง",
	},

	-- Lobby: wallet, shop, pass, spin, codes (GDD §13)
	["Wallet.Coins"] = { en = "{coins:int} coins", th = "{coins:int} coin" },
	["Wallet.Diamonds"] = { en = "{diamonds:int} diamonds", th = "{diamonds:int} Diamond" },
	["Wallet.Level"] = { en = "Level {level:int}", th = "เลเวล {level:int}" },
	["Wallet.LevelProgress"] = { en = "Level {level:int}  ·  {into:int}/{need:int} EXP", th = "เลเวล {level:int}  ·  {into:int}/{need:int} EXP" },
	["Wallet.Temporary"] = {
		en = "Your data could not be loaded: nothing is saved right now. Please rejoin later.",
		th = "โหลดข้อมูลของคุณไม่ได้: ตอนนี้จะไม่มีอะไรถูกบันทึก กรุณาเข้าเกมใหม่ภายหลัง",
	},
	["Buy.Coins"] = { en = "{price:int} coins", th = "{price:int} coin" },
	["Buy.Diamonds"] = { en = "{price:int} diamonds", th = "{price:int} Diamond" },
	["Buy.Robux"] = { en = "{price:int} R$", th = "{price:int} R$" },
	["Menu.Owned"] = { en = "Owned", th = "มีแล้ว" },
	["Menu.Equip"] = { en = "Equip", th = "ใช้" },
	["Menu.Equipped"] = { en = "Equipped", th = "ใช้อยู่" },
	["Menu.Unequip"] = { en = "Take off", th = "ถอด" },
	["Menu.NeedLevel"] = { en = "Needs level {level:int}", th = "ต้องเลเวล {level:int}" },
	["Menu.Mastery"] = { en = "Mastery {mastery:int}  ({points:int}/{per:int})", th = "Mastery {mastery:int}  ({points:int}/{per:int})" },
	["Menu.Loading"] = { en = "Loading your data...", th = "กำลังโหลดข้อมูล..." },
	["Shop.Skins"] = { en = "Skins", th = "สกิน" },
	["Shop.CoinPacks"] = { en = "Coin packs", th = "แพ็ก coin" },
	["Shop.CoinPack"] = { en = "{coins:int} coins", th = "{coins:int} coin" },
	["Shop.Bought"] = { en = "You got: {thing}", th = "ได้รับ: {thing}" },
	["Shop.Reason.NotForSale"] = { en = "Not for sale.", th = "ไม่ได้วางขาย" },
	["Shop.Reason.Owned"] = { en = "You already have it.", th = "คุณมีอยู่แล้ว" },
	["Shop.Reason.Level"] = { en = "Your level is too low.", th = "เลเวลยังไม่ถึง" },
	["Shop.Reason.Funds"] = { en = "Not enough to buy it.", th = "เงินไม่พอ" },
	["Shop.Reason.WrongCurrency"] = { en = "It cannot be bought that way.", th = "ซื้อด้วยวิธีนี้ไม่ได้" },
	["Shop.Reason.NoProduct"] = { en = "Robux purchases are not open yet.", th = "ยังซื้อด้วย Robux ไม่ได้" },
	["Shop.Reason.Unsaved"] = { en = "Your data is not loaded: try again later.", th = "ข้อมูลยังโหลดไม่สำเร็จ ลองใหม่ภายหลัง" },
	["Shop.Reason.NotOwned"] = { en = "You do not have it.", th = "คุณยังไม่มีสิ่งนี้" },
	["Skin.Slot.Gun"] = { en = "Gun skin", th = "สกินปืน" },
	["Skin.Slot.Knife"] = { en = "Knife skin", th = "สกินมีด" },
	["Skin.Slot.Wolf"] = { en = "Werewolf skin", th = "สกินหมาป่า" },
	["Skin.FromPass"] = { en = "From the Season Pass (level 60)", th = "ได้จาก Season Pass (เลเวล 60)" },
	["Skin.FromSpin"] = { en = "Only from the Daily Spin", th = "ได้จาก Daily Spin เท่านั้น" },
	["Skin.GunPass.Name"] = { en = "Frost Gun", th = "ปืนน้ำแข็ง" },
	["Skin.KnifePass.Name"] = { en = "Frost Knife", th = "มีดน้ำแข็ง" },
	["Skin.WolfPass.Name"] = { en = "Snow Wolf", th = "หมาป่าหิมะ" },
	["Skin.WolfSpin.Name"] = { en = "Ember Wolf", th = "หมาป่าเปลวไฟ" },
	["Skin.GunGold.Name"] = { en = "Golden Gun", th = "ปืนทองคำ" },
	["Skin.KnifeGold.Name"] = { en = "Golden Knife", th = "มีดทองคำ" },
	["Skin.WolfShadow.Name"] = { en = "Shadow Wolf", th = "หมาป่าเงา" },
	["Title.PassFree.Name"] = { en = "Night Watcher", th = "ผู้เฝ้าราตรี" },
	["Title.PassPremium.Name"] = { en = "Moon Hunter", th = "นักล่าจันทรา" },
	["Pass.Level"] = { en = "Season Pass level {level:int}", th = "Season Pass เลเวล {level:int}" },
	["Pass.Progress"] = { en = "{into:int}/{need:int} Pass EXP to the next level", th = "อีก {into:int}/{need:int} Pass EXP ถึงเลเวลถัดไป" },
	["Pass.Info"] = {
		en = "Pass EXP: win 150, lose 50 per match. Rewards are given as soon as you reach a level.",
		th = "Pass EXP: ชนะได้ 150 แพ้ได้ 50 ต่อเกม ถึงเลเวลไหนได้ของทันที",
	},
	["Pass.Premium"] = { en = "Premium: +10 levels now, and the Premium rewards", th = "Premium: +10 เลเวลทันที และได้ของแทร็ก Premium" },
	["Pass.PremiumOwned"] = { en = "Premium is active", th = "มี Premium แล้ว" },
	["Pass.Row"] = { en = "Lv {level:int}   Free: {free}   ·   Premium: {premium}", th = "Lv {level:int}   Free: {free}   ·   Premium: {premium}" },
	["Pass.After"] = {
		en = "Lv {level:int}+ (1,000 EXP each)   Free: {free}   ·   Premium: {premium}",
		th = "Lv {level:int} ขึ้นไป (เลเวลละ 1,000 EXP)   Free: {free}   ·   Premium: {premium}",
	},
	["Pass.Titles"] = { en = "Titles (shown over your head in the lobby)", th = "ฉายา (แสดงเหนือหัวใน Lobby)" },
	["Reward.Coins"] = { en = "{amount:int} coins", th = "{amount:int} coin" },
	["Reward.Diamonds"] = { en = "{amount:int} diamonds", th = "{amount:int} Diamond" },
	["Reward.Spin"] = { en = "{amount:int} Daily Spin", th = "Daily Spin {amount:int} ครั้ง" },
	["Reward.Premium"] = { en = "Season Pass Premium", th = "Season Pass Premium" },
	["Reward.Converted"] = { en = "{reward} (you already had {thing})", th = "{reward} (เพราะมี {thing} อยู่แล้ว)" },
	["Spin.Button"] = { en = "Spin!", th = "หมุน!" },
	["Spin.FreeReady"] = { en = "Your free spin is ready", th = "หมุนฟรีได้แล้ว" },
	["Spin.Extra"] = { en = "Extra spins: {count:int}", th = "หมุนเพิ่มได้อีก {count:int} ครั้ง" },
	["Spin.NextFree"] = { en = "Next free spin in {time}", th = "หมุนฟรีครั้งต่อไปในอีก {time}" },
	["Spin.Won"] = { en = "You won: {prize}!", th = "ได้รับ: {prize}!" },
	["Spin.NoneLeft"] = { en = "No spins left today.", th = "วันนี้หมุนครบแล้ว" },
	["Spin.Odds"] = { en = "{prize}: {chance}%", th = "{prize}: {chance}%" },
	["Codes.Placeholder"] = { en = "Type a code", th = "พิมพ์โค้ด" },
	["Codes.Redeem"] = { en = "Redeem", th = "ใช้โค้ด" },
	["Codes.Done"] = { en = "Code accepted: {rewards}", th = "ใช้โค้ดสำเร็จ: {rewards}" },
	["Codes.Reason.Unknown"] = { en = "That code does not exist.", th = "ไม่มีโค้ดนี้" },
	["Codes.Reason.Used"] = { en = "You already used this code.", th = "คุณใช้โค้ดนี้ไปแล้ว" },
	["Codes.Reason.Expired"] = { en = "This code has expired.", th = "โค้ดนี้หมดอายุแล้ว" },

	-- HUD
	["Hud.YourRole"] = { en = "You are: {role}", th = "คุณคือ: {role}" },
	["Hud.Dead"] = { en = "You are dead", th = "คุณตายแล้ว" },
	["Hud.Ghost"] = {
		en = "You are a ghost now. Only ghosts and the wolves can read what you write.",
		th = "ตอนนี้คุณเป็นผี ผีด้วยกันและฝ่ายหมาป่าเท่านั้นที่อ่านแชทของคุณได้",
	},
	["Chat.WolfTag"] = { en = "[Wolf]", th = "[หมาป่า]" },
	["Chat.GhostTag"] = { en = "[Ghost]", th = "[ผี]" },
	["Hud.Pack"] = { en = "Pack: {names}", th = "ฝูง: {names}" },

	-- Ability buttons (GDD §8)
	["Ability.Attack"] = { en = "Attack", th = "โจมตี" },
	["Ability.Sniff"] = { en = "Sniff", th = "ดมกลิ่น" },
	["Ability.Sprint"] = { en = "Sprint", th = "วิ่ง 4 ขา" },
	["Ability.Howl"] = { en = "Howl", th = "หอน" },
	["Ability.Shoot"] = { en = "Shoot", th = "ยิง" },
	["Ability.See"] = { en = "See", th = "มองทะลุ" },
	["Ability.Dash"] = { en = "Dash", th = "พุ่ง" },
	["Ability.Bless"] = { en = "Bless", th = "ให้พร" },
	["Ability.Stab"] = { en = "Stab", th = "แทง" },
	["Ability.Flashlight"] = { en = "Flashlight", th = "ไฟฉาย" },

	-- Ability feedback
	["Effect.Blocked"] = { en = "The attack was blocked!", th = "การโจมตีถูกกันไว้!" },
	["Effect.Blessed"] = { en = "You blessed {name}", th = "คุณให้พร {name} แล้ว" },
	["Effect.Stunned"] = { en = "Stunned!", th = "ติดสตั้น!" },
	["Picker.Bless"] = { en = "Who do you bless today?", th = "วันนี้จะให้พรใคร?" },
	["Picker.Close"] = { en = "Close", th = "ปิด" },
	["Picker.You"] = { en = "{name} (you)", th = "{name} (คุณ)" },

	-- Morning announcement in red (GDD §6.1)
	["Morning.Safe"] = { en = "You're safe... for now...", th = "พวกแกปลอดภัย... แค่ตอนนี้..." },
	-- DRAFT: wolf taunts shown when someone died last night.
	["Morning.Taunt1"] = { en = "One less heartbeat in the village. Who's next?", th = "เสียงหัวใจในหมู่บ้านหายไปอีกดวง... ใครเป็นรายต่อไป?" },
	["Morning.Taunt2"] = { en = "Did you sleep well? Not everyone did.", th = "เมื่อคืนหลับสบายไหม? บางคนไม่ได้ตื่นขึ้นมานะ" },
	["Morning.Taunt3"] = { en = "Lock your doors tighter tonight. It won't help.", th = "คืนนี้ล็อกประตูให้แน่นกว่าเดิมสิ... แต่ก็ไม่ช่วยอะไรหรอก" },

	-- Voting (GDD §6.2)
	["Vote.Title"] = { en = "Who is the wolf?", th = "ใครคือหมาป่า?" },
	["Vote.Confirm"] = { en = "Confirm", th = "ยืนยัน" },
	["Vote.Confirmed"] = { en = "Vote confirmed", th = "ยืนยันโหวตแล้ว" },
	["Vote.Exiled"] = { en = "{name} was exiled.", th = "{name} ถูกไล่ออกจากหมู่บ้าน" },
	["Vote.NoExile"] = { en = "Nobody was exiled.", th = "ไม่มีใครถูกไล่ออก" },
	["Vote.ChiefTieBreak"] = { en = "Ahem!", th = "Ahem!" },
	["Vote.RandomTieBreak"] = { en = "A tie! Fate decides...", th = "คะแนนเสมอ! ปล่อยให้โชคชะตาตัดสิน..." },
	["Vote.NightFalls"] = { en = "Night falls in {seconds:int} seconds", th = "กลางคืนจะมาถึงในอีก {seconds:int} วินาที" },

	-- Endings (GDD §7)
	["Ending.Village"] = { en = "Everyone lived happily ever after.", th = "ทุกคนอยู่ร่วมกันอย่างมีความสุขตลอดไป" },
	["Ending.Wolf"] = { en = "And the wolf lived happily ever after.", th = "แล้วหมาป่าก็อยู่อย่างมีความสุขตลอดไป" },
	["Ending.Killer"] = { en = "No one lived happily ever after.", th = "ไม่มีใครได้อยู่อย่างมีความสุขอีกเลย" },
	["Ending.Fool"] = { en = "The fool laughs last.", th = "คนบ้าได้หัวเราะเป็นคนสุดท้าย" },
	["End.Like"] = { en = "Like", th = "ถูกใจ" },
	["End.Liked"] = { en = "Liked", th = "ถูกใจแล้ว" },
	["End.LikeHint"] = {
		en = "Give your one like to the player you enjoyed most",
		th = "กดถูกใจให้ผู้เล่นที่ชอบที่สุด (1 คน)",
	},
	["End.Alive"] = { en = "Alive", th = "รอด" },
	["End.Dead"] = { en = "Dead", th = "ตาย" },
	["End.Won"] = { en = "Won", th = "ชนะ" },
	["End.Lost"] = { en = "Lost", th = "แพ้" },
	["End.You"] = { en = "{name} (you)", th = "{name} (คุณ)" },
	["End.Reward"] = { en = "+{coins:int} coins   +{exp:int} EXP   +{pass:int} Pass EXP", th = "+{coins:int} coin   +{exp:int} EXP   +{pass:int} Pass EXP" },
	["End.RewardDetail"] = {
		en = "Nights survived: {nights:int}   Tasks: {tasks:int}   {role} mastery +{points:int}",
		th = "รอดมา {nights:int} คืน   ภารกิจ {tasks:int}   Mastery {role} +{points:int}",
	},
	["End.Diamonds"] = { en = "+{diamonds:int} diamonds (mastery up!)", th = "+{diamonds:int} Diamond (Mastery เพิ่ม!)" },
	["End.MvpBonus"] = { en = "MVP: +20%!", th = "MVP: +20%!" },
	["End.Mvp"] = { en = "MVP", th = "MVP" },
	["End.Leave"] = { en = "Back to lobby", th = "กลับ Lobby" },

	-- Factions
	["Faction.Village"] = { en = "Villagers", th = "ฝ่ายชาวบ้าน" },
	["Faction.Wolf"] = { en = "Wolves", th = "ฝ่ายหมาป่า" },
	["Faction.Killer"] = { en = "Killer", th = "ฆาตกร" },
	["Faction.Fool"] = { en = "Fool", th = "คนบ้า" },

	-- Roles (GDD §8, §9)
	["Role.Wolf.Name"] = { en = "Werewolf", th = "หมาป่า" },
	["Role.Wolf.Desc"] = {
		en = "Transform at night and hunt. Win when the villagers left equal the wolves.",
		th = "แปลงร่างตอนกลางคืนแล้วออกล่า ชนะเมื่อชาวบ้านเหลือเท่ากับจำนวนฝ่ายหมาป่า",
	},
	["Role.Pup.Name"] = { en = "Wolf Pup", th = "ลูกหมาป่า" },
	["Role.Pup.Desc"] = {
		en = "You were bitten. Help the wolf: you need two hits to kill, and you can howl to reveal nearby players.",
		th = "คุณถูกกัดแล้ว ช่วยหมาป่าล่า ต้องตี 2 ครั้งคนถึงตาย และหอนเพื่อเผยตำแหน่งคนรอบตัวได้",
	},
	["Role.Villager.Name"] = { en = "Villager", th = "ชาวบ้าน" },
	["Role.Villager.Desc"] = { en = "Carries a flashlight.", th = "มีไฟฉายติดตัว" },
	["Role.Sheriff.Name"] = { en = "Sheriff", th = "นายอำเภอ" },
	["Role.Sheriff.Desc"] = {
		en = "Stun gun: one shot each day and each night. Stuns for 5 seconds. Kills the Killer instantly.",
		th = "ปืนสตั้น ยิงได้ 1 ครั้งต่อวันและต่อคืน สตั้น 5 วินาที ถ้ายิงโดนฆาตกร ฆาตกรตายทันที",
	},
	["Role.Doctor.Name"] = { en = "Doctor", th = "หมอ" },
	["Role.Doctor.Desc"] = {
		en = "Revive someone who died at night, once per game. A First aid allows one more.",
		th = "ชุบชีวิตคนที่ตายตอนกลางคืนได้ 1 ครั้งต่อเกม ใช้ First aid เพื่อชุบเพิ่มได้",
	},
	["Role.Seer.Name"] = { en = "Seer", th = "ผู้หยั่งรู้" },
	["Role.Seer.Desc"] = {
		en = "Once per night, see every survivor through walls for 5 seconds.",
		th = "คืนละครั้ง มองเห็นผู้รอดชีวิตทุกคนทะลุกำแพง 5 วินาที",
	},
	["Role.Chief.Name"] = { en = "Village Chief", th = "หัวหน้าหมู่บ้าน" },
	["Role.Chief.Desc"] = {
		en = "Your vote counts twice, and your side wins a tied vote.",
		th = "โหวตได้ 2 เสียง และชนะเมื่อคะแนนโหวตเสมอ",
	},
	["Role.Bodyguard.Name"] = { en = "Bodyguard", th = "บอดี้การ์ด" },
	["Role.Bodyguard.Desc"] = {
		en = "Dash forward. Hitting a wolf stuns it for 5 seconds. 30 second cooldown.",
		th = "พุ่งไปข้างหน้า ถ้าชนหมาป่าจะสตั้น 5 วินาที คูลดาวน์ 30 วินาที",
	},
	["Role.Monk.Name"] = { en = "Monk", th = "หลวงพ่อ" },
	["Role.Monk.Desc"] = {
		en = "Each morning, bless one player (even yourself). The blessing blocks one attack until the next morning.",
		th = "ทุกเช้าให้พรได้ 1 คน (รวมถึงตัวเอง) พรกันการโจมตีได้ 1 ครั้ง และหายไปเช้าวันถัดไป",
	},
	["Role.Engineer.Name"] = { en = "Engineer", th = "วิศวกร" },
	["Role.Engineer.Desc"] = {
		en = "Reinforce a door: full health and double maximum. Once per day and once per night.",
		th = "เสริมประตูให้เลือดเต็มและเลือดสูงสุด ×2 ใช้ได้กลางวัน 1 ครั้ง กลางคืน 1 ครั้ง",
	},
	["Role.Killer.Name"] = { en = "Killer", th = "ฆาตกร" },
	["Role.Killer.Desc"] = {
		en = "You work alone. Your knife kills in one hit: once per day and once per night. You cannot hold a gun.",
		th = "ทำงานคนเดียว มีดฆ่าได้ทีเดียวตาย กลางวัน 1 ครั้ง กลางคืน 1 ครั้ง ถือปืนไม่ได้",
	},
	["Role.Fool.Name"] = { en = "Fool", th = "คนบ้า" },
	["Role.Fool.Desc"] = {
		en = "You only win by getting voted out.",
		th = "ชนะได้ทางเดียว คือถูกโหวตไล่ออก",
	},

	-- Items (GDD §11)
	["Item.Shovel.Name"] = { en = "Shovel", th = "พลั่ว" },
	["Item.Shovel.Desc"] = { en = "Melee hit that stuns for 3 seconds. One use.", th = "ตีระยะใกล้ สตั้น 3 วินาที ใช้ได้ 1 ครั้ง" },
	["Item.Apple.Name"] = { en = "Apple", th = "แอปเปิ้ล" },
	["Item.Apple.Desc"] = { en = "Eat to run 30% faster for 5 seconds.", th = "กินแล้ววิ่งเร็วขึ้น 30% นาน 5 วินาที" },
	["Item.Axe.Name"] = { en = "Wooden Axe", th = "ขวานไม้" },
	["Item.Axe.Desc"] = { en = "Throw it to stun for 5 seconds. Two uses.", th = "ขว้างไปข้างหน้า สตั้น 5 วินาที ใช้ได้ 2 ครั้ง" },
	["Item.Gun.Name"] = { en = "Gun", th = "ปืน" },
	["Item.Gun.Desc"] = { en = "Works like the Sheriff's gun. One per player.", th = "เหมือนปืนนายอำเภอ ถือได้คนละ 1 กระบอก" },
	["Item.FirstAid.Name"] = { en = "First aid", th = "First aid" },
	["Item.FirstAid.Desc"] = { en = "Restores your health to full.", th = "ฟื้นเลือดตัวเองจนเต็ม" },
	["Item.Cross.Name"] = { en = "Cross", th = "Cross" },
	["Item.Cross.Desc"] = { en = "Blocks one attack, then breaks.", th = "กันการโจมตีได้ 1 ครั้ง แล้วหายไป" },
	["Item.Flashlight.Name"] = { en = "Flashlight", th = "ไฟฉาย" },
	["Item.Flashlight.Desc"] = { en = "Lights up the night.", th = "ส่องสว่างตอนกลางคืน" },
	["Item.Knife.Name"] = { en = "Knife", th = "มีด" },

	-- Tasks (GDD §10)
	["Task.RepairDoor"] = { en = "Repair a broken door", th = "ซ่อมประตูที่เสีย" },
	["Task.PlantCarrot"] = { en = "Plant carrots behind a house", th = "ปลูกแครอตหลังบ้าน" },
	["Task.PickApples"] = { en = "Pick apples in the forest ({done:int}/{total:int})", th = "เก็บแอปเปิ้ลในป่า ({done:int}/{total:int})" },
	["Task.ChopTrees"] = { en = "Chop trees ({done:int}/{total:int})", th = "ตัดต้นไม้ ({done:int}/{total:int})" },
	["Hud.Task"] = { en = "Task: {task}", th = "ภารกิจ: {task}" },
	["Hud.TaskDone"] = { en = "Task done", th = "ทำภารกิจแล้ว" },
	["Effect.Gained"] = { en = "You got: {item}", th = "ได้รับ: {item}" },
	["Effect.CrossInfo"] = {
		en = "The Cross protects you from one attack while you carry it.",
		th = "Cross จะกันการโจมตีให้ 1 ครั้งเมื่อพกติดตัว",
	},
	["Task.Complete"] = { en = "Task complete! +{coins:int} coins at the end of the game", th = "ภารกิจสำเร็จ! +{coins:int} coin ตอนจบเกม" },

	-- Interaction prompts (hold E)
	["Prompt.CallMeeting"] = { en = "Call meeting", th = "เรียกประชุม" },
	["Prompt.OpenDoor"] = { en = "Open door", th = "เปิดประตู" },
	["Prompt.BashDoor"] = { en = "Break door", th = "พังประตู" },
	["Prompt.Hide"] = { en = "Hide", th = "ซ่อน" },
	["Prompt.LeaveHiding"] = { en = "Come out", th = "ออกมา" },
	["Prompt.Search"] = { en = "Search", th = "ค้น" },
	["Prompt.Revive"] = { en = "Revive", th = "ชุบชีวิต" },
	["Prompt.Reinforce"] = { en = "Reinforce door", th = "เสริมประตู" },
	["Prompt.OpenCrate"] = { en = "Open crate", th = "เปิดกล่อง" },
	["Prompt.Repair"] = { en = "Repair door", th = "ซ่อมประตู" },
	["Prompt.Plant"] = { en = "Plant carrots", th = "ปลูกแครอต" },
	["Prompt.PickApple"] = { en = "Pick apple", th = "เก็บแอปเปิ้ล" },
	["Prompt.Chop"] = { en = "Chop tree", th = "ตัดต้นไม้" },
	["Prompt.PickUp"] = { en = "Pick up", th = "เก็บ" },
	["Prompt.DebugHitDoor"] = { en = "[Debug] Hit door", th = "[Debug] ตีประตู" },

	-- Chat channels (GDD §6.2, §12)
	["Chat.General"] = { en = "General", th = "แชทรวม" },
	["Chat.Wolf"] = { en = "Wolf", th = "แชทหมาป่า" },
	["Chat.Ghost"] = { en = "Ghost", th = "แชทผี" },
}

return Strings
