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
	["Phase.Waiting"] = { en = "Waiting for players {count:int}/{needed:int}", th = "รอผู้เล่น {count:int}/{needed:int}" },

	-- HUD
	["Hud.YourRole"] = { en = "You are: {role}", th = "คุณคือ: {role}" },
	["Hud.Dead"] = { en = "You are dead", th = "คุณตายแล้ว" },

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
	["Prompt.PickUp"] = { en = "Pick up", th = "เก็บ" },
	["Prompt.DebugHitDoor"] = { en = "[Debug] Hit door", th = "[Debug] ตีประตู" },

	-- Chat channels (GDD §6.2, §12)
	["Chat.General"] = { en = "General", th = "แชทรวม" },
	["Chat.Wolf"] = { en = "Wolf", th = "แชทหมาป่า" },
	["Chat.Ghost"] = { en = "Ghost", th = "แชทผี" },
}

return Strings
