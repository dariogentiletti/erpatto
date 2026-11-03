# Er Patto: tombola and Totopatto in test mode, before the patto starts
import os, sys
sys.argv = ['x']
exec(open('test_fun.py').read().split("A = Client('Player-1-AAA', 'Dario')")[0])
T[0] = START - 3 * 86400
A = Client('Player-1-AAA', 'Dario'); clients.append(A)
A.login(T[0])
opts = A.lua.table_from({'name': 'Er Patto der Cap', 'start': START, 'teamIndex': 1,
    'teams': A.lua.table_from({1: A.lua.table_from({'name': 'I Pazzi', 'hours': 30})})})
A.ns.CreatePatto(opts)
secs(5)
TB = A.ns.Tombola
check(TB.Testing() is False and TB.Card() is None, 'before the start, no card')
A.ns.db.opts.testMode = True
check(TB.Testing() is True and TB.Week() == 1 and TB.Card() is not None, 'test mode: week 1 card before the start')
A.ns.UI.Toggle(); A.ns.UI.Show('botteghino')
bv = A.ns.UI._views.botteghino
check(A.has('(prova') and bv.testBtn.shown and A.has('Schedina'), 'Botteghino in test mode, with the close button')
# what I do now counts: a duel lost, two quests
A.ns.T.Bump('dl'); A.ns.T.Bump('q', 80); A.ns.T.Bump('dg', 6); A.ns.T.Bump('fl', 10); A.ns.T.Bump('dw', 5); A.ns.T.Bump('fi', 50)
sc = TB.Score(A.rec())
check(sc.cells >= 1, 'my pre-start actions tick the card: %d cells' % sc.cells)
ok = TB.Bet('a', 'FAKE-3')
check(ok and A.g.ErPattoDB.testVotes.a == 'FAKE-3' and A.g.ErPattoDB.testVotes.sa == 5 and A.rec().vt is None, 'test bet (5 by default) kept on this computer only')
A.ns.Botteghino.Show('schedina')
check(A.has('Aldo') and A.has('Quota'), 'odds shown, test members included')
# click a member, write the stake, Punta
r = bv.q[2]
row = [x for x in r.rows.values() if x.shown and str(x.guid).startswith('FAKE')][0]
row.Click(row)
r.stake.SetText(r.stake, '4'); r.place.Click(r.place)
check(A.g.ErPattoDB.testVotes.b == row.guid and A.g.ErPattoDB.testVotes.sb == 4 and 'Giocata!' in str(r.mineLine.text), 'click, stake, Punta: placed and confirmed: ' + str(r.mineLine.text))
# the bulletin can be tried in test mode
A.ns.Home.ShowBulletin(True)
check(A.g.ErPattoBulletin.shown and '(prova)' in str(A.g.ErPattoBulletin.title.text), 'test bulletin')
total, sc2, right, lines, won, res = TB.SimulateClose()
check(total is not None and total >= sc2.points, 'simulated close: %s points, %s right' % (total, right))
btn = bv.testBtn; btn.Click(btn)
ch = A.g.ErPattoChiusura
check(ch and ch.shown and '(prova)' in str(ch.title.text) and "C'avresti" in str(ch.balance.text), 'close button: the closing window, in test mode')
check(any('chiusa (prova)' in str(n.t) for n in A.ns.News.List().values()), 'and a line in the news')
TB.Update()
check(A.rec().pts is None, 'no real piotte written in test mode')
A.ns.db.opts.testMode = False
check(TB.Testing() is False and TB.Card() is None, 'test mode off: back to no card')
bad = A.errors()
check(not bad, 'no errors: ' + str(bad[:3]))
print('\n%d failures' % len(fails))
