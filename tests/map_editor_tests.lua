package.path = "../../../?.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local Data = require("src.core.Data")
local MapLoader = require("src.world.MapLoader")
local MAPS = Data.maps

local function createMapEditorMock()
  local screen = {
    cursorBx = 32,
    cursorBy = 0,
    mode = 1,
    mapId = "PALLET_TOWN",
    def = MAPS.PALLET_TOWN,
    data = Data,
    neighbors = {},
    neighborMaps = {},
    neighborOriginals = {},
    neighborDirty = {},
    _sessionOriginals = {},
    _sessionEncounters = {},
    _sessionDirty = {},
    paletteColors = {},
    originalBlocks = {},
    originalWidth = 0,
    originalHeight = 0,
    originalWarps = {},
    originalObjects = {},
    originalSigns = {},
    originalBorder = 0,
    originalTextDefs = {},
    originalConnections = {},
    originalEncounters = {},
    originalRecipConnections = {},
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
    paletteList = {},
    spriteList = {},
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
  setmetatable(screen, { __index = screen })
  return screen
end

function test_mapEditorRename()
  print("Testing map_editor module rename...")
  local MapEditor = require("mods.map_editor.scene.map_editor")
  assert(type(MapEditor) == "table", "map_editor should return a table")
  assert(type(MapEditor.new) == "function", "map_editor should have a new function")
  print("map_editor rename test passed")
end

function test_drawingSceneFunctions()
  print("Testing Drawing scene-specific functions...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  assert(type(Drawing) == "table", "Drawing should be a table")
  assert(type(Drawing.drawMapEditor) == "function", "Drawing should have drawMapEditor")
  assert(type(Drawing.drawError) == "function", "Drawing should have drawError")
  assert(type(Drawing.drawBackdrop) == "function", "Drawing should have drawBackdrop")
  assert(type(Drawing.drawNewMapPreview) == "function", "Drawing should have drawNewMapPreview")
  assert(type(Drawing.drawCoordinates) == "function", "Drawing should have drawCoordinates")
  print("Drawing scene functions test passed")
end

function test_drawingDrawMapEditor()
  print("Testing Drawing.drawMapEditor...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local screen = {
    font = { draw = function() end, width = function() return 8 end },
    map = { renderer = nil },
    showPalette = false,
    mode = 1,
    showHelp = false,
    showGrid = false,
    cursorBx = 0,
    cursorBy = 0,
    mapChanged = false,
    _spritePicker = nil,
    _newMapState = nil,
  }
  local ok, err = pcall(function()
    Drawing.drawMapEditor(screen)
  end)
  assert(ok, "drawMapEditor should not error: " .. tostring(err))
  print("Drawing.drawMapEditor test passed")
end

function test_drawingDrawError()
  print("Testing Drawing.drawError...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local screen = {
    font = { draw = function() end, width = function() return 8 end },
    mapId = "TEST_MAP",
  }
  local ok, err = pcall(function()
    Drawing.drawError(screen)
  end)
  assert(ok, "drawError should not error: " .. tostring(err))
  print("Drawing.drawError test passed")
end

function test_drawingDrawBackdrop()
  print("Testing Drawing.drawBackdrop...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local screen = {}
  local ok, err = pcall(function()
    Drawing.drawBackdrop(screen)
  end)
  assert(ok, "drawBackdrop should not error: " .. tostring(err))
  print("Drawing.drawBackdrop test passed")
end

function test_drawingDrawCoordinates()
  print("Testing Drawing.drawCoordinates...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local screen = {
    font = { draw = function() end, width = function() return 8 end },
    cursorBx = 10,
    cursorBy = 5,
    mapChanged = false,
  }
  local ok, err = pcall(function()
    Drawing.drawCoordinates(screen)
  end)
  assert(ok, "drawCoordinates should not error: " .. tostring(err))
  print("Drawing.drawCoordinates test passed")
end

function test_drawingDrawNewMapPreview()
  print("Testing Drawing.drawNewMapPreview...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local screen = {
    font = { draw = function() end, width = function() return 8 end },
    def = { width = 10, height = 10 },
    scrollX = 0,
    scrollY = 0,
  }
  local ok, err = pcall(function()
    Drawing.drawNewMapPreview(screen)
  end)
  assert(ok, "drawNewMapPreview should not error: " .. tostring(err))
  screen._newMapState = {
    showPreview = true,
    width = 10,
    height = 10,
    dir = "N",
  }
  ok, err = pcall(function()
    Drawing.drawNewMapPreview(screen)
  end)
  assert(ok, "drawNewMapPreview with state should not error: " .. tostring(err))
  print("Drawing.drawNewMapPreview test passed")
end

function test_connectionEditorRenderer()
  print("Testing ConnectionEditorDialog renderer...")
  local ConnectionEditorDialog = require("mods.map_editor.renderer.connection_editor")
  assert(type(ConnectionEditorDialog) == "table", "ConnectionEditorDialog should be a table")
  assert(type(ConnectionEditorDialog.draw) == "function", "ConnectionEditorDialog should have draw")
  print("ConnectionEditorDialog renderer test passed")
end

function test_textInputRenderer()
  print("Testing TextInputDialog renderer...")
  local TextInputDialog = require("mods.map_editor.renderer.text_input")
  assert(type(TextInputDialog) == "table", "TextInputDialog should be a table")
  assert(type(TextInputDialog.draw) == "function", "TextInputDialog should have draw")
  print("TextInputDialog renderer test passed")
end

function test_all()
  test_mapEditorRename()
  test_drawingSceneFunctions()
  test_drawingDrawMapEditor()
  test_drawingDrawError()
  test_drawingDrawBackdrop()
  test_drawingDrawCoordinates()
  test_drawingDrawNewMapPreview()
  test_connectionEditorRenderer()
  test_textInputRenderer()

  print("\n=== ALL MAP_EDITOR TESTS PASSED ===")
end

if not pcall(test_all) then
  print("\n=== SOME MAP_EDITOR TESTS FAILED ===")
  os.exit(1)
end