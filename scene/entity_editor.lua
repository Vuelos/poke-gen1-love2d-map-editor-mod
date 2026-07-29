local MODES = { BLOCKS = 1, WARPS = 2, OBJECTS = 3, SIGNS = 4 }

local EntityEditor = {}

local function resolveText(data, mapId, textConst)
  if not data or not data.text_pointers or not data.text then return textConst end
  local pointers = data.text_pointers[mapId]
  if not pointers then return textConst end
  local entry = pointers[textConst]
  if not entry then return textConst end
  local resolved = data.text[entry.text]
  if type(resolved) == "string" then
    return resolved:gsub("[\n\f\v\r]", " "):gsub("%s+", " "):sub(1, 30)
  end
  return textConst
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
  if screen.mode == MODES.WARPS then
    for _, w in ipairs(screen.def.warps) do
      if w.x >= cx0 and w.x < cx1 and w.y >= cy0 and w.y < cy1 then return "warp", w end
    end
  elseif screen.mode == MODES.OBJECTS then
    for _, o in ipairs(screen.def.objects) do
      if o.x >= cx0 and o.x < cx1 and o.y >= cy0 and o.y < cy1 then return "object", o end
    end
  elseif screen.mode == MODES.SIGNS then
    for _, s in ipairs(screen.def.signs) do
      if s.x >= cx0 and s.x < cx1 and s.y >= cy0 and s.y < cy1 then return "sign", s end
    end
  end
  return nil, nil
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
    table.insert(items, { label = ("Sprite: %s"):format(ent.sprite or "?"), value = "sprite" })
    table.insert(items, { label = "DELETE", value = "delete" })
    return items
  elseif kind == "sign" then
    local textContent = resolveText(screen.data, screen.mapId, ent.text)
    return {
      { label = ("Move (%d,%d)"):format(ent.x, ent.y), value = "move" },
      { label = ("Text: %s"):format(textContent), value = "text" },
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
  menu.title = (kind:upper()) .. " at " .. ent.x .. "," .. ent.y
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
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    (kind:upper()) .. " at " .. ent.x .. "," .. ent.y, items, {
    onChoose = function(item)
      if item.value == "delete" then
        EntityEditor.removeEntity(screen, kind, ent)
        screen.game.stack:pop()
        return
      end
      if item.value == "move" then
        screen.game.stack:pop()
      end
      EntityEditor.editField(screen, kind, ent, item.value)
    end,
  })
  screen._entityEditMenu = menu
  screen.game.stack:push(menu)
end

function EntityEditor.editField(screen, kind, ent, field)
  if field == "move" then
    EntityEditor.startMoving(screen, kind, ent)
  elseif field == "destWarp" then
    local box = screen.mod.ui.ListMenu.new(screen.game, "Edit DESTWARP", {
      { label = "DESTWARP +1", value = "inc" },
      { label = "DESTWARP -1", value = "dec" },
    }, { onChoose = function(c)
        if screen.undo then screen.undo:capture(screen.def) end
        if c.value == "inc" then ent.destWarp = ent.destWarp + 1
        elseif c.value == "dec" then ent.destWarp = math.max(0, ent.destWarp - 1) end
        screen.mapChanged = true
        screen.game.stack:pop()
        EntityEditor.refreshMenuItems(screen, kind, ent)
      end,
    })
    screen.game.stack:push(box)
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
  elseif field == "sprite" then
    local SpriteChooser = require("mods.map_editor.scene.sprite_chooser")
    SpriteChooser.new(screen.game, {
      initial = ent.sprite or "",
      onDone = function(sel)
        if sel then
          if screen.undo then screen.undo:capture(screen.def) end
          ent.sprite = sel; screen.mapChanged = true
        end
      end,
    })
  elseif field == "dest" then
    local TextInput = require("mods.map_editor.scene.text_input")
    local dialog = TextInput.new(screen.game, {
      title = "Dest map ID",
      maxLen = 24,
      initial = ent.destMap or "",
      onDone = function(text)
        if text then
          if screen.undo then screen.undo:capture(screen.def) end
          ent.destMap = text; screen.mapChanged = true
        end
      end,
    })
    screen.game.stack:push(dialog)
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
  screen.entityMovingOrig = { x = ent.x, y = ent.y }
end

-- Shows a type picker when creating a new object on an empty tile.
function EntityEditor.showObjectTypePicker(screen)
  local items = {
    { label = "NPC", value = "npc" },
    { label = "Item Ball", value = "item" },
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

function EntityEditor.removeEntity(screen, kind, ent)
  local arr = kind == "warp" and screen.def.warps or kind == "object" and screen.def.objects or screen.def.signs
  if not arr then return end
  if screen.undo then screen.undo:capture(screen.def) end
  for i = #arr, 1, -1 do if arr[i] == ent then table.remove(arr, i); break end end
  screen.mapChanged = true
end

return EntityEditor