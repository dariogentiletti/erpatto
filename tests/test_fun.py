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
check(A.has('Settimana 1') and A.has('terno +2') and A.has('A che stanno') and A.has('piotte'), 'Botteghino, Tombola page: card, payouts, everybody on the card, purse')
check(not A.has('se gioca a piotte'), 'no explanation under the header')
A.ns.Botteghino.Show('ricchi')
check(A.has('Li ricchi') and A.has('Piotte') and not A.has('Sfotti'), 'Li ricchi page, no sfottò button there')
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
B.lua.execute('')
B.ns.T.Bump('dt', 3)
secs(10)
A.ns.Sfide.OpenSfotti('Player-1-BBB')
sf = A.g.ErPattoSfotti
lines = [str(r.text.text) for r in sf.radios.values()]
check(sf.shown and 'Pietro' in str(sf.title.text) and any('morti' in l for l in lines) and '3 piotte' in str(sf.text.text), 'the sfottò window: three lines, one from Pietro\'s deaths: ' + str(lines))
pick = [r for r in sf.radios.values() if 'morti' in str(r.text.text)][0]
pick.Click(pick)
sf.yes.Click(sf.yes)
secs(5)
check(TB.Balance() == before - 3 and any("t'ha sfottuto" in n and 'morti' in n for n in B.news()), "sfotto paid and delivered with the line chosen: " + str([n for n in B.news() if 'sfottuto' in n][:1]))

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
# ---- er duello a la gogna: the game's duel request is the yes, our windows only tell
S, SB, SC = A.ns.Sfide, B.ns.Sfide, C.ns.Sfide
for x in clients:
    x.lua.execute('EMOTES = {}; DoEmote = function(e, t) table.insert(EMOTES, e .. ":" .. tostring(t)) end; DUELS = {}; StartDuel = function(u) table.insert(DUELS, u) end; TARGETNAME = nil; UnitName = function(u) if u == "player" then return P_NAME end if u == "target" then return TARGETNAME end return nil end')
A.g.TARGETNAME, B.g.TARGETNAME, C.g.TARGETNAME = 'Pietro', 'Dario', 'Pietro'
secs(15)
def first(v): return v[0] if isinstance(v, tuple) else v
def second(v): return v[1] if isinstance(v, tuple) else None
NAMES = {A: 'Dario', B: 'Pietro', C: 'Gina'}
def duel(w, l):
    T[0] += 60
    for x in (w, l): x.ns.T.OnSystemMessage('%s has defeated %s in a duel' % (NAMES[w], NAMES[l]))
    secs(10)
def ndu(x): return len(list(x.g.DUELS.values()))
def shown(x, name): f = x.g[name]; return f is not None and f.shown
gogna_windows = ['ErPattoDuelloGogna', 'ErPattoAvviso', 'ErPattoRivincita', 'ErPattoPegno', 'ErPattoPena']
def one_at_a_time(x): return sum(1 for n in gogna_windows if shown(x, n)) <= 1
balA = A.ns.Tombola.Balance()
S.OpenDuel('Player-1-BBB', 'target')
dd = A.g.ErPattoDuelloGogna
check(dd.shown and 'Pietro' in str(dd.text.text) and 'pegno' in str(dd.text.text) and 'piotte' not in str(dd.text.text), 'the duel window: no piotte, the rule in one line')
dd.yes.Click(dd.yes)
check(ndu(A) == 1 and 'Richiesta de duello' in str(dd.msg.text) and A.ns.Tombola.Balance() == balA, 'Sfida! sends the game\'s duel request, nothing paid: ' + str(dd.msg.text))
check(not any('gogna' in str(x) for x in A.g.CHAT.values()), 'nothing in the chat')
secs(2)
av = B.g.ErPattoAvviso
check(av is not None and av.shown and 'gogna' in str(av.title.text) and 'accetta la richiesta' in str(av.text.text) and av.yes is None, 'Pietro is told what\'s at stake, no buttons of ours: ' + str(av and av.text.text))
check(ndu(B) == 0, 'Pietro sends no duel request of his own')
busy = SC.Gogna('Player-1-AAA')
check(first(busy) is False and 'ballo' in str(second(busy)), 'Gina can\'t throw one at Dario while he has one going: ' + str(second(busy)))
bet = C.g.ErPattoScommessa
check(bet is not None and bet.shown and 'Colosseo' in str(bet.title.text), 'Gina, in the same zone, can bet')
bet.stake.SetText(bet.stake, '3')
bet.pa.Click(bet.pa)
balC = C.ns.Tombola.Balance()
duel(A, B)
check(C.ns.Tombola.Balance() == balC + 6, 'Gina bet 3 on Dario and doubled')
off = B.g.ErPattoRivincita
check(off is not None and off.shown and str(off.yes.text) == 'Rivincita!' and one_at_a_time(B), 'Pietro lost: offered la rivincita, alone on his screen')
check(shown(A, 'ErPattoAvviso') and 'Hai vinto' in str(A.g.ErPattoAvviso.title.text) and one_at_a_time(A), 'Dario is told he won, nothing to click')
off.yes.Click(off.yes)
secs(2)
check(ndu(B) == 1 and 'Richiesta de duello' in str(off.msg.text), 'Rivincita! sends Pietro\'s duel request')
check(shown(A, 'ErPattoAvviso') and 'Rivincita' in str(A.g.ErPattoAvviso.title.text) and 'settimana' in str(A.g.ErPattoAvviso.text.text), 'Dario is told what la rivincita puts at stake')
duel(B, A)
off = A.g.ErPattoRivincita
check(off is not None and off.shown and str(off.yes.text) == 'La bella!' and one_at_a_time(A), 'Pietro got even: Dario can ask for la bella')
off.yes.Click(off.yes)
secs(2)
check(shown(B, 'ErPattoAvviso') and 'bella' in str(B.g.ErPattoAvviso.title.text).lower(), 'Pietro is told about la bella')
duel(B, A)
secs(10)
check(not shown(A, 'ErPattoRivincita'), 'after la bella nobody can ask for more')
peg = B.g.ErPattoPegno
check(peg.shown and 'Dario' in str(peg.text.text) and 'settimana' in str(peg.text.text) and one_at_a_time(B), 'Pietro won la bella Dario asked for: he chooses er pegno, a week')
check(shown(A, 'ErPattoAvviso') and 'sceje' in str(A.g.ErPattoAvviso.text.text), 'Dario is told he is a la gogna, er pegno to come')
verRow = [r for r in peg.pena.radios.values() if r.v == 3][0]
verRow.Click(verRow)
peg.yes.Click(peg.yes)
check('Scrivi' in str(peg.err.text), 'er verso needs its word')
sanRow = [r for r in peg.pena.radios.values() if r.v == 1][0]
sanRow.Click(sanRow)
peg.yes.Click(peg.yes)
secs(5)
pw = A.g.ErPattoPena
check(pw is not None and pw.shown and 'pecora' in str(pw.name.text) and 'mpecorato' in str(pw.text.text), 'Dario is told plainly what his pegno does: ' + str(pw and pw.text.text))
card = A.g.ErPattoSantino
check(card is not None and card.shown and str(card.who.text) == "Pietro me ha 'mpecorato", 'la pecora over Dario: ' + str(card and card.who.text))
gA = SC.AtGogna('Player-1-AAA')
check(gA is not None and gA.til - T[0] > 6 * 86400, 'a la gogna for a week, Gina sees it')
res = B.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ciao', 'Dario-Realm')
check('Porcello' not in str(res), 'no animal name in chat: ' + str(res))
check(str(SC.Champion()) == 'Player-1-BBB', 'Pietro sent Dario a la gogna: er Campione')
check(any('pure la bella' in n for n in C.news()) and any('Er pegno de' in n and 'pecora' in n for n in C.news()), 'news: the bella lost and er pegno')
r1 = S.Gogna('Player-1-CCC')
check(first(r1) is False and 'Stai a la gogna' in str(second(r1)), 'Dario a la gogna: no duelli a la gogna')
check(SB.BlockText('Player-1-BBB', SB.Series(), SB.Members()) is None, 'Pietro won: he can throw another one at once, no daily limit')
# not near: no request, the reason in the window
T[0] += 86400 + 60; secs(5)
C.g.TARGETNAME = None
SC.OpenDuel('Player-1-BBB')
gd = C.g.ErPattoDuelloGogna
gd.yes.Click(gd.yes)
check(ndu(C) == 0 and 'vicino' in str(gd.err.text), 'Pietro not near: no request, Gina is told: ' + str(gd.err.text))
C.g.TARGETNAME = 'Pietro'
# Pietro beats Gina, she says basta, Pietro doesn't choose: the mask, a day
gd.yes.Click(gd.yes)
secs(2)
duel(B, C)
C.g.ErPattoRivincita.no.Click(C.g.ErPattoRivincita.no)
secs(5)
peg = B.g.ErPattoPegno
check(peg.shown and 'Gina' in str(peg.text.text) and "'n giorno" in str(peg.text.text), 'she said basta: Pietro chooses at once, a day')
peg.Hide(peg)
T[0] += 1000; secs(40)
g = A.ns.Sfide.AtGogna('Player-1-CCC')
check(g is not None and 0 < g.til - T[0] < 86400 and g.s.pena == 1, 'Pietro didn\'t choose: Gina gets er santino for a day')
check(shown(C, 'ErPattoPena') and 'pecora' in str(C.g.ErPattoPena.name.text) and 'testa' in str(C.g.ErPattoPena.text.text), 'Gina is told about la pecora')
C.g.ErPattoPena.Hide(C.g.ErPattoPena)
# er piagnone
T[0] += 86400 + 60; secs(5)
B.g.TARGETNAME = 'Gina'
SB.Gogna('Player-1-CCC', 'target'); secs(2)
duel(B, C)
C.g.ErPattoRivincita.no.Click(C.g.ErPattoRivincita.no); secs(5)
peg = B.g.ErPattoPegno
row = [r for r in peg.pena.radios.values() if r.v == 4][0]
row.Click(row)
peg.yes.Click(peg.yes)
secs(10)
n0 = len([e for e in C.g.EMOTES.values() if 'CRY' in str(e)])
secs(125)
n1 = len([e for e in C.g.EMOTES.values() if 'CRY' in str(e)])
check(n1 >= n0 + 1, 'er piagnone: Gina cries every two minutes: %s -> %s' % (n0, n1))
check('piagne' in str(C.g.ErPattoPena.text.text), 'her window says so')
# la rivincita turned down: Gina beats Pietro, Pietro asks, Gina declines the duel request: Pietro a la gogna a day
T[0] += 86400 + 60; secs(5)
C.g.TARGETNAME = 'Pietro'; B.g.TARGETNAME = 'Gina'
ok = SC.Gogna('Player-1-BBB', 'target')
check(first(ok), 'Gina throws another: ' + str(second(ok)))
secs(8)
duel(C, B)
B.g.ErPattoRivincita.yes.Click(B.g.ErPattoRivincita.yes); secs(4)
check(shown(C, 'ErPattoAvviso') and 'nun accetti' in str(C.g.ErPattoAvviso.text.text), 'Gina is told what declining means')
T[0] += 20
C.g.FIRE('DUEL_FINISHED'); B.g.FIRE('DUEL_FINISHED')
secs(15)
check(any('nun ha dato la rivincita' in n for n in A.news()), 'declined: news says so')
peg = C.g.ErPattoPegno
check(peg.shown, 'Gina chooses er pegno')
row = [r for r in peg.pena.radios.values() if r.v == 6][0]
row.Click(row)
peg.yes.Click(peg.yes)
secs(5)
gB = A.ns.Sfide.AtGogna('Player-1-BBB')
check(gB is not None and gB.til - T[0] < 86400 and str(SC.Champion()) == 'Player-1-CCC', 'Pietro a la gogna a day; Gina has the crown')
check(shown(B, 'ErPattoPena') and 'servo de Gina' in str(B.g.ErPattoPena.text.text) and 'inchina' in str(B.g.ErPattoPena.text.text), 'Pietro is told what being er servo means: ' + str(B.g.ErPattoPena.text.text))
res = A.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ciao', 'Pietro-Realm')
check('servo de Gina' in str(res[1]), 'in chat: [servo de Gina]')
B.g.TARGETNAME = 'Gina'; B.g.FIRE('PLAYER_TARGET_CHANGED'); secs(1)
check(any('BOW' in str(e) for e in B.g.EMOTES.values()), 'Pietro bows to Gina when he targets her')
# a reload in the middle: the window still due comes back
T[0] += 86400 + 60; secs(5)
SC.Gogna('Player-1-BBB', 'target'); secs(8)
duel(C, B)
B.g.ErPattoRivincita.Hide(B.g.ErPattoRivincita)
B.ns.Sfide.Update()
check(not B.g.ErPattoRivincita.shown, 'closed by hand: not shown again in the same session')
B.ns.Sfide.Forget()
B.ns.Sfide.Update()
check(B.g.ErPattoRivincita.shown, 'after a reload Pietro is offered la rivincita again')
T[0] += 700; secs(40)
check(C.g.ErPattoPegno.shown and C.g.ErPattoPegno.yes.shown, 'ten minutes passed: Gina chooses er pegno')
peg = C.g.ErPattoPegno
row = [r for r in peg.pena.radios.values() if r.v == 2][0]
row.Click(row)
peg.yes.Click(peg.yes)
secs(5)
ok = SC.Pull('Player-1-BBB', 1)
secs(3)
check(first(ok) and any('DANCE' in str(e) for e in B.g.EMOTES.values()), 'er burattino: Gina pulls the strings, Pietro dances')
secs(4)
again = SC.Pull('Player-1-BBB', 2)
secs(3)
check(first(again) and any('CHICKEN' in str(e) for e in list(B.g.EMOTES.values())[-2:]), 'and again whenever she likes: the chicken')
# the dropdowns of the Sfide page: pick a member, pick what, the labels change
A.ns.Botteghino.Show('sfide')
pg = A.ns.UI._views.botteghino.sfide
pg.who.GetScript(pg.who, 'OnClick')(pg.who)
ch = A.g.ErPattoChoose
row = [r for r in ch.rows.values() if 'Pietro' in str(r.text.text)][0]
row.GetScript(row, 'OnClick')(row)
pg.what.GetScript(pg.what, 'OnClick')(pg.what)
row = [r for r in ch.rows.values() if 'pesci' in str(r.text.text)][0]
row.GetScript(row, 'OnClick')(row)
check(str(pg.who.label.text) == 'Pietro' and 'pesci' in str(pg.what.label.text) and not ch.shown and not ch.catcher.shown, 'the dropdowns pick and close: %s / %s' % (pg.who.label.text, pg.what.label.text))
pg.who.GetScript(pg.who, 'OnClick')(pg.who)
ch.catcher.GetScript(ch.catcher, 'OnClick')(ch.catcher)
check(not ch.shown, 'a click outside closes the list')
# Cimitero: hovering who's a la gogna tells er pegno
B.ns.UI.ShowProgress('rip')
cv = B.ns.UI._views.progresso.cimitero
hov = [l for l in cv.shame.values() if l.gogna is not None]
check(len(hov) > 0, 'someone a la gogna in the Cimitero list')
# a fall is a fall: an old breath bar doesn't make it drowning
A.g.FIRE('MIRROR_TIMER_START', 'BREATH', 180000, 180000, -1)
secs(2)
kind = A.ns.Fun.DeathKind()
check(str(kind[0] if isinstance(kind, tuple) else kind) != 'affogato', 'a full breath bar is not drowning: ' + str(kind))
# a sfida a piotte: who fishes more until the end of the week
balA, balB = A.ns.Tombola.Balance(), B.ns.Tombola.Balance()
ok, c4 = SB.Challenge(B.lua.table_from({'to': 'Player-1-AAA', 'k': 's', 'st': 'fi', 's': 2}))
check(ok and B.ns.Tombola.Balance() == balB - 2, 'Pietro throws a sfida a piotte')
nostake = S.Challenge(A.lua.table_from({'to': 'Player-1-CCC', 'k': 's', 'st': 'q', 's': 0}))
check(first(nostake) is False and 'piotta' in str(second(nostake)), 'a sfida is always for piotte')
secs(5)
dupe = S.Challenge(A.lua.table_from({'to': 'Player-1-BBB', 'k': 's', 'st': 'q', 's': 1}))
check(first(dupe) is False, 'one open sfida at a time between two: ' + str(second(dupe)) + str(len(A.ns.Sfide.All())))
ask = A.g.ErPattoSfida
check(ask.shown and 'pesci' in str(ask.text.text) and 'gogna' not in str(ask.text.text), 'Dario gets the sfida: ' + str(ask.text.text))
ask.yes.Click(ask.yes)
secs(5)
A.ns.Botteghino.Show('sfide')
check(A.has('Lancia \'na sfida') and A.has('in corso') and A.has('Chi fa più pesci') and not A.has('Duello a la gogna'), 'the Sfide page lists it, no gogna there')
B.ns.T.Bump('fi', 7); A.ns.T.Bump('fi', 3)
secs(10)
e = A.ns.Sfide.EndOf(T[0])
T[0] = e + 60; secs(70)
r4 = A.ns.Sfide.Store().res[c4.id]
check(r4 is not None and str(r4.w) == 'Player-1-BBB' and r4.da == 7 and r4.db == 3, 'the fishing week: Pietro 7 to 3: %s %s' % (r4 and (r4.w, r4.da, r4.db), [str(x) for x in A.ns.Sfide.State(A.ns.Sfide.All()[1])]))
# ---- schedina questions change every week, the capo swaps a square, an hour in a group is a piotta
q1 = [str(q.text) for q in A.ns.Tombola.Questions(1).values()]
q2 = [str(q.text) for q in A.ns.Tombola.Questions(2).values()]
check(len(q1) == 3 and len(set(q1)) == 3 and q1 != q2 and q1 == [str(q.text) for q in B.ns.Tombola.Questions(1).values()], 'three questions a week, new each week, the same for everyone: %s / %s' % (q1, q2))
wk = A.ns.Tombola.Week()
before = [str(x.id) for x in A.ns.Tombola.Card(wk).values()]
r = A.ns.Tombola.Swap(3)
check(first(r), 'the capo swaps square 3: ' + str(r))
secs(15)
afterA = [str(x.id) for x in A.ns.Tombola.Card(wk).values()]
afterB = [str(x.id) for x in B.ns.Tombola.Card(wk).values()]
check(afterA[2] != before[2] and afterA[:2] == before[:2] and afterA == afterB, 'only that square changed, and Pietro has the same card: %s -> %s' % (before[2], afterA[2]))
check(any('cambiato' in n and 'tombola' in n for n in B.news()), 'Pietro is told')
rb = B.ns.Tombola.Swap(1)
check(first(rb) is False, 'only the capo swaps')
groups = set()
check(len(set(afterA)) == 9, 'still nine different squares')
bal = B.ns.Tombola.Balance()
B.lua.execute('IsInGroup = function() return true end; IsInRaid = function() return false end; UnitName = function(u) if u == "party1" then return "Dario" end if u == "player" then return P_NAME end return nil end')
secs(3600 + 70)
check(B.ns.Tombola.Balance() == bal + 1, 'an hour in a group with Dario: one piotta more: %s -> %s' % (bal, B.ns.Tombola.Balance()))
B.lua.execute('IsInGroup = function() return false end')
# the gufata: Dario jinxes Pietro, who survives; then Gina jinxes Dario, who dies
balA, balB = A.ns.Tombola.Balance(), B.ns.Tombola.Balance()
ok = S.Gufa('Player-1-BBB', 10)
check(ok and A.ns.Tombola.Balance() == balA - 10, 'gufata placed')
secs(5)
gw = B.g.ErPattoGufaWatch
check(gw is not None and gw.shown and 'Dario te gufa' in str(gw['items'][1].title.text) and '10 piotte' in str(gw['items'][1].line1.text) and ':' in str(gw['items'][1].bar.text.text), 'Pietro sees the gufata with its timer: ' + str(gw and gw['items'][1].bar.text.text))
check(A.g.ErPattoGufaWatch is not None and A.g.ErPattoGufaWatch.shown and 'gufi Pietro' in str(A.g.ErPattoGufaWatch['items'][1].title.text), 'and Dario sees his own')
T[0] += 400; secs(70)
check(B.ns.Tombola.Balance() == balB + 10 and A.ns.Tombola.Balance() == balA - 10, 'Pietro lived: he takes the 10')
balA, balC = A.ns.Tombola.Balance(), C.ns.Tombola.Balance()
ok = SC.Gufa('Player-1-AAA', 10)
secs(5)
A.ns.Fun.Said('mo\' vado a pijà er boss', 'Dario')
A.ns.Fun.OnDeath(); A.ns.T.OnDeath()
secs(40)
check(C.ns.Tombola.Balance() == balC + 5 and A.ns.Tombola.Balance() == balA - 5, 'Dario died: Gina gets half more, Dario pays 5: %s %s' % (C.ns.Tombola.Balance(), A.ns.Tombola.Balance()))
# li scontrini: every line adds up to the purse, and the gufata paid
for x in (A, B, C):
    lines = list(x.ns.Tombola.Ledger().values())
    tot = sum((l.g or 0) - (l.s or 0) for l in lines)
    check(tot == x.ns.Tombola.Balance(), '%s: the scontrini add up to the purse: %s vs %s' % (x.name, tot, x.ns.Tombola.Balance()))
gl = [l for l in C.ns.Tombola.Ledger().values() if str(l.k) == 'gu']
check(gl and gl[0].g == 15 and gl[0].s == 10, 'Gina\'s gufata on Dario: 10 in, 15 back')
C.ns.Botteghino.Show('conti')
check(C.has('Scontrini') and C.has('Gufata su Dario') and C.has('Messe'), 'the Scontrini page lists it')
secs(30)
lgA = [str(C.ns.Tombola.LedgerText(l)) for l in C.ns.Tombola.LedgerOf(C.ns.state.members['Player-1-AAA']).values()]
check(any('Gufata de Gina' in t for t in lgA), 'and Gina can read Dario\'s: ' + str(lgA[:4]))
# the game blocks the emotes: remembered, and from then on a line in the emote colour for the patto
B.g.FIRE('ADDON_ACTION_BLOCKED', 'ErPatto', 'C_ChatInfo.PerformEmote()')
n0 = len(list(B.g.EMOTES.values()))
T[0] += 5
B.ns.Sfide.Emote('DANCE')
secs(3)
check(len(list(B.g.EMOTES.values())) == n0 and any('se mette a ballà' in str(m) for m in A.g.CHAT.values()), 'emote blocked once: no more tries, Dario reads the line')
# er karaoke: every song at every speed is there, and the speeds gather round 1x
import collections
media = os.path.join(ADDON, 'Media', 'karaoke')
missing = [f'k{i}_{sp:03d}.ogg' for i in range(1, 5) for sp in (50, 70, 85, 100, 115, 130, 150) if not os.path.exists(os.path.join(media, f'k{i}_{sp:03d}.ogg'))]
check(not missing, 'the karaoke files are all there: ' + str(missing))
cnt = collections.Counter(int(A.ns.Sfide.KaraSpeed()) for _ in range(2000))
check(cnt[100] > cnt[130] > cnt[150] and cnt[100] > cnt[70] > cnt[50], 'the speed: mostly 1x, rarely 0.5x or 1.5x: ' + str(sorted(cnt.items())))
# the graveyard
rip = A.rec().rip
check(rip and 'boss' in str(rip[1].w), 'the gravestone keeps the last words')
check(any('R.I.P.' in n and 'boss' in n for n in B.news()), 'and the friends read them in the news')
B.ns.UI.ShowProgress('rip')
check(B.has('Cimitero') and B.has('R.I.P.') and B.has('Li più morti') and B.has('A la gogna'), 'Cimitero page')
holders = A.ns.Titles.Holders()
check(holders['pecore'] and (holders['pecore']['Player-1-BBB'] or holders['pecore']['Player-1-CCC']), 'A Re de le Pecore: who went most a la gogna')
bad = [e for c in clients for e in c.errors()]
check(not bad, 'no errors: ' + str(bad[:4]))
unk = dict(A.g.UNKNOWN)
print('methods not in stub list:', {str(k): v for k, v in unk.items()})
print('\n%d failures' % len(fails))
