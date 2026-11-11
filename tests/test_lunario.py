# Er Patto: er Lunario. An appuntamento put up for a squadra, the answers, the bets, the reminders, what each
# one does while it runs, the summary and the bets paid; the dungeon on the calendar walked into early; another
# squadra's filter; one called off, its bets given back.
src = open('test_fun.py').read()
exec(src[:src.index("A = Client('Player-1-AAA', 'Dario')")])
random.seed(31)
def R(r): return r if isinstance(r, tuple) else (r, None)

A = Client('Player-1-AAA', 'Dario'); clients.append(A)
B = Client('Player-1-BBB', 'Pietro'); clients.append(B)
C = Client('Player-1-CCC', 'Gina'); clients.append(C)
for x in (A, B, C): x.g.P_LEVEL = 20
A.login(T[0]); B.login(T[0]); C.login(T[0])
opts = A.lua.table_from({'name': 'Er Patto der Cap', 'start': START, 'teamIndex': 1,
    'teams': A.lua.table_from({1: A.lua.table_from({'name': 'I Pazzi', 'hours': 30}), 2: A.lua.table_from({'name': 'Li Lenti', 'hours': 12})})})
A.ns.CreatePatto(opts)
code = str(A.ns.state.code)
B.ns.JoinPatto(code); C.ns.JoinPatto(code)
B.ns.P.UpdateSelf(B.ns.state, B.ns.recordGuid, B.lua.table_from({'team': 't1', 'tat': T[0]}), 'team')
C.ns.P.UpdateSelf(C.ns.state, C.ns.recordGuid, C.lua.table_from({'team': 't2', 'tat': T[0]}), 'team')
secs(60)
check(len(list(A.ns.state.members.keys())) == 3, 'three in the patto: Dario and Pietro in I Pazzi, Gina in Li Lenti')
LA, LB, LC = A.ns.Lunario, B.ns.Lunario, C.ns.Lunario
secs(30)  # the first look at the list (nothing to tell about what was already there)

# ---- Dario puts up Shadowfang Keep for tomorrow at 21:00, I Pazzi, 5 places
p = A.ns.U.RomeParts(T[0] + 86400)
t0 = A.ns.U.FromRome(p.year, p.month, p.day, 21, 0)
ok, e = R(LA.Create(A.lua.table_from({'k': 'dg', 'n': 'Shadowfang Keep', 't': t0, 'd': 120, 'tm': 't1', 'm': 5, 'no': 'Portate le pozioni', 'q': 'd,dt,h'})))
check(ok and e and str(e.n) == 'Shadowfang Keep', 'Dario puts up Shadowfang Keep, tomorrow 21:00: ' + str(e if not ok else e.id))
eid = str(e.id)
secs(40)
eb_ = LB.Find(eid)
check(eb_ is not None and LB.Visible(eb_, 'mine'), 'Pietro (I Pazzi) has it, in his squadra\'s list')
check(any('Caciara nova' in n and 'Shadowfang' in n for n in B.news()) and any('caciara nova' in str(m) for m in B.g.CHAT.values()), 'and is told: a line in the chat and the news')
ec = LC.Find(eid)
check(ec is not None and not LC.Visible(ec, 'mine') and LC.Visible(ec, 'all') and not any('Shadowfang' in n for n in C.news()), 'Gina (Li Lenti) has it only with the filter on all squadre, and isn\'t told')
yes, maybe, mine = LA.Answers(LA.Find(eid))[0:3]
check(len(list(yes.values())) == 1 and mine == 1, 'who puts it up is in')

# ---- answers
LB.Answer(eid, 1)
secs(10)
yes = LA.Answers(LA.Find(eid))[0]
check(sorted(str(m.name) for m in yes.values()) == ['Dario', 'Pietro'], 'Pietro says "Ce sto": Dario sees both in')

# ---- the bets: Gina (other squadra) and Pietro on who does more damage; Dario on who dies more
ok1 = R(LC.Bet(eid, 'd', 'Player-1-AAA', 10))
ok2 = R(LB.Bet(eid, 'd', 'Player-1-AAA', 5))
ok3 = R(LA.Bet(eid, 'dt', 'Player-1-BBB', 4))
bad1 = R(LA.Bet(eid, 'd', 'Player-1-AAA', 5))
bad2 = R(LC.Bet(eid, 'h', 'Player-1-BBB', 50))
bad4 = R(LC.Bet(eid, 'mx', 'Player-1-BBB', 5))
bad3 = R(LC.Bet(eid, 'h', 'Player-1-CCC', 5))
check(ok1[0] and ok2[0] and ok3[0], 'three bets placed')
check(not bad1[0] and not bad2[0] and not bad3[0], 'never on yourself, at most 25, only on who is in: %s | %s | %s' % (bad1[1], bad2[1], bad3[1]))
check(not R(LC.Bet(eid, 'd', 'Player-1-BBB', 3))[0], 'one bet per question')
check(not bad4[0] and [str(x) for x in LC.Qs(LC.Find(eid)).values()] == ['d', 'dt', 'h'], 'only on the three questions Dario picked putting it up (not the biggest hit): ' + str(bad4[1]))
balC0 = C.ns.Tombola.Balance(); balB0 = B.ns.Tombola.Balance(); balA0 = A.ns.Tombola.Balance()
secs(20)
pools = LA.Pools(LA.Find(eid))
check(pools.d.total == 15 and pools.dt.total == 4, 'the pools everyone sees: damage %s, deaths %s' % (pools.d.total, pools.dt.total))

# ---- the dungeon on the calendar walked into a day early: a reminder
A.g.INSTANCE = True; A.g.INST_NAME = 'Shadowfang Keep'; A.g.INST_KIND = 'party'
LA.CheckInstance()
av = A.g.ErPattoAvviso
check(av is not None and av.shown and 'Shadowfang' in str(av.text.text) and 'squadra' in str(av.title.text).lower() + str(av.text.text), 'walking into Shadowfang Keep the day before: "aspetta la squadra"')
A.g.INSTANCE = False; A.g.INST_NAME = 'Elwynn Forest'; A.g.INST_KIND = 'none'

# ---- fifteen minutes before, and the start
T[0] = t0 - 14 * 60; secs(35)
check(any('tra 15 minuti' in str(m) and 'Shadowfang' in str(m) for m in B.g.CHAT.values()), 'fifteen minutes before: Pietro is called')
check(not any('tra 15 minuti' in str(m) for m in C.g.CHAT.values()), 'Gina (other squadra) is not')
late = R(LC.Bet(eid, 'dt', 'Player-1-AAA', 2))   # Gina: 2 on Dario dying more, still in time
check(late[0], 'a bet fourteen minutes before is still in time')
T[0] = t0 + 10; secs(35)
check(not R(LC.Bet(eid, 'dt', 'Player-1-AAA', 2))[0], 'the bets close when it starts')
check(any('comincia' in str(m).lower() and 'Shadowfang' in str(m) for m in A.g.CHAT.values()), 'the start: Dario is told')

# ---- only what happens in the dungeon counts: before going in, a fight in town is nothing
LA.OnCombatLine('SPELL_DAMAGE', 'Player-1-AAA', None, 5000, None)
LA.OnDeath()
for c_ in (A, B): c_.g.INSTANCE = True; c_.g.INST_NAME = 'Shadowfang Keep'; c_.g.INST_KIND = 'party'
LA.Regate(); LB.Regate()
# ---- what they do: Dario 1200 damage and a killing blow, Pietro 300 damage, 400 healing and a death
LA.OnCombatLine('SPELL_DAMAGE', 'Player-1-AAA', None, 700, None)
LA.OnCombatLine('SWING_DAMAGE', 'Player-1-AAA', 500, None, None)
LA.OnCombatLine('PARTY_KILL', 'Player-1-AAA', None, None, None)
LA.OnCombatLine('SPELL_DAMAGE', 'Player-1-ZZZ', None, 99999, None)
LB.OnCombatLine('SPELL_DAMAGE', 'Player-1-BBB', None, 300, None)
LB.OnCombatLine('SPELL_HEAL', 'Player-1-BBB', None, 500, 100)
LB.OnDeath()
B.g.NOWV = B.g.NOWV + 1; LB.OnDeath()  # the second time the game says it: one death
# the rest that's counted: what Pietro takes, the biggest hit, the jumps, the chat, the time on the ground
LB.OnCombatLine('SWING_DAMAGE', 'Creature-0-1', 250, None, None, 'Player-1-BBB')
LB.OnCombatLine('SPELL_DAMAGE', 'Creature-0-1', None, 150, None, 'Player-1-AAA')
secs(40); LB.OnAlive()
# Dario leaves the dungeon before the end: what he does outside isn't counted
A.g.INSTANCE = False; A.g.INST_NAME = 'Silverpine Forest'; A.g.INST_KIND = 'none'; LA.Regate()
LA.OnCombatLine('SPELL_DAMAGE', 'Player-1-AAA', None, 9000, None)
# ---- the end (two hours), and the three minutes for the records
T[0] = t0 + 120 * 60 + 5; secs(40)
B.g.INSTANCE = False; B.g.INST_NAME = 'Silverpine Forest'; B.g.INST_KIND = 'none'  # out of the dungeon: the records travel again
secs(20)
ra = A.rec().er; rb = B.rec().er
check(ra and ra[1].d == 1200 and ra[1].k == 1 and rb and rb[1].d == 300 and rb[1].h == 400 and rb[1].dt == 1,
      'each one wrote how it went: Dario %s/%s, Pietro %s/%s/%s' % (ra and ra[1].d, ra and ra[1].k, rb and rb[1].d, rb and rb[1].h, rb and rb[1].dt))
check(ra[1].mx == 700 and rb[1].tk == 250 and rb[1].fd is not None and rb[1].fd > 0 and rb[1].td >= 40 and ra[1].fd is None and ra[1].dt is None,
      'and the rest: Dario\'s biggest hit %s (the 5000 in town and the 9000 outside don\'t count, nor his death before going in); Pietro took %s, first death after %s s, %s s dead' % (ra[1].mx, rb[1].tk, rb[1].fd, rb[1].td))
check(next(iter(LB.Winners(LB.Find(eid), 'fd')[0].keys())) == 'Player-1-BBB' and next(iter(LA.Winners(LA.Find(eid), 'mx')[0].keys())) == 'Player-1-AAA', 'who died first: Pietro (the only one); the biggest hit: Dario')
check(A.stat('ap') == 1 and B.stat('ap') == 1 and C.stat('ap') == 0, 'one appuntamento done for each of the two (A Presenzialista counts it)')
T[0] += 200; secs(40)
sm = B.g.ErPattoRiepilogo
lines = ' | '.join(str(l.text) for l in sm.lines.values()) if sm else ''
check(sm is not None and sm.shown and 'Shadowfang' in str(sm.title.text) and 'Più danno' in lines and 'Dario' in lines and 'Più cure' in lines and 'Pietro' in lines,
      'the summary on Pietro\'s screen: ' + lines)
check(C.g.ErPattoRiepilogo is not None and C.g.ErPattoRiepilogo.shown, 'Gina gets it too: she bet')
# damage: Dario won; pool 15 split between Gina (10) and Pietro (5); deaths: Pietro won, Dario alone on him: 4 back
# Gina: +10 from the damage pool, -2 of her late bet on Dario dying more (Pietro died more)
check(C.ns.Tombola.Balance() == balC0 + 10 - 2 and B.ns.Tombola.Balance() == balB0 + 5,
      'the damage pool (15) goes to who said Dario, in proportion: Gina %+d (and -2 lost), Pietro %+d' % (C.ns.Tombola.Balance() - balC0, B.ns.Tombola.Balance() - balB0))
check(A.ns.Tombola.Balance() == balA0 + 6, 'the deaths pool (4 + 2) to Dario, the only one right: +%s' % (A.ns.Tombola.Balance() - balA0))
check('Le puntate tue' in str(sm.net.text), 'and the summary tells Pietro his piotte: ' + str(sm.net.text))
check(any('Finito' in n and 'Shadowfang' in n for n in A.news()), 'and a line in the news')
secs(60)
check(C.ns.Tombola.Balance() == balC0 + 8, 'paid once')

# ---- every day, a minute after the first look: what's coming that I'm in, and what waits for my answer
p3 = A.ns.U.RomeParts(T[0] + 86400)
ok, e4 = R(LB.Create(B.lua.table_from({'k': 'dg', 'n': 'Wailing Caverns', 't': A.ns.U.FromRome(p3.year, p3.month, p3.day, 21, 0), 'd': 120, 'tm': 't1', 'm': 5})))
secs(40)
n0 = len(list(A.g.CHAT.values()))
T[0] = A.ns.U.FromRome(p3.year, p3.month, p3.day, 9, 0); secs(35)
said = [str(m) for m in list(A.g.CHAT.values())[n0:]]
check(any('aspetta la risposta tua' in m and 'Wailing Caverns' in m for m in said), 'the morning of the day: Dario is asked about Wailing Caverns (no answer yet): ' + str(said[-2:]))
LA.Answer(str(e4.id), 1)
n1 = len(list(A.g.CHAT.values())); secs(60)
check(not any('aspetta la risposta' in str(m) for m in list(A.g.CHAT.values())[n1:]), 'once a day, not every minute')
n2 = len(list(A.g.CHAT.values()))
T[0] = A.ns.U.FromRome(p3.year, p3.month, p3.day, 20, 1); secs(35)
check(any("tra 'n'ora" in str(m) and 'Wailing' in str(m) for m in list(A.g.CHAT.values())[n2:]), 'an hour before, who\'s in is called')
T[0] = A.ns.U.FromRome(p3.year, p3.month, p3.day, 23, 30); secs(40)

# ---- the window: Prossimi, Mese, the detail
p2 = A.ns.U.RomeParts(T[0] + 2 * 86400)
ok, e2 = LA.Create(A.lua.table_from({'k': 'du', 'n': 'Torneo ar Crossroads', 't': A.ns.U.FromRome(p2.year, p2.month, p2.day, 22, 30), 'd': 60, 'tm': ''}))
ok, e3 = LC.Create(C.lua.table_from({'k': 'bg', 'n': 'Warsong Gulch', 't': A.ns.U.FromRome(p2.year, p2.month, p2.day, 20, 0), 'd': 90, 'tm': 't2', 'm': 10}))
secs(40)
A.ns.UI.Toggle(); A.ns.Lunario.Show()
check(A.has('Prossimi') and A.has('Mese') and A.has('Torneo ar Crossroads') and A.has('Shadowfang Keep') and not A.has('Warsong Gulch'), 'Lunario, Prossimi: mine and the whole patto\'s, not Li Lenti\'s')
v = A.ns.UI._views.lunario
v.tabMonth.GetScript(v.tabMonth, 'OnClick')(v.tabMonth); A.ns.UI.Refresh()
check(A.has('22:30') and A.has('Torneo ar Crossroads'), 'Mese: the torneo in its square')
check(A.has('Ce stanno') and A.has('Le puntate'), 'the detail: who\'s in, the bets')
check(not R(LC.Create(C.lua.table_from({'k': 'bg', 'n': 'X', 't': T[0] + 3600, 'tm': 't1'})))[0], 'Gina can\'t put one up for I Pazzi (only the capo)')
# Baretto: the next one
A.ns.UI.Show('casa')
check(A.has('Caciare') and A.has('Torneo ar Crossroads') and A.has('tra ') and A.has('Notizie'), 'the Baretto: the caciare to come, with how long to go')
B.ns.UI.Toggle(); B.ns.UI.Show('casa')
hb = B.g.ErPattoHUD; ha = A.g.ErPattoHUD
check(ha.cac.shown and 'Torneo ar Crossroads tra' in str(ha.cac.text.text), 'under Dario\'s cap bar: the torneo he\'s in and how long to go: ' + str(ha.cac.text.text))
check(not hb.cac.shown, 'under Pietro\'s nothing: the one waiting for his answer isn\'t today')
if False: check(True, 'under Pietro\'s: one waits for his answer: ' + str(hb.cac.text.text))
check(B.has('Torneo ar Crossroads') and B.has('nova: ce stai?') and B.has('(1 nova)'), 'Pietro hasn\'t answered the torneo: "nova: ce stai?", and the count in the title')

# ---- a caciara today and no answer: under the bar, and a window (once) with the two answers
pz = A.ns.U.RomeParts(T[0] + 86400); T[0] = A.ns.U.FromRome(pz.year, pz.month, pz.day, 10, 0); secs(35)
okt, et = R(LA.Create(A.lua.table_from({'k': 'ca', 'n': 'Er drago de oggi', 't': T[0] + 2 * 3600, 'd': 60, 'tm': 't1'})))
p9 = A.ns.U.RomeParts(T[0]); p8 = A.ns.U.RomeParts(T[0] + 2 * 3600)
secs(70)
B.ns.UI.RefreshHUD()
check(B.g.ErPattoCaciaraOggi is None or not B.g.ErPattoCaciaraOggi.shown, 'put up while Pietro plays: no window (the chat tells him)')
LB.AskToday()   # as when he comes in
ad = B.g.ErPattoCaciaraOggi
if p9.day == p8.day:
    check(B.g.ErPattoHUD.cac.shown and 'ce stai?' in str(B.g.ErPattoHUD.cac.text.text), 'today\'s without Pietro\'s answer: under his bar: ' + str(B.g.ErPattoHUD.cac.text.text))
    check(ad is not None and ad.shown and 'drago' in str(ad.name.text) and 'Comincia tra' in str(ad.count.text) and 'Dario' in str(ad.who.text), 'and the window: what, who\'s in, how long to go: %s | %s' % (ad.what.text, ad.count.text))
    ad.yes.Click(ad.yes); secs(10)
    check(not ad.shown and LB.Answers(LB.Find(str(et.id)))[2] == 1, 'Ce sto: he\'s in, the window goes')
    secs(70)
    check(not ad.shown, 'and it doesn\'t come back')
LA.Cancel(str(et.id)); secs(20)

# ---- the other kinds: an elite to kill, world PvP, a long quest: put up, seen by the others, with their questions
for k, n, q in (('ca', 'Er drago de Duskwood', 'k'), ('wp', 'Scorribanda a Crossroads', 'hk'), ('qu', 'La questona de la spada', 'k')):
    okk, ek = R(LB.Create(B.lua.table_from({'k': k, 'n': n, 't': T[0] + 3 * 86400, 'd': 120, 'tm': 't1'})))
    secs(40)
    fa = LA.Find(str(ek.id)) if okk else None
    check(okk and fa is not None and str(fa.k) == k and LA.Pools(fa)[q] is not None, '%s (%s): Dario has it, with its bets' % (A.ns.Lunario.KINDS[k].name, n))
    LB.Cancel(str(ek.id)); secs(20)

# ---- a battleground: gnomes killed count only in there, and only gnomes
okg, eg = R(LA.Create(A.lua.table_from({'k': 'bg', 'n': 'Warsong Gulch', 't': T[0] + 600, 'd': 60, 'tm': 't1', 'q': 'gn,hk'})))
check(okg and [str(x) for x in LA.Qs(eg).values()] == ['gn', 'hk'], 'a battleground with "chi ammazza più gnomi?" picked')
A.lua.execute('GetPlayerInfoByGUID = function(g) if g == "Player-1-GNO" then return "Mago", "MAGE", "Gnomo", "Gnome", 2, "Gnomello", "" end return "Guerriero", "WARRIOR", "Umano", "Human", 2, "Ugo", "" end')
T[0] += 630; secs(35)
LA.OnCombatLine('PARTY_KILL', 'Player-1-AAA', None, None, None, 'Player-1-GNO')   # not in the battleground yet
A.g.INSTANCE = True; A.g.INST_NAME = 'Warsong Gulch'; A.g.INST_KIND = 'pvp'
A.lua.execute('local old = IsInInstance IsInInstance = function() return INSTANCE, INST_KIND end')
LA.Regate()
LA.OnCombatLine('PARTY_KILL', 'Player-1-AAA', None, None, None, 'Player-1-GNO')
LA.OnCombatLine('PARTY_KILL', 'Player-1-AAA', None, None, None, 'Player-1-GNO')
LA.OnCombatLine('PARTY_KILL', 'Player-1-AAA', None, None, None, 'Player-1-HUM')
T[0] += 3600; secs(40)
rg = [r for r in A.rec().er.values() if str(r.i) == str(eg.id)]
check(len(rg) == 1 and rg[0].gn == 2, 'two gnomes (the human and the one before going in don\'t count): %s' % (rg and rg[0].gn))
A.g.INSTANCE = False; A.g.INST_KIND = 'none'

# ---- called off: the bets given back
R(LB.Bet(str(e2.id), 'dw', 'Player-1-AAA', 6))
balB1 = B.ns.Tombola.Balance()
secs(20)
okc = R(LA.Cancel(str(e2.id)))
secs(40)
check(okc and LB.State(LB.Find(str(e2.id))) == 'annullato', 'Dario calls the torneo off')
check(B.ns.Tombola.Balance() == balB1 + 6, 'Pietro\'s 6 piotte come back (%s)' % (B.ns.Tombola.Balance() - balB1))
check(not R(LB.Cancel(str(e3.id)))[0], 'Pietro can\'t call off Gina\'s')

bad = [x for c in clients for x in c.errors()]
check(not bad, 'no errors: ' + str(bad[:3]))
print('\n%d failures' % len(fails))
