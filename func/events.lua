-- Event handlers for the map editor: mouse, keyboard, and the hooks that
-- install/uninstall them at the love.* level.

local Common = require("mods.map_editor.func.common")
local EntityEditor = require("mods.map_editor.scene.entity_editor")
local MODES = Common.MODES
local CELL_PX = Common.CELL_PX
local PAL_BLOCK_SIZE = Common.PAL_BLOCK_SIZE
local PAL_GAP = Common.PAL_GAP
local PAL_ROWS = Common.PAL_ROWS
local PAL_COLS = Common.PAL_COLS
local PAL_VISIBLE = Common.PAL_VISIBLE

local Events = {}

function Events.hookMouse(self)
  local ref = self
  self._origKeypressed = love.keypressed
  self._origMousepressed = love.mousepressed
  self._origWheelmoved = love.wheelmoved
  love.keypressed = function(key, scancode, isrepeat)
    if ref.game and ref.game.stack and ref.game.stack:top() ~= ref then
      if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "n" then
        while ref.game.stack:top() ~= ref do ref.game.stack:pop() end
      end
    end
    if ref._origKeypressed then ref._origKeypressed(key, scancode, isrepeat) end
  end
  love.mousepressed = function(x, y, btn)
    if ref._origMousepressed then ref._origMousepressed(x, y, btn) end
    if btn == 1 then ref:onClick(x, y) end
    if btn == 2 then ref:onRightClick(x, y) end
  end
  love.wheelmoved = function(dx, dy)
    if ref._origWheelmoved then ref._origWheelmoved(dx, dy) end
    if dy ~= 0 then ref:onWheel(dy) end
  end
end

function Events.unhookMouse(self)
  if self._origKeypressed then
    love.keypressed = self._origKeypressed; self._origKeypressed = nil
  end
  if self._origMousepressed then
    love.mousepressed = self._origMousepressed; self._origMousepressed = nil
  end
  if self._origWheelmoved then
    love.wheelmoved = self._origWheelmoved; self._origWheelmoved = nil
  end
end

function Events.onClick(self, x, y)
  local vw, vh = 160, 144
  local palW = self.showPalette and 40 or 0
  local mapViewW = vw - palW
  if y >= 0 and y < 8 then
    for i = 1, 5 do
      local mx = (i - 1) * 32
      if x >= mx and x < mx + 28 then
        self.mode = i
        self:clampScroll()
        return
      end
    end
  end
  if x >= 0 and x < mapViewW and y >= 8 and y < 144 then
    local bx = math.floor((x + self.scrollX) / CELL_PX)
    local by = math.floor(((y - 8) + self.scrollY) / CELL_PX)
    local step = (self.mode == MODES.BLOCKS) and 2 or 1
    self.cursorBx = math.floor(bx / step) * step
    self.cursorBy = math.floor(by / step) * step
    if self.mode == MODES.BLOCKS then self:paintBlock() end
    self:clampScroll()
  elseif self.showPalette and x >= mapViewW then
    if self.mode == MODES.OBJECTS then
      local perPage = 14
      local pageStart = math.floor((self.selectedBlock - 1) / perPage) * perPage
      local px = x - (mapViewW + 4)
      local py = y - 10
      local col = math.floor(px / 18)
      local row = math.floor(py / 20)
      if col >= 0 and col < 2 and row >= 0 and row < 7 then
        local idx = pageStart + row * 2 + col + 1
        if idx >= 1 and idx <= #self.spriteList then
          self.selectedBlock = idx
          local kind, ent = EntityEditor.selectedEntity(self)
          if kind == "object" and ent then
            if self.undo then self.undo:capture(self.def) end
            ent.sprite = self.spriteList[idx]
            self.mapChanged = true
          end
        end
      end
    else
      local px = x - (mapViewW + 4)
      local py = y - 10
      local row = math.floor(py / (PAL_BLOCK_SIZE + PAL_GAP))
      local inside = px >= 0 and px < palW - 4 and row >= 0 and row < PAL_ROWS
        and py % (PAL_BLOCK_SIZE + PAL_GAP) < PAL_BLOCK_SIZE
      local idx = inside and (self.paletteOffset + row + 1) or nil
      if idx and idx >= 1 and idx <= #self.paletteList then
        self.selectedBlock = self.paletteList[idx] or (idx - 1)
      end
    end
  end
end

function Events.onRightClick(self, x, y)
  local palW = self.showPalette and 40 or 0
  local mapViewW = 160 - palW
  if x < 0 or x >= mapViewW or y < 8 or y >= 144 then return end
  local cx = math.floor((x + self.scrollX) / CELL_PX)
  local cy = math.floor(((y - 8) + self.scrollY) / CELL_PX)
  local bx = math.floor(cx / 2)
  local by = math.floor(cy / 2)
  if bx >= 0 and bx < self.def.width and by >= 0 and by < self.def.height then
    local idx = by * self.def.width + bx + 1
    if idx >= 1 and idx <= #self.def.blocks then
      self.selectedBlock = self.def.blocks[idx]
    end
  end
end

function Events.onWheel(self, dy)
  if self.showPalette then
    local maxOffset = math.max(0, #self.paletteList - PAL_VISIBLE)
    local delta = (dy > 0 and -PAL_COLS or PAL_COLS)
    self.paletteOffset = math.max(0, math.min(self.paletteOffset + delta,
      maxOffset))
  else
    local n = #self.tileset.blocks
    self.selectedBlock = (self.selectedBlock + (dy > 0 and -1 or 1) + n) % n
  end
end

function Events.onKeyPressed(self, key)
  if self.game.stack:top() ~= self then
    if key == "1" or key == "2" or key == "3" or key == "4" or key == "5" or key == "n" then
      while self.game.stack:top() ~= self do self.game.stack:pop() end
    else
      return
    end
  end

  if self.entityMoving then
    local ent = self.entityMovingTarget
    if key == "up" or key == "w" then ent.y = math.max(0, ent.y - 1)
    elseif key == "down" or key == "s" then ent.y = ent.y + 1
    elseif key == "left" or key == "a" then ent.x = math.max(0, ent.x - 1)
    elseif key == "right" or key == "d" then ent.x = ent.x + 1
    elseif key == "return" or key == "space" then
      self.entityMoving = false
      self.entityMovingKind = nil
      self.entityMovingTarget = nil
      self.entityMovingOrig = nil
      self.mapChanged = true
    elseif key == "escape" then
      ent.x = self.entityMovingOrig.x
      ent.y = self.entityMovingOrig.y
      self.entityMoving = false
      self.entityMovingKind = nil
      self.entityMovingTarget = nil
      self.entityMovingOrig = nil
    end
    return
  end

  if self._newMapState and self._newMapState.editField then
    local s = self._newMapState
    if key == "left" then
      if s.editField == "w" then s.width = math.max(1, s.width - 1)
      elseif s.editField == "h" then s.height = math.max(1, s.height - 1)
      else
        local dirs = { "N", "W", "S", "E" }
        for i = 1, 4 do
          if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
        end
      end
    elseif key == "right" then
      if s.editField == "w" then s.width = math.min(64, s.width + 1)
      elseif s.editField == "h" then s.height = math.min(64, s.height + 1)
      else
        local dirs = { "N", "E", "S", "W" }
        for i = 1, 4 do
          if dirs[i] == s.dir then s.dir = dirs[i % 4 + 1]; break end
        end
      end
    elseif key == "up" or key == "down" then
      local fields = { "w", "h", "dir" }
      for i = 1, 3 do
        if fields[i] == s.editField then
          s.editField = fields[(key == "up" and (i - 2) or i) % 3 + 1]
          break
        end
      end
    elseif key == "return" or key == "space" then self:_newMapConfirm()
    elseif key == "escape" then self._newMapState = nil end
    return
  end

  if key == "s" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:savePatches()
  elseif key == "e" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:exportPatches()
  elseif key == "z" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("undo")
  elseif key == "y" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then self:restoreSnapshot("redo")
  elseif key == "up" or key == "w" or key == "down" or key == "s" or key == "left" or key == "a" or key == "right" or key == "d" then
    local step = (self.mode == MODES.BLOCKS) and 2 or 1
    if key == "up" or key == "w" then self.cursorBy = self.cursorBy - step
    elseif key == "down" or key == "s" then self.cursorBy = self.cursorBy + step
    elseif key == "left" or key == "a" then self.cursorBx = self.cursorBx - step
    elseif key == "right" or key == "d" then self.cursorBx = self.cursorBx + step end
  elseif key == "tab" then self.showPalette = not self.showPalette
  elseif key == "q" then
    if self.mode == MODES.OBJECTS and #self.spriteList > 0 then
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind == "object" and ent then
        if self.undo then self.undo:capture(self.def) end
        for i = #self.spriteList, 1, -1 do
          if self.spriteList[i] == ent.sprite then
            local prev = (i - 2 + #self.spriteList) % #self.spriteList + 1
            ent.sprite = self.spriteList[prev]
            self.selectedBlock = prev
            self.mapChanged = true
            break
          end
        end
      else
        self.selectedBlock = (self.selectedBlock - 2 + #self.spriteList) % #self.spriteList + 1
      end
    else
      self.selectedBlock = (self.selectedBlock - 1 + #self.tileset.blocks) % #self.tileset.blocks
    end
  elseif key == "e" then
    if self.mode == MODES.OBJECTS and #self.spriteList > 0 then
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind == "object" and ent then
        if self.undo then self.undo:capture(self.def) end
        for i = 1, #self.spriteList do
          if self.spriteList[i] == ent.sprite then
            local next = i % #self.spriteList + 1
            ent.sprite = self.spriteList[next]
            self.selectedBlock = next
            self.mapChanged = true
            break
          end
        end
      else
        self.selectedBlock = self.selectedBlock % #self.spriteList + 1
      end
    else
      self.selectedBlock = (self.selectedBlock + 1) % #self.tileset.blocks
    end
  elseif key == "f" and self.mode == MODES.BLOCKS then self:floodFill()
  elseif key == "g" then self.showGrid = not self.showGrid
  elseif key == "h" then self.showHelp = not self.showHelp
  elseif key == "1" then self.mode = MODES.BLOCKS
  elseif key == "2" then self.mode = MODES.WARPS
  elseif key == "3" then self.mode = MODES.OBJECTS
  elseif key == "4" then self.mode = MODES.SIGNS
  elseif key == "5" then
    self.mode = MODES.ENCOUNTERS
    require("mods.map_editor.scene.encounter_editor").edit(self)
  elseif key == "6" then
    local ent = EntityEditor.selectedEntity(self)
    if ent and ent.kind == "connection" then
      require("mods.map_editor.scene.connection_editor").edit(self, ent)
    else
      self.mode = MODES.CONNECTIONS
    end
  elseif key == "return" or key == "space" then
    if self.mode == MODES.BLOCKS then self:paintBlock()
    elseif self.mode == MODES.ENCOUNTERS then
      require("mods.map_editor.scene.encounter_editor").edit(self)
    else
      local kind, ent = EntityEditor.selectedEntity(self)
      if kind then EntityEditor.editEntity(self, kind, ent)
      elseif self.mode == MODES.WARPS then EntityEditor.addEntity(self, "warp")
      elseif self.mode == MODES.OBJECTS then EntityEditor.showObjectTypePicker(self)
      elseif self.mode == MODES.SIGNS then EntityEditor.addEntity(self, "sign") end
    end
  elseif key == "r" and self.mode == MODES.BLOCKS then self:revertBlock()
  elseif key == "n" then self:newMapDialog()
  elseif key == "escape" then
    if self._newMapState then self._newMapState = nil
    elseif self.showHelp then self.showHelp = false
    else self.game.stack:pop() end
  end
  self:clampScroll()
end

return Events
