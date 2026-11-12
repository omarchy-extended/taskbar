-- omext taskbar: its key, if one is set ("key": "SUPER + CTRL + J" in
-- ~/.config/omext/taskbar.json; none by default). It brings the taskbar up
-- with the keyboard on it (Left and Right, Enter, Escape), and takes it down
-- again. Only while the taskbar is on in the shell.
local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local function read(path)
  local f = io.open(path, "r")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  return text
end
local keys = read(config .. "/omext/taskbar.json"):match('"key"%s*:%s*"([^"]+)"')
if keys and keys ~= "" and read(config .. "/omarchy/shell.json"):find('"omext.taskbar"', 1, true) then
  pcall(hl.unbind, keys)
  pcall(hl.bind, keys, hl.dsp.global("omext:taskbar-keys"), { description = "The taskbar, by keyboard" })
end
