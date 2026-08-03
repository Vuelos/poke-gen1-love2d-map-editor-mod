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
| `Q` / `E` | Jump the palette cursor **10 rows** up/down (scaled by the grid: 3 columns for blocks, 4 for sprites). |
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

### Connections

Adding a connection (create picker → *Connection* → direction) asks where it
should point:

* **Existing map** — pick from the current maps.
* **Create new map** — opens the new-map dialog with the direction already
  locked in; enter a width/height and confirm. A brand-new map is created next
  to the current one (unique `_EXT` id, filled with the current border block)
  and the connection is pointed at it, ready to be positioned.

The new-map dialog runs in two steps: it first asks for a name (pre-filled
with a fresh unique default like `NEW_MAP`, `NEW_MAP_2`, …), then edits the
dimensions.  Duplicate map names are rejected (the input reopens), Escape
cancels, and entity names are checked for uniqueness within a map when
edited.  The name input arms `love.keyboard.setTextInput` while it is open so
typed characters actually reach the text field (and restores it on close);
the first keystroke replaces the prefilled default instead of appending to it,
so typing a custom name never leaves `NEW_MAP` glued to the front.  `Enter`
confirms, `Escape` cancels, `Backspace` edits, and the gamepad confirms with
`A` and cancels with `B`.  Digits typed into the field are plain text -- the
editor's `1`/`2`/`3` mode-switch keys are suppressed while the input is on
top, so a name like `CAVE2` types and confirms normally.  On the dimensions
step the keys are direct: `A`/`Left` shrink
width, `D`/`Right` grow width, `W`/`Up` grow height, `S`/`Down` shrink
height, and `Q`/`E` adjust the active numeric field by **±10**.  `Tab` moves
between W/H/Dir, and while `Dir` is active `Left`/`Right` cycle the
direction.  The gamepad mirrors these on the dimensions step too (`D-pad`,
`A` = confirm, `B` = cancel).  Connection silhouettes and their clickable
strips span the edited map's full edge (full width for N/S, full height for
W/E).

You can also repoint an existing connection: edit it → *Map* → **New map...**.
While a connection is being moved/positioned the camera keeps the edited map on
screen instead of chasing the silhouette off the opposite edge.

When a new map is a connection's destination, the editor checks where its body
would land in the world layout before creating anything:

* If it would **overlap** an existing map, the creation is rejected with an OK
  alert (and a brand-new connection added for the occasion is dropped again).
* If it lands **flush** (zero gap) against another map, that map gets a
  reciprocal connection pointing back at it automatically, with matching
  offsets, so the seam is traversable both ways.

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

The suites export their test lists to the shared runner; run everything from
the repo root:

```
luajit mods/map_editor/tests/test_all.lua
```

Each suite can also be run on its own (as a module definition) for a quick
smoke check of a single file by loading it first, but `test_all.lua` is the
canonical entry point.
