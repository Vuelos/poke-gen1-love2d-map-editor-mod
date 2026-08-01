-- Rendering for the text input dialog.

local TextInputDialog = {}

function TextInputDialog.draw(self)
  local Font = self.font
  if self.whiteBg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)
  else
    love.graphics.setColor(0.1, 0.1, 0.1, 0.9)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(1, 1, 1, 1)
  end
  Font.draw(self.title, 8, 16)
  Font.draw(">" .. self.text .. "_", 8, 48)
end

return TextInputDialog