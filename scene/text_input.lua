-- Text input dialog for the map editor.
-- Captures keyboard input to let the user enter arbitrary text strings.
-- Supports backspace, Enter (confirm), Escape (cancel), and typed
-- characters via love.textinput.  Pushes itself onto the game stack.
-- The gamepad A/B buttons confirm/cancel too, matching the editor's
-- ListMenu dialogs (polled through the Input abstraction in update()).

local TextInput = {}
local TextInputDialog = require("mods.map_editor.renderer.text_input")
TextInput.isOpaque = true

-- Marks this state as one that consumes typed characters: the map editor's
-- global key handler treats 1/2/3 as mode-switch keys, and those digits must
-- NOT fire while a name is being typed (they are text here, not commands).
TextInput.capturesText = true

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is
-- armed, and arming it is what raises the soft keyboard (src/import/
-- RomImporter.lua, #578).  Desktop has text input on by default and the
-- hosted save editor depends on it staying on (tools/save-editor/Kit.lua,
-- #529), so disarm only lowers on mobile.
function TextInput.isMobile()
  local osName = love.system and love.system.getOS and love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

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
    initial = opts.initial or "",
    onDone = opts.onDone,
    font = require("src.render.Font")
  }
  setmetatable(self, { __index = TextInput })

  if love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, true)
  end

  -- Hook love.textinput to capture typed characters.  The first keystroke
  -- replaces the prefilled default (e.g. "NEW_MAP") instead of appending to
  -- it, so typing a custom name never leaves the default glued to the front.
  self._origTextInput = love.textinput
  love.textinput = function(t)
    if #self.text < self.maxLen then
      if self.text ~= "" and self.text == self.initial then
        self.text = ""
      end
      self.text = self.text .. t
    end
  end

  return self
end

-- Called when the dialog is popped.  A pop from outside (the global Escape
-- handler, a parent flow bailing out) is a cancel, so it resolves the dialog
-- with onDone(nil) exactly once; confirm/cancel resolve it themselves first.
function TextInput:exit()
  if self._resolved then
    self:_cleanup()
    return
  end
  self._resolved = true
  self:_cleanup()
  if self.onDone then self.onDone(nil) end
end

-- Restores the original love.textinput handler and lowers the soft
-- keyboard on mobile only (setTextInput is global SDL state on desktop).
-- Idempotent: pop runs this once and the explicit commit/cancel paths run it
-- again, but the handler is only ever restored the first time.
function TextInput:_cleanup()
  if self._origTextInput ~= nil then
    love.textinput = self._origTextInput
    self._origTextInput = nil
  end
  if TextInput.isMobile() and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
  end
end

-- Polls the gamepad while this dialog is the top state: A confirms, B
-- cancels.  Keyboard input never overlaps here -- while this state is on
-- top, Game routes raw keys to onKeyPressed and skips the Input abstraction.
function TextInput:update()
  local input = self.game and self.game.input
  if not input or not input.wasPressed then return end
  if input:wasPressed("a") then
    self:_commit()
  elseif input:wasPressed("b") then
    self:_cancel()
  end
end

function TextInput:_commit()
  if self._resolved then return end
  self._resolved = true
  self:_cleanup()
  self.game.stack:pop()
  if self.onDone then self.onDone(self.text) end
end

function TextInput:_cancel()
  if self._resolved then return end
  self._resolved = true
  self:_cleanup()
  self.game.stack:pop()
  if self.onDone then self.onDone(nil) end
end

-- Handles key presses: backspace deletes last char, Enter confirms,
-- Escape cancels.  Digits are typed text (love.textinput delivers them), so
-- they are deliberately not handled here -- and the editor's mode-switch
-- keys are blocked while this state is on top (see capturesText).
function TextInput:onKeyPressed(key)
  if key == "backspace" then
    self.text = self.text:sub(1, -2)
  elseif key == "return" or key == "kpenter" then
    self:_commit()
  elseif key == "escape" then
    self:_cancel()
  end
end

function TextInput:draw()
  TextInputDialog.draw(self)
end

return TextInput
