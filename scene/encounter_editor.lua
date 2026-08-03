local EncounterEditor = {}

-- Builds a list of species IDs sorted alphabetically from game data.
local function speciesList(data)
  if not data or not data.pokemon then return {} end
  local keys = {}
  for k in pairs(data.pokemon) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

-- Shows a species picker list for a slot.  Q/E page through the list.
local function editSpecies(screen, groupKey, slotIdx, current)
  local list = speciesList(screen.data)
  local items = {}
  for _, id in ipairs(list) do
    table.insert(items, { label = id, value = id })
  end
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    ("%s %d species: %s"):format(groupKey, slotIdx, current), items, {
    qePage = true,
    onChoose = function(c)
      screen.game.stack:pop()
      local enc = screen.data.encounters[screen.mapId]
      if not enc or not enc[groupKey] then return end
      enc[groupKey].slots[slotIdx].species = c.value
      EncounterEditor.edit(screen)
    end,
  })
  screen.game.stack:push(menu)
end

-- Edits a single encounter slot's species (level is adjusted directly from
-- the encounter list with left/right).
local function editSlot(screen, groupKey, slotIdx)
  local enc = screen.data.encounters[screen.mapId]
  if not enc or not enc[groupKey] then return end
  local slot = enc[groupKey].slots[slotIdx]
  if not slot then return end
  local items = {
    { label = ("Species: %s"):format(slot.species), value = "species" },
  }
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    ("%s slot %d"):format(groupKey, slotIdx), items, {
    onChoose = function(c)
      screen.game.stack:pop()
      if c.value == "species" then
        editSpecies(screen, groupKey, slotIdx, slot.species)
      end
    end,
  })
  screen.game.stack:push(menu)
end

-- Builds an onLeft/onRight/onPageUp/onPageDown pair that applies
-- a delta and re-labels the row in place.  `apply` returns false
-- (and nothing changes) at a clamp.
local function adjust(labelFn, apply)
  return {
    onLeft = function(item) if apply(-1) then item.label = labelFn() end end,
    onRight = function(item) if apply(1) then item.label = labelFn() end end,
    onPageUp = function(item) if apply(-10) then item.label = labelFn() end end,
    onPageDown = function(item) if apply(10) then item.label = labelFn() end end,
  }
end

-- Opens the encounter editor for the current map.
function EncounterEditor.edit(screen)
  local data = screen.data
  local mapId = screen.mapId
  local enc = data.encounters and data.encounters[mapId]
  if not enc then
    enc = { grass = { rate = 25, slots = {} } }
    for i = 1, 10 do
      table.insert(enc.grass.slots, { level = 5, species = "PIDGEY" })
    end
    data.encounters = data.encounters or {}
    data.encounters[mapId] = enc
  end

  local items = {}

  local function rateRow(group)
    local cap = group:sub(1, 1):upper() .. group:sub(2)
    local labelFn = function() return ("%s rate: %d"):format(cap, enc[group].rate) end
    local row = { label = labelFn(), group = group, field = "rate" }
    local edits = adjust(labelFn, function(d)
      local current = enc[group].rate
      local v = math.max(0, math.min(current + d, 100))
      if v == current then return false end
      enc[group].rate = v
      screen.mapChanged = true
      return true
    end)
    row.onLeft, row.onRight = edits.onLeft, edits.onRight
    return row
  end

  local function slotRow(group, i, slot)
    local labelFn = function() return ("  %d: %s L%d"):format(i, slot.species, slot.level) end
    local row = { label = labelFn(), group = group, slot = i }
    local edits = adjust(labelFn, function(d)
      local v = math.max(1, math.min(slot.level + d, 100))
      if v == slot.level then return false end
      slot.level = v
      screen.mapChanged = true
      return true
    end)
    row.onLeft, row.onRight = edits.onLeft, edits.onRight
    return row
  end

  if enc.grass then
    table.insert(items, rateRow("grass"))
    for i, slot in ipairs(enc.grass.slots) do
      table.insert(items, slotRow("grass", i, slot))
    end
  end

  if enc.water then
    table.insert(items, rateRow("water"))
    for i, slot in ipairs(enc.water.slots) do
      table.insert(items, slotRow("water", i, slot))
    end
  end

  local menu = screen.mod.ui.ListMenu.new(screen.game,
    "Encounters: " .. mapId, items, {
    qePage = true,
    onChoose = function(c)
      if not c.slot then return end
      screen.game.stack:pop()
      editSlot(screen, c.group, c.slot)
    end,
  })
  screen._entityEditMenu = menu
  screen.game.stack:push(menu)
end

return EncounterEditor
