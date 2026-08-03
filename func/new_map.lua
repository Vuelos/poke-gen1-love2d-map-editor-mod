-- New map creation dialog: inline W/H/Dir spinner with white background,
-- map preview rectangle, and bidirectional warp connection.  Also used to
-- create a destination map for a new map connection (direction locked,
-- no warps).

local NewMap = {}
local NewMapDialog = require("mods.map_editor.renderer.new_map_dialog")
local Neighbors = require("mods.map_editor.func.neighbors")

-- Opposite connection side, used when a new map lands flush against an
-- existing map and a reciprocal connection is added to the neighbour.
local RECIP = { north = "south", south = "north", east = "west", west = "east" }

-- Opens the inline new-map dialog.  `lockDir` optionally pins the direction
-- (a connection's chosen side) and hides the Dir field; when set, confirming
-- links the pending connection to the freshly created map instead of adding
-- warps.  The dialog runs in two steps: first a unique name is chosen, then
-- width/height/direction are edited.  The name is pre-filled with a fresh
-- unique default, so just confirming it proceeds straight to dimensions.
function NewMap.newMapDialog(self, lockDir)
  local dir = lockDir
  if dir == "north" then dir = "N"
  elseif dir == "south" then dir = "S"
  elseif dir == "east" then dir = "E"
  elseif dir == "west" then dir = "W"
  end
  self._newMapState = {
    step = "name", editField = "w", width = 10, height = 10,
    dir = dir or "N", showPreview = true, lockDir = dir ~= nil,
    name = NewMap.uniqueMapName(self.data, "NEW_MAP"),
  }
  self:_newMapNameStep()
end

-- True when `name` is already used as another map's display name (a map's
-- display name is its `name` field, falling back to its id).
function NewMap.isMapNameUsed(data, name, excludeId)
  for id, def in pairs(data.maps or {}) do
    if id ~= excludeId and (def.name or id) == name then return true end
  end
  return false
end

-- Returns a display name based on `base` (default "NEW_MAP") that no map
-- uses yet: "NEW_MAP", "NEW_MAP_2", "NEW_MAP_3", ...
function NewMap.uniqueMapName(data, base)
  base = (base ~= nil and base ~= "") and base or "NEW_MAP"
  local name = base
  local n = 1
  while NewMap.isMapNameUsed(data, name) do
    n = n + 1
    name = base .. "_" .. n
  end
  return name
end

-- Picks a fresh id next to this map's id, then creates the map definition
-- in data.maps (empty block grid filled with the border block) and returns
-- the new id.  The display name is `name` (validated for uniqueness, falling
-- back to a fresh "NEW_MAP" when empty/duplicated).
function NewMap.createNewMap(self, width, height, name)
  local data = self.data
  data.maps = data.maps or {}
  local border = self.def.borderBlock or 0
  local blocks = {}
  for i = 1, width * height do blocks[i] = border end
  local newId = self.mapId .. "_EXT"
  local n = 1
  while data.maps[newId] do
    n = n + 1
    newId = self.mapId .. "_EXT" .. n
  end
  local newName = (name ~= nil and name ~= "") and name or "NEW_MAP"
  if NewMap.isMapNameUsed(data, newName, newId) then
    newName = NewMap.uniqueMapName(data, newName)
  end
  data.maps[newId] = {
    id = newId, name = newName, width = width, height = height,
    blocks = blocks, borderBlock = border,
    warps = {}, objects = {}, signs = {},
    tileset = self.def.tileset, palette = self.def.palette,
  }
  return newId
end

-- Shows a simple OK alert.  The editor has no toast/notification surface
-- yet, so the established one-item ListMenu dialog pattern is used.
function NewMap.showMessage(self, text)
  local menu = self.mod.ui.ListMenu.new(self.game, text, {
    { label = "OK", value = "ok" },
  }, {
    onChoose = function() self.game.stack:pop() end,
  })
  self.game.stack:push(menu)
end

-- Step 1 of the new-map dialog: pick a unique name.  Pushes the text input
-- dialog pre-filled with the default name.  Confirming a non-empty, unique
-- name moves the dialog to the dimensions step; an empty or duplicated name
-- reopens the input so a valid one is chosen; Escape cancels the whole
-- dialog.
function NewMap._newMapNameStep(self)
  local state = self._newMapState
  if not state then return end
  local TextInput = require("mods.map_editor.scene.text_input")
  local function open()
    local input = TextInput.new(self.game, {
      title = "Map name",
      maxLen = 32,
      initial = state.name or "",
      onDone = function(text)
        if text == nil then
          -- Cancelled: drop the pending connection flow (and the connection
          -- that was added speculatively before this dialog opened), so no
          -- orphan state is left behind.
          local pending = self._pendingConn
          self._pendingConn = nil
          if pending and pending.move and self.def.connections then
            self.def.connections[pending.dir] = nil
          end
          self._newMapState = nil
          return
        end
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" or NewMap.isMapNameUsed(self.data, text) then
          open()
          return
        end
        state.name = text
        state.step = "dims"
      end,
    })
    self.game.stack:push(input)
  end
  open()
end

function NewMap._newMapConfirm(self)
  local state = self._newMapState
  if not state or state.step ~= "dims" then return end

  -- When the new map is a connection's destination, probe where its body
  -- would land in the world layout before creating anything: an overlap
  -- with an existing map rejects the creation (nothing is created, so no
  -- orphan map is left behind), and a flush (0-gap) contact against
  -- another map becomes a reciprocal connection on both sides.
  local pending = self._pendingConn
  local flush
  if pending then
    local kind, probeId, probeSide, probeOff = Neighbors.probePlacement(
      self.data.maps, self.mapId, pending.dir, pending.conn.offset or 0,
      state.width, state.height)
    if kind == "overlap" then
      if pending.move and self.def.connections then
        -- The connection was added speculatively before the dialog opened;
        -- drop it so the map data stays clean.
        self.def.connections[pending.dir] = nil
      end
      self._pendingConn = nil
      self._newMapState = nil
      NewMap.showMessage(self, "New map would overlap an existing map")
      return
    end
    if kind == "flush" then
      flush = { id = probeId, side = probeSide, offset = probeOff }
    end
  end

  local newId = NewMap.createNewMap(self, state.width, state.height, state.name)

  if flush then
    local newDef = self.data.maps[newId]
    local otherDef = self.data.maps[flush.id]
    newDef.connections = newDef.connections or {}
    newDef.connections[flush.side] = { map = flush.id, offset = flush.offset }
    if otherDef then
      otherDef.connections = otherDef.connections or {}
      otherDef.connections[RECIP[flush.side]] = { map = newId, offset = -flush.offset }
    end
    self.mod.log:info("Auto-connected new map %s to %s (%s)", newId, flush.id, flush.side)
  end

  if self._pendingConn then
    -- New map is the destination of a connection: point the pending
    -- connection at it and hand off to moving/editing, no warps needed.
    local pending = self._pendingConn
    self._pendingConn = nil
    pending.conn.map = newId
    pending.conn.offset = 0
    self._selectedDir = pending.dir
    self._newMapState = nil
    self.mapChanged = true
    local EntityEditor = require("mods.map_editor.scene.entity_editor")
    if pending.move then
      EntityEditor.startMoving(self, "connection", pending.conn)
    else
      EntityEditor.editEntity(self, "connection", pending.conn)
    end
    return
  end

  local cx, cy
  if state.dir == "N" then cx = self.def.width; cy = 0
  elseif state.dir == "S" then cx = self.def.width; cy = self.def.height * 2 - 1
  elseif state.dir == "E" then cx = self.def.width * 2 - 1; cy = self.def.height
  else cx = 0; cy = self.def.height end
  table.insert(self.def.warps, { x = cx, y = cy, destMap = newId, destWarp = 1 })

  local rx, ry
  if state.dir == "N" then rx = state.width; ry = state.height * 2 - 1
  elseif state.dir == "S" then rx = state.width; ry = 0
  elseif state.dir == "E" then rx = 0; ry = state.height
  else rx = state.width * 2 - 1; ry = state.height end
  local newDef = self.data.maps[newId]
  table.insert(newDef.warps, { x = rx, y = ry, destMap = self.mapId, destWarp = #self.def.warps })

  self._newMapState = nil
  self.mapChanged = true
  self.mod.log:info("Created new map %s (%dx%d) connected %s", newId, state.width, state.height, state.dir)
end

function NewMap.drawNewMapDialog(self)
  NewMapDialog.draw(self)
end

return NewMap
