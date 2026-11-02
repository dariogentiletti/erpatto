import os
from harness import new_runtime
lua, ns = new_runtime(['Util.lua', 'Model.lua'])
res = lua.execute(r'''
local ns = ...
''') if False else None
test = lua.eval(r'''function(ns)
  local U, M = ns.U, ns.M
  local out = {}
  local function add(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(p, " ") end
  -- Italian time
  local start = U.FromRome(2026, 11, 5, 0, 0)
  add("start epoch", start, "expected", 1793660400)
  add("start shown", U.When(start))
  local summer = U.FromRome(2027, 7, 1, 21, 0)
  add("summer", U.FormatRomeInput(summer), "utc hour", U.UTCParts(summer).hour)
  local dstStart = U.FromRome(2027, 3, 28, 3, 0)
  add("dst day 03:00 Rome -> UTC hour", U.UTCParts(dstStart).hour)
  add("parse", U.ParseRome("2026-11-05 00:00") == start, U.ParseRome("05/11/2026 00:00") == start, U.ParseRome("junk"))
  add("until", U.Until(2*86400 + 23*3600), U.Until(3700), U.Until(0))
  add("hours", U.Hours(11.5), U.Hours(29.4), U.Hours(1), U.Hours(0.4))
  add("thousands", U.Thousands(54100), U.Thousands(4084700), U.Thousands(400))
  -- model
  local settings = { start = start, calib = { { from = 1, h20 = 25, h60 = 190 } },
    teams = { { id = "t1", name = "I Cesaroni", pace = { { from = 1, hours = 12 } } },
              { id = "t2", name = "Carabinieri 8", pace = { { from = 1, hours = 30 } } } } }
  local s = M.Schedule(settings)
  local function caps(id) local c = {} for _, r in ipairs(s.teams[id]) do c[#c+1] = r.cap end return table.concat(c, ",") end
  add("slow", caps("t1"))
  add("fast", caps("t2"))
  add("weeks", s.n)
  local r1 = s.teams.t1[1]
  add("week1 slow ding XP", math.floor(r1.dingXp + 0.5), "hours", string.format("%.1f", r1.dingHours))
  -- pace change from week 3 with real level 14 and 10 hours
  settings.teams[1].pace[2] = { from = 3, hours = 10, level = 14 }
  local s2 = M.Schedule(settings)
  local c = {} for _, r in ipairs(s2.teams.t1) do c[#c+1] = r.cap end
  add("slow after change", table.concat(c, ","))
  -- calibration change from week 4 keeps weeks 1-3
  settings.calib[2] = { from = 4, h20 = 20, h60 = 150 }
  local s3 = M.Schedule(settings)
  local c3 = {} for _, r in ipairs(s3.teams.t1) do c3[#c3+1] = r.cap end
  add("slow after calib", table.concat(c3, ","))
  -- status
  ns.NOW = start + 8 * 86400
  local st = M.Status(settings, "t2", start + 8 * 86400)
  add("status fast wk", st.week, "cap", st.cap, "next", st.nextCap, "unlock", U.When(st.unlockAt), "finish", st.finishWeek)
  local pre = M.Status(settings, "t1", start - 3600)
  add("pre-start wk", pre.week, "cap", pre.cap, "started", pre.started, "unlock", U.When(pre.unlockAt))
  add("player", M.PlayerState(15, 19), M.PlayerState(19, 19), M.PlayerState(22, 19), M.PlayerState(0, 19))
  -- serializer
  local obj = { a = 1, b = "ciao|mondo,{x}=y\\z", c = { true, false, 3.25, "è" }, [5] = "cinque", nested = { deep = { deeper = "ok" } } }
  local txt = U.Serialize(obj)
  local back = U.Deserialize(txt)
  add("ser len", #txt, "roundtrip", back.a, back.b == obj.b, back.c[1], back.c[2], back.c[3], back.c[4], back[5], back.nested.deep.deeper)
  add("bad inputs", U.Deserialize("{sa=n1"), U.Deserialize("x"), U.Deserialize(string.rep("{", 50)), U.Deserialize(nil))
  add("code", U.RandomCode(8):match("^[A-Z2-9]+$") ~= nil)
  return table.concat(out, "\n")
end''')
print(test(ns))
