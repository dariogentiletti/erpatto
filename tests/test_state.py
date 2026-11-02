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
