# Wolf Village — Prompt สำหรับ Claude Code

## ส่วนที่ 1: เตรียมเครื่องก่อนเริ่ม (สำหรับคุณ)

1. ติดตั้ง **Claude Code** และ **GitHub CLI** (`gh`) แล้วรัน `gh auth login` ให้ล็อกอิน GitHub
2. สร้างโฟลเดอร์ว่างชื่อ `wolf-village` แล้ววางไฟล์ `GDD.md` ไว้ข้างใน
3. ติดตั้ง Roblox Studio MCP ในโฟลเดอร์นั้น:
   ```
   claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest
   ```
   แล้วติดตั้งปลั๊กอินใน Studio ตามคู่มือ (README) ของ `robloxstudio-mcp`
4. เปิด Roblox Studio → สร้าง Baseplate ใหม่ → **Publish** เป็นเกมใหม่ชื่อ Wolf Village (place นี้คือ **Match place**)
5. ใน Studio: Game Settings → Security → เปิด **Allow HTTP Requests** และ **Enable Studio Access to API Services**
6. เปิดปลั๊กอิน MCP ใน Studio ให้ขึ้นว่าเชื่อมต่อแล้ว
7. เปิด terminal ในโฟลเดอร์ `wolf-village` → พิมพ์ `claude` → คัดลอกส่วนที่ 2 ทั้งหมดไปวาง

ระหว่างทำงาน Claude Code จะหยุดเป็นช่วงๆ เพื่อให้คุณเทสต์และส่ง ID ต่างๆ (แอนิเมชัน, เสียง, สินค้า Robux) ให้

---

## ส่วนที่ 2: PROMPT (คัดลอกตั้งแต่บรรทัดถัดไปจนจบไฟล์)

You are the sole developer of **Wolf Village**, a Roblox social-deduction game ("friendly-looking but not so friendly"). The complete design is in `GDD.md` in this folder (written in Thai). It is the source of truth: read all of it before doing anything. Values marked `[ค่าเริ่มต้น]` are tunable defaults. If something you need is not in the GDD, ask me and do not invent a gameplay rule. Reply to me in Thai. Write code, comments and commit messages in English.

### Tools and workflow (no Rojo)
- You work directly in the open Roblox Studio session through the Roblox Studio MCP server (`robloxstudio`). First, verify the connection by listing the DataModel. If it fails, stop and tell me.
- **Studio is where the game runs. The GitHub repo is the backup and history.** Keep the two in sync:
  - Before editing a script, read its current source from Studio. I may have changed something.
  - After each milestone, export every script (Script / LocalScript / ModuleScript) from Studio into `src/`. Mirror the DataModel path, e.g. `src/ServerScriptService/Services/VoteService.server.luau`, `src/ReplicatedStorage/Shared/Config.luau`. Use the suffixes `.server.luau`, `.client.luau`, `.luau`.
  - Everything physical (map, houses, wolf rig, UI) must be created by **builder scripts** saved in `build/` (e.g. `build/BuildVillage.luau`). Run them in Studio through MCP. The world must be rebuildable from the repo alone, so never hand-place parts without a builder script.
  - Then `git add -A`, commit with a clear message, and push.
- Create a new **private** GitHub repo named `wolf-village` with `gh repo create wolf-village --private`. Add `GDD.md`, a `README.md` (setup + folder map) and a `.gitignore`.

### Architecture rules
- **Server-authoritative.** The client only sends intents through RemoteEvents/RemoteFunctions. The server validates everything: role, phase, distance, cooldowns, item ownership. Rate-limit every remote.
- **Information hiding.** Never replicate secret information to clients who must not know it. That covers roles, wolf identity, who voted for whom, hiding spots, and the forest red highlight. Create Highlights on the client only for the viewer who is allowed to see them, triggered by a server event sent to that player only.
- **One `Config` ModuleScript** in ReplicatedStorage holds every number in the GDD: timers, speeds, cooldowns, HP, damage, drop rates, prices, EXP, spin odds, plus placeholders for asset IDs (animations, sounds, Game Pass/Developer Product IDs). No magic numbers elsewhere.
- **Code style.** Use ModuleScript services with a single bootstrap Script per side. Use typed Luau (`--!strict` where practical).
- **Interactions.** Use `ProximityPrompt` with `HoldDuration` for all "hold E" interactions so PC, mobile and console all work. Give abilities on-screen buttons via `ContextActionService`.
- **Chat.** Use `TextChatService` with custom `TextChannel`s: General, Wolf, Ghost. Route visibility exactly as GDD §6.2/§12 describes. Text must go through Roblox filtering.
- **Text localization.** Put all player-facing text in a `LocalizationTable` (en + th) and use keys in code. Detect the player's locale automatically. There is no language setting.
- **Saving data.** Use DataStoreService with session locking and retry/backoff (ProfileStore is acceptable). Save coins, diamonds, EXP/level, pass EXP/level/premium, owned roles/skins, mastery per role, daily spin timestamp, redeemed codes.
- **Purchases.** Handle Robux purchases with `MarketplaceService.ProcessReceipt`, made idempotent (store receipt IDs).
- **Two places in one experience.** **Lobby place** (queue pads, menus, shop) and **Match place** (the round). The lobby reserves a server with `TeleportService` and passes the mode (Casual 12 / Turbo 6) in TeleportData. Build the Match place first.
- **Testing in Studio.** Add `Config.Debug` (active only when `RunService:IsStudio()`) that allows starting a match with fewer players, forcing a chosen role, and shortening timers. Teleports do not work in Studio, so give the Match place a fallback that starts in Casual mode when there is no TeleportData.

### Art and audio
- **Style.** Low-poly, bright and cute by day; dark with black distance fog at night. Build everything from Parts/WedgeParts with a consistent palette. Village layout: 12 houses in a ring around a central plaza with the meeting table, gardens behind each house, a fence, a walkable forest, then a dark dense outer forest with invisible walls.
- **One-way window.** Outsiders cannot see in. Do it client-side: the window is opaque unless the local player is inside that house.
- **Werewolf rig.** Blocky, gray, glowing yellow eyes, large hunched shoulders and claws. Make a custom Motor6D rig in Parts. Author its animations as `KeyframeSequence`s in ServerStorage: bipedal walk, quadruped run, attack, maul (~3 s), howl. Then **stop and ask me to publish them**, and put the IDs I give you into Config. Until then, use a simple tween-based fallback so the game stays playable. Make the wolf pup a scaled-down version.
- **Humans.** R6 with the default Roblox animations.
- **Sounds.** List every sound you need (howl, door hits, death scream, crickets, owl, night music, UI clicks, etc.) with a suggested search term. I will send Creator Store IDs; use silent placeholders until then.

### Milestones
Do them in order. At the end of each milestone:
1. Export to `src/` + commit + push.
2. Give me a short Thai test checklist (what to click and what should happen).
3. **Wait for my "ok" before starting the next milestone.**

0. **Setup.** Repo, README, folder structure, Config with every GDD value, verify MCP.
1. **Map (Match place).** Village, houses with interiors (bed, wardrobe, one-way window, door with HP bar), meeting table, gardens, fence, forest + task trees, outer forest + invisible walls, day/night lighting presets.
2. **Core loop.**
   - Round state machine: RoleSelect → Day 1 (3 min) → Full-moon warning (10 s) → Night (3 min) → Day (5 min, meeting unlocks after 3 min, forced meeting at 0) → Meeting countdown (1 min) → Meeting/vote (2 min) → 10 s → Night …
   - Random house warp at night and front-of-house warp in the morning (forest players excluded).
   - Doors (HP, owner can open but not re-close, repaired-look next morning).
   - Voting UI exactly as GDD §6.2: headshots, silhouettes gray/blue, auto-confirm, chief double vote + "Ahem!" tie-break, random tie-break.
   - Exile, morning red announcements, all win conditions in GDD §7, ending text.
3. **Wolf side.**
   - Transformation and spawn at the plaza center, speed 20, one-hit melee with 1 s cooldown.
   - Sniff and four-legged sprint (with maul lock), forest red highlight, door bashing, searching hiding spots.
   - Wolf pup: conversion on the first night kill, half damage, howl, promotion two nights after the main wolf is gone.
4. **Roles.** All 10 roles in GDD §9, including the role-selection screen (pick 3 owned roles), assignment without duplicates, and Turbo rules.
5. **Tasks, items, crate.**
   - Daily random personal task.
   - All items in GDD §11, crate drop odds, drop-on-death / scatter-on-exile / center-pile-on-leave, one-gun limit, role items never drop.
   - Hiding under bed and in wardrobe.
6. **Ghosts and chat.** Invisible ghosts that can walk; General/Wolf/Ghost channels with the GDD visibility rules; leave-anytime with rewards kept.
7. **End of match.** Scoreboard revealing roles, likes (not self), MVP +20%, reward calculation (GDD §13), teleport back to the lobby.
8. **Lobby place.** I will create the second place and open it for you. Build the hub, 2× Casual 12/12 pads and 2× Turbo 6/6 pads with live counters, and the matchmaking teleport. Add the left UI (Shop / Role / Monster / Settings) and the right UI (News / Codes / Pass / Daily Spin).
9. **Data and economy.**
   - DataStore profiles, player level, mastery → diamonds.
   - Role shop (coin / Robux / diamond, level gates), skins shop.
   - Season Pass (free/premium tracks, +10 levels on premium, post-60 rules), Daily Spin (exact odds and duplicate rules), Codes.
   - Robux products: give me the exact list of Game Passes / Developer Products to create, with prices, and wait for my IDs.
10. **Polish.** EN/TH localization pass, mobile/console controls check, audio hookup, performance check (streaming, part counts), final export.

### Things only I (the owner) can do
When you reach one of these, stop and tell me exactly what to do, step by step in Thai:
- Publish animations
- Pick sound IDs
- Create Game Passes / Developer Products
- Enable voice chat
- Create the Lobby place
- Publish the game
- Run multi-player tests (Studio → Test → Clients and Servers)

Start with Milestone 0 now.
