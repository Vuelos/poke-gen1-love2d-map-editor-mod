-- Shared test runner for the map editor.  Each suite module returns
-- { name, setup?, teardown?, tests = { function names } }; this file
-- requires them all into one process, runs every test, and sets the
-- exit code from the combined result.  Run from the repo root with:
--
--   luajit mods/map_editor/tests/test_all.lua

package.path = "../../../?.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local SUITES = {
  require("mods.map_editor.tests.connection_tests"),
  require("mods.map_editor.tests.map_editor_tests"),
  require("mods.map_editor.tests.editor_screen_tests"),
}

local allOk = true

for _, suite in ipairs(SUITES) do
  if suite.setup then suite.setup() end
  local failed = {}
  for _, name in ipairs(suite.tests) do
    local ok, err = pcall(_G[name])
    if not ok then
      failed[#failed + 1] = name .. ": " .. tostring(err)
      allOk = false
    end
  end
  if suite.teardown then suite.teardown() end
  if #failed > 0 then
    print("\n=== SOME " .. suite.name .. " TESTS FAILED ===")
    for _, f in ipairs(failed) do print("  FAIL " .. f) end
  else
    print("\n=== ALL " .. suite.name .. " TESTS PASSED ===")
  end
end

if allOk then
  print("\n=== ALL TEST SUITES PASSED ===")
else
  print("\n=== SOME TEST SUITES FAILED ===")
  os.exit(1)
end
