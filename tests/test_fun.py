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
# ---- er duello a la gogna
S, SB, SC = A.ns.Sfide, B.ns.Sfide, C.ns.Sfide
for x in clients:
    x.lua.execute('EMOTES = {}; DoEmote = function(e, t) table.insert(EMOTES, e .. ":" .. tostring(t)) end; DUELS = {}; StartDuel = function(u) table.insert(DUELS, u) end')
secs(15)
def first(v): return v[0] if isinstance(v, tuple) else v
def second(v): return v[1] if isinstance(v, tuple) else None
NAMES = {A: 'Dario', B: 'Pietro', C: 'Gina'}
def duel(w, l):
    T[0] += 60
    for x in (w, l): x.ns.T.OnSystemMessage('%s has defeated %s in a duel' % (NAMES[w], NAMES[l]))
    secs(10)
balA, balB = A.ns.Tombola.Balance(), B.ns.Tombola.Balance()
S.OpenDuel('Player-1-BBB')
dd = A.g.ErPattoDuelloGogna
check(dd.shown and 'Pietro' in str(dd.text.text) and 'pegno' in str(dd.text.text) and 'piotte' not in str(dd.text.text), 'the duel window: no piotte, the rule in one line: ' + str(dd.text.text))
dd.yes.Click(dd.yes)
check(dd.shown and 'Aspetto' in str(dd.msg.text) and not dd.yes.shown and A.ns.Tombola.Balance() == balA, 'thrown: the window waits, nothing paid')
check(not any('gogna' in str(x) for x in A.g.CHAT.values()), 'nothing in the chat')
secs(2)
call = B.g.ErPattoChiamata
check(call is not None and call.shown and 'Dario' in str(call.text.text) and 'gogna' in str(call.title.text) and 'pegno' in str(call.text.text), 'Pietro gets the call at once: ' + str(call and call.text.text))
busy = SC.Gogna('Player-1-AAA')
check(first(busy) is False and 'ballo' in str(second(busy)), 'Gina can\'t throw one at Dario while he has one going: ' + str(second(busy)))
call.yes.Click(call.yes)
secs(2)
check('detto de sì' in str(dd.msg.text), 'Dario\'s window says Pietro accepted: ' + str(dd.msg.text))
bet = C.g.ErPattoScommessa
check(bet is not None and bet.shown and 'Colosseo' in str(bet.title.text) and 'gogna' in str(bet.text.text), 'Gina, in the same zone, can bet: ' + str(bet and bet.text.text))
check(not hasattr(bet, 'no') or bet.no is None, 'no "Gnente" button between the two names')
bet.stake.SetText(bet.stake, '3')
bet.pa.Click(bet.pa)
balC = C.ns.Tombola.Balance()
duel(A, B)
check(C.ns.Tombola.Balance() == balC + 6, 'Gina bet 3 on Dario and doubled: %s -> %s' % (balC, C.ns.Tombola.Balance()))
off = B.g.ErPattoRivincita
check(off is not None and off.shown and str(off.yes.text) == 'Rivincita!' and 'settimana' in str(off.text.text), 'Pietro lost: he is offered la rivincita')
wait = A.g.ErPattoPegno
check(wait is not None and wait.shown and 'rivincita' in str(wait.msg.text), 'Dario waits to see if he wants it: ' + str(wait and wait.msg.text))
off.yes.Click(off.yes)
secs(2)
call = A.g.ErPattoChiamata
check(call.shown and 'Rivincita' in str(call.title.text) and 'settimana' in str(call.text.text), 'Dario is asked for la rivincita')
call.yes.Click(call.yes)
secs(2)
duel(B, A)
off = A.g.ErPattoRivincita
check(off is not None and off.shown and str(off.yes.text) == 'La bella!', 'Pietro got even: Dario can ask for la bella')
check(B.g.ErPattoPegno.shown and 'bella' in str(B.g.ErPattoPegno.msg.text), 'Pietro waits to see if Dario wants la bella')
off.yes.Click(off.yes)
secs(2)
call = B.g.ErPattoChiamata
check(call.shown and 'bella' in str(call.title.text).lower(), 'Pietro is asked for la bella')
call.yes.Click(call.yes)
secs(2)
duel(B, A)
secs(10)
check(not A.g.ErPattoRivincita.shown, 'after la bella nobody can ask for more')
peg = B.g.ErPattoPegno
check(peg.shown and 'Dario' in str(peg.text.text) and 'settimana' in str(peg.text.text) and peg.yes.shown, 'Pietro won la bella that Dario asked for: he chooses er pegno, a week: ' + str(peg.text.text))
check(A.ns.Sfide.AtGogna('Player-1-AAA') is not None and A.ns.Sfide.NickOf(A.rec()) is None, 'Dario is a la gogna, er pegno still to come')
nickRow = [r for r in peg.pena.radios.values() if r.v == 2][0]
nickRow.Click(nickRow)
peg.yes.Click(peg.yes)
check('Scrivi' in str(peg.err.text), 'a nickname is needed: ' + str(peg.err.text))
peg.pena.text.SetText(peg.pena.text, 'Pippa')
peg.pena.text.GetScript(peg.pena.text, 'OnTextChanged')(peg.pena.text)
peg.yes.Click(peg.yes)
secs(5)
nA = SC.NickOf(C.ns.state.members['Player-1-AAA'])
check(nA is not None and str(nA.t) == 'Pippa' and nA.til - T[0] > 6 * 86400, 'Dario is "Pippa" for a week, Gina sees it')
colA = str(C.ns.UI.H.Colored(C.ns.state.members['Player-1-AAA']))
check('Dario' in colA and '"Pippa"' in colA, 'Dario keeps his name, with "Pippa" next to it: ' + colA)
res = B.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ciao', 'Dario-Realm')
check(res[0] is False and 'Pippa' in str(res[1]), 'and in chat: ' + str(res[1]))
check(str(SC.Champion()) == 'Player-1-BBB' and C.ns.Titles.Holders()['campione']['Player-1-BBB'], 'Pietro sent Dario a la gogna: er Campione')
check(any('pure la bella' in n for n in C.news()) and any('Er pegno de' in n and 'Pippa' in n for n in C.news()), 'news: the bella lost and er pegno')
# a la gogna nobody duels: Dario can't throw one, Pietro already had his today
r1 = S.Gogna('Player-1-CCC')
check(first(r1) is False and 'Stai a la gogna' in str(second(r1)), 'Dario a la gogna: no duelli a la gogna: ' + str(second(r1)))
r2 = SB.Gogna('Player-1-CCC')
check(first(r2) is False and 'oggi' in str(second(r2)), 'Pietro had his one today: ' + str(second(r2)))
SC.OpenDuel('Player-1-AAA')
gd = C.g.ErPattoDuelloGogna
check(gd.shown and 'gogna' in str(gd.err.text) and gd.yes.enabled is False, 'Gina\'s window says Dario is a la gogna, Sfida! off: ' + str(gd.err.text))
gd.no.Click(gd.no)
# the next day: Pietro beats Gina, she says basta, Pietro doesn't choose: the picture, a day
T[0] += 86400 + 60; secs(5)
ok = SC.Gogna('Player-1-BBB')
check(first(ok), 'Gina throws one at Pietro the next day')
secs(2)
B.g.ErPattoChiamata.yes.Click(B.g.ErPattoChiamata.yes)
secs(2)
duel(B, C)
offC = C.g.ErPattoRivincita
check(offC.shown, 'Gina is offered la rivincita')
offC.no.Click(offC.no)
secs(5)
peg = B.g.ErPattoPegno
check(peg.shown and 'Gina' in str(peg.text.text) and "'n giorno" in str(peg.text.text), 'she said basta: Pietro chooses at once, a day')
peg.Hide(peg)
T[0] += 1000; secs(40)
g = A.ns.Sfide.GognaOf(A.ns.state.members['Player-1-CCC'])
check(g is not None and 0 < g.til - T[0] < 86400, 'Pietro didn\'t choose: Gina gets the picture for a day')
check(any('nun ha scelto' in n for n in A.news()), 'news: he didn\'t choose')
# the figuraccia: the day after, Pietro beats Gina again and makes her cluck
T[0] += 86400 + 60; secs(5)
SB.Gogna('Player-1-CCC'); secs(2)
C.g.ErPattoChiamata.yes.Click(C.g.ErPattoChiamata.yes); secs(2)
duel(B, C)
C.g.ErPattoRivincita.no.Click(C.g.ErPattoRivincita.no); secs(5)
peg = B.g.ErPattoPegno
row = [r for r in peg.pena.radios.values() if r.v == 4][0]
row.Click(row)
peg.pena.emote.Click(peg.pena.emote)
peg.yes.Click(peg.yes)
secs(10)
check(any('CHICKEN' in str(e) for e in C.g.EMOTES.values()), 'Gina does the chicken in front of everyone: ' + str(list(C.g.EMOTES.values())))
# la rivincita refused: Gina beats Pietro, who asks for it; Gina says no: Pietro a la gogna a day
T[0] += 86400 + 60; secs(5)
SC.Gogna('Player-1-BBB'); secs(2)
B.g.ErPattoChiamata.yes.Click(B.g.ErPattoChiamata.yes); secs(2)
duel(C, B)
B.g.ErPattoRivincita.yes.Click(B.g.ErPattoRivincita.yes); secs(2)
check(C.g.ErPattoChiamata.shown and str(C.g.ErPattoChiamata.no.text) == 'Nun te la do', 'Gina can refuse la rivincita')
C.g.ErPattoChiamata.no.Click(C.g.ErPattoChiamata.no); secs(5)
check('tirato indietro' in str(B.g.ErPattoRivincita.msg.text), 'Pietro\'s window says she refused: ' + str(B.g.ErPattoRivincita.msg.text) + ' / ' + str(B.g.ErPattoRivincita.shown))
check(any('nun ha dato la rivincita' in n for n in A.news()), 'news: rivincita refused')
peg = C.g.ErPattoPegno
row = [r for r in peg.pena.radios.values() if r.v == 5][0]
row.Click(row)
peg.yes.Click(peg.yes)
secs(5)
gB = A.ns.Sfide.AtGogna('Player-1-BBB')
check(gB is not None and gB.til - T[0] < 86400 and str(SC.Champion()) == 'Player-1-CCC', 'Pietro a la gogna a day; Gina beat the champion: the crown is hers')
hook = A.lua.eval('function(N) local o = N.Banner; BANNERS = {}; N.Banner = function(t, s, ...) table.insert(BANNERS, tostring(t) .. " / " .. tostring(s)) return o(t, s, ...) end end')
hook(A.ns.News)
B.ns.Fun.OnDeath(); B.ns.T.OnDeath()
secs(30)
bn = [str(x) for x in A.g.BANNERS.values()]
check(any('morto de novo Pietro' in n and 'strillone de Gina' in n for n in bn), 'lo strillone: Dario is told Pietro died: ' + str(bn[-2:]))
# a crash in the middle: Pietro beats Dario... Dario is a la gogna; Gina beats Pietro, Pietro reloads before asking
T[0] += 86400 + 60; secs(5)
ok = SC.Gogna('Player-1-BBB')
check(first(ok), 'Gina throws another: ' + str(second(ok)))
secs(8)
B.g.ErPattoChiamata.yes.Click(B.g.ErPattoChiamata.yes); secs(4)
duel(C, B)
B.g.ErPattoRivincita.Hide(B.g.ErPattoRivincita)
B.ns.Sfide.Update()
check(not B.g.ErPattoRivincita.shown, 'closed by hand: not shown again in the same session')
B.ns.Sfide.Forget()  # what a reload (or a crash and a new login) does
B.ns.Sfide.Update()
check(B.g.ErPattoRivincita.shown, 'after a reload Pietro is offered la rivincita again: ' + str([str(x.state) for x in B.ns.Sfide.Series().values()][:2]))
T[0] += 700; secs(40)
check(C.g.ErPattoPegno.shown and C.g.ErPattoPegno.yes.shown, 'ten minutes passed: Gina chooses er pegno: ' + str([str(x.state) for x in C.ns.Sfide.Series().values()][:2]))
C.g.ErPattoPegno.Hide(C.g.ErPattoPegno)
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
check(B.has('Er Cimitero') and B.has('R.I.P.') and B.has('Li più morti') and B.has('A la gogna'), 'Cimitero page')
holders = A.ns.Titles.Holders()
check(holders['pecore'] and (holders['pecore']['Player-1-BBB'] or holders['pecore']['Player-1-CCC']), 'A Re de le Pecore: who went most a la gogna')
bad = [e for c in clients for e in c.errors()]
check(not bad, 'no errors: ' + str(bad[:4]))
unk = dict(A.g.UNKNOWN)
print('methods not in stub list:', {str(k): v for k, v in unk.items()})
print('\n%d failures' % len(fails))
