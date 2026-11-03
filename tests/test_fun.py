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
check(A.has('La Tombola, settimana 1') and A.has('La Schedina') and A.has('Li più ricchi') and A.has('piotte'), 'Botteghino: card, schedina, richest, purse')

# ---- la Schedina: Dario bets 10 on Pietro levelling most; Pietro bets 5 on himself, Gina nobody
TB = A.ns.Tombola
bal0 = TB.Balance()
ok = TB.Bet('a', 'Player-1-BBB')
ok2 = TB.Bet('a', None, 10)
check(ok and ok2 and str(A.rec().vt.a) == 'Player-1-BBB' and A.rec().vt.sa == 10 and TB.Balance() == bal0 - 10, 'bet placed and paid: 10 piotte on Pietro')
bad = TB.Bet('a', None, 'boh')
check((bad[0] if isinstance(bad, tuple) else bad) is False, 'a stake must be a number')
ok7 = TB.Bet('a', None, 7)
check(ok7 and A.rec().vt.sa == 7 and TB.Balance() == bal0 - 7, 'any stake, not just 1/5/10: 7')
# typed in the box and Punta
A.ns.UI.Show('botteghino')
r1 = A.ns.UI._views.botteghino.q[1]
r1.stake.SetText(r1.stake, '10'); r1.place.Click(r1.place)
check(A.rec().vt.sa == 10 and TB.Balance() == bal0 - 10, 'typed 10 in the box and Punta')
res = TB.Bet('b', None, 5)
check(res[0] is False if isinstance(res, tuple) else res is False, 'no stake without a pick')
big = TB.Bet('c', 'Player-1-AAA', 10000)
check((big[0] if isinstance(big, tuple) else big) is False, 'cannot stake more than you have')
B.ns.Tombola.Bet('a', 'Player-1-BBB'); B.ns.Tombola.Bet('a', None, 5)
secs(10)
check(str(B.ns.state.members['Player-1-AAA'].vt.a) == 'Player-1-BBB', 'the others see the bet')
A.ns.UI.Show('botteghino')
check(A.has('Montepremi 15: Pietro 2 (paga 1,0)'), 'pot and the top pick with its payout')
T[0] = START + WEEK + 3600; secs(130)
book = A.g.ErPattoDB.points[code]
check(book.weeks[1] is not None and book.right == 1 and book.weeks[1].w == 10, 'week 1 paid: pot 15 shared 10/5 -> Dario gets 10: %s' % (book.weeks[1].w,))
ch = A.g.ErPattoChiusura
check(ch and ch.shown and 'Settimana 1 chiusa' in str(ch.title.text) and '+10' in str(ch.schMoney.text) and 'Pietro' in str(ch.rows[1].detail.text), 'closed week shown in its own window, not the chat: ' + str(ch and ch.title.text))
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
check(A.g.ErPattoGuide is not None, 'the guide opened once after creating the patto')
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
bad = [e for c in clients for e in c.errors()]
check(not bad, 'no errors: ' + str(bad[:4]))
unk = dict(A.g.UNKNOWN)
print('methods not in stub list:', {str(k): v for k, v in unk.items()})
print('\n%d failures' % len(fails))
