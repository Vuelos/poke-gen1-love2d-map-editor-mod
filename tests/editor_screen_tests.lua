package.path = "../../../?.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local Data = require("src.core.Data")
Data:load()
local MapLoader = require("src.world.MapLoader")
local MAPS = Data.maps
local Snapshot = require("mods.map_editor.func.snapshot")
local Common = require("mods.map_editor.func.common")

local function createMapEditorMock()
  local def = MAPS.PALLET_TOWN
  local screen = {
    cursorBx = 32,
    cursorBy = 0,
    mode = 1,
    mapId = "PALLET_TOWN",
    def = def,
    data = Data,
    tileset = Data.tilesets[def.tileset],
    neighbors = {},
    neighborMaps = {},
    neighborOriginals = {},
    neighborDirty = {},
    _sessionOriginals = {},
    _sessionEncounters = {},
    _sessionDirty = {},
    paletteColors = {},
    mapChanged = false,
    expandShiftL = 0,
    expandShiftT = 0,
    selectedBlock = 0,
    showPalette = true,
    showHelp = false,
    showGrid = false,
    undo = nil,
    map = nil,
    mapW = 0,
    mapH = 0,
    _entityEditMenu = nil,
    _spritePicker = nil,
    _newMapState = nil,
    font = {
      draw = function() end,
      width = function() return 8 end,
    },
    mod = {
      ui = {
        ListMenu = {
          new = function(self, game, title, items, opts)
            return {
              title = title,
              items = items,
              onChoose = opts.onChoose or function() end,
              stack = {}
            }
          end
        }
      },
      log = {
        info = function() end,
        warn = function() end,
        error = function() end,
      },
      save = {
        get = function(self, key, def) return def end,
        set = function(self, key, v) end,
      }
    }
  }
  screen.map = MapLoader.load(Data, screen.mapId)
  local function mixin(t, src) for k, v in pairs(src) do t[k] = v end end
  mixin(screen, require("mods.map_editor.func.map_ops"))
  mixin(screen, require("mods.map_editor.func.editor_neighbors"))
  mixin(screen, require("mods.map_editor.func.editor_session"))
  return screen
end

function test_snapshotCapture()
  print("Testing Snapshot.capture...")
  local screen = createMapEditorMock()
  local orig = Snapshot.capture(screen.def)

  assert(type(orig) == "table", "Snapshot.capture should return a table")
  assert(Common.tablesEqual(orig.blocks, screen.def.blocks), "capture should copy blocks")
  assert(orig.width == screen.def.width, "capture should copy width")
  assert(orig.height == screen.def.height, "capture should copy height")
  assert(orig.borderBlock == screen.def.borderBlock, "capture should copy borderBlock")
  assert(type(orig.warps) == "table", "capture should copy warps")
  assert(type(orig.objects) == "table", "capture should copy objects")
  assert(type(orig.signs) == "table", "capture should copy signs")
  assert(orig.textDefs == nil or type(orig.textDefs) == "table", "capture should copy textDefs")
  assert(type(orig.connections) == "table", "capture should copy connections")

  print("Snapshot.capture test passed")
end

function test_storeOriginal()
  print("Testing storeOriginal...")
  local screen = createMapEditorMock()

  screen:storeOriginal()

  assert(screen._originalSnapshot ~= nil, "storeOriginal should set _originalSnapshot")
  assert(screen.originalRecipConnections ~= nil, "storeOriginal should set originalRecipConnections")
  assert(type(screen.paletteList) == "table" and #screen.paletteList > 0,
         "storeOriginal should fill paletteList")
  assert(type(screen.spriteList) == "table", "storeOriginal should set spriteList")

  print("storeOriginal test passed")
end

function test_mapPaletteColors()
  print("Testing mapPaletteColors...")
  local screen = createMapEditorMock()
  local palette = screen:mapPaletteColors()

  assert(type(palette) == "table", "mapPaletteColors should return a table")
  print("mapPaletteColors test passed")
end

function test_cleanupTextInjection()
  print("Testing cleanupTextInjection...")
  local screen = createMapEditorMock()

  local tp = screen.data.text_pointers or {}
  screen.data.text_pointers = tp
  local perMap = tp[screen.mapId] or {}
  tp[screen.mapId] = perMap
  screen.data.text = screen.data.text or {}

  local origDefs = { { const = "TEXT_EDITOR_KEEP", key = "map_editor_keep_text",
                        text = "keep" } }
  perMap.TEXT_EDITOR_KEEP = { text = "map_editor_keep_text" }
  screen.data.text["map_editor_keep_text"] = "keep"

  local junkDef = { const = "TEXT_EDITOR_JUNK", key = "map_editor_junk_text",
                    text = "junk" }
  perMap.TEXT_EDITOR_JUNK = { text = "map_editor_junk_text" }
  screen.data.text["map_editor_junk_text"] = "junk"

  screen:cleanupTextInjection(screen.mapId, origDefs)

  assert(perMap.TEXT_EDITOR_JUNK == nil, "cleanup should remove non-original TEXT_EDITOR_ pointers")
  assert(perMap.TEXT_EDITOR_KEEP ~= nil, "cleanup should keep original TEXT_EDITOR_ pointers")
  assert(screen.data.text["map_editor_keep_text"] == "keep", "cleanup should keep original text")
  assert(screen.data.text["map_editor_junk_text"] == nil, "cleanup should remove non-original text")

  print("cleanupTextInjection test passed")
end

function test_persistenceSessionMaps()
  print("Testing persistSessionMaps...")
  local screen = createMapEditorMock()

  screen:storeOriginal()

  screen.mapChanged = true
  screen._sessionDirty["PALLET_TOWN"] = true

  screen:persistSessionMaps()

  assert(screen._sessionDirty["PALLET_TOWN"] == nil, "persistSessionMaps should clear dirty flag")
  assert(screen._sessionOriginals["PALLET_TOWN"] ~= nil, "persistSessionMaps should set sessionOriginal")

  print("persistSessionMaps test passed")
end

function test_mapUnderCursor()
  print("Testing mapUnderCursor...")
  local screen = createMapEditorMock()
  local Neighbors = require("mods.map_editor.func.neighbors")
  screen.neighbors = Neighbors.compute(Data.maps, screen.mapId, 2)
  screen.neighborMaps = {}
  for _, nb in ipairs(screen.neighbors) do
    screen.neighborMaps[nb.id] = nb.def
  end

  screen.cursorBx = 2
  screen.cursorBy = -18

  local nb = screen:mapUnderCursor()
  if not nb then
    error("mapUnderCursor should return a neighbor when cursor is over a connection")
  end
  if nb.id ~= "ROUTE_1" then
    error("mapUnderCursor should resolve the map under the cursor, got " .. tostring(nb.id))
  end

  print("mapUnderCursor test passed")
end

function test_keyBehavior()
  print("Testing key behavior...")
  local screen = createMapEditorMock()

  local Neighbors = require("mods.map_editor.func.neighbors")
  screen.neighbors = Neighbors.compute(Data.maps, screen.mapId, 2)
  screen.neighborMaps = {}
  for _, nb in ipairs(screen.neighbors) do
    screen.neighborMaps[nb.id] = nb.def
  end

  screen.cursorBx = 2
  screen.cursorBy = -18
  screen.mode = 1

  local nb = screen:mapUnderCursor()
  if not nb then
    error("mapUnderCursor should detect the neighbor")
  end
  if nb.id ~= "ROUTE_1" then
    error("mapUnderCursor should resolve the map under the cursor, got " .. tostring(nb.id))
  end

  print("key behavior test passed")
end

-- Each suite exports { name, tests } and is run by test_all.lua.
return {
  name = "EDITOR_SCREEN",
  tests = {
    "test_snapshotCapture",
    "test_storeOriginal",
    "test_mapPaletteColors",
    "test_cleanupTextInjection",
    "test_persistenceSessionMaps",
    "test_mapUnderCursor",
    "test_keyBehavior",
  },
}