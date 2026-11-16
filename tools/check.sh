#!/usr/bin/env bash
# Offline checks: rule tests + map build (Lune), then type check (luau-lsp, optional).
# Usage:  tools/check.sh
# Tools:  LUNE (default "lune"), LUAU_LSP (default "luau-lsp"),
#         ROBLOX_TYPES = path to luau-lsp's globalTypes.d.luau
set -euo pipefail
cd "$(dirname "$0")/.."

LUNE="${LUNE:-lune}"
LUAU_LSP="${LUAU_LSP:-luau-lsp}"

"$LUNE" run tools/test.luau
"$LUNE" run tools/build_place.luau

if command -v "$LUAU_LSP" >/dev/null 2>&1 && [ -n "${ROBLOX_TYPES:-}" ]; then
	"$LUNE" run tools/sourcemap.luau
	"$LUAU_LSP" analyze --sourcemap sourcemap.json \
		--definitions "@roblox=$ROBLOX_TYPES" --base-luaurc .luaurc src build
	echo "type check passed"
else
	echo "type check skipped (set LUAU_LSP and ROBLOX_TYPES to enable)"
fi
