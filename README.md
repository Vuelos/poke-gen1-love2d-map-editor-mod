Map editor mod for https://github.com/bryanthaboi/gen1recomp

F6 to open the editor
H for commands info

Mostly vivecoded

WARNING! Save after editing the map so you dont got stuck on a solid block or outside the map.

---

## Overview

The map editor lets you edit the overworld **maps, entities and encounters** of the
current game save at runtime, without touching the ROM. Changes are stored as
patches on the save file (`Ctrl+S`) and auto-applied whenever that save loads, or
can be exported as Lua data into the mod folder (`Ctrl+E`) to be shared, or imported into current save (`Ctrl+I`)

## Opening the editor

* **F6** — open the editor on the map the player is currently standing on.

## Modes

Switch with the number keys **1 / 2 / 3** (also works from sub-menus).

| Key | Mode | What you edit |
|-----|------|---------------|
| `1` | **MAP** | Tiles/blocks. Paint, revert, select, expand. |
| `2` | **ENT** | Entities: warps, objects (NPC / item / trainer), signs, connections. |
| `3` | **ENC** | Encounters: encounter rates and species/level slots. |

The mode bar highlights the active mode. A **`!`** marker (bottom-left, next to the
cursor coordinates) means the map has unsaved changes.

## Controls

### Map view (all modes)

| Keys | Action |
|------|--------|
| `Arrows` / `WASD` | Move cursor (MAP steps by 2 cells = one block; ENT/ENC by 1). |
| `Enter` / `Space` | MAP: paint selected block. ENT: edit entity, or create-picker on an empty tile. ENC: open encounter editor. |
| `R` | MAP: revert block under cursor to its original state. |
| `F` | MAP: copy the block under the cursor into the selected block. |
| `G` | Toggle the block grid overlay. |
| `H` | Toggle this help screen. |
| `Esc` | Close sub-menu / the editor. |

### Global

| Keys | Action |
|------|--------|
| `Ctrl+S` | Save patches for the current map onto the current save. |
| `Ctrl+E` | Export **all** map edits to `mods/<mod>/map_edits/patches.lua`. |
| `Ctrl+I` | Import map edits from `mods/<mod>/map_edits/patches.lua`. |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo (captures block paints, reverts, expansions, entity edits, connection shifts). |

### Palette (Tab to focus)

| Keys | Action |
|------|--------|
| `Tab` | Give/remove input focus from the palette panel. |
| `Arrows` / `WASD` | Move the palette cursor (yellow box, same size as the red selection box). |
| `Enter` / `Space` | Select the item under the palette cursor. |
| `Esc` | Remove palette focus. |
| `G` / `H` | Grid / help toggles still work. |

## MAP mode — blocks

* The palette shows the tileset's blocks in a **3-column** grid.
* **Paint** (`Enter`) writes the selected block; painting past an edge
  **auto-expands the map** in that direction and fills the new area with the
  currently **selected block** (not the border block).
* Expansion also shifts warps/objects/signs and connection offsets to match, and
  updates the reciprocal connections on connected maps so seams stay aligned.
* **Revert** (`R`) restores a block to its original persisted state.
* **Select** (`F`) picks the block under the cursor as the current selection.

## ENT mode — entities

Q/E cycle through all entities on the map (warps → objects → signs → connections),
moving the cursor to each one. `Enter` on an entity opens its edit menu; `Enter` on
empty ground opens a create picker.

Editable per type:

* **Warp** — Move, destination map, destination warp, Delete.
* **Object (NPC/item/trainer)** — Move, Sprite, **Name** (free text input),
  Item, Class, Party index, Movement, Range, Text, Delete.
* **Sign** — Move, Text, Delete.
* **Connection** — Move (offset), Map, Delete.

## ENC mode — encounters

`3` (or `Enter` in ENC) opens the encounter list for the map. Rows show the
encounter rate and each species slot with its level.

* **Left / Right** — adjust the value by **±1**.
* **Q / E** — adjust the value by **±10**.
* Rate and level both clamp to a **0–100** range.
* `Enter` on a slot row opens the species picker (full species list, sorted;
  **Q/E page** through it).

## Cross-seam editing

In MAP mode, all maps connected to the edited one are laid out around it so you can
paint straight across seams. Painting over a neighbor's body edits that map; the
edited map always wins inside its own body. Neighbor edits are tracked and saved
with `Ctrl+S` too (unsaved neighbor edits are reverted when you leave).

## Persistence & safety

* **Save** (`Ctrl+S`) writes a diff against the map's original state into the
  save's patch table. Patches are re-applied on `save.loaded`, so edits survive
  restarting the game.
* **Export** (`Ctrl+E`) writes every map's patches + encounter changes to
  `mods/<mod>/map_edits/patches.lua`; **Import** (`Ctrl+I`) reads that file back
  into the live data.
* **Exit without saving** restores the original map data, including reciprocal
  connections and encounter tables, so the running game is never left mutated.
* Custom entity text and encounter patches are handled separately from block/object
  patches and are also undone/restored on unsaved exit.

> Tip: always `Ctrl+S` after resizing/expanding a map so you don't end up stuck on a
> solid block or outside the map on the next boot.

### How the runtime patches work

The mod is self-contained — it does not modify `src/core/Input.lua`,
`src/ui/ListMenu.lua` or `src/world/WorldAPI.lua`. Instead `func/patch_core.lua`
patches them at mod load:

* **Input** — maps `q`→`pageUp` and `e`→`pageDown`. This is hooked through
  `Input.applyBindings` so the mapping survives every bindings rebuild (init,
  options changes, rebinds).
* **ListMenu** — the `update` loop handles `qePage` lists: `Q/E` fire per-row
  `onPageUp`/`onPageDown` handlers when present, otherwise page the cursor; rows
  can also expose `onLeft`/`onRight` for ±N adjustments.
* **WorldAPI** — adds `rebaseMap(mapId, shiftX, shiftY)` so the runtime repositions
  the player after a map expansion is saved.

### Running the tests

```
luajit mods/map_editor/tests/map_editor_tests.lua
luajit mods/map_editor/tests/editor_screen_tests.lua
```
