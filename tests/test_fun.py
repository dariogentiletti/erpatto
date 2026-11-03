# Er Patto: dings told to everyone, invites, fun counters, Avventure, Tombola, Totopatto, Casa, Bollettino
from lupa.lua51 import LuaRuntime
import os, random, re
random.seed(5)
ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = [l.strip() for l in open(os.path.join(ADDON, 'ErPatto.toc')) if l.strip().endswith('.lua')]
START = 1793833200
WEEK = 604800
fails = []
def check(cond, label):
    print(('OK  ' if cond else 'FAIL') + ' ' + label)
    if not cond: fails.append(label)
class Client:
    def __init__(self, guid, name):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        for st in ['stub3.lua', 'stub4.lua', 'stub5.lua', 'stub6.lua']: self.lua.execute(open(st).read())
        self.lua.execute('math.randomseed(%d)' % random.randint(1, 10**6))
        self.ns = self.lua.table()
        load = self.lua.eval('function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; return f end')
        for f in FILES: load(open(os.path.join(ADDON, f)).read(), f)("ErPatto", self.ns)
        self.g = self.lua.globals()
        self.g.P_GUID, self.g.P_NAME = guid, name
        self.name = name
    def login(self, t):
        self.g.NOWV = t
        self.g.FIRE('ADDON_LOADED', 'ErPatto'); self.g.FIRE('PLAYER_LOGIN'); self.g.FIRE('PLAYER_ENTERING_WORLD')
    def texts(self): return [str(x) for x in self.g.VISIBLE_TEXTS().values()]
    def has(self, sub): return any(sub in t for t in self.texts())
    def rec(self): return self.ns.MyRecord()
    def stat(self, k): return self.rec().stats.t[k] or 0
    def news(self): return [str(n.t) for n in self.ns.News.List().values()]
    def errors(self):
        logs = [str(x) for x in self.g.ErPattoDB.log.values() if '[Errore]' in str(x)]
        return logs + list(self.g.ERRORS.values())
clients = []
T = [START + 86400]
def step(n=1, dt=0.25):
    for _ in range(n):
        T[0] += dt
        for c in clients:
            c.g.NOWV = T[0]; c.g.RUN_TIMERS()
        for c in clients:
            for m in c.g.TAKE_OUTBOX().values():
                for d in clients:
                    if d is c: continue
                    if m.kind == 'CHANNEL' and d.g.JOINED and d.g.JOINED == c.g.JOINED:
                        d.ns.C.OnAddonMessage(m.prefix, m.text, 'CHANNEL', c.name, '', 0, 7, d.g.JOINED)
                    elif m.kind == 'WHISPER' and m.target == d.name:
                        d.ns.C.OnAddonMessage(m.prefix, m.text, 'WHISPER', c.name, d.name)
def secs(s): step(int(s / 0.25))

A = Client('Player-1-AAA', 'Dario'); clients.append(A)
B = Client('Player-1-BBB', 'Pietro'); clients.append(B)
A.login(T[0]); B.login(T[0])
opts = A.lua.table_from({'name': 'Er Patto der Cap', 'start': START, 'teamIndex': 1,
    'teams': A.lua.table_from({1: A.lua.table_from({'name': 'I Pazzi', 'hours': 30})})})
A.ns.CreatePatto(opts)
code = str(A.ns.state.code)
B.ns.JoinPatto(code)
B.ns.P.UpdateSelf(B.ns.state, B.ns.recordGuid, B.lua.table_from({'team': 't1', 'tat': T[0]}), 'team')
secs(30)
check(B.ns.P.HasSettings(B.ns.state) and 'Player-1-BBB' in [str(k) for k in A.ns.state.members.keys()], 'two members in the patto, started')

# ---- a ding: everyone gets the banner and the news
B.g.P_LEVEL = 5; B.g.FIRE('PLAYER_LEVEL_UP', 5)
secs(10)
ban = A.g.ErPattoBanner
check(ban is not None and ban.shown and 'Pietro' in str(ban.title.text) and '5' in str(ban.title.text), 'ding banner on the other screen: ' + str(ban and ban.title.text))
check(any('Pietro' in n and 'livello' in n for n in A.news()), 'ding in the news list')
check(len(list(A.g.SOUNDS.values())) > 0, 'banner plays a sound')
A.ns.db.opts.toasts = False
B.g.P_LEVEL = 6; B.g.FIRE('PLAYER_LEVEL_UP', 6); secs(12)
check(any('livello' in n and '6' in n for n in A.news()), 'banners off: still in the news')
A.ns.db.opts.toasts = True

# ---- fishing, gathering, luck
A.g.FISHING = True
A.lua.eval("function() LOOT = { { qty = 3, link = '|cffffffff|Hitem:6303::::::::|h[Raw Slitherskin Mackerel]|h|r' } } end")()
A.g.FIRE('LOOT_OPENED'); A.g.FISHING = False
A.lua.eval("function() LOOT = {} end")()
check(A.stat('fi') == 3, 'fish caught counted: %s' % A.stat('fi'))
A.lua.eval("function() ITEMINFO[765] = { 7, 9 } ITEMINFO[2770] = { 7, 7 } end")()
A.g.FIRE('CHAT_MSG_LOOT', 'You receive loot: |cffffffff|Hitem:765::::::::|h[Silverleaf]|h|rx4.')
A.g.FIRE('CHAT_MSG_LOOT', 'You receive loot: |cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|rx2.')
check(A.stat('he') == 4 and A.stat('mi') == 2, 'herbs and ore gathered: %s %s' % (A.stat('he'), A.stat('mi')))
A.g.FIRE('CHAT_MSG_LOOT', 'You receive loot: |cff0070dd|Hitem:2000::::::::|h[Spada Blu]|h|r.')
A.g.FIRE('CHAT_MSG_LOOT', 'You receive loot: |cffa335ee|Hitem:2001::::::::|h[Spada Viola]|h|r.')
secs(5)
check(A.stat('lb') == 1 and A.stat('le') == 1 and A.rec().fe and str(A.rec().fe.n) == 'Spada Viola', 'blue and epic counted, first epic remembered')
secs(10)
check(any('Dario' in n and 'epico' in n for n in B.news()), 'the epic is news for the others')
check(A.ns.Fun.LuckOf(A.rec(), 't') > 0, 'luck has a value')

# ---- silly deaths and the nemesis
A.g.FALLING = True; A.g.FIRE('PLAYER_DEAD'); A.g.FALLING = False
secs(1)
check(A.stat('em') == 1 and str(A.rec().ed.k) == 'cascato', 'death by falling is a silly death')
A.g.P_LEVEL = 12
A.lua.eval("""function() UNITS.target = { guid = "Creature-0-1-2-3-4-60", name = "Kobold Vermin", level = 2 } end""")()
A.g.FIRE('PLAYER_DEAD'); secs(1)
A.g.FIRE('PLAYER_DEAD'); secs(1)
A.lua.eval("function() UNITS.target = nil end")()
check(A.stat('em') == 3 and str(A.rec().ed.k) == 'pischello', 'killed by a mob ten levels lower is silly too')
secs(6)
check(A.rec().ne and str(A.rec().ne.n) == 'Kobold Vermin' and A.rec().ne.c == 2, 'nemesis: what killed me most')
secs(10)
check(any('Dario' in n and 'Kobold Vermin' in n for n in B.news()), "silly death in the others' news: " + str(B.news()[:3]))

# ---- famous kills, travel, hearthstone
A.g.FIRE('ENCOUNTER_END', 1, 'Edwin VanCleef', 1, 5, 1)
secs(5)
check(A.stat('nk') == 1 and any(str(x.n) == 'Edwin VanCleef' for x in A.rec().nkl.values()), 'boss kill counted as a famous kill')
for x in range(7):
    A.lua.eval("function() MAPPOS = { x = %d, y = 0 } end" % (x * 40))()
    A.ns.Fun.SampleTravel()
check(A.stat('tr') >= 200, 'travel counted in yards: %s' % A.stat('tr'))
A.g.FIRE('UNIT_SPELLCAST_SUCCEEDED', 'player', 'cast', 8690)
check(A.stat('hs') == 1, 'hearthstone counted')
secs(70)

# ---- Avventure page
A.ns.UI.Toggle()
A.ns.UI.ShowProgress('adv')
check(A.has('Fortuna') and A.has('Pesci pescati') and A.has('Morti ridicole') and A.has('Re der duello') and A.has('Nemesi der patto'), 'Avventure: the fun cards')
check(A.has('Kobold Vermin') and A.has('Strada fatta'), 'nemesis card and road card filled')
holders = A.ns.Titles.Holders()
mine = [str(k) for k, v in holders.items() if v['Player-1-AAA']]
check('pescivendolo' in mine and 'imbranato' in mine and 'fruttarolo' in mine, 'new titles go to whoever leads: ' + str(sorted(mine)))
A.ns.UI.ShowProgress('titles')
check(A.has('A Pescivendolo') and A.has('Dario'), 'titles page shows the new titles and their holders')

# ---- Tombola
card = A.ns.Tombola.Card()
ids = [str(sq.id) for sq in card.values()]
cardB = [str(sq.id) for sq in B.ns.Tombola.Card().values()]
check(len(set(ids)) == 9 and ids == cardB, 'one 3x3 card, the same for everybody: ' + ','.join(ids))
groups = [str(sq.zero or (sq.k if isinstance(sq.k, str) else '+'.join(sq.k.values()))) for sq in card.values()]
check(len(set(groups)) == 9, 'never two squares on the same thing: ' + ','.join(groups))
sc = A.ns.Tombola.Score(A.rec())
A.ns.Tombola.Update()
check(A.rec().pts and A.rec().pts.t == 20 + sc.points, 'my piotte shared: 20 + %s' % sc.points)
A.ns.UI.Show('botteghino')
check(A.has('Settimana 1') and A.has('Quanto paga') and A.has('A che stanno') and A.has('piotte'), 'Botteghino, Tombola page: card, payouts, everybody on the card, purse')
check(not A.has('se gioca a piotte'), 'no explanation under the header')
A.ns.Botteghino.Show('ricchi')
check(A.has('Li ricchi') and A.has('Sfotti') and A.has('Piotte'), 'Li ricchi page')
A.ns.Botteghino.Show('schedina')
check(A.has('Chi sale più livelli?') and A.has('Quota') and A.has('Puntate'), 'Schedina page: the three questions with odds')

# ---- la Schedina: Dario bets 10 on Pietro levelling most; Pietro bets 5 on himself, Gina nobody
TB = A.ns.Tombola
bal0 = TB.Balance()
ok = TB.Bet('a', 'Player-1-BBB')
ok2 = TB.Bet('a', None, 10)
check(ok and ok2 and str(A.rec().vt.a) == 'Player-1-BBB' and A.rec().vt.sa == 10 and TB.Balance() == bal0 - 10, 'bet placed and paid: 10 piotte on Pietro')
check(A.rec().vt.qa and A.rec().vt.qa > 10, 'the odds are taken with the bet: %s' % A.rec().vt.qa)
bad = TB.Bet('a', None, 'boh')
check((bad[0] if isinstance(bad, tuple) else bad) is False, 'a stake must be a number')
ok7 = TB.Bet('a', None, 7)
check(ok7 and A.rec().vt.sa == 7 and TB.Balance() == bal0 - 7, 'any stake, not just 1/5/10: 7')
# typed in the box and Punta
A.ns.Botteghino.Show('schedina')
bv = A.ns.UI._views.botteghino
r1 = bv.q[1]
r1.stake.SetText(r1.stake, '10'); r1.place.Click(r1.place)
check(A.rec().vt.sa == 10 and TB.Balance() == bal0 - 10, 'typed 10 in the box and Punta')
check('Giocata!' in str(r1.mineLine.text) and '10 su Pietro a ' in str(r1.mineLine.text) and 'Si vince' in str(r1.winLine.text), 'the bet is confirmed and says what it pays: ' + str(r1.mineLine.text) + ' / ' + str(r1.winLine.text))
check(r1.place.text == 'Cambia', 'the button now changes the bet')
# click a member in the list, write the stake, Punta
r2 = bv.q[2]
row = [b for b in r2.rows.values() if b.shown and str(b.guid) == 'Player-1-AAA'][0]
row.Click(row)
check(row.selTex.shown and 'Su Dario a ' in str(r2.mineLine.text), 'clicking a member picks them: ' + str(r2.mineLine.text))
r2.stake.SetText(r2.stake, '3'); r2.stake.GetScript(r2.stake, 'OnTextChanged')(r2.stake)
check('Si vince' in str(r2.winLine.text), 'the payout shows while you write the stake: ' + str(r2.winLine.text))
r2.place.Click(r2.place)
check(str(A.rec().vt.b) == 'Player-1-AAA' and A.rec().vt.sb == 3, 'Punta places it')
res = TB.Bet('c', None, 5)
check(res[0] is False if isinstance(res, tuple) else res is False, 'no stake without a pick')
big = TB.Bet('c', 'Player-1-AAA', 10000)
check((big[0] if isinstance(big, tuple) else big) is False, 'cannot stake more than you have')
qBefore = TB.Odds(1, A.ns.UI.Members(), 'a')[0]['Player-1-BBB'].q
B.ns.Tombola.Bet('a', 'Player-1-BBB'); B.ns.Tombola.Bet('a', None, 5)
secs(10)
check(str(B.ns.state.members['Player-1-AAA'].vt.a) == 'Player-1-BBB', 'the others see the bet')
odds = TB.Odds(1, A.ns.UI.Members(), 'a')[0]
check(odds['Player-1-BBB'].q <= qBefore and odds['Player-1-BBB'].staked == 15 and odds['Player-1-AAA'].q > odds['Player-1-BBB'].q,
  'more piotte on Pietro, he pays less; who nobody plays pays more: %s -> %s, Dario %s' % (qBefore, odds['Player-1-BBB'].q, odds['Player-1-AAA'].q))
A.ns.Botteghino.Show('schedina')
prow = [b for b in bv.q[1].rows.values() if b.shown and str(b.guid) == 'Player-1-BBB'][0]
check(str(prow.staked.text) == '15' and prow.mine.shown, 'Pietro: 15 piotte on him, my check on him')
mineQ = A.rec().vt.qa
T[0] = START + WEEK + 3600; secs(130)
book = A.g.ErPattoDB.points[code]
expect = 10 * mineQ // 10
check(book.weeks[1] is not None and book.right >= 1 and book.weeks[1].w >= expect, 'week 1 paid at my odds: 10 x %s = %s, got %s' % (mineQ, expect, book.weeks[1].w))
ch = A.g.ErPattoChiusura
check(ch and ch.shown and 'Settimana 1 chiusa' in str(ch.title.text) and ('+%d' % expect) in str(ch.rows[1].res.text) and 'Pietro' in str(ch.rows[1].detail.text), 'closed week shown in its own window, not the chat: ' + str(ch and ch.title.text) + ' ' + str(ch.rows[1].res.text))
check(not any('Schedina de la settimana' in str(x) for x in A.g.CHAT.values()), 'nothing in the chat')
check(any('Settimana 1 chiusa' in n for n in A.news()), 'and a line in the news')
ch.ok.Click(ch.ok)
check(not ch.shown, 'Daje closes it')
# a sfottò costs 3 and lands on the other screen
before = TB.Balance()
ok, msg = TB.Sfotti('Player-1-BBB')
secs(5)
check(ok and TB.Balance() == before - 3 and any("t'ha sfottuto" in n for n in B.news()), "sfotto paid and delivered to the friend (banner queued, news)")

# ---- Casa and Er Bollettino
A.ns.UI.Show('casa')
check(A.has('Er cap tuo') and A.has("Mo' online") and A.has('Notizie') and A.has("'Sta settimana"), 'Casa: cap, online, news, week')
check(A.has('Prossimo cap') or A.has('Cap '), 'Casa shows the cap')
A.ns.Home.ShowBulletin(True)
bull = A.g.ErPattoBulletin
check(bull.shown and 'settimana 1' in str(bull.title.text) and A.has('Er più veloce') and A.has('Pietro'), 'Er Bollettino of week 1: ' + str(bull.title.text))

# ---- invite: a player with no patto gets a window and joins in one click
C = Client('Player-1-CCC', 'Gina'); clients.append(C)
C.login(T[0])
A.ns.InviteFriend('Gina')
secs(2)
inv = C.g.ErPattoInvite
check(inv is not None and inv.shown and 'Dario' in str(inv.text.text), "invite window on the friend's screen")
check(any('ha ricevuto' in str(x) for x in A.g.CHAT.values()), 'the inviter knows it arrived')
inv.yes.Click(inv.yes)
check(C.ns.state is not None and str(C.ns.state.code) == code, 'one click and she is in the patto')
secs(20)
check(C.ns.P.HasSettings(C.ns.state), 'she got the settings from the others')
A.ns.InviteFriend('Nessuno'); secs(10)
check(any('nun risponne' in str(x) for x in A.g.CHAT.values()), 'nobody answers: told to give the code')

# ---- wipes: Dario and Pietro die ten seconds apart in the same zone
A.g.FIRE('PLAYER_DEAD'); secs(10)
B.g.FIRE('PLAYER_DEAD'); secs(15)
check(any('Wipe' in n and 'Dario' in n and 'Pietro' in n for n in A.news()), 'wipe in the news: ' + str([n for n in A.news() if 'Wipe' in n][:1]))
check(A.ns.News.WipeCount() == 1 and B.ns.News.WipeCount() == 1, 'one wipe counted, on both sides')

# ---- the race to each milestone: hours played when reaching level 10
B.g.P_LEVEL = 10; B.g.FIRE('PLAYER_LEVEL_UP', 10); secs(10)
mp = A.ns.state.members['Player-1-BBB'].mp
check(mp is not None and mp[10] is not None, 'played time at level 10 shared: %s' % (mp and mp[10]))
A.ns.UI.ShowProgress('diary')
diary = A.ns.UI._views.progresso.diary
row = [b for b in diary.list.rows.values() if b.shown and b.guid == 'Player-1-BBB'][0]
row.Click(row)
check(A.has('Livello 10 in '), 'diary shows the time to reach level 10')

# ---- versions: a friend with a newer one gets you told once
A.ns.VERSION = '0.10.0'
B.ns.P.UpdateSelf(B.ns.state, B.ns.recordGuid, B.lua.table_from({'ver': '0.11.2'}), 'ver'); secs(10)
check(any('0.11.2' in str(x) and 'aggiorna' in str(x) for x in A.g.CHAT.values()), 'newer version noticed')
check(A.ns.Extras.VersionKey('dev') is None and A.ns.Extras.VersionKey('v0.10.3') > A.ns.Extras.VersionKey('0.9.9'), 'version compare')

# ---- the small things
check(A.g.ErPattoMinimapButton is not None and A.g.ErPattoMinimapButton.shown, 'minimap button')
A.ns.db.opts.minimap = False; A.ns.Fire('Refresh')
check(not A.g.ErPattoMinimapButton.shown, 'minimap button can be hidden')
check(A.g.ErPattoGuide is None and A.ns.Extras.INFO.botteghino is not None, 'no guide; each tab explains itself on the i')
A.lua.eval("""function() UNITS.target = { guid = "Player-1-BBB", name = "Pietro" } TT = {} end""")()
A.ns.Extras.TooltipLine(A.g.GameTooltip, 'target')
A.lua.eval("function() UNITS.target = nil end")()
check(any('Er Patto' in str(x) for x in A.g.TT.values()), 'patto line on a member\'s tooltip: ' + str(list(A.g.TT.values())))
txt = str(A.ns.Extras.ShareText())
check('Er Patto der Cap' in txt and 'Pietro' in txt and 'Dario' in txt, 'share text for Discord: ' + txt.split('\n')[0])
A.ns.Extras.ShowShare()
check(A.g.ErPattoShare.shown, 'share window')

nils = []
for page in ['adv', 'titles', 'rank', 'diary']:
    A.ns.UI.ShowProgress(page)
    nils += [t for t in A.texts() if re.search(r'\bnil\b', t)]
for tab in ['casa', 'pg', 'cap', 'gruppi', 'botteghino', 'imp', 'capo']:
    A.ns.UI.Show(tab)
    nils += [t for t in A.texts() if re.search(r'\bnil\b', t)]
check(not nils, 'no "nil" on any page: ' + str(nils[:3]))
A.ns.db.opts.testMode = True
for page in ['adv', 'titles']:
    A.ns.UI.ShowProgress(page)
A.ns.UI.Show('botteghino')
A.ns.UI.Show('casa')
check(A.has('Aldo'), 'test mode members fill the new pages too')
A.ns.db.opts.testMode = False
# ---- le sfide
S, SB, SC = A.ns.Sfide, B.ns.Sfide, C.ns.Sfide
for x in clients:
    x.lua.execute('EMOTES = {}; DoEmote = function(e, t) table.insert(EMOTES, e .. ":" .. tostring(t)) end; DUELS = {}; StartDuel = function(u) table.insert(DUELS, u) end')
secs(15)
balA, balB = A.ns.Tombola.Balance(), B.ns.Tombola.Balance()
# the menu: Duello a la gogna on Pietro, the loser takes a nickname
S.OpenDuel('Player-1-BBB')
dd = A.g.ErPattoDuelloGogna
check(dd.shown and 'Pietro' in str(dd.who.text), 'the duel window from the right click menu')
nickRow = [r for r in dd.pena.radios.values() if r.v == 2][0]
nickRow.Click(nickRow)
dd.pena.text.SetText(dd.pena.text, 'Pippa')
dd.pena.text.GetScript(dd.pena.text, 'OnTextChanged')(dd.pena.text)
dd.stake.SetText(dd.stake, '5')
dd.go.Click(dd.go)
check(not dd.shown and A.ns.Tombola.Balance() == balA - 5, 'duel a la gogna thrown, stake paid: %s -> %s' % (balA, A.ns.Tombola.Balance()))
secs(5)
ask = B.g.ErPattoSfida
check(ask is not None and ask.shown and 'Dario' in str(ask.text.text) and 'Pippa' in str(ask.text.text) and 'gogna' in str(ask.title.text), 'Pietro gets the dialog at once: ' + str(ask and ask.text.text))
dupe = S.Challenge(A.lua.table_from({'to': 'Player-1-BBB', 'k': 's', 'st': 'q', 'w': 'h', 's': 1}))
check((dupe[0] if isinstance(dupe, tuple) else dupe) is False, 'one open sfida at a time between two')
ask.yes.Click(ask.yes)
secs(5)
check(B.ns.Tombola.Balance() == balB - 5, 'Pietro paid when accepting')
bet = C.g.ErPattoScommessa
check(bet is not None and bet.shown and 'gogna' in str(bet.text.text), 'Gina, in the same zone, can bet on the duel')
bet.stake.SetText(bet.stake, '3')
bet.pa.Click(bet.pa)
balC = C.ns.Tombola.Balance()
A.ns.Botteghino.Show('sfide')
check(A.has('Lancia \'na sfida') and A.has('in corso') and A.has('Er soprannome "Pippa"'), 'the Sfide page lists it')
T[0] += 60
A.ns.T.OnSystemMessage('Dario has defeated Pietro in a duel')
B.ns.T.OnSystemMessage('Dario has defeated Pietro in a duel')
secs(40)
check(A.ns.Tombola.Balance() == balA + 5 and B.ns.Tombola.Balance() == balB - 5, 'Dario takes both stakes: %s, %s' % (A.ns.Tombola.Balance(), B.ns.Tombola.Balance()))
check(C.ns.Tombola.Balance() == balC + 6, 'Gina bet 3 on Dario and doubled: %s -> %s' % (balC, C.ns.Tombola.Balance()))
nB = S.NickOf(A.ns.state.members['Player-1-BBB'])
check(nB is not None and str(nB.t) == 'Pippa' and '"Pippa"' in str(A.ns.UI.H.Colored(A.ns.state.members['Player-1-BBB'])), 'Pietro is "Pippa" for everyone')
res = A.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ciao', 'Pietro-Realm')
check(res[0] is False and 'Pippa' in str(res[1]), 'and in chat: ' + str(res[1]))
check(any('Pippa' in n for n in A.news()) and any('battuto' in n for n in A.news()), 'news: the result and the duel')
# the verse and the figuraccia: Pietro throws one back with the verse; then one with the figuraccia
ok, c2 = SB.Challenge(B.lua.table_from({'to': 'Player-1-AAA', 'k': 'd', 's': 0, 'p': 3, 't': 'bee'}))
secs(5)
A.g.ErPattoSfida.yes.Click(A.g.ErPattoSfida.yes)
secs(5)
T[0] += 60
A.ns.T.OnSystemMessage('Pietro has defeated Dario in a duel')
B.ns.T.OnSystemMessage('Pietro has defeated Dario in a duel')
secs(40)
res = B.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ho perso', 'Dario-Realm')
check('ho perso' in str(res[1]) and str(res[1]).endswith('bee|r'), 'Dario ends what he writes with "bee": ' + str(res[1]))
ok, c3 = S.Challenge(A.lua.table_from({'to': 'Player-1-BBB', 'k': 'd', 's': 0, 'p': 4, 'e': 2}))
secs(5)
B.g.ErPattoSfida.yes.Click(B.g.ErPattoSfida.yes)
secs(5)
T[0] += 60
A.ns.T.OnSystemMessage('Dario has defeated Pietro in a duel')
B.ns.T.OnSystemMessage('Dario has defeated Pietro in a duel')
secs(40)
check(any('CHICKEN' in str(e) for e in B.g.EMOTES.values()), 'Pietro does the chicken in front of everyone: ' + str(list(B.g.EMOTES.values())))
# a counted sfida: who fishes more in an hour
ok, c4 = SB.Challenge(B.lua.table_from({'to': 'Player-1-AAA', 'k': 's', 'st': 'fi', 'w': 'h', 's': 2}))
secs(5)
A.g.ErPattoSfida.yes.Click(A.g.ErPattoSfida.yes)
secs(5)
B.ns.T.Bump('fi', 7); A.ns.T.Bump('fi', 3)
T[0] += 3700; secs(70)
r4 = A.ns.Sfide.Store().res[c4.id]
check(r4 is not None and str(r4.w) == 'Player-1-BBB' and r4.da == 7 and r4.db == 3, 'the fishing hour: Pietro 7 to 3')
# the gufata: Dario jinxes Pietro, who survives; then Gina jinxes Dario, who dies
balA, balB = A.ns.Tombola.Balance(), B.ns.Tombola.Balance()
ok = S.Gufa('Player-1-BBB', 10)
check(ok and A.ns.Tombola.Balance() == balA - 10, 'gufata placed')
secs(5)
T[0] += 400; secs(70)
check(B.ns.Tombola.Balance() == balB + 10 and A.ns.Tombola.Balance() == balA - 10, 'Pietro lived: he takes the 10')
balA, balC = A.ns.Tombola.Balance(), C.ns.Tombola.Balance()
ok = SC.Gufa('Player-1-AAA', 10)
secs(5)
A.ns.Fun.Said('mo\' vado a pijà er boss', 'Dario')
A.ns.Fun.OnDeath(); A.ns.T.OnDeath()
secs(40)
check(C.ns.Tombola.Balance() == balC + 5 and A.ns.Tombola.Balance() == balA - 5, 'Dario died: Gina gets half more, Dario pays 5: %s %s' % (C.ns.Tombola.Balance(), A.ns.Tombola.Balance()))
# the graveyard
rip = A.rec().rip
check(rip and 'boss' in str(rip[1].w), 'the gravestone keeps the last words')
check(any('R.I.P.' in n and 'boss' in n for n in B.news()), 'and the friends read them in the news')
B.ns.UI.ShowProgress('rip')
check(B.has('Er Cimitero') and B.has('R.I.P.') and B.has('Li più morti') and B.has('Le penitenze'), 'Cimitero page')
holders = A.ns.Titles.Holders()
check(holders['pecore'] and holders['pecore']['Player-1-BBB'], 'A Re de le Pecore: who took most penitenze')
bad = [e for c in clients for e in c.errors()]
check(not bad, 'no errors: ' + str(bad[:4]))
unk = dict(A.g.UNKNOWN)
print('methods not in stub list:', {str(k): v for k, v in unk.items()})
print('\n%d failures' % len(fails))
