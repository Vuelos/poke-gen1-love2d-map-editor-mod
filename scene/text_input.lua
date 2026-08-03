-- Text input dialog for the map editor.
-- Captures keyboard input to let the user enter arbitrary text strings.
-- Supports backspace, Enter (confirm), Escape (cancel), and typed
-- characters via love.textinput.  Pushes itself onto the game stack.

local TextInput = {}
local TextInputDialog = require("mods.map_editor.renderer.text_input")
TextInput.isOpaque = true

-- Opens a text input dialog and pushes it onto the game stack.
--   game     - The Game object.
--   opts     - { title, maxLen, initial, onDone }.
--              onDone(text) receives the entered text on confirm,
--              or nil on cancel.
function TextInput.new(game, opts)
  opts = opts or {}
  local self = {
    game = game,
    title = opts.title or "Enter text",
    maxLen = opts.maxLen or 32,
    text = opts.initial or "",
    onDone = opts.onDone,
    font = require("src.render.Font")
  }
  setmetatable(self, { __index = TextInput })

  -- Hook love.textinput to capture typed characters
  self._origTextInput = love.textinput
  love.textinput = function(t)
    if #self.text < self.maxLen then
      self.text = self.text .. t
    end
  end

  return self
end

-- Ensures love.textinput is restored when the screen is popped.
function TextInput:exit()
  self:_cleanup()
end

-- Restores the original love.textinput handler.
function TextInput:_cleanup()
  if self._origTextInput then
    love.textinput = self._origTextInput
    self._origTextInput = nil
  end
end

-- Handles key presses: backspace deletes last char, Enter confirms,
-- Escape cancels.  Both confirm and cancel restore love.textinput.
function TextInput:onKeyPressed(key)
  if key == "backspace" then
    self.text = self.text:sub(1, -2)
  elseif key == "return" or key == "kpenter" then
    self:_cleanup()
    self.game.stack:pop()
    if self.onDone then self.onDone(self.text) end
  elseif key == "escape" then
    self:_cleanup()
    self.game.stack:pop()
    if self.onDone then self.onDone(nil) end
  end
end

function TextInput:draw()
  TextInputDialog.draw(self)
end

return TextInput