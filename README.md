# Wolf Village

Roblox social-deduction game — "friendly-looking but not so friendly".
The full design is in [`GDD.md`](GDD.md) (Thai). It is the source of truth.

## How this project works

- **Roblox Studio is where the game runs. This repo is the backup and history.**
  Scripts are written in Studio through the Roblox Studio MCP server and
  exported here after every milestone (no Rojo).
- Everything physical (map, houses, rigs, UI) is created by **builder scripts**
  in `build/`, so the world can always be rebuilt from this repo alone.
- Every gameplay number lives in one module:
  `src/ReplicatedStorage/Shared/Config.luau`.

## Setup (owner's machine)

1. Install Claude Code and Roblox Studio.
2. In this folder: `claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest`,
   then install the Studio plugin from the `robloxstudio-mcp` README.
3. Open the **Match place** in Studio. Game Settings → Security: enable
   *Allow HTTP Requests* and *Enable Studio Access to API Services*.
4. Turn the MCP plugin on in Studio, then run `claude` in this folder.

### Rebuilding the world in Studio

With `src/` imported into Studio, run the builders in this order (command bar
or the MCP "run code" tool):

1. `build/BuildVillage.luau` — whole map under `Workspace.Map`
2. `build/BuildLighting.luau` — Lighting + Day preset
3. `build/BuildLocalization.luau` — en/th `LocalizationTable`

All builders are idempotent: they delete what they built before and rebuild it.

## Folder map

| Path | What it is |
|---|---|
| `GDD.md` | Game design document (Thai) |
| `docs/OWNER_TODO.md` | Things only the owner can do: sound IDs, Robux products, open questions (Thai) |
| `docs/CLAUDE_CODE_PROMPT.md` | The working agreement / milestone plan |
| `src/` | Every script, mirroring the DataModel path |
| `src/ReplicatedStorage/Shared/Config.luau` | All tunable numbers and asset-ID placeholders |
| `src/ReplicatedStorage/Shared/Strings.luau` | All player-facing text (en + th) |
| `src/ReplicatedStorage/Shared/Rng.luau` | Random interface (seedable for tests) |
| `src/ReplicatedStorage/Shared/Logic/` | Pure shared rules: round phases, levels / Season Pass |
| `src/ServerScriptService/Logic/` | Pure server rules: role assignment, voting, win conditions, rewards, loot, wolf pup |
| `src/ServerScriptService/Services/` | Server services (from milestone 2) |
| `src/StarterPlayer/StarterPlayerScripts/` | Client scripts (from milestone 2) |
| `build/` | Builder scripts that create the map, lighting, localization table |
| `tests/` | Offline tests for the rules and for the map contract |
| `tools/` | Offline tooling (optional, see below) |

Script file suffixes: `.server.luau` = Script, `.client.luau` = LocalScript,
`.luau` = ModuleScript.

## Offline checks (optional, no Studio needed)

The rule modules are pure Luau and the builders only use plain Instance APIs,
so both can be run outside Studio with [Lune](https://github.com/lune-org/lune):

```
lune run tools/test.luau         # rule tests + map contract tests
lune run tools/build_place.luau  # runs build/ and writes out/WolfVillage.rbxl
tools/check.sh                   # both, plus a luau-lsp type check if available
```

`out/WolfVillage.rbxl` opens in Roblox Studio and contains the generated map
and every script in `src/`. It is a convenience preview; `out/` is not committed.

## Milestones

0. Setup · 1. Map · 2. Core loop · 3. Wolf side · 4. Roles · 5. Tasks, items,
crate · 6. Ghosts and chat · 7. End of match · 8. Lobby place · 9. Data and
economy · 10. Polish. Each one ends with an export to `src/`, a commit, and a
test checklist for the owner.
