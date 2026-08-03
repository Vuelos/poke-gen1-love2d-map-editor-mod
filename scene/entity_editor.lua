local Common = require("mods.map_editor.func.common")
local Palette = require("mods.map_editor.scene.palette")
local MODES = Common.MODES

local EntityEditor = {}

local function resolveText(data, mapId, textConst)
  if not data or not data.text_pointers or not data.text then return textConst end
  local pointers = data.text_pointers[mapId]
  if not pointers then return textConst end
  local entry = pointers[textConst]
  if not entry then return textConst end

  local resolved = nil
  if entry.text and data.text then
    resolved = data.text[entry.text]
  end
  if not resolved and entry.label and data.text then
    resolved = data.text["_" .. entry.label]
  end

  local content = ""
  if type(resolved) == "string" then
    content = resolved:gsub("[\n\f\v\r]", " "):gsub("%s+", " ")
  end
  return content ~= "" and content or textConst
end

local function objectType(ent)
  if not ent then return nil end
  if ent.trainerClass then return "trainer"
  elseif ent.item then return "item"
  else return "npc" end
end

local function objectItemsList(data)
  if not data or not data.items then return {} end
  local keys = {}
  for k in pairs(data.items) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

local function trainerClassList(data)
  if not data or not data.trainers then return {} end
  local keys = {}
  for k in pairs(data.trainers) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

function EntityEditor.selectedEntity(screen)
  local cx0 = screen.cursorBx
  local cy0 = screen.cursorBy
  local cx1 = cx0 + (screen.brushSize or 1)
  local cy1 = cy0 + (screen.brushSize or 1)
  if screen.mode == MODES.ENT then
    for _, w in ipairs(screen.def.warps or {}) do
      if w.x >= cx0 and w.x < cx1 and w.y >= cy0 and w.y < cy1 then return "warp", w end
    end
    for _, o in ipairs(screen.def.objects or {}) do
      if o.x >= cx0 and o.x < cx1 and o.y >= cy0 and o.y < cy1 then return "object", o end
    end
    for _, s in ipairs(screen.def.signs or {}) do
      if s.x >= cx0 and s.x < cx1 and s.y >= cy0 and s.y < cy1 then return "sign", s end
    end
    local conns = screen.def.connections or {}
    local mw = screen.def.width * 2
    local mh = screen.def.height * 2
    for dir, conn in pairs(conns) do
      local off = (conn.offset or 0) * 2
      local cxo, cyo, cw, ch
      if dir == "north" then
        cw = mw; ch = 4
        cxo = off; cyo = -ch
      elseif dir == "south" then
        cw = mw; ch = 4
        cxo = off; cyo = mh
      elseif dir == "west" then
        cw = 4; ch = mh
        cxo = -cw; cyo = off
      elseif dir == "east" then
        cw = 4; ch = mh
        cxo = mw; cyo = off
      else
        cxo = 0; cyo = 0; cw = 0; ch = 0
      end
      if cx0 >= cxo and cx0 < cxo + cw and cy0 >= cyo and cy0 < cyo + ch then
        screen._selectedDir = dir
        return "connection", conn
      end
    end
    screen._selectedDir = nil
  end
  return nil, nil
end

-- Returns a flat, ordered list of all entities (warps, objects, signs,
-- connections) with the cursor position that targets each one.
local function allEntities(screen)
  local out = {}
  local def = screen.def
  for _, w in ipairs(def.warps or {}) do
    out[#out + 1] = { kind = "warp", ent = w, bx = w.x, by = w.y }
  end
  for _, o in ipairs(def.objects or {}) do
    out[#out + 1] = { kind = "object", ent = o, bx = o.x, by = o.y }
  end
  for _, s in ipairs(def.signs or {}) do
    out[#out + 1] = { kind = "sign", ent = s, bx = s.x, by = s.y }
  end
  local mw = def.width * 2; local mh = def.height * 2
  for dir, c in pairs(def.connections or {}) do
    local off = (c.offset or 0) * 2
    local bx, by
    if dir == "north" then bx = off + mw / 2; by = -2
    elseif dir == "south" then bx = off + mw / 2; by = mh + 2
    elseif dir == "west" then bx = -2; by = off + mh / 2
    else bx = mw + 2; by = off + mh / 2 end
    out[#out + 1] = { kind = "connection", ent = c, dir = dir, bx = bx, by = by }
  end
  return out
end

-- True when another object/sign/warp on this map already uses `name`
-- (excluding `exclude`), so entity names stay unique within a map.
function EntityEditor.isEntityNameUsed(screen, name, exclude)
  local def = screen.def
  for _, arr in ipairs({ def.objects or {}, def.signs or {}, def.warps or {} }) do
    for _, ent in ipairs(arr) do
      if ent ~= exclude and ent.name and ent.name == name then return true end
    end
  end
  return false
end

-- Cycles the selection to the previous/next entity on the map (ENT mode),
-- moving the cursor to target it and syncing the sprite palette highlight.
function EntityEditor.cycleEntity(screen, dir)
  local list = allEntities(screen)
  if #list == 0 then return end
  local idx = nil
  local kind, ent = EntityEditor.selectedEntity(screen)
  if kind then
    for i, item in ipairs(list) do
      if item.ent == ent and item.kind == kind then idx = i; break end
    end
  end
  if not idx then
    for i, item in ipairs(list) do
      if item.kind == "connection" and item.dir == screen._selectedDir then idx = i; break end
    end
  end
  if not idx then idx = 1
  elseif dir == "prev" then idx = (idx - 2 + #list) % #list + 1
  else idx = idx % #list + 1 end
  local item = list[idx]
  screen.cursorBx = item.bx
  screen.cursorBy = item.by
  if item.kind == "connection" then
    screen._selectedDir = item.dir
  end
  if item.kind == "object" and item.ent.sprite then
    for i, sid in ipairs(screen.spriteList or {}) do
      if sid == item.ent.sprite then screen.selectedBlock = i; break end
    end
  end
end

function EntityEditor.buildItems(screen, kind, ent)
  if kind == "warp" then
    return {
      { label = ("Move (%d,%d)"):format(ent.x, ent.y), value = "move" },
      { label = ("Dest: %s"):format(ent.destMap), value = "dest" },
      { label = ("Warp: %d"):format(ent.destWarp), value = "destWarp" },
      { label = "DELETE", value = "delete" },
    }
  elseif kind == "object" then
    local otype = objectType(ent)
    local items = {
      { label = ("Move (%d,%d)"):format(ent.x, ent.y), value = "move" },
      { label = ("Sprite: Change"), value = "sprite" },
      { label = ("Name: %s"):format(ent.name or "NONE"), value = "name" },
    }
    if otype == "item" then
      table.insert(items, { label = ("Item: %s"):format(ent.item or "NONE"), value = "item" })
    elseif otype == "trainer" then
      table.insert(items, { label = ("Class: %s"):format(ent.trainerClass), value = "trainerClass" })
      table.insert(items, { label = ("Party: %d"):format(ent.trainerParty or 1), value = "trainerParty" })
    end
    table.insert(items, { label = ("Move: %s"):format(ent.movement), value = "movement" })
    table.insert(items, { label = ("Range: %s"):format(ent.range or "NONE"), value = "range" })
    local textContent = resolveText(screen.data, screen.mapId, ent.text)
    table.insert(items, { label = ("Text: %s"):format(textContent), value = "text" })
    table.insert(items, { label = "DELETE", value = "delete" })
    return items
  elseif kind == "sign" then
    local textContent = resolveText(screen.data, screen.mapId, ent.text)
    return {
      { label = ("Move (%d,%d)"):format(ent.x, ent.y), value = "move" },
      { label = ("Text: %s"):format(textContent), value = "text" },
      { label = "DELETE", value = "delete" },
    }
  elseif kind == "connection" then
    return {
      { label = ("Move %s"):format(screen._selectedDir or "?"), value = "move" },
      { label = ("Map: %s"):format(ent.map or "NONE"), value = "map" },
      { label = "DELETE", value = "delete" },
    }
  end
  return nil
end

function EntityEditor.refreshMenuItems(screen, kind, ent)
  local menu = screen._entityEditMenu
  if not menu then return end
  local items = EntityEditor.buildItems(screen, kind, ent)
  if not items then return end
  menu.items = items
  if kind == "connection" then
    menu.title = (kind:upper()) .. " " .. (screen._selectedDir or "?")
  else
    menu.title = (kind:upper()) .. " at " .. (ent.x or "?") .. "," .. (ent.y or "?")
  end
  menu.index = 1
  menu.scroll = 0
end

function EntityEditor.addEntity(screen, kind)
  if screen.undo then screen.undo:capture(screen.def) end
  local cx = screen.cursorBx
  local cy = screen.cursorBy
  if kind == "warp" then
    table.insert(screen.def.warps, { x = cx, y = cy, destMap = screen.mapId, destWarp = 1 })
  elseif kind == "object" then
    EntityEditor.showObjectTypePicker(screen)
  elseif kind == "sign" then
    table.insert(screen.def.signs, { x = cx, y = cy, text = "TEXT_GENERIC" })
  elseif kind == "connection" then
    EntityEditor.showConnectionDirPicker(screen)
  elseif kind == "npc" then
    table.insert(screen.def.objects, { index = #screen.def.objects + 1, x = cx, y = cy,
      sprite = "SPRITE_YOUNGSTER", movement = "STAY", range = "NONE", text = "TEXT_GENERIC" })
  elseif kind == "item" then
    table.insert(screen.def.objects, { index = #screen.def.objects + 1, x = cx, y = cy,
      sprite = "SPRITE_POKE_BALL", movement = "STAY", range = "NONE", text = "TEXT_GENERIC",
      item = "POTION" })
  elseif kind == "trainer" then
    local trainerId = "OPP_YOUNGSTER"
    if screen.data and screen.data.trainers then
      for k in pairs(screen.data.trainers) do trainerId = k; break end
    end
    table.insert(screen.def.objects, { index = #screen.def.objects + 1, x = cx, y = cy,
      sprite = "SPRITE_YOUNGSTER", movement = "WALK", range = "ANY_DIR", text = "TEXT_GENERIC",
      trainerClass = trainerId, trainerParty = 1 })
  end
  screen.mapChanged = true
end

function EntityEditor.editEntity(screen, kind, ent)
  local items = EntityEditor.buildItems(screen, kind, ent)
  if not items then return end
  local title
  if kind == "connection" then
    title = (kind:upper()) .. " " .. (screen._selectedDir or "?")
  else
    title = (kind:upper()) .. " at " .. (ent.x or "?") .. "," .. (ent.y or "?")
  end
  local menu = screen.mod.ui.ListMenu.new(screen.game, title, items, {
    onChoose = function(item)
      if item.value == "delete" then
        EntityEditor.removeEntity(screen, kind, ent)
        screen.game.stack:pop()
        return
      end
      if item.value == "move" then
        screen.game.stack:pop()
      end
       if item.value == "sprite" then
         -- Enter sprite picker mode: the palette gains focus and its cursor
         -- is parked on the entity's current sprite.  WASD/arrows move the
         -- cursor (scrolling the page so every sprite stays reachable),
         -- Enter confirms the change, Escape cancels.
         local currentSprite = ent.sprite or ""
         local itemIndex = 1
         for i, sid in ipairs(screen.spriteList or {}) do
           if sid == currentSprite then itemIndex = i; break end
         end
         screen.selectedBlock = itemIndex
         Palette.focus(screen)
         screen._spritePicker = {
          ent = ent,
          kind = kind,
          origSprite = currentSprite,
        }
        screen.game.stack:pop()
      else
        EntityEditor.editField(screen, kind, ent, item.value)
      end
    end,
  })
  screen._entityEditMenu = menu
  screen.game.stack:push(menu)
end

function EntityEditor.editField(screen, kind, ent, field)
  if field == "map" then
    if kind == "connection" then
      local items = { { label = "New map...", value = "__new__" } }
      local maps = {}
      for mapId in pairs(screen.game.data.maps or {}) do table.insert(maps, mapId) end
      table.sort(maps)
      for _, mapId in ipairs(maps) do
        table.insert(items, { label = mapId, value = mapId })
      end
      local box = screen.mod.ui.ListMenu.new(screen.game, "Select Map", items, {
        qePage = true,
        onChoose = function(c)
          screen.game.stack:pop()
          if c.value == "__new__" then
            screen._pendingConn = {
              conn = ent, dir = screen._selectedDir or "east", move = false,
            }
            screen:newMapDialog(screen._selectedDir)
            return
          end
          if screen.undo then screen.undo:capture(screen.def) end
          ent.map = c.value; screen.mapChanged = true
        end,
      })
      screen.game.stack:push(box)
      return
    end
  end
  if field == "move" then
    EntityEditor.startMoving(screen, kind, ent)
  elseif field == "sprite" then
    local items = {}
    for _, id in ipairs(screen.spriteList or {}) do
      table.insert(items, { label = id, value = id })
    end
    local box = screen.mod.ui.ListMenu.new(screen.game, "Select sprite", items, {
      onChoose = function(c)
        screen.game.stack:pop()
        if screen.undo then screen.undo:capture(screen.def) end
        ent.sprite = c.value; screen.mapChanged = true
        for i, sid in ipairs(screen.spriteList or {}) do
          if sid == c.value then screen.selectedBlock = i; break end
        end
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })
    screen.game.stack:push(box)
  elseif field == "destWarp" then
  local items = {}

  local destMap = screen.game.data.maps and screen.game.data.maps[ent.destMap]

  if destMap and destMap.warps then
    for i, warp in ipairs(destMap.warps) do
      local label = warp.label or ("Warp " .. (i - 1))

      table.insert(items, {
        label = string.format(
          "%d: %s (%d, %d)",
          i - 1,
          label,
          warp.x,
          warp.y
        ),
        value = i - 1, -- 0-based
      })
    end
  end

  local box = screen.mod.ui.ListMenu.new(screen.game, "Select Destination Warp", items, {
    onChoose = function(c)
      if screen.undo then
        screen.undo:capture(screen.def)
      end

      ent.destWarp = c.value
      screen.mapChanged = true

      screen.game.stack:pop()
      EntityEditor.refreshMenuItems(screen, kind, ent)
    end,
  })

    screen.game.stack:push(box)
  elseif field == "name" then
    local TextInput = require("mods.map_editor.scene.text_input")
    local function open()
      local input = TextInput.new(screen.game, {
        title = "Object name",
        maxLen = 32,
        initial = ent.name or "",
        onDone = function(text)
          if text and text ~= "" then
            if EntityEditor.isEntityNameUsed(screen, text, ent) then
              open()
              return
            end
            if screen.undo then screen.undo:capture(screen.def) end
            ent.name = text; screen.mapChanged = true
            EntityEditor.refreshMenuItems(screen, kind, ent)
          end
        end,
      })
      screen.game.stack:push(input)
    end
    open()
  elseif field == "movement" then
    local box = screen.mod.ui.ListMenu.new(screen.game, "Movement", {
      { label = "STAY", value = "STAY" }, { label = "WALK", value = "WALK" },
    }, { onChoose = function(c)
      if screen.undo then screen.undo:capture(screen.def) end
      ent.movement = c.value; screen.mapChanged = true
      screen.game.stack:pop()
      EntityEditor.refreshMenuItems(screen, kind, ent)
    end })
    screen.game.stack:push(box)
  elseif field == "range" then
    local box = screen.mod.ui.ListMenu.new(screen.game, "Range", {
      { label = "NONE", value = "NONE" },
      { label = "UP", value = "UP" },
      { label = "RIGHT", value = "RIGHT" },
      { label = "DOWN", value = "DOWN" },
      { label = "LEFT", value = "LEFT" },
      { label = "ANY_DIR", value = "ANY_DIR" },
      { label = "LEFT_RIGHT", value = "LEFT_RIGHT" },
    }, { onChoose = function(c)
      if screen.undo then screen.undo:capture(screen.def) end
      ent.range = c.value; screen.mapChanged = true
      screen.game.stack:pop()
      EntityEditor.refreshMenuItems(screen, kind, ent)
    end })
    screen.game.stack:push(box)
  elseif field == "item" then
    local list = objectItemsList(screen.data)
    local items = {}
    for _, id in ipairs(list) do
      table.insert(items, { label = id, value = id })
    end
    local box = screen.mod.ui.ListMenu.new(screen.game, "Select item", items, {
      onChoose = function(c)
        screen.game.stack:pop()
        if screen.undo then screen.undo:capture(screen.def) end
        ent.item = c.value; screen.mapChanged = true
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })
    screen.game.stack:push(box)
  elseif field == "trainerClass" then
    local list = trainerClassList(screen.data)
    local items = {}
    for _, id in ipairs(list) do
      table.insert(items, { label = id, value = id })
    end
    local box = screen.mod.ui.ListMenu.new(screen.game, "Trainer class", items, {
      onChoose = function(c)
        screen.game.stack:pop()
        if screen.undo then screen.undo:capture(screen.def) end
        ent.trainerClass = c.value; ent.trainerParty = 1; screen.mapChanged = true
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })
    screen.game.stack:push(box)
  elseif field == "trainerParty" then
    local max = 1
    if ent.trainerClass and screen.data and screen.data.trainers then
      local def = screen.data.trainers[ent.trainerClass]
      if def and def.parties then max = #def.parties end
    end
    local items = {
      { label = ("Party +1 (max %d)"):format(max), value = "inc" },
      { label = ("Party -1"), value = "dec" },
    }
    local box = screen.mod.ui.ListMenu.new(screen.game,
      ("Party index: %d"):format(ent.trainerParty or 1), items, {
      onChoose = function(c)
        screen.game.stack:pop()
        if screen.undo then screen.undo:capture(screen.def) end
        if c.value == "inc" then ent.trainerParty = math.min(max, (ent.trainerParty or 1) + 1)
        elseif c.value == "dec" then ent.trainerParty = math.max(1, (ent.trainerParty or 1) - 1) end
        screen.mapChanged = true
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })
    screen.game.stack:push(box)
  elseif field == "dest" then
    local items = {}

    for mapId, map in pairs(screen.game.data.maps or {}) do
      table.insert(items, {
        label = string.format("%s - %s", mapId, map.name or map.label or mapId),
        value = mapId,
      })
    end

    table.sort(items, function(a, b)
      return a.label < b.label
    end)

    local box = screen.mod.ui.ListMenu.new(screen.game, "Select Destination Map", items, {
      qePage = true,
      onChoose = function(c)
        if screen.undo then
          screen.undo:capture(screen.def)
        end

        ent.destMap = c.value
        screen.mapChanged = true

        screen.game.stack:pop()
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })

  screen.game.stack:push(box)
  elseif field == "text" then
    local TextChooser = require("mods.map_editor.scene.text_chooser")
    TextChooser.new(screen.game, screen.def, {
      title = "Edit message text",
      onDone = function(textConst)
        if textConst then
          if screen.undo then screen.undo:capture(screen.def) end
          ent.text = textConst; screen.mapChanged = true
        end
      end,
    })
  end
end

function EntityEditor.startMoving(screen, kind, ent)
  if not screen or not ent then return end
  if screen.undo then screen.undo:capture(screen.def) end
  screen.entityMoving = true
  screen.entityMovingKind = kind
  screen.entityMovingTarget = ent
  if kind == "connection" then
    screen.entityMovingOrig = { offset = ent.offset or 0 }
    -- Position cursor at connection zone so scroll follows
    local dir = screen._selectedDir
    local mw = screen.def.width * 2; local mh = screen.def.height * 2
    local off = (ent.offset or 0) * 2
    if dir == "north" then screen.cursorBx = off + mw / 2; screen.cursorBy = -2
    elseif dir == "south" then screen.cursorBx = off + mw / 2; screen.cursorBy = mh + 2
    elseif dir == "west" then screen.cursorBx = -2; screen.cursorBy = off + mh / 2
    elseif dir == "east" then screen.cursorBx = mw + 2; screen.cursorBy = off + mh / 2 end
  else
    screen.entityMovingOrig = { x = ent.x, y = ent.y }
  end
end

-- Shows a picker when creating a new entity on an empty tile in ENT mode.
function EntityEditor.showCreatePicker(screen)
  local items = {
    { label = "Warp", value = "warp" },
    { label = "Object", value = "object" },
    { label = "Sign", value = "sign" },
    { label = "Connection", value = "connection" },
  }
  local menu = screen.mod.ui.ListMenu.new(screen.game, "Create entity", items, {
    onChoose = function(c)
      screen.game.stack:pop()
      EntityEditor.addEntity(screen, c.value)
    end,
  })
  screen.game.stack:push(menu)
end

-- Shows a type picker when creating a new object on an empty tile.
function EntityEditor.showObjectTypePicker(screen)
  local items = {
    { label = "NPC", value = "npc" },
    { label = "Item", value = "item" },
    { label = "Trainer", value = "trainer" },
  }
  local menu = screen.mod.ui.ListMenu.new(screen.game, "Create object type", items, {
    onChoose = function(c)
      screen.game.stack:pop()
      EntityEditor.addEntity(screen, c.value)
    end,
  })
  screen.game.stack:push(menu)
end

-- Shows a direction picker when creating or editing a connection.
-- If editing an existing connection, allows changing its direction key.
function EntityEditor.showConnectionDirPicker(screen, existingEnt)
  local items = {
    { label = "North", value = "north" },
    { label = "South", value = "south" },
    { label = "East", value = "east" },
    { label = "West", value = "west" },
  }
  local title = existingEnt and "Change direction" or "Connection direction"
  local menu = screen.mod.ui.ListMenu.new(screen.game, title, items, {
    onChoose = function(c)
      screen.game.stack:pop()
      if not screen.def.connections then screen.def.connections = {} end
      local dir = c.value
      screen._selectedDir = dir
      if existingEnt then
        for oldDir, conn in pairs(screen.def.connections) do
          if conn == existingEnt then
            if screen.undo then screen.undo:capture(screen.def) end
            screen.def.connections[oldDir] = nil
            screen.def.connections[dir] = conn
            screen.mapChanged = true
            EntityEditor.editEntity(screen, "connection", conn)
            return
          end
        end
      else
        if screen.def.connections[dir] then
          screen._selectedDir = dir
          EntityEditor.editEntity(screen, "connection", screen.def.connections[dir])
          return
        end
        if screen.undo then screen.undo:capture(screen.def) end
        local conn = { map = screen.mapId, offset = 0 }
        screen.def.connections[dir] = conn
        screen.mapChanged = true
        -- Ask where the connection should point, then enter moving mode so
        -- the user can position the silhouette on the map.
        screen._selectedDir = dir
        EntityEditor.chooseConnectionDestination(screen, conn, dir)
      end
    end,
  })
  screen.game.stack:push(menu)
end

-- Asks whether a new connection should point at an existing map or at a
-- freshly created map, then routes to the matching picker/dialog.
function EntityEditor.chooseConnectionDestination(screen, conn, dir)
  local menu = screen.mod.ui.ListMenu.new(screen.game, "Connection destination", {
    { label = "Existing map", value = "existing" },
    { label = "Create new map", value = "new" },
  }, {
    onChoose = function(c)
      screen.game.stack:pop()
      if c.value == "new" then
        screen._pendingConn = { conn = conn, dir = dir, move = true }
        screen:newMapDialog(dir)
      else
        EntityEditor.chooseExistingMap(screen, conn, dir)
      end
    end,
  })
  screen.game.stack:push(menu)
end

-- Lets the user pick an existing map as a connection's destination.
function EntityEditor.chooseExistingMap(screen, conn, dir)
  local items = {}
  for mapId in pairs(screen.data.maps or {}) do
    table.insert(items, { label = mapId, value = mapId })
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  local menu = screen.mod.ui.ListMenu.new(screen.game, "Select Map", items, {
    qePage = true,
    onChoose = function(c)
      screen.game.stack:pop()
      conn.map = c.value
      screen.mapChanged = true
      screen._selectedDir = dir
      EntityEditor.startMoving(screen, "connection", conn)
    end,
  })
  screen.game.stack:push(menu)
end

function EntityEditor.removeEntity(screen, kind, ent)
  if kind == "connection" then
    local conns = screen.def.connections or {}
    for dir, c in pairs(conns) do
      if c == ent then
        if screen.undo then screen.undo:capture(screen.def) end
        conns[dir] = nil
        screen.mapChanged = true
        return
      end
    end
    return
  end
  local arr = kind == "warp" and screen.def.warps or kind == "object" and screen.def.objects or screen.def.signs
  if not arr then return end
  if screen.undo then screen.undo:capture(screen.def) end
  for i = #arr, 1, -1 do if arr[i] == ent then table.remove(arr, i); break end end
  screen.mapChanged = true
end

return EntityEditor