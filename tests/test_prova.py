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
A.ns.UI.Toggle(); A.ns.UI.ShowProgress('tombola')
pv = A.ns.UI._views.progresso
check(A.has('(prova') and pv.tombola.testBtn.shown and A.has('Totopatto'), 'tombola page in test mode, with the close button')
# what I do now counts: a duel lost, two quests
A.ns.T.Bump('dl'); A.ns.T.Bump('q', 20); A.ns.T.Bump('dg', 1)
sc = TB.Score(A.rec())
check(sc.cells >= 1, 'my pre-start actions tick the card: %d cells' % sc.cells)
ok = TB.Vote('a', 'FAKE-3')
check(ok and A.g.ErPattoDB.testVotes.a == 'FAKE-3' and A.rec().vt is None, 'test vote kept on this computer only')
A.ns.UI.ShowProgress('tombola')
check(A.has('Voti:'), 'votes shown, test members included')
total, sc2, right, lines = TB.SimulateClose()
check(total is not None and total >= sc2.points, 'simulated close: %s points, %s right' % (total, right))
btn = pv.tombola.testBtn; btn.Click(btn)
check(any('prova, settimana chiusa' in str(x) for x in A.g.CHAT.values()) and A.g.ErPattoBanner.shown, 'close button: chat and banner')
TB.Update()
check(A.rec().pts is None or A.rec().pts.t == 0, 'no real points written in test mode')
A.ns.db.opts.testMode = False
check(TB.Testing() is False and TB.Card() is None, 'test mode off: back to no card')
bad = A.errors()
check(not bad, 'no errors: ' + str(bad[:3]))
print('\n%d failures' % len(fails))
