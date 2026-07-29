local EncounterEditor = {}

-- Builds a list of species IDs sorted alphabetically from game data.
local function speciesList(data)
  if not data or not data.pokemon then return {} end
  local keys = {}
  for k in pairs(data.pokemon) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

-- Shows a +/- picker for a numeric field (rate or level).
local function editNumber(screen, groupKey, slotIdx, field, current)
  local items = {
    { label = "+1", value = "inc" },
    { label = "-1", value = "dec" },
  }
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    ("%s %s: %d"):format(groupKey, field, current), items, {
    onChoose = function(c)
      screen.game.stack:pop()
      local enc = screen.data.encounters[screen.mapId]
      if not enc then return end
      local target = slotIdx and enc[groupKey].slots[slotIdx] or enc[groupKey]
      if c.value == "inc" then target[field] = target[field] + 1
      elseif c.value == "dec" then
        if slotIdx then target[field] = math.max(1, target[field] - 1)
        else target[field] = target[field] - 1 end
      end
      if not slotIdx then target[field] = math.max(0, math.min(target[field], 255)) end
      EncounterEditor.edit(screen)
    end,
  })
  screen.game.stack:push(menu)
end

-- Shows a species picker list for a slot.
local function editSpecies(screen, groupKey, slotIdx, current)
  local list = speciesList(screen.data)
  local items = {}
  for _, id in ipairs(list) do
    table.insert(items, { label = id, value = id })
  end
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    ("%s %d species: %s"):format(groupKey, slotIdx, current), items, {
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

-- Edits a single encounter slot (species + level).
local function editSlot(screen, groupKey, slotIdx)
  local enc = screen.data.encounters[screen.mapId]
  if not enc or not enc[groupKey] then return end
  local slot = enc[groupKey].slots[slotIdx]
  if not slot then return end
  local items = {
    { label = ("Species: %s"):format(slot.species), value = "species" },
    { label = ("Level: %d"):format(slot.level), value = "level" },
  }
  local menu = screen.mod.ui.ListMenu.new(screen.game,
    ("%s slot %d"):format(groupKey, slotIdx), items, {
    onChoose = function(c)
      screen.game.stack:pop()
      if c.value == "species" then
        editSpecies(screen, groupKey, slotIdx, slot.species)
      elseif c.value == "level" then
        editNumber(screen, groupKey, slotIdx, "level", slot.level)
      end
    end,
  })
  screen.game.stack:push(menu)
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

  if enc.grass then
    table.insert(items, { label = ("Grass rate: %d"):format(enc.grass.rate),
                          group = "grass", field = "rate", slot = nil })
    for i, slot in ipairs(enc.grass.slots) do
      table.insert(items, { label = ("  %d: %s L%d"):format(i, slot.species, slot.level),
                            group = "grass", slot = i })
    end
  end

  if enc.water then
    table.insert(items, { label = ("Water rate: %d"):format(enc.water.rate),
                          group = "water", field = "rate", slot = nil })
    for i, slot in ipairs(enc.water.slots) do
      table.insert(items, { label = ("W%d: %s L%d"):format(i, slot.species, slot.level),
                            group = "water", slot = i })
    end
  end

  local menu = screen.mod.ui.ListMenu.new(screen.game,
    "Encounters: " .. mapId, items, {
    onChoose = function(c)
      screen.game.stack:pop()
      if c.field == "rate" then
        editNumber(screen, c.group, nil, "rate", enc[c.group].rate)
      elseif c.slot then
        editSlot(screen, c.group, c.slot)
      end
    end,
  })
  screen._entityEditMenu = menu
  screen.game.stack:push(menu)
end

return EncounterEditor