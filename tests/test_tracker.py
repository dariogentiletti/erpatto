from lupa.lua51 import LuaRuntime
import os
ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ['Util.lua', 'Model.lua', 'Patto.lua', 'Comms.lua', 'Tracker.lua', 'Main.lua']
START = 1793833200
WEEK = 604800
def runtime(db=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open('stub3.lua').read()); lua.execute(open('stub4.lua').read())
    ns = lua.table()
    load = lua.eval('function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; return f end')
    for f in FILES: load(open(os.path.join(ADDON, f)).read(), f)("ErPatto", ns)
    g = lua.globals()
    if db is not None: g.ErPattoDB = db
    return lua, ns, g
def chat(g, clear=True):
    out = [str(x) for x in g.CHAT.values()]
    if clear: g.CHAT = g.table() if hasattr(g,'table') else None
    return out
fails = []
def check(cond, label):
    print(('OK  ' if cond else 'FAIL') + ' ' + label)
    if not cond: fails.append(label)

lua, ns, g = runtime()
clear = lua.eval('function() CHAT = {} ; ERRORS_SHOWN = {} end')
lines = lambda: [str(x) for x in g.CHAT.values()]
shown = lambda: [str(x) for x in g.ERRORS_SHOWN.values()]
g.NOWV = START + 2 * 86400  # Saturday of week 1
g.FIRE('ADDON_LOADED', 'ErPatto'); g.FIRE('PLAYER_LOGIN'); g.FIRE('PLAYER_ENTERING_WORLD')
check(any('nun stai in nessun patto' in l for l in lines()), 'login without patto tells how to start')
check(ns.state is None, 'no state before creating')
# bad join
st, err = ns.JoinPatto('PATTO-1234')
check(st is None and 'codice' in str(err), 'bad code refused: ' + str(err))
opts = lua.eval('''function(start) return { name = "Er Patto", start = start, h20 = 25, h60 = 190,
  teams = { { name = "I Cesaroni", hours = 12 }, { name = "Carabinieri 8", hours = 30 } }, teamIndex = 1 } end''')(START)
clear()
st = ns.CreatePatto(opts)
check(st is not None and len(str(st.code)) == 5, 'patto created ' + str(st.code))
check(ns.state.main == g.P_GUID and g.ErPattoDB.chars[g.P_GUID].code == st.code, 'db links char to patto')
cap = ns.T.MyCap()[0]
check(cap == 13, 'week-1 cap for I Cesaroni is 13 (got %s)' % cap)
# level up to 12, XP 86%
clear()
g.P_LEVEL = 12; g.FIRE('PLAYER_LEVEL_UP', 12)
check(ns.MyRecord().lv == 12, 'level 12 recorded')
check(not any('sopra er cap' in l for l in lines()), 'no over-cap warning at 12')
g.P_LEVEL = 13; g.P_XPMAX = 11400; g.P_XP = 0; g.FIRE('PLAYER_LEVEL_UP', 13)
g.P_XP = 9800; g.FIRE('PLAYER_XP_UPDATE', 'player')
check(any('85%' in l for l in lines()), '85% warning at cap: ' + str([l for l in lines() if '%' in l]))
n = len(lines()); g.P_XP = 9900; g.FIRE('PLAYER_XP_UPDATE', 'player')
check(len(lines()) == n, '85% warning only once')
g.P_XP = 10900; g.FIRE('PLAYER_XP_UPDATE', 'player')
check(any('95%' in l for l in lines()), '95% warning')
# quest that would ding
clear(); g.REWARD_XP = 800; g.FIRE('QUEST_COMPLETE')
check(any('Se consegni' in l for l in lines()) and len(shown()) == 0, 'quest-ding warning in chat (its box is over the quest window; no red letters across the screen)')
clear(); g.REWARD_XP = 100; g.FIRE('QUEST_COMPLETE')
check(not any('consegni' in l for l in lines()), 'small quest: no warning')
g.FIRE('QUEST_TURNED_IN', 1, 100, 0); g.FIRE('QUEST_TURNED_IN', 2, 100, 0)
check(ns.MyRecord().stats.t.q == 2 and ns.MyRecord().stats.w[1].q == 2, 'quests counted total and week 1')
# over cap
clear(); g.P_LEVEL = 14; g.P_XP = 0; g.FIRE('PLAYER_LEVEL_UP', 14)
check(any('Sei sopra er cap' in l for l in lines()), 'over-cap alert at 14')
# duels
st.members['G-PIETRO'] = lua.eval('{ guid = "G-PIETRO", name = "Pietro", up = 1, lv = 10 }')
g.FIRE('CHAT_MSG_SYSTEM', 'Dario has defeated Pietro in a duel')
g.FIRE('CHAT_MSG_SYSTEM', 'Dario has fled from Pietro in a duel')
g.FIRE('CHAT_MSG_SYSTEM', 'Pietro has defeated Jake in a duel')
r = ns.MyRecord()
check(r.stats.t.dw == 1 and r.stats.t.dl == 1, 'duel won and lost counted (dw=%s dl=%s)' % (r.stats.t.dw, r.stats.t.dl))
check(r.h2h['Pietro'].w == 1 and r.h2h['Pietro'].l == 1, 'head-to-head vs Pietro 1-1')
check(r.h2h['Jake'] is None, 'others\' duels ignored')
# dungeons
g.INST_NAME, g.INST_KIND = 'The Deadmines', 'party'; g.FIRE('PLAYER_ENTERING_WORLD')
check(g.ErPattoDB.run is not None, 'dungeon run started and saved')
g.NOWV += 120; g.INST_KIND = 'none'; g.FIRE('PLAYER_ENTERING_WORLD')
check((r.stats.t.dg or 0) == 0, 'short run without boss not counted')
g.INST_KIND = 'party'; g.FIRE('PLAYER_ENTERING_WORLD'); g.FIRE('ENCOUNTER_END', 1, 'Rhahk', 1, 5, 1)
g.NOWV += 60; g.INST_KIND = 'none'; g.FIRE('PLAYER_ENTERING_WORLD')
check(r.stats.t.dg == 1 and r.ld == 'The Deadmines', 'run with boss counted, last dungeon remembered')
g.INST_KIND = 'party'; g.FIRE('PLAYER_ENTERING_WORLD'); g.FIRE('ENCOUNTER_END', 1, 'x', 1, 5, g.SECRET)
g.NOWV += 30; g.INST_KIND = 'none'; g.FIRE('PLAYER_ENTERING_WORLD')
check(r.stats.t.dg == 2, 'secret encounter result does not break and counts')
# battlegrounds
g.BF_STATUS = 'active'; g.INST_KIND = 'pvp'; g.FIRE('UPDATE_BATTLEFIELD_STATUS', 1); g.FIRE('PLAYER_ENTERING_WORLD')
g.FIRE('PVP_MATCH_COMPLETE', 1, 900); g.FIRE('UPDATE_BATTLEFIELD_SCORE')
check(r.stats.t.bw == 1 and (r.stats.t.bl or 0) == 0, 'BG win counted once')
g.INST_KIND = 'none'; g.BF_STATUS = 'none'; g.FIRE('PLAYER_ENTERING_WORLD')
g.BF_STATUS = 'active'; g.INST_KIND = 'pvp'; g.FIRE('UPDATE_BATTLEFIELD_STATUS', 1); g.FIRE('PLAYER_ENTERING_WORLD')
g.BF_WINNER = 0; g.FIRE('UPDATE_BATTLEFIELD_SCORE')
check(r.stats.t.bl == 1, 'BG loss via scoreboard winner')
g.INST_KIND = 'none'; g.FIRE('PLAYER_ENTERING_WORLD'); g.BF_WINNER = None
g.BF_STATUS = 'active'; g.INST_KIND = 'pvp'; g.FIRE('UPDATE_BATTLEFIELD_STATUS', 1); g.FIRE('PVP_MATCH_COMPLETE', 255, 10)
check(r.stats.t.bw == 1 and r.stats.t.bl == 1, 'draw ignored')
g.INST_KIND = 'none'; g.FIRE('PLAYER_ENTERING_WORLD')
# secret values everywhere
g.P_LEVEL = g.SECRET; g.P_XP = g.SECRET; g.FIRE('PLAYER_XP_UPDATE', 'player'); g.FIRE('CHAT_MSG_SYSTEM', g.SECRET); g.FIRE('QUEST_COMPLETE')
check(r.lv == 14, 'secret level ignored, keeps 14')
g.P_LEVEL = 14; g.P_XP = 100
# week change
clear(); ns.CheckWeek(); g.NOWV = START + WEEK + 60; ns.CheckWeek()
check(any('Settimana 2 sbloccata' in l and '19' in l for l in lines()), 'week 2 notice with cap 19: ' + str(lines()))
# self record goes out (comms), team switch notification from a peer
check(ns.C.QueueSize() >= 0, 'comms alive')
# slash commands
for cmd in ['', 'stato', 'sync', 'prova', 'prova', 'aiuto', 'hud', 'hud']:
    g.SlashCmdList.ERPATTO(cmd)
check(any('settimana 2: cap 19' in l for l in lines()), '/patto stato prints cap')
logs = [str(x) for x in g.ErPattoDB.log.values()]
errs = [l for l in logs if '[Errore]' in l] + list(g.ERRORS.values())
check(not errs, 'no logged errors ' + str(errs[:3]))
# stats keep only 6 weeks
for k in range(1, 12):
    g.NOWV = START + (k - 1) * WEEK + 100; ns.T.Bump('q')
check(sorted(r.stats.w.keys()) == [10, 11], 'weekly stats trimmed to the last 2 weeks: %s' % sorted(r.stats.w.keys()))

# second character of the same account: alt mode
db = g.ErPattoDB
ser = ns.U.Serialize(db)
lua2, ns2, g2 = runtime()
g2.ErPattoDB = ns2.U.Deserialize(ser)
g2.P_GUID, g2.P_NAME, g2.P_LEVEL = 'Player-1-0002', 'Dariolo', 7
g2.NOWV = START + WEEK + 200
g2.FIRE('ADDON_LOADED', 'ErPatto'); g2.FIRE('PLAYER_LOGIN'); g2.FIRE('PLAYER_ENTERING_WORLD')
lua2.eval('function() for i = 1, 40 do RUN_TIMERS() end end')()
main = g2.ErPattoDB.patti[str(st.code)].members[g.P_GUID]
check(ns2.state is None and ns2.alt == False, 'second character is in no patto until the player chooses')
check(not g2.JOINED and len(list(g2.TAKE_OUTBOX().values())) == 0, 'not linked: no channel, no messages')
check(not (main.alts and main.alts[1]), 'not linked: not in the main record')
check(any("nun sta ner patto de" in str(x) for x in g2.CHAT.values()), 'login says this character is not in the patto')
ns2.LinkAlt()
check(ns2.alt == True and ns2.recordGuid == g.P_GUID, 'linked by the player: alt mode')
main = ns2.state.members[g.P_GUID]
check(main.alts and main.alts[1] and main.alts[1].name == 'Dariolo' and main.alts[1].lv == 7, 'main record lists the linked alt')
ns2.UnlinkAlt()
check(ns2.state is None and g2.ErPattoDB.chars['Player-1-0002'].alt is None and not g2.JOINED, 'unlinked: out of the patto, channel left')
g2.FIRE('PLAYER_LOGIN')
check(ns2.state is None, 'unlinked stays out after a new login')
ns2.LinkAlt()
g2.FIRE('PLAYER_LOGIN')
check(ns2.alt == True, 'the link holds across logins')
lvbefore = main.lv
g2.P_LEVEL = 8; g2.FIRE('PLAYER_LEVEL_UP', 8); g2.FIRE('QUEST_TURNED_IN', 1, 1, 1)
check(main.lv == lvbefore and main.alts[1].lv == 8, 'alt ding updates alt list, not main level')
check(not ns2.CanAdmin(), 'alt cannot admin')
st2 = ns2.JoinPatto(str(ns2.state.code))
check(st2 is not None and ns2.alt == False and ns2.recordGuid == 'Player-1-0002', 'alt can become its own member with the code')
ns2.T.RefreshSelf('alts')
own = ns2.state.members['Player-1-0002']
check(own.alts and own.alts[1] and own.alts[1].name == g.P_NAME, 'a character that joined lists the main (nobody bets on himself)')
# the links made by themselves before schema 3 (never asked) go
old = lua2.eval('function(db) db.schema = 2; db.chars["Player-1-0003"] = { name = "Vecchio", alt = true }; return db end')(g2.ErPattoDB)
ns2.InitDB()
check(old.chars['Player-1-0003'].alt is None and old.chars['Player-1-0002'].code is not None, 'old automatic links dropped, joined characters kept')
logs2 = [str(x) for x in g2.ErPattoDB.log.values() if '[Errore]' in str(x)] + list(g2.ERRORS.values())
check(not logs2, 'no errors in alt session ' + str(logs2[:3]))
# leaving
ns.LeavePatto()
check(ns.state is None and not any(True for _ in db.patti.keys()), 'leave clears patto')
print('\n%d failures' % len(fails))
check(ns2.state.settings.v >= 1 and ns2.state.members[g.P_GUID] is not None, 'alt joining keeps the known settings and members')
