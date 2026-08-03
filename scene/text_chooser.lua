-- Text chooser for the map editor.
-- Shows all TEXT_* constants defined for the current map with a preview
-- of the resolved text.  Includes a "Custom text..." option for entering
-- arbitrary text IDs or literal strings.
-- On selection, calls opts.onDone(textConst) where textConst is the
-- TEXT_* constant name (e.g. "TEXT_GENERIC") or the custom string entered
-- by the user.

local TextChooser = {}

-- Opens a text chooser dialog for the given map.
--   game     - The Game object.
--   def      - The map definition (screen.def) with .label field.
--   opts     - { title, onDone }.
--              onDone(textConst) receives the selected TEXT_* constant or
--              the custom text string entered by the user.
function TextChooser.new(game, def, opts)
  opts = opts or {}
  local mapLabel = def.label or def.id
  local title = opts.title or ("Texts: " .. mapLabel)

  local pointers = {}
  if game.data and game.data.text_pointers then
    pointers = game.data.text_pointers[mapLabel] or {}
  end

  local items = {}

  for constName, entry in pairs(pointers) do
    local resolved = nil
    if entry.text and game.data and game.data.text then
      resolved = game.data.text[entry.text]
    end
    if not resolved and entry.label and game.data and game.data.text then
      resolved = game.data.text["_" .. entry.label]
    end
    local content = ""
    if type(resolved) == "string" then
      content = resolved:gsub("[\n\f\v\r]", " "):gsub("%s+", " ")
    end

    -- ListMenu draws label at x=16 and right text at x=152-Font.width(right).
    -- Show the message content as the label and the const name as right text.
    local displayLabel = content
    if #displayLabel == 0 then displayLabel = constName end
    local displayRight = constName
    local avail = 17
    local labelLen = #displayLabel
    local rightLen = #displayRight
    if labelLen + rightLen > avail then
      local maxLabel = avail - rightLen - 3
      if maxLabel < 1 then
        displayRight = nil
        maxLabel = avail - 3
      end
      if maxLabel >= 1 and maxLabel < labelLen then
        displayLabel = displayLabel:sub(1, maxLabel) .. "..."
      end
    end

    table.insert(items, {
      label = displayLabel,
      right = displayRight,
      value = constName,
    })
  end

  table.sort(items, function(a, b) return (a.label or "") < (b.label or "") end)
  table.insert(items, 1, { label = "Custom text...", value = "__custom__" })

  if #items == 1 then
    table.insert(items, { label = "(no texts found)", value = nil })
  end

  local menu = require("src.ui.ListMenu").new(game, title, items, {
    onChoose = function(item, menu)
      if not item.value then return end
      menu.game.stack:pop()
      if item.value == "__custom__" then
        local TextInput = require("mods.map_editor.scene.text_input")
        menu.game.stack:push(TextInput.new(menu.game, {
          title = "Enter message text",
          maxLen = 64,
          onDone = function(text)
            if text and #text > 0 then
              local n = #(def.textDefs or {}) + 1
              local constName = "TEXT_EDITOR_" .. tostring(n)
              local textKey = "map_editor_" .. mapLabel .. "_" .. constName
              def.textDefs = def.textDefs or {}
              table.insert(def.textDefs, { const = constName, key = textKey, text = text })
              -- Inject into game data immediately so it resolves now
              if game.data and game.data.text_pointers and game.data.text then
                if not game.data.text_pointers[mapLabel] then
                  game.data.text_pointers[mapLabel] = {}
                end
                game.data.text_pointers[mapLabel][constName] = { text = textKey }
                game.data.text[textKey] = text
              end
              if opts.onDone then opts.onDone(constName) end
            else
              if opts.onDone then opts.onDone(nil) end
            end
          end,
        }))
      else
        if opts.onDone then opts.onDone(item.value) end
      end
    end,
  })

  game.stack:push(menu)
end

return TextChooser