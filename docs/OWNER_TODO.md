# Wolf Village — สิ่งที่รอเจ้าของเกม

ไฟล์นี้รวมทุกอย่างที่ Claude ทำเองไม่ได้ หรือที่ GDD ยังไม่ได้ระบุ
เมื่อได้คำตอบ/ID แล้ว Claude จะใส่ลงใน `src/ReplicatedStorage/Shared/Config.luau`

---

## 1. คำถามเรื่องกติกา (GDD ไม่ได้ระบุ หรือตีความได้หลายแบบ)

ตอนนี้โค้ดใช้ "ค่าที่ตั้งไว้ก่อน" ตามคอลัมน์ขวา ทุกค่ามีป้าย `[ASSUMED]` ใน Config และแก้ได้ในบรรทัดเดียว

| # | คำถาม | ค่าที่ตั้งไว้ก่อน |
|---|---|---|
| 1 | Turbo: ฆาตกร / คนบ้า ออกได้ไหม? (GDD บอกว่าสองบทนี้ "เข้าไปแทนช่องชาวบ้าน" แต่ Turbo ไม่มีช่องชาวบ้าน) | ออกไม่ได้ |
| 2 | Turbo: ถ้าบทที่เลือกไว้ถูกคนอื่นได้ไปหมด และไม่มีบทอื่นที่ตัวเองมีเหลือ จะให้ได้บทพิเศษที่ **ยังไม่ได้ซื้อ** ไหม? (GDD บอกว่าทุกคนต้องมีบท) | ได้ (สุ่มจากบทที่เหลือ) |
| 3 | Casual: ถ้าคนได้บทพิเศษไม่ถึง 6 คน ชาวบ้านมีมากกว่า 5 คนได้ใช่ไหม? | ได้ (ชาวบ้านเป็นตัวเติม ไม่จำกัดจำนวน) |
| 4 | ฆาตกรชนะแบบ "ฆ่าได้มากกว่าหมาป่า" ต้องยังมีชีวิตอยู่ตอนเกมจบไหม? | ต้องยังมีชีวิต |
| 5 | หมาป่าหมดแล้วแต่ฆาตกรยังอยู่และชาวบ้านเหลือมากกว่า 1 คน: เกมเล่นต่อจนฆาตกรตาย (ชาวบ้านชนะ) หรือเหลือ 1+1 (ฆาตกรชนะ) ใช่ไหม? | ใช่ เล่นต่อ |
| 6 | หมดเวลากลางวันโดยไม่มีใครกดประชุม: เข้าประชุมทันที หรือยังนับถอยหลัง 1 นาทีก่อน? | เข้าประชุมทันที |
| 7 | โหวตตัวเองได้ไหม? (มีผลกับคนบ้า) | ไม่ได้ |
| 8 | คะแนนเสมอ แต่หัวหน้าไม่ได้โหวตฝั่งที่เสมอ (หรือไม่ได้โหวต) | สุ่มจากคนที่เสมอ |
| 9 | เงาโหวตของหัวหน้าแสดง 2 เงาใช่ไหม? (จะทำให้คนอื่นเดาได้ว่าใครโดนหัวหน้าโหวต) | แสดง 2 เงา |
| 10 | MVP +20% คิดจากอะไร? | coin ทั้งหมด (รวม coin ภารกิจ) และ EXP |
| 11 | คูลดาวน์สกิลวิ่ง 4 ขาของหมาป่า (GDD บอกแค่ความเร็ว 30 นาน 5 วินาที) | 30 วินาที |
| 12 | เวลาหน้าเลือกบท และถ้าเลือกไม่ทัน | 30 วินาที / สุ่ม 3 บทจากที่มี |
| 13 | ผู้เล่นที่ **ยังไม่ตาย** กดออกจากเกมกลางเกม ได้รางวัลไหม? (GDD พูดถึงเฉพาะผี) | ยังไม่ได้ทำ รอคำตอบ |
| 14 | เวลาแสดง Scoreboard ก่อนส่งกลับ Lobby | 30 วินาที |

### Season Pass / Shop

| # | คำถาม | ค่าที่ตั้งไว้ก่อน |
|---|---|---|
| 15 | **ราคา Premium ของ Season Pass (Robux)** — ไม่มีใน GDD | ยังไม่มี (ต้องการคำตอบ) |
| 16 | Premium ก่อน Lv60: ช่องที่เป็น coin เปลี่ยนเป็น Diamond **กี่เม็ด**? | 10 Diamond (เท่ากับหลัง Lv60) |
| 17 | คนซื้อ Premium ได้ของแทร็ก Free ด้วยใช่ไหม? | ได้ทั้งสองแทร็ก |
| 18 | Pass เริ่มที่ Lv0 (ต้องเก็บ 200 EXP ก่อนถึง Lv1) หรือเริ่มที่ Lv1 เลย? | เริ่มที่ Lv0 |
| 19 | **ราคาสกิน** ใน Shop (สกินปืน / มีด / หมาป่า) และมีสกินอะไรบ้าง — ไม่มีใน GDD | ยังไม่มี (ต้องการคำตอบ) |
| 20 | Daily Spin รีเซ็ตเมื่อไร? | เที่ยงคืน UTC (07:00 เวลาไทย) |

### ค่าที่ต้องปรับตอนเทสต์จริง (ไม่ใช่กติกา)
ระยะตีของหมาป่า (7 studs), ระยะตีประตู, ระยะ/ความเร็วพุ่งของบอดี้การ์ด, ระยะปืน, เวลากดค้างเพื่อซ่อน/ชุบ/เสริมประตู/เปิดกล่อง,
ขนาดลูกหมาป่า (60%) — ทั้งหมดอยู่ใน Config ติดป้าย `[ASSUMED]`

### ข้อความที่ร่างให้ (รออนุมัติ)
ข้อความเยาะเย้ยตอนเช้าเมื่อมีคนตาย 3 แบบ (`Morning.Taunt1–3` ใน `Strings.luau`) — GDD บอกแค่ว่าเป็น "ข้อความเยาะเย้ยจากหมาป่า"

---

## 2. เสียง (ส่ง ID จาก Creator Store มาได้เลย ไม่ต้องรอ)

วิธีหา: Roblox Studio → Toolbox → Audio (หรือ create.roblox.com/store/audio) → ค้นคำในคอลัมน์ "คำค้น" → คลิกขวา Copy Asset ID
ระหว่างนี้ทุกเสียงเป็นค่า 0 (เงียบ)

| Key ใน Config | ใช้ตอนไหน | คำค้นแนะนำ | ID |
|---|---|---|---|
| `WolfHowl` | เข้ากลางคืน / สกิลหอนของลูกหมาป่า | wolf howl | |
| `FullMoonSting` | ขึ้นข้อความ "Full moon in 10 seconds" | horror sting / suspense hit | |
| `DoorHit` | หมาป่าตีประตู | wood door bang / door pound | |
| `DoorBreak` | ประตูแตก | wood break / door smash | |
| `DoorOpen` | เปิดประตู | door open creak | |
| `DeathScream` | คนตาย | scream / man scream | |
| `WolfAttack` | หมาป่าตะปบ | claw swipe / slash | |
| `WolfMaul` | ขย้ำเหยื่อ (~3 วิ) | monster eating / growl bite | |
| `WolfGrowl` | หมาป่าแปลงร่าง | wolf growl / snarl | |
| `Crickets` | บรรยากาศกลางคืน (วนลูป) | crickets night ambience | |
| `Owl` | บรรยากาศกลางคืน (สุ่มเป็นระยะ) | owl hoot | |
| `NightMusic` | เพลงกลางคืน ช้า เบา ชวนกลัว (วนลูป) | creepy ambient music / dark ambience | |
| `DayAmbience` | บรรยากาศกลางวัน (วนลูป) | birds chirping / village ambience | |
| `MorningRooster` | เช้าวันใหม่ | rooster crow | |
| `MeetingBell` | มีคนกดเรียกประชุม | bell ring / town bell | |
| `VoteSelect` | เลือกคนในหน้าโหวต | ui select / pop | |
| `VoteConfirm` | ยืนยันโหวต | ui confirm | |
| `Exile` | ประกาศผลไล่ออก | gavel / dramatic drum hit | |
| `Gunshot` | ปืนนายอำเภอ / ปืนจากกล่อง | taser / stun gun / gunshot | |
| `StunHit` | โดนสตั้น | stun / bonk | |
| `AxeThrow` | ขว้างขวาน | whoosh throw | |
| `KnifeStab` | มีดฆาตกร | knife stab | |
| `BodyguardDash` | บอดี้การ์ดพุ่ง | dash whoosh | |
| `Revive` | หมอชุบชีวิต | heal / revive magic | |
| `Blessing` | หลวงพ่อให้พร | holy chime / bless | |
| `BlessingBreak` | พร / Cross กันการโจมตีแล้วแตก | shield break / glass shatter | |
| `Reinforce` | วิศวกรเสริมประตู | hammer wood / metal clank | |
| `AppleEat` | กินแอปเปิ้ล | apple bite / crunch | |
| `TreeChop` | ตัดต้นไม้ | axe chop wood | |
| `Digging` | ปลูกแครอต / พลั่ว | shovel dig dirt | |
| `ItemPickup` | เก็บไอเทม | item pickup / pop | |
| `CrateOpen` | เปิดกล่องไม้ | chest open / crate open | |
| `TaskComplete` | ทำภารกิจสำเร็จ | success chime | |
| `UIClick` | กดปุ่ม UI | ui click | |
| `UIOpen` | เปิดหน้าต่าง UI | ui open / swoosh | |
| `Purchase` | ซื้อของสำเร็จ | cash register / purchase | |
| `SpinTick` | Daily Spin กำลังหมุน | wheel tick / click | |
| `SpinWin` | Daily Spin ได้รางวัล | prize win / fanfare short | |
| `WinJingle` | จบเกม ฝ่ายตัวเองชนะ | victory jingle | |
| `LoseJingle` | จบเกม ฝ่ายตัวเองแพ้ | defeat / sad jingle | |

---

## 3. สินค้า Robux (สร้างเมื่อถึง Milestone 9 — ดูรายการไว้ก่อนได้)

สร้างที่ create.roblox.com → เกม Wolf Village → Monetization → **Developer Products** แล้วส่ง Product ID กลับมา

| Key ใน Config | ชื่อสินค้า | ราคา (R$) |
|---|---|---|
| `Coins500` | 500 Coins | 49 |
| `Coins1200` | 1,200 Coins | 99 |
| `Coins2600` | 2,600 Coins | 199 |
| `Coins7000` | 7,000 Coins | 499 |
| `RoleChief` | Role: Village Chief | 99 |
| `RoleBodyguard` | Role: Bodyguard | 99 |
| `RoleSeer` | Role: Seer | 199 |
| `RoleMonk` | Role: Monk | 199 |
| `RoleEngineer` | Role: Engineer | 199 |
| `RoleKiller` | Role: Killer | 399 |
| `RoleFool` | Role: Fool | 399 |
| `SeasonPassPremium` | Season Pass Premium | รอคำตอบข้อ 15 |
| (สกิน) | รอคำตอบข้อ 19 | |

หมายเหตุ: แนะนำให้ทุกอย่างเป็น **Developer Product** (ไม่ใช่ Game Pass) เพราะเกมบันทึกความเป็นเจ้าของไว้ในข้อมูลผู้เล่นเอง
ทำให้ซื้อด้วย Diamond ได้ในราคาเดียวกันตาม GDD และถ้าวันหนึ่งมีซีซันใหม่ก็ขาย Premium ซ้ำได้

---

## 4. แอนิเมชันหมาป่า (Milestone 3)

Claude จะสร้าง `KeyframeSequence` 5 ตัวไว้ใน ServerStorage: เดิน 2 ขา, วิ่ง 4 ขา, ตี, ขย้ำ, หอน
จากนั้นคุณต้อง Publish แต่ละตัวในบัญชีของคุณแล้วส่ง Animation ID มา (จะมีขั้นตอนละเอียดให้ตอนนั้น)

| Key ใน Config | ID |
|---|---|
| `WolfWalk` | |
| `WolfRun` | |
| `WolfAttack` | |
| `WolfMaul` | |
| `WolfHowl` | |

---

## 5. อื่นๆ ที่ต้องทำเอง (จะแจ้งขั้นตอนเมื่อถึงเวลา)

- เปิด voice chat ใน Game Settings
- สร้าง place ที่สอง (Lobby) ใน experience เดียวกัน — Milestone 8
- Publish เกม
- เทสต์หลายคน (Studio → Test → Clients and Servers)
