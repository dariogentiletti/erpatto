-- minimal fake WoW API for logic tests
SECRET = setmetatable({}, { __tostring = function() error("secret printed") end, __concat = function() error("secret concatenated") end })
issecretvalue = function(v) return v == SECRET end
date = os.date; time = os.time
NOW = 1793660400
GetServerTime = function() return NOW end
GetTime = function() return NOW end
DEFAULT_CHAT_FRAME = { lines = {}, AddMessage = function(self, m) table.insert(self.lines, m) end }
