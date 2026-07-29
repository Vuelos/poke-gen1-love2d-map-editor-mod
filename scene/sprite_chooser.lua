-- Sprite chooser for the map editor.
-- Lists all available sprite IDs from game.data.sprites with frame info.
-- Pushes a ListMenu onto the game stack; calls onDone(selectedId) on
-- selection, or onDone(nil) on cancel.

local SpriteChooser = {}

-- Opens a sprite selection dialog.
--   opts.title   - Menu title (default "Select Sprite").
--   opts.initial - Sprite ID to pre-select (e.g. "SPRITE_YOUNGSTER").
--   opts.onDone  - Callback: onDone(id) on select, onDone(nil) on cancel.
function SpriteChooser.new(game, opts)
  opts = opts or {}
  local items = {}
  local sprites = (game.data and game.data.sprites) or {}
  local keys = {}
  for k in pairs(sprites) do table.insert(keys, k) end
  table.sort(keys)

  for _, id in ipairs(keys) do
    local def = sprites[id]
    local info = tostring(def.frames or 1) .. "f"
    if def.walker then info = info .. " walk" end
    table.insert(items, { label = id, value = id, right = info })
  end

  if #items == 0 then
    table.insert(items, { label = "(no sprites found)", value = nil })
  end

  local menu = require("src.ui.ListMenu").new(game, opts.title or "Select Sprite", items, {
    onChoose = function(item, menu)
      if not item.value then return end
      menu.game.stack:pop()
      if opts.onDone then opts.onDone(item.value) end
    end,
    onCancel = function()
      if opts.onDone then opts.onDone(nil) end
    end,
  })

  -- Pre-select initial sprite if provided
  if opts.initial then
    for i, item in ipairs(items) do
      if item.value == opts.initial then menu.index = i; break end
    end
  end

  game.stack:push(menu)
end

return SpriteChooser