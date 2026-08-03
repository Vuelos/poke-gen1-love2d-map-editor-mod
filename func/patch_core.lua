-- Patches core modules at load time so the map editor mod is
-- self-contained and does not require committed changes to
-- src/core/Input.lua, src/ui/ListMenu.lua, or src/world/WorldAPI.lua.

local function patchInput()
  local Input = require("src.core.Input")
  if Input and Input.keyBindings then
    Input.keyBindings["q"] = "pageUp"
    Input.keyBindings["e"] = "pageDown"
  end
end

local function patchListMenu()
  local ListMenu = require("src.ui.ListMenu")
  if not ListMenu then return end
  if rawget(ListMenu, "_patched") then return end

  local ROWS = 7
  local REPEAT_DELAY = 16
  local REPEAT_RATE = 4

  local function moveIndex(self, delta)
    local n = #self.items
    if n == 0 then return end
    local next = self.index + delta
    if self.wrap then
      next = ((next - 1) % n) + 1
    else
      next = math.max(1, math.min(n, next))
    end
    self.index = next
  end

  local function syncScroll(self)
    if self.index - self.scroll > self.rows then
      self.scroll = self.index - self.rows
    end
    if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
  end

  local function beep(self)
    if self.noSound or not (self.game and self.game.data) then return end
    require("src.core.Sound").play(self.game.data, "Press_AB")
  end

  local function navPressed(self, dir)
    local item = self.items[self.index]
    if (dir == "left" or dir == "right") and item and (item.onLeft or item.onRight) then
      if dir == "left" and item.onLeft then item.onLeft(item, self) end
      if dir == "right" and item.onRight then item.onRight(item, self) end
      syncScroll(self)
      return true
    end
    if dir == "up" then
      moveIndex(self, -1)
    elseif dir == "down" then
      moveIndex(self, 1)
    elseif dir == "left" and self.pageJump then
      moveIndex(self, -self.rows)
    elseif dir == "right" and self.pageJump then
      moveIndex(self, self.rows)
    else
      return false
    end
    syncScroll(self)
    return true
  end

  local function pageMove(self, dir)
    moveIndex(self, dir == "left" and -self.rows or self.rows)
    syncScroll(self)
    return true
  end

  local origNew = ListMenu.new

  function ListMenu.new(game, title, items, opts)
    opts = opts or {}
    local self = origNew(game, title, items, opts)
    self.qePage = opts.qePage
    return self
  end

  function ListMenu:update(dt)
    if self.script then
      self.script(self)
      return
    end
    local input = self.game.input
    if #self.items == 0 then
      if input:wasPressed("a") or input:wasPressed("b") then
        beep(self)
        self.game.stack:pop()
        if self.onCancel then self.onCancel() end
      end
      return
    end

    local moved = false
    if input:wasPressed("up") then
      moved = navPressed(self, "up")
      self.holdDir, self.holdFrames = "up", 0
    elseif input:wasPressed("down") then
      moved = navPressed(self, "down")
      self.holdDir, self.holdFrames = "down", 0
    elseif input:wasPressed("left") then
      moved = navPressed(self, "left")
      self.holdDir, self.holdFrames = "left", 0
    elseif input:wasPressed("right") then
      moved = navPressed(self, "right")
      self.holdDir, self.holdFrames = "right", 0
     elseif self.qePage and input:wasPressed("pageUp") then
      local item = self.items[self.index]
      if item and item.onPageUp then
        item.onPageUp(item, self)
        syncScroll(self)
        moved = true
      else
        moved = pageMove(self, "left")
      end
     elseif self.qePage and input:wasPressed("pageDown") then
      local item = self.items[self.index]
      if item and item.onPageDown then
        item.onPageDown(item, self)
        syncScroll(self)
        moved = true
      else
        moved = pageMove(self, "right")
      end
    elseif self.onSelectKey and input:wasPressed("select") then
      self.onSelectKey(self.items[self.index], self)
    elseif input:wasPressed("b") then
      beep(self)
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
      return
    elseif input:wasPressed("a") then
      beep(self)
      local item = self.items[self.index]
      if self.onChoose then
        self.onChoose(item, self)
      end
      return
    end

    if self.keyRepeat then
      local dir = self.holdDir
      if dir and input:isDown(dir) then
        self.holdFrames = self.holdFrames + 1
        local afterDelay = self.holdFrames - self.repeatDelay
        if afterDelay >= 0 and afterDelay % self.repeatRate == 0 then
          navPressed(self, dir)
        end
      else
        self.holdDir, self.holdFrames = nil, 0
      end
    end

    if not moved then syncScroll(self) end
  end

  ListMenu._patched = true
end

local function patchWorldAPI()
  local WorldAPI = require("src.world.WorldAPI")
  if not WorldAPI or WorldAPI.rebaseMap then return end

  function WorldAPI:rebaseMap(mapId, cellShiftX, cellShiftY)
    local ow = self:overworld()
    if not ow then return true end
    if ow.npcPool then
      local prefix = mapId .. "_obj_"
      for key in pairs(ow.npcPool) do
        if type(key) == "string" and key:sub(1, #prefix) == prefix then
          ow.npcPool[key] = nil
        end
      end
    end
    if ow.map and ow.map.id == mapId and ow.player
       and (cellShiftX ~= 0 or cellShiftY ~= 0) then
      local p = ow.player
      p.cellX = p.cellX + cellShiftX
      p.cellY = p.cellY + cellShiftY
      p.px, p.py = p.cellX * 16, p.cellY * 16
    end
    return true
  end
end

return function()
  patchInput()
  patchListMenu()
  patchWorldAPI()
end