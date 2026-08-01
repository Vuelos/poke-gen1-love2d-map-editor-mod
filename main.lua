-- Map Editor mod entry point.
-- Registers the editor screen, injects "MAP EDITOR" into the START menu,
-- intercepts F6 to toggle the editor, and auto-applies saved patches on
-- save load.

local SCREEN = "MapEditor"
local Save = require("mods.map_editor.func.save")

-- Walks the game state stack and save data to determine the current
-- overworld map ID.  Returns nil if no map can be identified.
local function currentMapId(game)
  local stack = game.stack
  if stack then
    local states = stack.states
    if states then
      for i = #states, 1, -1 do
        local s = states[i]
        if s.isOverworld and s.map and s.map.id then
          return s.map.id
        end
      end
    end
  end
  local save = game.save
  if save and save.player and save.player.map then return save.player.map end
  return nil
end

return function(mod)

  -- Registers the MapEditor screen so it can be opened by ID via
  -- Screens.push or mod.ui.push.
  mod.content.screens:register(SCREEN, {
    new = function(game, mapId)
      mapId = mapId or currentMapId(game) or "PALLET_TOWN"
       local MapEditor = require("mods.map_editor.scene.map_editor")
       local screen = MapEditor.new(mod, game, mapId)
      if not screen then
        mod.log:error("Could not create editor for map %s", mapId)
        local s = { game = game, isOpaque = true }
        function s:draw()
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.rectangle("fill", 0, 0, 160, 144)
          love.graphics.setColor(0, 0, 0, 1)
          mod.ui.Font.draw("EDITOR ERROR", 32, 40)
          mod.ui.Font.draw("Could not load map", 16, 60)
          mod.ui.Font.draw(mapId, 16, 70)
          mod.ui.Font.draw("Check tileset assets", 8, 80)
        end
        function s:onKeyPressed() self.game.stack:pop() end
        return s
      end
      return screen
    end,
  })

  -- Intercepts F6 to toggle the map editor open/closed.
  -- Also intercepts 1-6 and Escape while the editor is on the stack
  -- to allow mode switching and menu closing from sub-menus.
  do
    local Game = require("src.core.Game")
    local SCREEN_ID = "MapEditor"
    local orig = Game.keypressed
    if orig then
      Game.keypressed = function(self, key)
        local states = self.stack and self.stack.states
        if key == "f6" then
          if states then
            for i = #states, 1, -1 do
              if states[i].screenId == SCREEN_ID then
                self.stack:pop(); return
              end
            end
          end
          local mapId = currentMapId(self)
          if mapId then
            require("src.ui.Screens").push(self, SCREEN_ID, mapId)
            return
          end
          mod.log:warn("F6: no overworld map to edit")
          return
        end
        -- Number keys: pop sub-menus above editor, forward key to editor
        if key >= "1" and key <= "3" and states then
          for i = #states, 1, -1 do
            if states[i].screenId == SCREEN_ID then
              while self.stack:top() ~= states[i] do self.stack:pop() end
              break
            end
          end
        end
        -- Escape: close top sub-menu if editor is on stack but not top
        if key == "escape" and states then
          local editorOnStack = false
          for i = #states, 1, -1 do
            if states[i].screenId == SCREEN_ID then
              editorOnStack = true; break
            end
          end
          if editorOnStack and self.stack:top() and self.stack:top().screenId ~= SCREEN_ID then
            self.stack:pop(); return
          end
        end
        return orig(self, key)
      end
    end
  end

  -- Listens for save.loaded events and applies any saved map patches
  -- to the game data, then invalidates the map loader cache so the
  -- changes take effect.
  mod.events:on("save.loaded", function()
    local patches = mod.save:get("map_editor_patches", {})
    if not next(patches) then return end
    local Data = require("src.core.Data")
    local count = Save.applyPatchesToData(patches, Data)
    if count > 0 then
      mod.log:info("Applied %d map patches from save", count)
      local MapLoader = require("src.world.MapLoader")
      if MapLoader and MapLoader.invalidateAll then
        MapLoader.invalidateAll()
      end
    end
  end)

  mod.log:info("Map Editor loaded — F6 to open on current map, or START menu")
end