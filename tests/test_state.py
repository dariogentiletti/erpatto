import os
from harness import new_runtime
lua, ns = new_runtime(['Util.lua', 'Model.lua', 'Patto.lua'])
test = lua.eval(r'''function(ns)
  local U, M, P = ns.U, ns.M, ns.P
  local out = {}
  local function add(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(p, " ") end
  local fired = {}
  ns.On("SettingsChanged", function() fired.s = (fired.s or 0) + 1 end)
  ns.On("SelfChanged", function(_, why) fired.self = why end)
  -- codes
  local code = P.NewCode()
  add("code format", code:match("^PATTO%-%w%w%w%w%-%w%w%w%w$") ~= nil, "normalize", P.NormalizeCode(" " .. code:lower():gsub("%-", " ") .. " ") == code,
      "bad", P.NormalizeCode("PATTO-1234-OOOO"), P.NormalizeCode("abc"))
  add("channel", P.ChannelName("PATTO-K7Q2-M9XD"), "pw", P.ChannelPassword("PATTO-K7Q2-M9XD"), "pw stable", P.ChannelPassword("PATTO-K7Q2-M9XD") == P.ChannelPassword("PATTO-K7Q2-M9XD"))
  -- create (capo = Dario, fast team)
  local start = U.FromRome(2026, 11, 5, 0, 0)
  NOW = start - 86400
  local A = P.Create({ name = "Er Patto", start = start, h20 = 25, h60 = 190, guid = "G-DARIO", playerName = "Dario Rossi",
    teams = { { name = "I Cesaroni", hours = 12 }, { name = "Carabinieri 8", hours = 30 } }, teamIndex = 2 })
  add("created", A.settings.v, A.admins.capo, A.members["G-DARIO"].team, #A.settings.teams)
  -- joiner Pietro
  local B = P.Join(A.code, "G-PIETRO", "Pietro Cesaroni")
  add("joiner has settings", P.HasSettings(B))
  -- sync over the wire (serialize/deserialize like the network does)
  local function wire(x) return U.Deserialize(U.Serialize(x)) end
  add("merge admins", P.MergeAdmins(B, wire(A.admins)), "merge settings", P.MergeSettings(B, wire(A.settings)), "merge bans", P.MergeBans(B, wire(A.bans)))
  add("merge capo record", P.MergeMember(B, wire(A.members["G-DARIO"]), "G-PIETRO"))
  add("B sees", P.HasSettings(B), B.settings.teams[1].name, B.members["G-DARIO"].name)
  -- Pietro picks a team and the change flows back
  NOW = NOW + 60
  add("choose team", P.ChooseTeam(B, "G-PIETRO", "t1"), fired.self)
  add("bad team", P.ChooseTeam(B, "G-PIETRO", "t9"))
  add("A gets Pietro", P.MergeMember(A, wire(B.members["G-PIETRO"]), "G-DARIO"), P.TeamName(A, A.members["G-PIETRO"].team))
  -- same record again is ignored, my own record from others is ignored
  add("dupe ignored", P.MergeMember(A, wire(B.members["G-PIETRO"]), "G-DARIO") == false, "self ignored", P.MergeMember(A, wire(A.members["G-DARIO"]), "G-DARIO") == false)
  -- Pietro switches to the fast team: switch log on A
  NOW = NOW + 60
  P.ChooseTeam(B, "G-PIETRO", "t2")
  P.MergeMember(A, wire(B.members["G-PIETRO"]), "G-DARIO")
  add("switch log A", #A.switches, A.switches[1] and (A.switches[1].name .. " " .. tostring(A.switches[1].from) .. "->" .. tostring(A.switches[1].to)))
  -- permissions: Pietro cannot change pace, Dario can
  add("pietro pace", P.SetPace(B, "G-PIETRO", "t1", 8))
  add("dario pace", P.SetPace(A, "G-DARIO", "t1", 10), A.settings.v, "rows", #A.settings.teams[1].pace, A.settings.teams[1].pace[1].hours)
  -- forged settings from a non-admin are refused
  local forged = wire(A.settings); forged.v = 99; forged.by = "G-PIETRO"
  add("forged refused", P.MergeSettings(B, forged) == false)
  add("real update", P.MergeSettings(B, wire(A.settings)), B.settings.teams[1].pace[1].hours)
  -- vice: Dario makes Pietro vice; then Pietro can edit; admins from a non-capo refused
  add("vice", P.SetVice(A, "G-DARIO", "G-PIETRO", true), P.MergeAdmins(B, wire(A.admins)), P.IsAdmin(B, "G-PIETRO"))
  local fakeAdmins = wire(B.admins); fakeAdmins.v = 50; fakeAdmins.by = "G-PIETRO"; fakeAdmins.capo = "G-PIETRO"
  add("fake capo refused", P.MergeAdmins(A, fakeAdmins) == false, A.admins.capo)
  -- after the start: pace edits apply from next week, history kept
  NOW = start + 9 * 86400   -- week 2
  local before = M.TeamRows(A.settings, A.settings.teams[1])
  P.SetPace(A, "G-DARIO", "t1", 6, 15)
  local after = M.TeamRows(A.settings, A.settings.teams[1])
  add("week2 edit: from", A.settings.teams[1].pace[#A.settings.teams[1].pace].from, "caps w1-2 same", before[1].cap == after[1].cap and before[2].cap == after[2].cap, "w3", before[3].cap, "->", after[3].cap)
  add("start locked", P.SetStart(A, "G-DARIO", start + 3600))
  -- in the middle of week 1 the capo gives I Cesaroni more hours, again and again: it counts from this week
  local s2 = start + 20 * 86400
  local D = P.Create({ name = "Er Patto 2", start = s2, h20 = 25, h60 = 190, guid = "G-DARIO", playerName = "Dario Rossi",
    teams = { { name = "I Cesaroni", hours = 12 }, { name = "Carabinieri 8", hours = 30 } }, teamIndex = 1 })
  NOW = s2 + 3 * 86400
  local function caps(st) local r = M.TeamRows(st.settings, st.settings.teams[1]) return r[1].cap .. "," .. r[2].cap .. "," .. r[3].cap end
  local c12 = caps(D)
  local ok1, f1 = P.SetPace(D, "G-DARIO", "t1", 18)
  local c18 = caps(D)
  local ok2, f2 = P.SetPace(D, "G-DARIO", "t1", 20)
  local c20 = caps(D)
  local ok3, f3 = P.SetPace(D, "G-DARIO", "t1", 30)
  local c30 = caps(D)
  local function check(c, label) out[#out + 1] = (c and "OK   " or "FAIL ") .. label end
  check(f1 == 1 and f2 == 1 and f3 == 1 and c12 ~= c18 and c18 ~= c20 and c20 ~= c30 and #D.settings.teams[1].pace == 1,
    "more hours in week 1, three times: each counts from week 1, caps redone every time (" .. c12 .. " > " .. c18 .. " > " .. c20 .. " > " .. c30 .. ")")
  add("more hours now", ok1, f1, ok2, f2, ok3, f3, "caps", c12, c18, c20, c30, "rows", #D.settings.teams[1].pace)
  -- typed 30 by mistake, nobody that high yet: back to 20 at once
  local okb, fb = P.SetPace(D, "G-DARIO", "t1", 20)
  check(fb == 1 and caps(D) == c20 and #D.settings.teams[1].pace == 1, "a number typed wrong, nobody over it: corrected for this week too (" .. caps(D) .. ")")
  P.SetPace(D, "G-DARIO", "t1", 30)
  -- fewer hours with someone already at level 20: this week's cap stays, from next week
  D.members["G-DARIO"].lv = 20
  local ok4, f4 = P.SetPace(D, "G-DARIO", "t1", 14)
  local c14 = caps(D)
  local ok5, f5 = P.SetPace(D, "G-DARIO", "t1", 16)
  check(f4 == 2 and f5 == 2 and c14:sub(1, 3) == c30:sub(1, 3) and #D.settings.teams[1].pace == 2,
    "fewer hours, one of them at 20 already: this week's cap stays (" .. c30 .. " -> " .. c14 .. "), from week 2, changed again it replaces the row")
  add("fewer hours next week", ok4, f4, c14, "then 16", f5, caps(D), "rows", #D.settings.teams[1].pace)
  -- week 3: more hours count for week 3, weeks 1 and 2 untouched
  NOW = s2 + 15 * 86400
  local b3 = caps(D)
  local ok6, f6 = P.SetPace(D, "G-DARIO", "t1", 40)
  local a3 = caps(D)
  check(f6 == 3 and a3:sub(1, 6) == b3:sub(1, 6) and a3 ~= b3, "week 3: more hours from week 3, weeks 1 and 2 as they were (" .. b3 .. " -> " .. a3 .. ")")
  add("week 3 more", f6, b3, "->", caps(D))
  -- ban
  local C = P.Join(A.code, "G-TROLL", "Troll")
  P.MergeMember(A, wire(C.members["G-TROLL"]), "G-DARIO")
  add("ban", P.Ban(A, "G-DARIO", "G-TROLL"), A.members["G-TROLL"] == nil, "ban capo", P.Ban(A, "G-DARIO", "G-DARIO"))
  add("banned record refused", P.MergeMember(A, wire(C.members["G-TROLL"]), "G-DARIO") == false)
  -- malformed input
  add("junk member", P.MergeMember(A, { guid = 5 }, "G-DARIO"), P.MergeMember(A, "x", "G-DARIO"), P.MergeSettings(A, { v = 1000 }))
  local big = wire(A.members["G-DARIO"]); big.name = string.rep("A", 500); big.up = NOW + 5; big.guid = "G-BIG"
  P.MergeMember(A, big, "G-DARIO")
  add("long name clipped", #A.members["G-BIG"].name)
  add("sorted", #P.SortedMembers(A), #P.SortedMembers(A, "t2"))
  add("record bytes", #U.Serialize(A.members["G-PIETRO"]), "settings bytes", #U.Serialize(A.settings))
  return table.concat(out, "\n")
end''')
print(test(ns))
