-- Connection editor tests: camera clamping while dragging a connection
-- silhouette (the map must stay on screen), and creating a brand-new map as
-- the destination of a new connection.

package.path = "../../../?.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
Data:load()
local Renderer = require("src.render.Renderer")
local Common = require("mods.map_editor.func.common")
local MODES = Common.MODES
local MODULE = "mods.map_editor.func.camera"

local savedUI = { Renderer.uiWidth, Renderer.uiHeight }
local function setUI(w, h)
  Renderer.uiWidth, Renderer.uiHeight = w, h
end
local function restoreUI()
  Renderer.uiWidth, Renderer.uiHeight = savedUI[1], savedUI[2]
end

local function cameraScreen(mapW, mapH)
  local s = {
    showPalette = true,
    mode = MODES.ENT,
    brushSize = 1,
    cursorBx = 0, cursorBy = 0,
    scrollX = 0, scrollY = 0,
    mapW = mapW, mapH = mapH,
    neighbors = {},
    entityMoving = false,
    entityMovingKind = nil,
    _selectedDir = nil,
  }
  for k, v in pairs(require(MODULE)) do s[k] = v end
  return s
end

local function placeCursor(s, dir, mapW, mapH, offset)
  local mw = mapW / 32 * 2
  local mh = mapH / 32 * 2
  local off = offset * 2
  if dir == "north" then s.cursorBx = off + mw / 2; s.cursorBy = -2
  elseif dir == "south" then s.cursorBx = off + mw / 2; s.cursorBy = mh + 2
  elseif dir == "west" then s.cursorBx = -2; s.cursorBy = off + mh / 2
  elseif dir == "east" then s.cursorBx = mw + 2; s.cursorBy = off + mh / 2 end
end

local function beginMove(s, dir)
  s.entityMoving = true
  s.entityMovingKind = "connection"
  s._selectedDir = dir
end

function test_cameraClampEastFits()
  print("Testing camera clamp (east, map fits)...")
  setUI(512, 384) -- default 1024x768 window -> viewW = 400
  local s = cameraScreen(320, 288)
  placeCursor(s, "east", 320, 288, 0)
  beginMove(s, "east")
  s:clampScroll()
  if not (s.scrollX <= 0) then
    error("east small map: scroll should keep map left edge on screen, got " .. s.scrollX)
  end
  if not (-s.scrollX + 320 <= 400) then
    error("east small map: map right edge should stay visible, got scrollX " .. s.scrollX)
  end
  print("Camera clamp test passed")
end

function test_cameraClampEastBigMap()
  print("Testing camera clamp (east, map bigger than viewport)...")
  setUI(512, 384)
  local s = cameraScreen(640, 576)
  placeCursor(s, "east", 640, 576, 0)
  beginMove(s, "east")
  s:clampScroll()
  if not (640 - s.scrollX >= 400 - 64) then
    error("east big map: map body should fill the viewport, got scrollX " .. s.scrollX)
  end
  if not (s.scrollX >= 640 - 400) then
    error("east big map: scroll should not chase the strip off the map, got " .. s.scrollX)
  end
  print("Camera clamp east big map test passed")
end

function test_cameraClampWest()
  print("Testing camera clamp (west)...")
  setUI(512, 384)
  local s = cameraScreen(640, 576)
  placeCursor(s, "west", 640, 576, 0)
  beginMove(s, "west")
  s:clampScroll()
  if not (s.scrollX >= -64 and s.scrollX <= 0) then
    error("west: strip reachable and map left edge on screen, got " .. s.scrollX)
  end
  print("Camera clamp west test passed")
end

function test_cameraClampNorth()
  print("Testing camera clamp (north)...")
  setUI(512, 384)
  local s = cameraScreen(320, 288)
  placeCursor(s, "north", 320, 288, 0)
  beginMove(s, "north")
  s:clampScroll()
  if not (s.scrollY >= -64 and s.scrollY <= 0) then
    error("north: strip reachable and map top edge on screen, got " .. s.scrollY)
  end
  print("Camera clamp north test passed")
end

function test_cameraClampAfterMove()
  print("Testing camera clamp (after move ends)...")
  setUI(512, 384)
  local s = cameraScreen(320, 288)
  s.cursorBx, s.cursorBy = 20, 20
  s:clampScroll()
  if s.entityMoving then error("clamp should not set entityMoving") end
  print("Camera clamp after-move test passed")
end

local function makeStack()
  local stack = {}
  function stack:push(v) table.insert(self, v) end
  function stack:pop() table.remove(self) end
  function stack:top() return self[#self] end
  return stack
end

local function makeEditorScreen(stack)
  local screen = {
    mapId = "PALLET_TOWN",
    data = Data,
    def = {
      width = 10, height = 9, borderBlock = 5,
      tileset = "tileset_overworld", palette = "pal_red",
      warps = {}, objects = {}, signs = {},
    },
    game = { data = Data, stack = stack },
    undo = nil,
    _selectedDir = nil,
    mapChanged = false,
    cursorBx = 0, cursorBy = 0,
    entityMoving = false,
    entityMovingKind = nil,
    entityMovingTarget = nil,
    entityMovingOrig = nil,
    mod = {
      ui = {
        ListMenu = {
          new = function(game, title, items, opts)
            return { title = title, items = items, onChoose = (opts or {}).onChoose or function() end }
          end,
        },
      },
      log = { info = function() end },
    },
  }
  for k, v in pairs(require("mods.map_editor.func.new_map")) do screen[k] = v end
  return screen
end

-- Editor screen bound to an isolated maps table (so probe tests don't touch
-- the real game Data or trip on its actual connections).
local function probeScreen(stack, data, rootId)
  rootId = rootId or "ROOT"
  local screen = makeEditorScreen(stack)
  screen.mapId = rootId
  screen.data = data
  screen.def = data.maps[rootId]
  return screen
end

function test_newConnectionCreatesNewMap()
  print("Testing new connection -> create new map...")
  local stack = makeStack()
  local screen = makeEditorScreen(stack)
  local EntityEditor = require("mods.map_editor.scene.entity_editor")

  local count = 0
  for _ in pairs(Data.maps) do count = count + 1 end

  EntityEditor.showConnectionDirPicker(screen, nil)
  local picker = stack:top()
  picker.onChoose({ value = "east" })

  local dest = stack:top()
  if dest.title ~= "Connection destination" then
    error("expected a destination picker, got " .. tostring(dest.title))
  end
  dest.onChoose({ value = "new" })

  if not screen._newMapState then error("new map dialog should be open") end
  if screen._newMapState.step ~= "name" then error("dialog should start on the name step") end
  if screen._newMapState.lockDir ~= true then error("dir should be locked") end
  if screen._newMapState.dir ~= "E" then error("dir should normalize to E, got " .. tostring(screen._newMapState.dir)) end
  if not screen._pendingConn then error("pending connection should be recorded") end

  local nameInput = stack:top()
  if not nameInput or not nameInput.onDone then error("name text input should be pushed") end
  nameInput.onDone("CONN_NEW")
  if screen._newMapState.step ~= "dims" then error("dialog should move to dimensions after naming") end
  if screen._newMapState.name ~= "CONN_NEW" then error("chosen name should be applied") end

  screen._newMapState.width = 12
  screen._newMapState.height = 8
  screen:_newMapConfirm()

  local newId = screen.mapId .. "_EXT"
  local newDef = Data.maps[newId]
  if not newDef then error("new map " .. newId .. " should exist") end
  if newDef.width ~= 12 or newDef.height ~= 8 then error("new map dims wrong") end
  if #newDef.blocks ~= 96 then error("new map blocks not filled") end
  local conn = screen.def.connections["east"]
  if not conn then error("connection should exist") end
  if conn.map ~= newId then error("connection should point at the new map") end
  if not screen.entityMoving then error("should enter moving mode after confirm") end
  if screen.entityMovingKind ~= "connection" then error("moving a connection") end
  if screen._newMapState ~= nil then error("dialog should be closed") end
  if screen._pendingConn ~= nil then error("pending conn should be cleared") end

  local after = 0
  for _ in pairs(Data.maps) do after = after + 1 end
  if after ~= count + 1 then error("exactly one map should have been created") end

  print("New connection -> new map test passed")
end

function test_existingConnectionNewMapUniqueIds()
  print("Testing unique ids for multiple created maps...")
  local stack = makeStack()
  -- Isolated data: real Pallet Town connects to Route 1/21, and a new map
  -- placed there would (correctly) be rejected as overlapping, so test id
  -- naming against a bare map in open space.
  local data = {
    maps = {
      PALLET_TOWN = { id = "PALLET_TOWN", width = 10, height = 9, borderBlock = 5,
                      tileset = "tileset_overworld", palette = "pal_red",
                      blocks = {}, warps = {}, objects = {}, signs = {},
                      connections = {} },
    },
  }
  local screen = probeScreen(stack, data, "PALLET_TOWN")
  screen.mapId = "PALLET_TOWN"

  screen._pendingConn = { conn = { map = "PALLET_TOWN", offset = 0 }, dir = "north", move = false }
  screen:newMapDialog("north")
  stack:top().onDone("UNIQUE_A")
  screen._newMapState.width = 5
  screen:_newMapConfirm()

  screen._pendingConn = { conn = { map = "PALLET_TOWN", offset = 0 }, dir = "south", move = false }
  screen:newMapDialog("south")
  stack:top().onDone("UNIQUE_B")
  screen._newMapState.width = 6
  screen:_newMapConfirm()

  if not data.maps["PALLET_TOWN_EXT"] then error("first map should use _EXT") end
  if not data.maps["PALLET_TOWN_EXT2"] then error("second map should use _EXT2") end
  if screen.entityMoving then error("move=false path should not enter moving mode") end

  print("Unique ids test passed")
end

function test_inputNewMapDirectKeys()
  print("Testing input_newmap direct width/height keys...")
  local InputNewMap = require("mods.map_editor.inputs.input_newmap")
  local screen = { _newMapState = { editField = "w", width = 10, height = 10, dir = "E", lockDir = true } }
  local s = screen._newMapState
  InputNewMap.onKeyPressed(screen, "a")
  if s.width ~= 9 then error("a should shrink width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "left")
  if s.width ~= 8 then error("left should shrink width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "d")
  if s.width ~= 9 then error("d should grow width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "right")
  if s.width ~= 10 then error("right should grow width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "w")
  if s.height ~= 11 then error("w should grow height, got " .. s.height) end
  InputNewMap.onKeyPressed(screen, "up")
  if s.height ~= 12 then error("up should grow height, got " .. s.height) end
  InputNewMap.onKeyPressed(screen, "s")
  if s.height ~= 11 then error("s should shrink height, got " .. s.height) end
  InputNewMap.onKeyPressed(screen, "down")
  if s.height ~= 10 then error("down should shrink height, got " .. s.height) end
  if s.dir ~= "E" then error("dir should stay locked") end
  print("Input new-map direct keys test passed")
end

function test_inputNewMapFastSteps()
  print("Testing input_newmap Q/E +/-10...")
  local InputNewMap = require("mods.map_editor.inputs.input_newmap")
  local screen = { _newMapState = { editField = "w", width = 10, height = 10, dir = "N", lockDir = false } }
  local s = screen._newMapState
  InputNewMap.onKeyPressed(screen, "e")
  if s.width ~= 20 then error("e should add 10 to width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "q")
  if s.width ~= 10 then error("q should subtract 10 from width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "tab")
  InputNewMap.onKeyPressed(screen, "e")
  if s.height ~= 20 then error("e on height field should add 10, got " .. s.height) end
  InputNewMap.onKeyPressed(screen, "q")
  if s.height ~= 10 then error("q on height field should subtract 10, got " .. s.height) end
  InputNewMap.onKeyPressed(screen, "tab")
  InputNewMap.onKeyPressed(screen, "e")
  if s.width ~= 10 then error("e on dir field should not change width, got " .. s.width) end
  InputNewMap.onKeyPressed(screen, "w")
  if s.height ~= 11 then error("w should still grow height, got " .. s.height) end
  print("Input new-map Q/E test passed")
end

function test_inputNewMapTabCycling()
  print("Testing input_newmap tab field cycling + dir arrows...")
  local InputNewMap = require("mods.map_editor.inputs.input_newmap")
  local screen = { _newMapState = { editField = "w", width = 10, height = 10, dir = "N", lockDir = false } }
  local s = screen._newMapState
  InputNewMap.onKeyPressed(screen, "tab")
  if s.editField ~= "h" then error("tab should move w -> h, got " .. s.editField) end
  InputNewMap.onKeyPressed(screen, "tab")
  if s.editField ~= "dir" then error("tab should move h -> dir, got " .. s.editField) end
  InputNewMap.onKeyPressed(screen, "right")
  if s.dir ~= "E" then error("right on dir should cycle N -> E, got " .. s.dir) end
  InputNewMap.onKeyPressed(screen, "left")
  if s.dir ~= "N" then error("left on dir should cycle back E -> N, got " .. s.dir) end
  InputNewMap.onKeyPressed(screen, "tab")
  if s.editField ~= "w" then error("tab should wrap dir -> w, got " .. s.editField) end
  s.editField = "dir"
  InputNewMap.onKeyPressed(screen, "a")
  if s.width ~= 9 then error("a should shrink width even while dir active, got " .. s.width) end
  print("Input new-map tab cycling test passed")
end

function test_newMapDefaultName()
  print("Testing new-map default name + uniqueness...")
  local stack = makeStack()
  local screen = makeEditorScreen(stack)
  local NewMap = require("mods.map_editor.func.new_map")

  screen:newMapDialog("north")
  if screen._newMapState.step ~= "name" then error("dialog should start on the name step") end
  if screen._newMapState.name ~= "NEW_MAP" then
    error("first map should default to NEW_MAP, got " .. tostring(screen._newMapState.name))
  end
  stack:top().onDone("NEW_MAP")
  screen:_newMapConfirm()

  screen:newMapDialog("south")
  if screen._newMapState.name ~= "NEW_MAP_2" then
    error("second map should default to NEW_MAP_2, got " .. tostring(screen._newMapState.name))
  end
  stack:top().onDone("NEW_MAP_2")
  screen:_newMapConfirm()

  if NewMap.isMapNameUsed(Data, "NEW_MAP") ~= true then error("NEW_MAP should be in use") end
  if NewMap.isMapNameUsed(Data, "DOES_NOT_EXIST") ~= false then error("free name should not be in use") end
  if NewMap.isMapNameUsed(Data, "PALLET_TOWN") ~= true then error("map id counts as its display name") end

  local unique = NewMap.uniqueMapName(Data, "NEW_MAP")
  if unique ~= "NEW_MAP_3" then error("uniqueMapName should pick NEW_MAP_3, got " .. tostring(unique)) end

  print("New-map default name test passed")
end

function test_newMapNameRejectsDuplicate()
  print("Testing new-map name step rejects duplicates...")
  local stack = makeStack()
  local screen = makeEditorScreen(stack)
  screen:newMapDialog("east")
  local initial = screen._newMapState.name

  local input = stack:top()
  if not input or not input.onDone then error("name text input should be pushed") end
  input.onDone("PALLET_TOWN")
  if screen._newMapState.name ~= initial then
    error("duplicate name should be rejected, got " .. tostring(screen._newMapState.name))
  end
  if screen._newMapState.step ~= "name" then error("should stay on the name step after a duplicate") end
  if stack:top() == input then error("a fresh input should be pushed after a duplicate") end

  input = stack:top()
  input.onDone("MY_UNIQUE_MAP")
  if screen._newMapState.name ~= "MY_UNIQUE_MAP" then
    error("unique name should be accepted, got " .. tostring(screen._newMapState.name))
  end
  if screen._newMapState.step ~= "dims" then error("valid name should move to dimensions step") end
  print("New-map name duplicate rejection test passed")
end

function test_newMapNameCancel()
  print("Testing new-map name step cancel...")
  local stack = makeStack()
  local screen = makeEditorScreen(stack)
  -- The caller adds the connection speculatively before the dialog opens;
  -- cancelling must drop it again along with the pending flow state.
  screen.def.connections = { east = { map = "PALLET_TOWN", offset = 0 } }
  screen._pendingConn = { conn = screen.def.connections.east, dir = "east", move = true }
  screen:newMapDialog("east")
  stack:top().onDone(nil)
  if screen._newMapState ~= nil then error("cancel should close the whole dialog") end
  if screen._pendingConn ~= nil then error("cancel should clear the pending connection") end
  if screen.def.connections["east"] ~= nil then
    error("cancel should drop the speculative connection added for the flow")
  end
  print("New-map name cancel test passed")
end

function test_fullSizeConnectionPreview()
  print("Testing full-size connection silhouette + hitbox...")
  local Drawing = require("mods.map_editor.renderer.drawing")
  local EntityEditor = require("mods.map_editor.scene.entity_editor")

  local screen = {
    def = {
      width = 10, height = 9, borderBlock = 5,
      connections = { east = { map = "VIRIDIAN_CITY", offset = 0 } },
    },
    data = Data,
    scrollX = 0, scrollY = 0,
    font = { draw = function() end, width = function() return 8 end },
    mode = MODES.ENT, brushSize = 1,
  }

  local rects = {}
  local origRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h)
    table.insert(rects, { mode = mode, x = x, y = y, w = w, h = h })
  end
  Drawing.drawConnectionSilhouettes(screen)
  love.graphics.rectangle = origRect

  if #rects < 2 then error("silhouette should draw fill + line rectangles") end
  local fill = rects[1]
  if fill.w ~= 64 then error("east strip width should be 2 blocks, got " .. fill.w) end
  if fill.h ~= screen.def.height * 32 then
    error("east strip should span the map's full height, got " .. fill.h)
  end

  screen.cursorBx = screen.def.width * 2 + 2
  screen.cursorBy = screen.def.height * 2 - 1
  local kind, conn = EntityEditor.selectedEntity(screen)
  if kind ~= "connection" then error("full-height strip should be clickable at its bottom edge") end
  if not conn then error("connection entity expected") end
  print("Full-size connection preview test passed")
end

function test_entityNameDuplicate()
  print("Testing entity duplicate-name check...")
  local EntityEditor = require("mods.map_editor.scene.entity_editor")
  local screen = {
    def = {
      objects = { { name = "LASS" }, { x = 1 } },
      signs = { { name = "TEXT_A" } },
      warps = {},
    },
  }
  if not EntityEditor.isEntityNameUsed(screen, "LASS") then error("LASS should be detected as used") end
  if EntityEditor.isEntityNameUsed(screen, "LASS", screen.def.objects[1]) then
    error("excluding the entity itself should not flag a duplicate")
  end
  if EntityEditor.isEntityNameUsed(screen, "FREE_NAME") then
    error("unused name should not be flagged")
  end
  print("Entity duplicate-name check test passed")
end

-- Overlap scenario: ROOT connects east to A at offset -8, so A's body
-- extends up beside ROOT.  A new map placed north of ROOT that is wide
-- enough reaches A and overlaps it, which must abort creation.
function test_newConnectionOverlapRejected()
  print("Testing new connection overlap rejection...")
  local stack = makeStack()
  local data = {
    maps = {
      ROOT = { id = "ROOT", width = 10, height = 9, borderBlock = 5,
               tileset = "tileset_overworld", palette = "pal_red",
               blocks = {}, warps = {}, objects = {}, signs = {},
               connections = { east = { map = "A", offset = -8 } } },
      A = { id = "A", width = 4, height = 4, borderBlock = 0, blocks = {},
            warps = {}, objects = {}, signs = {}, connections = {} },
    },
  }
  local screen = probeScreen(stack, data)

  local count = 0
  for _ in pairs(data.maps) do count = count + 1 end

  -- Simulate the speculative connection the direction picker adds.
  screen.def.connections.north = { map = "ROOT", offset = 0 }
  screen._pendingConn = { conn = screen.def.connections.north, dir = "north", move = true }
  screen:newMapDialog("north")
  stack:top().onDone("OVERLAP")
  screen._newMapState.width = 20
  screen._newMapState.height = 8
  screen:_newMapConfirm()

  local top = stack:top()
  if not top or not top.title then error("an OK dialog should be shown on overlap") end
  if top.title ~= "New map would overlap an existing map" then
    error("unexpected message title: " .. tostring(top.title))
  end
  if not top.items or top.items[1].label ~= "OK" then
    error("message dialog should offer an OK item")
  end

  local after = 0
  for _ in pairs(data.maps) do after = after + 1 end
  if after ~= count then error("overlap should not create any map") end
  if not Data.maps["ROOT_EXT"] and data.maps["ROOT_EXT"] then
    error("no map should be created on overlap")
  end
  if screen.def.connections.north then error("speculative connection should be removed on overlap") end
  if not screen.def.connections.east then error("unrelated connection should be kept") end
  if screen._pendingConn ~= nil then error("pending connection should be cleared on overlap") end
  if screen._newMapState ~= nil then error("dialog should close on overlap") end

  top.onChoose({ value = "ok" })
  if stack:top() == top then error("OK should close the message dialog") end

  print("New connection overlap rejection test passed")
end

-- Flush scenario: ROOT connects west to C at offset -4, so C's body sits
-- directly to the west of where a new map lands north of ROOT.  The new map
-- touches C with zero gap, which must auto-create a reciprocal connection.
function test_newConnectionFlushReciprocal()
  print("Testing new connection flush reciprocal links...")
  local stack = makeStack()
  local data = {
    maps = {
      ROOT = { id = "ROOT", width = 10, height = 9, borderBlock = 5,
               tileset = "tileset_overworld", palette = "pal_red",
               blocks = {}, warps = {}, objects = {}, signs = {},
               connections = { west = { map = "C", offset = -4 } } },
      C = { id = "C", width = 4, height = 4, borderBlock = 0, blocks = {},
            warps = {}, objects = {}, signs = {}, connections = {} },
    },
  }
  local screen = probeScreen(stack, data)

  screen._pendingConn = { conn = { map = "ROOT", offset = 0 }, dir = "north", move = false }
  screen:newMapDialog("north")
  stack:top().onDone("FLUSH")
  screen._newMapState.width = 4
  screen._newMapState.height = 4
  screen:_newMapConfirm()

  local newId = "ROOT_EXT"
  local newDef = data.maps[newId]
  if not newDef then error("new map should be created when the layout allows it") end
  local wc = newDef.connections and newDef.connections.west
  if not wc then error("new map should auto-connect west to the flush map") end
  if wc.map ~= "C" or wc.offset ~= 0 then
    error("flush connection should be C at offset 0, got " .. tostring(wc.map) .. "/" .. tostring(wc.offset))
  end
  local ec = data.maps.C.connections and data.maps.C.connections.east
  if not ec then error("flush map should get a reciprocal east connection") end
  if ec.map ~= newId or ec.offset ~= 0 then
    error("reciprocal connection should be " .. newId .. " at offset 0, got "
      .. tostring(ec.map) .. "/" .. tostring(ec.offset))
  end

  print("New connection flush reciprocal test passed")
end

function test_probePlacementGeometry()
  print("Testing probe placement geometry...")
  local Neighbors = require("mods.map_editor.func.neighbors")
  local data = {
    maps = {
      ROOT = { id = "ROOT", width = 10, height = 9, connections = {} },
    },
  }
  local rootDef = data.maps.ROOT

  local x0, y0, x1, y1 = Neighbors.mapRectAt(rootDef, "north", 0, 4, 4)
  if x0 ~= 0 or y0 ~= -128 or x1 ~= 128 or y1 ~= 0 then
    error("mapRectAt north wrong: " .. x0 .. "," .. y0 .. " " .. x1 .. "," .. y1)
  end
  x0, y0, x1, y1 = Neighbors.mapRectAt(rootDef, "south", 3, 4, 4)
  if x0 ~= 96 or y0 ~= 288 or x1 ~= 224 or y1 ~= 416 then
    error("mapRectAt south wrong: " .. x0 .. "," .. y0 .. " " .. x1 .. "," .. y1)
  end
  x0, y0, x1, y1 = Neighbors.mapRectAt(rootDef, "east", -2, 4, 4)
  if x0 ~= 320 or y0 ~= -64 or x1 ~= 448 or y1 ~= 64 then
    error("mapRectAt east wrong: " .. x0 .. "," .. y0 .. " " .. x1 .. "," .. y1)
  end
  x0, y0, x1, y1 = Neighbors.mapRectAt(rootDef, "west", 5, 4, 4)
  if x0 ~= -128 or y0 ~= 160 or x1 ~= 0 or y1 ~= 288 then
    error("mapRectAt west wrong: " .. x0 .. "," .. y0 .. " " .. x1 .. "," .. y1)
  end

  local kind = Neighbors.probePlacement(data.maps, "ROOT", "north", 0, 4, 4)
  if kind ~= nil then error("open space should return nil, got " .. tostring(kind)) end

  print("Probe placement geometry test passed")
end

function test_textInputArmsAndFirstKeystrokeClearsDefault()
  print("Testing text input arming + first-keystroke clears default...")
  local TextInput = require("mods.map_editor.scene.text_input")

  local savedSetTextInput = love.keyboard.setTextInput
  local savedTextInput = love.textinput
  -- Sentinel standing in for main.lua's love.textinput: cleanup must restore
  -- exactly this when the dialog closes (and only once).
  local sentinel = function(text) end
  love.textinput = sentinel
  local armed = nil
  love.keyboard.setTextInput = function(on) armed = on end

  local done = "UNSET"
  local game = { stack = makeStack() }
  local input = TextInput.new(game, {
    title = "Map name", maxLen = 32, initial = "NEW_MAP",
    onDone = function(t) done = t end,
  })

  if armed ~= true then error("opening a text input should arm setTextInput(true)") end
  if not input.capturesText then error("text input should be marked as text-capturing") end

  love.textinput("M")
  love.textinput("Y")
  if input.text ~= "MY" then
    error("first keystroke should replace the default, got " .. tostring(input.text))
  end

  input:onKeyPressed("return")
  if done ~= "MY" then error("confirm should deliver the typed name, got " .. tostring(done)) end
  if love.textinput ~= sentinel then error("love.textinput should be restored after confirm") end

  love.keyboard.setTextInput = savedSetTextInput
  if savedTextInput then love.textinput = savedTextInput end
  print("Text input arming + default-clear test passed")
end

function test_textInputGamepadConfirmAndCancel()
  print("Testing text input gamepad A/B confirm-cancel...")
  local TextInput = require("mods.map_editor.scene.text_input")

  local savedTextInput = love.textinput
  local sentinel = function(text) end
  love.textinput = sentinel

  local done
  local input = TextInput.new({ stack = makeStack() }, { initial = "X",
    onDone = function(t) done = t end })
  input.game.input = { wasPressed = function(self, b) return b == "a" end }
  input:update()
  if done ~= "X" then error("gamepad A should confirm the name, got " .. tostring(done)) end
  if love.textinput ~= sentinel then error("love.textinput should be restored after confirm") end

  local cancelled = false
  local input2 = TextInput.new({ stack = makeStack() }, { initial = "Y",
    onDone = function(t) cancelled = (t == nil) end })
  input2.game.input = { wasPressed = function(self, b) return b == "b" end }
  input2:update()
  if not cancelled then error("gamepad B should cancel the name input") end
  if love.textinput ~= sentinel then error("love.textinput should be restored after cancel") end

  if savedTextInput then love.textinput = savedTextInput end
  print("Text input gamepad confirm/cancel test passed")
end

function test_textInputDigitsAreText()
  print("Testing digits typed into a name are appended as text...")
  local TextInput = require("mods.map_editor.scene.text_input")

  local savedTextInput = love.textinput
  love.textinput = function(text) end

  local done
  local input = TextInput.new({ stack = makeStack() }, { initial = "NEW_MAP",
    onDone = function(t) done = t end })
  love.textinput("M")
  love.textinput("A")
  love.textinput("P")
  love.textinput("2") -- a mode-switch digit: must be plain text here
  if input.text ~= "MAP2" then
    error("digits should be typed text, got " .. tostring(input.text))
  end
  input:onKeyPressed("return")
  if done ~= "MAP2" then error("name with digits should confirm, got " .. tostring(done)) end

  if savedTextInput then love.textinput = savedTextInput end
  print("Digit-as-text test passed")
end

function test_textInputExternalPopCancels()
  print("Testing external pop cancels the dialog...")
  local TextInput = require("mods.map_editor.scene.text_input")

  local savedTextInput = love.textinput
  love.textinput = function(text) end

  -- Real pop semantics: StateStack:pop calls exit() on the popped state.
  local stack = {}
  function stack:push(v) table.insert(self, v) end
  function stack:pop()
    local s = table.remove(self)
    if s and s.exit then s:exit() end
    return s
  end
  function stack:top() return self[#self] end

  local resolved = 0
  local input = TextInput.new({ stack = stack }, { initial = "NEW_MAP",
    onDone = function(t)
      resolved = resolved + 1
      if t ~= nil then error("external pop should cancel, got " .. tostring(t)) end
    end })
  stack:push(input)
  stack:pop() -- the editor's Escape handler pops the dialog without confirming
  if resolved ~= 1 then
    error("external pop should resolve the dialog once as a cancel, got " .. resolved)
  end

  if savedTextInput then love.textinput = savedTextInput end
  print("External pop-cancel test passed")
end

function test_inputNewMapGamepadMapping()
  print("Testing new-map gamepad mapping...")
  local InputNewMap = require("mods.map_editor.inputs.input_newmap")

  local function screenWith(button)
    return {
      _newMapState = { editField = "h", width = 10, height = 10, dir = "N", lockDir = false },
      game = { input = { wasPressed = function(self, b) return b == button end } },
    }
  end

  local calls = {}
  local savedOnKeyPressed = InputNewMap.onKeyPressed
  InputNewMap.onKeyPressed = function(self, k) calls[#calls + 1] = k end
  local order = { "up", "down", "left", "right", "return", "escape" }
  for i, btn in ipairs({ "up", "down", "left", "right", "a", "b" }) do
    local screen = screenWith(btn)
    InputNewMap.updateGamepad(screen)
    if calls[i] ~= order[i] then
      error("gamepad " .. btn .. " should map to " .. order[i] .. ", got " .. tostring(calls[i]))
    end
  end
  InputNewMap.onKeyPressed = savedOnKeyPressed

  -- No gamepad / no dialog open: must be a no-op.
  local idle = { game = { input = nil } }
  InputNewMap.updateGamepad(idle)
  local idle2 = { _newMapState = nil, game = { input = { wasPressed = function() return true end } } }
  InputNewMap.updateGamepad(idle2)
  if #calls ~= 6 then error("updateGamepad should not fire when no dialog or input") end

  print("New-map gamepad mapping test passed")
end

-- Each suite exports { name, teardown, tests } and is run by test_all.lua.
return {
  name = "CONNECTION",
  teardown = restoreUI,
  tests = {
    "test_cameraClampEastFits",
    "test_cameraClampEastBigMap",
    "test_cameraClampWest",
    "test_cameraClampNorth",
    "test_cameraClampAfterMove",
    "test_newConnectionCreatesNewMap",
    "test_existingConnectionNewMapUniqueIds",
    "test_inputNewMapDirectKeys",
    "test_inputNewMapTabCycling",
    "test_inputNewMapFastSteps",
    "test_newMapDefaultName",
    "test_newMapNameRejectsDuplicate",
    "test_newMapNameCancel",
    "test_fullSizeConnectionPreview",
    "test_entityNameDuplicate",
    "test_newConnectionOverlapRejected",
    "test_newConnectionFlushReciprocal",
    "test_probePlacementGeometry",
    "test_textInputArmsAndFirstKeystrokeClearsDefault",
    "test_textInputGamepadConfirmAndCancel",
    "test_textInputDigitsAreText",
    "test_textInputExternalPopCancels",
    "test_inputNewMapGamepadMapping",
  },
}
