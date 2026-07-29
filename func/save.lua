-- Patch persistence for the map editor.
-- Builds minimal change-diff patches, saves/loads them via the mod save
-- system, and provides helpers for export and application.

local Common = require("mods.map_editor.func.common")
local Save = {}

local KEY = "map_editor_patches"
local ENC_KEY = "map_editor_encounter_patches"
local tablesEqual = Common.tablesEqual

-- Builds a minimal patch containing only the fields that differ between
-- the current map definition and the original snapshot.
function Save.buildPatch(mapDef, original)
  local patch = {}
  local tracked = {"blocks", "warps", "objects", "signs", "borderBlock", "width", "height", "textDefs"}
  if original then
    for _, key in ipairs(tracked) do
      local cur = mapDef[key]
      local orig = original[key]
      if not tablesEqual(cur, orig) then
        patch[key] = cur
      end
    end
  else
    for _, key in ipairs(tracked) do
      patch[key] = mapDef[key]
    end
  end
  return patch
end

-- Returns all saved patches from the mod save data.
function Save.getPatches(mod)
  return mod.save:get(KEY, {})
end

-- Persists a patch for the given mapId into the mod save system.
function Save.savePatch(mod, mapId, patch)
  local patches = Save.getPatches(mod)
  patches[mapId] = patch
  mod.save:set(KEY, patches)
end

-- Removes the patch for the given mapId from the mod save data.
function Save.removePatch(mod, mapId)
  local patches = Save.getPatches(mod)
  patches[mapId] = nil
  mod.save:set(KEY, patches)
end

-- Applies a patches table (mapId -> patch) to Data.maps entries in place.
-- Returns the number of maps that were patched.
function Save.applyPatchesToData(patches, data)
  local applied = 0
  for mapId, patch in pairs(patches) do
    local target = data.maps[mapId]
    if target then
      for key, value in pairs(patch) do
        target[key] = value
      end
      -- Inject custom text defs into the text resolution system
      if patch.textDefs and data.text_pointers and data.text then
        for _, td in ipairs(patch.textDefs) do
          if not data.text_pointers[mapId] then
            data.text_pointers[mapId] = {}
          end
          data.text_pointers[mapId][td.const] = { text = td.key }
          data.text[td.key] = td.text
        end
      end
      applied = applied + 1
    end
  end
  return applied
end

-- Formats a patch as a Lua source string suitable for export.
-- Returns nil if no patch exists for the given mapId.
function Save.exportAsLua(mod, mapId)
  local patches = Save.getPatches(mod)
  local patch = patches[mapId]
  if not patch then return nil end
  local lines = {
    "-- Map editor patch for " .. mapId,
    "return {",
  }
  for key, value in pairs(patch) do
    if key == "blocks" then
      lines[#lines + 1] = "  blocks = {"
      local parts = {}
      for _, v in ipairs(value) do
        parts[#parts + 1] = tostring(v)
      end
      lines[#lines + 1] = "    " .. table.concat(parts, ", ")
      lines[#lines + 1] = "  },"
    elseif type(value) == "table" then
      local ok, enc = pcall(require("src.mods.Merge").encode, value)
      lines[#lines + 1] = "  " .. key .. " = " .. (ok and enc or "{}") .. ","
    else
      lines[#lines + 1] = "  " .. key .. " = " .. tostring(value) .. ","
    end
  end
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n")
end

-- Saves an encounter patch for the given mapId.
function Save.saveEncounterPatch(mod, mapId, data)
  local patches = Save.getEncounterPatches(mod)
  patches[mapId] = data
  mod.save:set(ENC_KEY, patches)
end

-- Returns all saved encounter patches from the mod save data.
function Save.getEncounterPatches(mod)
  return mod.save:get(ENC_KEY, {})
end

-- Removes the encounter patch for the given mapId.
function Save.removeEncounterPatch(mod, mapId)
  local patches = Save.getEncounterPatches(mod)
  patches[mapId] = nil
  mod.save:set(ENC_KEY, patches)
end

-- Applies encounter patches to data.encounters.
function Save.applyEncounterPatches(patches, data)
  if not patches then return 0 end
  local applied = 0
  for mapId, encData in pairs(patches) do
    if data.encounters then
      data.encounters[mapId] = encData
      applied = applied + 1
    end
  end
  return applied
end

-- Writes a Lua file to the save directory under edited_maps/ and returns
-- the full path.
function Save.writeFile(mapId, luaContent)
  local path = "edited_maps/" .. mapId .. ".lua"
  love.filesystem.createDirectory("edited_maps")
  love.filesystem.write(path, luaContent)
  return love.filesystem.getSaveDirectory() .. "/" .. path
end

return Save