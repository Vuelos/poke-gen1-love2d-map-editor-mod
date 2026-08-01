-- Map editor scene: main editing UI.  Delegates most logic to sub-modules
-- (map_ops, camera, events, new_map, save, snapshot, editor_neighbors,
--  editor_session, editor_import_export, renderer, entity_editor).

local Save = require("mods.map_editor.func.save")
local Snapshot = require("mods.map_editor.func.snapshot")
local Drawing = require("mods.map_editor.renderer.drawing")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local Undo = require("mods.map_editor.func.undo")
local Fill = require("mods.map_editor.func.fill")
local Common = require("mods.map_editor.func.common")
local TileRenderer = require("src.render.TileRenderer")
local PaletteFX = require("src.render.PaletteFX")
local EditorNeighbors = require("mods.map_editor.func.editor_neighbors")
local EditorSession = require("mods.map_editor.func.editor_session")
local EditorImportExport = require("mods.map_editor.func.editor_import_export")

local MODES = Common.MODES
local BLOCK_PX = Common.BLOCK_PX
local CELL_PX = Common.CELL_PX
local Renderer = require("src.render.Renderer")

local MapEditor = {}

-- Mixin methods from extracted sub-modules
local function mixin(t, src) for k, v in pairs(src) do t[k] = v end end
mixin(MapEditor, require("mods.map_editor.func.map_ops"))
mixin(MapEditor, require("mods.map_editor.func.camera"))
mixin(MapEditor, require("mods.map_editor.func.events"))
mixin(MapEditor, require("mods.map_editor.func.new_map"))
mixin(MapEditor, EditorNeighbors)
mixin(MapEditor, EditorSession)
mixin(MapEditor, EditorImportExport)
mixin(MapEditor, require("mods.map_editor.scene.palette"))

-- Builds a new MapEditor for the given mod, game, and mapId.
-- Loads tileset, renderer, palette; initialises cursor, scroll, undo stack,
-- and takes an original-state snapshot for change tracking.
-- Returns nil if the map or tileset cannot be loaded.
function MapEditor.new(mod, game, mapId)
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
    paletteFocus = false,
    paletteCursorX = nil,
    paletteCursorY = nil,
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
    -- Per-map session state for maps that were edited as primary and then
    -- switched away from (via switchToMap): their pre-edit baselines and a
    -- dirty flag so Ctrl+S saves them and an unsaved exit restores them.
    _sessionOriginals = {},
    _sessionEncounters = {},
    _sessionDirty = {},
    sgbPalettes = function(self)
      if PaletteFX.usesGbcPack() then return {} end
      local ow = self.game.overworld
      return ow and ow.sgbPalettes and ow:sgbPalettes(self.game) or nil
    end,
    _spritePicker = nil,
    spriteList = nil,
  }

  if data.sprites then
    local list = {}
    for id in pairs(data.sprites) do list[#list + 1] = id end
    table.sort(list)
    self.spriteList = list
  end

  TileRenderer.tick(0)

  setmetatable(self, { __index = MapEditor })
  self:rebuildNeighbors()
  self:storeOriginal()
  return self
end

-- Reloads the map renderer from data and refreshes the original snapshot.
function MapEditor:reloadMap()
  local MapLoader = require("src.world.MapLoader")
  MapLoader.invalidate(self.mapId)
  self.map = MapLoader.load(self.data, self.mapId)
  TileRenderer.tick(0)
  self:storeOriginal()
end

-- Called when the screen is entered: applies any saved patches, rebuilds
-- the renderer, and hooks mouse events.
function MapEditor:enter()
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
  function MapEditor:exit()
    if self.mapChanged and self._originalSnapshot then
      Snapshot.restore(self.def, self._originalSnapshot)
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
        local origDefs = self._originalSnapshot.textDefs or {}
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
          Snapshot.restore(m.def, orig)
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
    -- Restore any maps that were focused and then switched away from without
    -- saving.  This runs even when the focused map itself was clean, so an
    -- unsaved exit still reverts the other edited maps.
    local SessionMapLoader = require("src.world.MapLoader")
    for mapId in pairs(self._sessionDirty or {}) do
      local orig = self._sessionOriginals and self._sessionOriginals[mapId]
      local def = self.data and self.data.maps and self.data.maps[mapId]
      if def and orig then
        Snapshot.restore(def, orig)
        local origEnc = self._sessionEncounters and self._sessionEncounters[mapId]
        if origEnc == nil then
          if self.data and self.data.encounters then self.data.encounters[mapId] = nil end
        else
          self.data.encounters = self.data.encounters or {}
          self.data.encounters[mapId] = Common.deepCopy(origEnc)
        end
        self:cleanupTextInjection(mapId, orig.textDefs)
        if SessionMapLoader and SessionMapLoader.invalidate then
          SessionMapLoader.invalidate(mapId)
        end
      end
    end
  end

-- Called every frame to keep the tile renderer and scroll clamp updated.
function MapEditor:update()
  TileRenderer.tick(0)
  self:clampScroll()
end

-- Fullscreen canvas: instead of the classic 160x144 GB rectangle, the
-- editor requests a UI surface that fills the window at the crisp integer
-- fit scale (bounded by the renderer's caps).  Game:draw applies this while
-- the editor is the top state; sub-menus on the stack fall back to the
-- classic surface and the editor adapts by reading the live size each frame.
function MapEditor:uiSize()
  local pw, ph = love.graphics.getDimensions()
  if love.graphics.getPixelDimensions then pw, ph = love.graphics.getPixelDimensions() end
  local S = math.max(1, math.ceil(math.max(
    pw / Renderer.MAX_UI_WIDTH, ph / Renderer.MAX_UI_HEIGHT)))
  local w = math.max(Renderer.WIDTH, math.floor(pw / S))
  local h = math.max(Renderer.HEIGHT, math.floor(ph / S))
  return math.min(w, Renderer.MAX_UI_WIDTH), math.min(h, Renderer.MAX_UI_HEIGHT)
end

-- Renders the editor: delegates to Drawing.drawMapEditor.
function MapEditor:draw()
  Drawing.drawMapEditor(self)
end

return MapEditor