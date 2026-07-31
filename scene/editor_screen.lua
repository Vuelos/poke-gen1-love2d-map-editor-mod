-- Map editor screen: main editing UI.  Delegates most logic to sub-modules
-- (map_ops, camera, events, new_map, save, drawing, entity_editor).

local Save = require("mods.map_editor.func.save")
local Drawing = require("mods.map_editor.drawing")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local Undo = require("mods.map_editor.func.undo")
local Fill = require("mods.map_editor.func.fill")
local Common = require("mods.map_editor.func.common")
local TileRenderer = require("src.render.TileRenderer")
local PaletteFX = require("src.render.PaletteFX")
local FieldDefaults = require("src.world.FieldDefaults")

local MODES = Common.MODES
local BLOCK_PX = Common.BLOCK_PX
local Renderer = require("src.render.Renderer")

local EditorScreen = {}

-- Mixin methods from extracted sub-modules
local function mixin(t, src) for k, v in pairs(src) do t[k] = v end end
mixin(EditorScreen, require("mods.map_editor.func.map_ops"))
mixin(EditorScreen, require("mods.map_editor.func.camera"))
mixin(EditorScreen, require("mods.map_editor.func.events"))
mixin(EditorScreen, require("mods.map_editor.func.new_map"))

-- Builds a new EditorScreen for the given mod, game, and mapId.
-- Loads tileset, renderer, palette; initialises cursor, scroll, undo stack,
-- and takes an original-state snapshot for change tracking.
-- Returns nil if the map or tileset cannot be loaded.
function EditorScreen.new(mod, game, mapId)
  local data = game.data
  local def = data.maps[mapId]
  if not def then return nil end
  local tileset = data.tilesets[def.tileset]
  if not tileset then return nil end

  local MapLoader = require("src.world.MapLoader")
  local map = MapLoader.load(data, mapId)
  if not map or not map.renderer then return nil end

  local self = {
    mod = mod, game = game, data = data,
    mapId = mapId, def = def, tileset = tileset,
    map = map,
    mode = MODES.MAP,
    cursorBx = 0, cursorBy = 0,
    scrollX = 0, scrollY = 0,
    selectedBlock = 1,
    paletteOffset = 0,
    showPalette = true,
    showHelp = false,
    showGrid = false,
    mapChanged = false,
    undo = Undo.new(),
    originalBlocks = nil,
    originalWidth = nil,
    originalHeight = nil,
    font = mod.ui.Font,
    isOpaque = true,
    mapW = def.width * BLOCK_PX, mapH = def.height * BLOCK_PX,
    paletteColors = nil,
    brushSize = 1,
    neighbors = {},
    neighborMaps = {},
    neighborOriginals = {},
    neighborDirty = {},
    sgbPalettes = function(self)
      if PaletteFX.usesGbcPack() then return {} end
      local ow = self.game.overworld
      return ow and ow.sgbPalettes and ow:sgbPalettes(self.game) or nil
    end,
  }

  TileRenderer.tick(0)

  local palettes = FieldDefaults.field(data, "palettes")
  local palName = def.palette
  if not palName then palName = palettes.byMap and palettes.byMap[mapId] end
  if not palName then palName = palettes.byTileset and palettes.byTileset[def.tileset] end
  if not palName then
    for _, row in ipairs(palettes.byPrefix or {}) do
      if row.prefix and mapId:find(row.prefix, 1, true) == 1 then
        palName = row.palette; break
      end
    end
  end
  if not palName then palName = palettes.default end
  self.paletteColors = PaletteFX.pal(data, palName)

  setmetatable(self, { __index = EditorScreen })
  self:rebuildNeighbors()
  self:storeOriginal()
  return self
end

-- Loads and lays out the maps connected to this one (BFS over the
-- connection graph, mirroring the runtime survey zoom) so MAP mode can
-- draw and edit across the seams.  Rebuilt whenever the connection graph
-- can change: on entry, after a save (reconciliation rewrites return
-- offsets), and after an undo/redo that restored a different layout.
function EditorScreen:rebuildNeighbors()
  local Neighbors = require("mods.map_editor.func.neighbors")
  local MapLoader = require("src.world.MapLoader")
  local list, byId = {}, {}
  for _, n in ipairs(Neighbors.compute(self.data.maps, self.mapId, 2)) do
    local ok, m = pcall(MapLoader.load, self.data, n.id)
    if ok and m and m.renderer and m.def then
      byId[n.id] = m
      table.insert(list, {
        id = n.id, ox = n.ox, oy = n.oy,
        def = m.def, map = m,
        tileset = self.data.tilesets[m.def.tileset],
      })
    end
  end
  self.neighbors = list
  self.neighborMaps = byId
  self:refreshNeighborOriginals()
end

-- Snapshots the current state of every laid-out neighbor so tile edits
-- can be diffed on save and restored on an unsaved exit.  Runs whenever
-- the neighbor set is (re)built; a save re-captures so the diff baseline
-- tracks only what moved since the last save.
function EditorScreen:refreshNeighborOriginals()
  self.neighborOriginals = {}
  for _, nb in ipairs(self.neighbors or {}) do
    local d = nb.def
    self.neighborOriginals[nb.id] = {
      blocks = Common.deepCopy(d.blocks),
      warps = Common.deepCopy(d.warps),
      objects = Common.deepCopy(d.objects),
      signs = Common.deepCopy(d.signs),
      borderBlock = d.borderBlock,
      width = d.width, height = d.height,
      textDefs = Common.deepCopy(d.textDefs),
      connections = Common.deepCopy(d.connections),
    }
  end
end

-- Persists patches for every neighbor map that received tile edits since
-- the last save, diffed against the originals captured when the neighbor
-- set was last rebuilt.  Merges field-by-field so a connection patch
-- written by reconciliation on the same map survives.
function EditorScreen:persistNeighborPatches()
  local Save2 = require("mods.map_editor.func.save")
  for nbId in pairs(self.neighborDirty or {}) do
    local m = self.neighborMaps and self.neighborMaps[nbId]
    local orig = self.neighborOriginals and self.neighborOriginals[nbId]
    if m and m.def and orig then
      local patch = Save2.buildPatch(m.def, {
        blocks = orig.blocks, warps = orig.warps, objects = orig.objects,
        signs = orig.signs, borderBlock = orig.borderBlock,
        width = orig.width, height = orig.height,
        textDefs = orig.textDefs, connections = orig.connections,
      })
      if next(patch) then
        for key, value in pairs(patch) do
          Save2.updatePatchField(self.mod, nbId, key, value)
        end
      end
    end
  end
  self.neighborDirty = {}
end

-- Reloads the map renderer from data and refreshes the original snapshot.
function EditorScreen:reloadMap()
  local MapLoader = require("src.world.MapLoader")
  MapLoader.invalidate(self.mapId)
  self.map = MapLoader.load(self.data, self.mapId)
  TileRenderer.tick(0)
  self:storeOriginal()
end

-- Called when the screen is entered: applies any saved patches, rebuilds
-- the renderer, and hooks mouse events.
function EditorScreen:enter()
  local patches = Save.getPatches(self.mod)
  local patch = patches[self.mapId]
  if patch then
    for key, value in pairs(patch) do
      if key == "blocks" then
        for i, v in ipairs(value) do
          if self.def.blocks[i] ~= nil then self.def.blocks[i] = v end
        end
      elseif key ~= "id" then
        self.def[key] = value
      end
    end
  end

  if self.def.connections then
      Save.applyConnectionPatches({
          [self.mapId] = self.def.connections
      }, self.data)
  end  
  
  -- Inject custom text defs into game data so they resolve correctly
  if self.def.textDefs and self.data then
    for _, td in ipairs(self.def.textDefs) do
      if not self.data.text_pointers[self.mapId] then
        self.data.text_pointers[self.mapId] = {}
      end
      self.data.text_pointers[self.mapId][td.const] = { text = td.key }
      self.data.text[td.key] = td.text
    end
  end
  -- Apply encounter patches
  local encPatches = Save.getEncounterPatches(self.mod)
  local encPatch = encPatches and encPatches[self.mapId]
  if encPatch and self.data then
    self.data.encounters = self.data.encounters or {}
    self.data.encounters[self.mapId] = encPatch
  end
  self.map.renderer:rebuild()
  -- Re-derive the neighbor layout now that persisted patches are applied
  -- (connections may have moved the strip offsets).
  self:rebuildNeighbors()
  -- Re-snapshot after applying persisted patches so the restore target on
  -- exit is the last saved state, not the pre-patch data.
  self:storeOriginal()
end

  -- Called when the screen is exited: restores original game data if changes
  -- were made but not saved, preventing in-place modifications from leaking
  -- into the game runtime.  Dimensions and blocks are restored together so
  -- the block array always matches width*height.
  function EditorScreen:exit()
    if self.mapChanged and self.originalBlocks then
      self.def.blocks = self.originalBlocks
      self.def.warps = Common.deepCopy(self.originalWarps)
      self.def.objects = Common.deepCopy(self.originalObjects)
      self.def.signs = Common.deepCopy(self.originalSigns)
      self.def.connections = Common.deepCopy(self.originalConnections or {})
      self.def.width = self.originalWidth
      self.def.height = self.originalHeight
      self.def.borderBlock = self.originalBorder
      self.def.textDefs = Common.deepCopy(self.originalTextDefs or {})
      if self.data then
        -- Restore reciprocal connections the expansion reconciliation
        -- rewrote on connected maps.
        if self.data.maps then
          for otherId, otherConns in pairs(self.originalRecipConnections or {}) do
            local otherDef = self.data.maps[otherId]
            if otherDef then
              otherDef.connections = Common.deepCopy(otherConns)
            end
          end
        end
        if self.originalEncounters then
          self.data.encounters = self.data.encounters or {}
          self.data.encounters[self.mapId] = Common.deepCopy(self.originalEncounters)
        elseif self.data.encounters then
          self.data.encounters[self.mapId] = nil
        end
        -- Remove editor-injected custom text that was never saved, then
        -- re-inject the original defs so saved custom text still resolves.
        local origDefs = self.originalTextDefs or {}
        local function inOrig(v, field)
          for _, td in ipairs(origDefs) do if td[field] == v then return true end end
          return false
        end
        if self.data.text_pointers then
          for _, label in ipairs({ self.mapId, self.def and self.def.label }) do
            local perMap = label and self.data.text_pointers[label]
            if perMap then
              for k in pairs(perMap) do
                if k:find("^TEXT_EDITOR_") and not inOrig(k, "const") then perMap[k] = nil end
              end
            end
          end
        end
        if self.data.text then
          for k in pairs(self.data.text) do
            if k:find("^map_editor_") and not inOrig(k, "key") then self.data.text[k] = nil end
          end
        end
        for _, td in ipairs(origDefs) do
          if not self.data.text_pointers[self.mapId] then self.data.text_pointers[self.mapId] = {} end
          self.data.text_pointers[self.mapId][td.const] = { text = td.key }
          self.data.text[td.key] = td.text
        end
      end
      -- Restore any connected maps whose tiles were edited but not saved,
      -- and drop their renderer cache so the runtime re-reads the restored
      -- blocks instead of drawing a stale window batch.
      local NeighborMapLoader = require("src.world.MapLoader")
      for nbId in pairs(self.neighborDirty or {}) do
        local m = self.neighborMaps and self.neighborMaps[nbId]
        local orig = self.neighborOriginals and self.neighborOriginals[nbId]
        if m and m.def and orig then
          m.def.width = orig.width
          m.def.height = orig.height
          m.def.blocks = Common.deepCopy(orig.blocks)
          m.def.warps = Common.deepCopy(orig.warps)
          m.def.objects = Common.deepCopy(orig.objects)
          m.def.signs = Common.deepCopy(orig.signs)
          m.def.borderBlock = orig.borderBlock
          m.def.textDefs = Common.deepCopy(orig.textDefs)
          m.def.connections = Common.deepCopy(orig.connections)
        end
        NeighborMapLoader.invalidate(nbId)
      end
      local invalidated = false
      local world = self.mod.world
      if world and world.invalidateMap then
        invalidated = world:invalidateMap(self.mapId) ~= nil
      end
      if not invalidated then
        local MapLoader = require("src.world.MapLoader")
        MapLoader.invalidate(self.mapId)
      end
    end
  end

-- Builds a patch of only the changed fields and saves it via the Save
-- module.  Reloads the map to reflect the persisted state.
function EditorScreen:savePatches()
  local patch = Save.buildPatch(self.def, {
    blocks = self.originalBlocks, warps = self.originalWarps,
    objects = self.originalObjects, signs = self.originalSigns,
    borderBlock = self.originalBorder, width = self.originalWidth, height = self.originalHeight,
    textDefs = self.originalTextDefs, connections = self.originalConnections,
  })
  Save.savePatch(self.mod, self.mapId, patch)
  -- An expansion shifts this map's connection offsets; keep the connected
  -- maps' return connections mirroring them (and persist those patches).
  self:reconcileReciprocalConnections()
  -- Persist tile edits made across the seams into connected maps.
  self:persistNeighborPatches()
  -- Resync the live world: pooled NPCs for this map keep their pre-edit
  -- positions while the def's objects moved, and after an expansion the
  -- player must translate with the content.  Do this before invalidateMap
  -- so the reload respawns the NPCs from the edited def.
  local world = self.mod.world
  local shiftX = (self.expandShiftL or 0) * 2
  local shiftY = (self.expandShiftT or 0) * 2
  if world and world.rebaseMap
     and (patch.objects ~= nil or shiftX ~= 0 or shiftY ~= 0) then
    world:rebaseMap(self.mapId, shiftX, shiftY)
  end
  local invalidated = false
  if world and world.invalidateMap then
    invalidated = world:invalidateMap(self.mapId) ~= nil
  end
  if not invalidated then
    local MapLoader = require("src.world.MapLoader")
    MapLoader.invalidate(self.mapId)
  end
  self.map = require("src.world.MapLoader").load(self.data, self.mapId)
  TileRenderer.tick(0)
  -- Re-inject custom text defs into the fresh game data after reload
  if self.def.textDefs and self.data then
    for _, td in ipairs(self.def.textDefs) do
      if not self.data.text_pointers[self.mapId] then
        self.data.text_pointers[self.mapId] = {}
      end
      self.data.text_pointers[self.mapId][td.const] = { text = td.key }
      self.data.text[td.key] = td.text
    end
  end
  -- Save encounter patch
  local currentEnc = self.data and self.data.encounters and self.data.encounters[self.mapId]
  if not Common.tablesEqual(currentEnc, self.originalEncounters) then
    if currentEnc then
      Save.saveEncounterPatch(self.mod, self.mapId, Common.deepCopy(currentEnc))
    else
      Save.removeEncounterPatch(self.mod, self.mapId)
    end
  end
  -- Re-derive the neighbor layout now that the offsets may have moved, and
  -- re-capture its originals so the next save diffs against this state.
  self:rebuildNeighbors()
  self:storeOriginal(); self.mapChanged = false
  self.map.renderer:rebuild()
end

-- Exports the current patch as a Lua file on disk, suitable for use as
-- a mod override script.
function EditorScreen:exportPatches()
  local patch = Save.buildPatch(self.def, {
    blocks = self.originalBlocks, warps = self.originalWarps,
    objects = self.originalObjects, signs = self.originalSigns,
    borderBlock = self.originalBorder, width = self.originalWidth, height = self.originalHeight,
    textDefs = self.originalTextDefs, connections = self.originalConnections,
  })
  local lua = {"-- Map editor export for " .. self.mapId, "return {"}
  for key, value in pairs(patch) do
    if key == "blocks" then
      lua[#lua + 1] = "  blocks = {"
      local parts = {}
      for _, v in ipairs(value) do parts[#parts + 1] = tostring(v) end
      lua[#lua + 1] = "    " .. table.concat(parts, ", "); lua[#lua + 1] = "  },"
    elseif type(value) == "table" then
      local ok, enc = pcall(require("src.mods.Merge").encode, value)
      lua[#lua + 1] = "  " .. key .. " = " .. (ok and enc or "{}") .. ","
    else
      lua[#lua + 1] = "  " .. key .. " = " .. tostring(value) .. ","
    end
  end
  lua[#lua + 1] = "}"
  local text = table.concat(lua, "\n")
  local path = Save.writeFile(self.mapId, text)
  self.mod.log:info("Exported %s patches to %s", self.mapId, path)
end

-- Called every frame to keep the tile renderer and scroll clamp updated.
function EditorScreen:update()
  TileRenderer.tick(0)
  self:clampScroll()
end

-- Fullscreen canvas: instead of the classic 160x144 GB rectangle, the
-- editor requests a UI surface that fills the window at the crisp integer
-- fit scale (bounded by the renderer's caps).  Game:draw applies this while
-- the editor is the top state; sub-menus on the stack fall back to the
-- classic surface and the editor adapts by reading the live size each frame.
function EditorScreen:uiSize()
  local pw, ph = love.graphics.getDimensions()
  if love.graphics.getPixelDimensions then pw, ph = love.graphics.getPixelDimensions() end
  local S = math.max(1, math.ceil(math.max(
    pw / Renderer.MAX_UI_WIDTH, ph / Renderer.MAX_UI_HEIGHT)))
  local w = math.max(Renderer.WIDTH, math.floor(pw / S))
  local h = math.max(Renderer.HEIGHT, math.floor(ph / S))
  return math.min(w, Renderer.MAX_UI_WIDTH), math.min(h, Renderer.MAX_UI_HEIGHT)
end

-- Renders the editor: map tiles, grid, entity markers, cursor, palette,
-- mode bar, and help overlay.
function EditorScreen:draw()
  local renderer = self.map.renderer
  local vw, vh = Renderer:uiSize()
  if not renderer then
    love.graphics.setColor(0, 0, 0, 1); love.graphics.rectangle("fill", 0, 0, vw, vh)
    love.graphics.setColor(1, 1, 1, 1)
    self.font.draw("MAP EDITOR", 40, 30)
    self.font.draw(self.mapId, 40, 50); return
  end

  self.viewW, self.viewH = vw, vh
  local palW = self.showPalette and self.mode ~= MODES.ENC and Common.PAL_W or 0
  local mapViewW = vw - palW
  local viewH = vh - 8

  -- Opaque backdrop so the overworld world-pass never shows through gaps
  -- between the viewport, palette, and mode bar on the fullscreen canvas.
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, vw, vh)
  love.graphics.setColor(1, 1, 1, 1)

  love.graphics.setScissor(0, 8, mapViewW, viewH)
  Drawing.drawMap(self)
  love.graphics.setScissor(0, 8, mapViewW, viewH)
  Drawing.drawGrid(self)

  if self.mode == MODES.ENT then
    Drawing.drawEntityMarkers(self)
  end
  Drawing.drawCursor(self)

  -- New map preview rectangle
  if self._newMapState and self._newMapState.showPreview then
    local s = self._newMapState
    local bw = self.def.width * 32
    local bh = self.def.height * 32
    local pw = s.width * 32
    local ph = s.height * 32
    local px, py
    if s.dir == "N" then
      px = (bw - pw) / 2; py = -ph
    elseif s.dir == "S" then
      px = (bw - pw) / 2; py = bh
    elseif s.dir == "E" then
      px = bw; py = (bh - ph) / 2
    else
      px = -pw; py = (bh - ph) / 2
    end
    love.graphics.setColor(0, 1, 0, 0.35)
    love.graphics.rectangle("fill", px - self.scrollX, py - self.scrollY, pw, ph)
    love.graphics.setColor(0, 1, 0, 0.8)
    love.graphics.rectangle("line", px - self.scrollX, py - self.scrollY, pw, ph)
    love.graphics.setColor(1, 1, 1, 1)
  end

  love.graphics.setScissor()

  if self.showPalette then Drawing.drawPalette(self, mapViewW) end

  Drawing.drawModeBar(self)
  -- Coordinates at bottom-left
  love.graphics.setColor(0.6, 0.6, 0.6, 1)
  self.font.draw(("%d,%d"):format(self.cursorBx, self.cursorBy), 0, viewH)
  if self.mapChanged then
    love.graphics.setColor(1, 0.8, 0.2, 1)
    self.font.draw("!", 50, viewH)
  end
  love.graphics.setColor(1, 1, 1, 1)

  if self._newMapState and self._newMapState.editField then self:drawNewMapDialog() end

  if self.showHelp then
    Drawing.drawHelp(self)
  end
end

return EditorScreen