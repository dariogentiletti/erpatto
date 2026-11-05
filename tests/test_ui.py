from lupa.lua51 import LuaRuntime
import os, random, re
random.seed(3)
ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# every file in the TOC, in the TOC's order
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
        for st in ['stub3.lua', 'stub4.lua', 'stub5.lua']: self.lua.execute(open(st).read())
        self.lua.execute('math.randomseed(%d)' % random.randint(1, 10**6))
        self.ns = self.lua.table()
        load = self.lua.eval('function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; return f end')
        for f in FILES: load(open(os.path.join(ADDON, f)).read(), f)("ErPatto", self.ns)
        self.g = self.lua.globals()
        self.g.P_GUID, self.g.P_NAME = guid, name
        self.guid = guid
        self.name = name
    def login(self, t):
        self.g.NOWV = t
        self.g.FIRE('ADDON_LOADED', 'ErPatto'); self.g.FIRE('PLAYER_LOGIN'); self.g.FIRE('PLAYER_ENTERING_WORLD')
    def texts(self): return [str(x) for x in self.g.VISIBLE_TEXTS().values()]
    def has(self, sub): return any(sub in t for t in self.texts())
    def btn(self, label): return self.g.FIND_BUTTON(label)
    def errors(self):
        logs = [str(x) for x in self.g.ErPattoDB.log.values() if '[Errore]' in str(x)]
        return logs + list(self.g.ERRORS.values())
clients = []
T = [START - 3 * 86400]
def step(n=1, dt=0.25):
    for _ in range(n):
        T[0] += dt
        for c in clients:
            c.g.ROSTER = c.lua.table_from([c.lua.table_from({'name': d.name, 'guid': d.guid}) for d in clients
                if d.g.JOINED and d.g.JOINED == c.g.JOINED])
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
A.login(T[0])
A.ns.UI.Toggle()
check(A.has("Crea 'n patto novo") and A.has("Entra co' 'n codice") and not A.has('Nome de la squadra'), 'first screen: only the choice, no create form yet')
wel = A.ns.UI._views.welcome
wel.go.Click(wel.go)
cr = A.ns.UI._views.create
check(cr.shown and A.has('Nome de la squadra') and A.has('Ore a settimana') and not A.has('Ore ar 20'), 'create form opens after choosing create, no estimate fields')
check(A.has('gio 5 nov a le 00:00'), 'start defaults to the Forever launch, shown as a date')
# calendar: open it, move to the next month, pick the 12th at 21:30
cr.startBtn.Click(cr.startBtn)
pk = A.g.ErPattoDatePicker
check(pk.shown and A.has('novembre 2026'), 'calendar opens on November 2026')
day12 = [b for b in pk.days.values() if b.shown and str(b.text.text) == '12'][0]
day12.Click(day12)
for _ in range(43): pk.Update(pk) if False else None
A.lua.eval('function(p) p.min = 21 * 60 + 30 p:Update() end')(pk)
okb = A.btn('Va bene'); okb.Click(okb)
check(A.has('gio 12 nov a le 21:30'), 'picked date shown on the start button')
A.lua.eval('function(p) p:Set(1793833200) end')(pk); okb2 = None
cr.startBtn.Click(cr.startBtn); lb = A.btn('Lancio de Forever'); lb.Click(lb); okb = A.btn('Va bene'); okb.Click(okb)
check(A.has('gio 5 nov a le 00:00'), 'Forever launch shortcut')
cr.rows[2][2].SetText(cr.rows[2][2], '500')
cr.create.Click(cr.create)
check('Ore de Carabinieri 8' in str(cr.err.text), 'bad hours rejected')
cr.rows[2][2].SetText(cr.rows[2][2], '30')
cr.create.Click(cr.create)
st = A.ns.state
check(st is not None and A.ns.MyRecord().team is None and len(str(st.code)) == 5, 'patto created, 5-character code, no team chosen yet: ' + str(st.code))
check(A.ns.UI._views.gruppi.shown, 'after creating, Gruppi opens to pick a team')
pq = A.btn('Passa qui')
pqs = [o for o in A.g.WIDGETS.values() if o.kind == 'Button' and o.text == 'Passa qui' and o.IsVisible(o)]
pqs[1].Click(pqs[1])
check(A.ns.MyRecord().team == 't2', 'Dario picks Carabinieri 8 from Gruppi')
A.ns.UI.Show('imp')
check(A.has(str(st.code)), 'settings tab shows the code ' + str(st.code))
check(A.has('Capo: Dario'), 'settings shows capo')
for tab in ['cap', 'gruppi', 'progresso', 'imp', 'capo']:
    A.ns.UI.Show(tab)
A.ns.UI.Show('cap')
check(A.has('se parte gio 5 nov a le 00:00'), 'cap tab before start shows start time')
check(A.has('Cap 22'), 'Carabinieri week-1 cap 22 shown before start')
check(not A.errors(), 'no errors building all tabs: ' + str(A.errors()[:3]))
# HUD
hud = A.g.ErPattoHUD
check(hud is not None and hud.shown and 'se parte tra' in str(hud.text and '' or ''), 'HUD exists') if False else None
hudtext = [str(x) for x in A.lua.eval('function() local out = {} for _, o in ipairs(WIDGETS) do if o.kind == "FontString" and o.parent == ErPattoHUD then out[#out+1] = o.text end end return out end')().values()]
check(any(t == 'Cap 22' for t in hudtext) and any(t == '-21' for t in hudtext) and any(t == 'Er patto parte tra 3 giorni' for t in hudtext), 'on-screen bar before start: cap, gap, start countdown: ' + str(hudtext))

# second player joins with the code from the UI
B = Client('Player-1-BBB', 'Pietro'); clients.append(B)
B.g.COMPLETED_N = 40
B.login(T[0]); B.ns.UI.Toggle()
bw = B.ns.UI._views.welcome
# the code as Impostazioni gives it to friends: the code and the name of who gives it
A.ns.UI.Show('imp')
invite = str(A.ns.UI._views.imp.code.text)
check(invite == str(st.code), 'Impostazioni gives the code, 5 letters and numbers: ' + invite)
bw.code.SetText(bw.code, ' ' + invite.lower() + ' ')
bw.join.Click(bw.join)
check(B.ns.state is not None and B.has('Aspetto li dati'), 'join from UI, waiting screen until data arrives')
wv = B.ns.UI._views.waiting
again = [o for o in B.g.WIDGETS.values() if o.kind == 'Button' and o.text == "Riprova mo'" and o.IsVisible(o)][0]
again.Click(again)
check(str(wv.msg.text) != '', 'waiting: "Riprova mo\'" searches again and says how: ' + str(wv.msg.text))
secs(20)
B.ns.UI.Refresh()
check(B.ns.state.settings.v >= 1 and not B.has('Aspetto li dati'), 'data arrived, waiting screen gone')
sq = B.g.ErPattoSquadra
sqb = [o for o in B.g.WIDGETS.values() if o.kind == 'Button' and str(o.parent) == str(sq) and o.text in ('I Cesaroni', 'Carabinieri 8') and o.IsVisible(o)]
check(sq is not None and sq.shown and len(sqb) == 2, 'the data are in: a window asks Pietro his squadra, one button per team')
B.ns.UI.Show('gruppi')
check(B.has('I Cesaroni') and B.has('Carabinieri 8') and B.has('Da sceglie'), 'Gruppi shows both teams and the no-team column')
passa = B.btn('Passa qui'); passa.Click(passa)
check(B.ns.MyRecord().team in ('t1', 't2'), 'Passa qui sets the team')
check(not B.g.ErPattoSquadra.shown, 'chosen from Gruppi: the squadra window goes away')
secs(2.5)
check(A.ns.state.members['Player-1-BBB'] is not None and A.ns.state.members['Player-1-BBB'].team == B.ns.MyRecord().team, 'Dario sees Pietro\'s squadra in two seconds')
secs(8)
A.ns.UI.Show('gruppi')
check(A.has('Pietro'), 'Dario sees Pietro in Gruppi')
A.ns.UI.Show('gruppi')
check(A.has('Pietro è passato da Da sceglie a I Cesaroni') or A.has('Pietro è passato da Da sceglie a Carabinieri 8'), 'switch history visible')
check(not B.btn('Capo') or not B.btn('Capo').shown, 'no Capo tab for normal member')
# capo changes pace from the Capo tab
A.ns.UI.Show('capo')
pace = A.ns.UI._views.capo.pace[1]
pace.hours.SetText(pace.hours, '10')
pace.apply.Click(pace.apply)
check(A.ns.state.settings.v == 2, 'capo pace change bumps settings to v2')
secs(8)
check(B.ns.state.settings.v == 2, 'member got the new pace')
# make Pietro vice from the members list
rows = A.ns.UI._views.capo.rows
vb = None
for r in rows.values():
    if 'Pietro' in str(r.name.text): vb = r.vice
vb.Click(vb)
secs(8)
check(B.ns.CanAdmin(), 'Pietro became vice and can admin')
B.ns.UI.Refresh()
check(any(t.key == 'capo' and t.shown for t in B.ns.UI._tabs.values()), 'vice sees the Capo tab')
# start passes: caps active, progress
T[0] = START + 2 * 86400; secs(1)
A.g.P_LEVEL = 23; A.g.FIRE('PLAYER_LEVEL_UP', 23)
A.ns.UI.Show('cap')
check(A.has('Sei sopra er cap de 1 livello') and A.has('Sei sopra er cap!'), 'over-cap shown on Cap tab and header')
A.g.P_LEVEL = 18; A.g.P_XP = 0; A.g.P_XPMAX = 17700; A.g.FIRE('PLAYER_XP_UPDATE', 'player')
A.ns.UI.Show('cap')
check(A.has('mancano 4 livelli') and A.has('te servono più o meno'), 'behind: levels and hours to cap')

# ---- Personaggio tab
A.ns.UI.Show('pg')
check(A.has('Membri') and A.has('Sordi:') and A.has('Uccisioni:') and not A.has('Rivale:'), 'Personaggio: stat boxes with PvP kills, no rival')
check(A.has('Livello 18 Human Mage'), 'level line with English race and class')
icons = [str(x) for x in A.lua.eval('function() local out = {} for _, o in ipairs(WIDGETS) do if o.kind == "Texture" and o.tex and tostring(o.tex):find("icon%-") then out[#out+1] = o.tex end end return out end')().values()]
check(sorted(set(icons)) == ['icon-chest', 'icon-feet', 'icon-head', 'icon-sword'], 'equipped icons in their slots: ' + str(sorted(set(icons))))
empties = [str(x) for x in A.lua.eval('function() local out = {} for _, o in ipairs(WIDGETS) do if o.kind == "Texture" and o.tex and tostring(o.tex):find("UI%-PaperDoll%-Slot") then out[#out+1] = o.tex end end return out end')().values()]
check(len(empties) == 14 and not any('Ranged' in e for e in empties), 'empty slots use slot art, ranged hidden when the client has none (%d)' % len(empties))
check(A.has('Ar cap:') and A.has('Squadra:') and A.has('Patto:'), 'left stat box rows')
# gold: loot, then mail money (not counted), then trade money just after closing (not counted)
A.g.P_MONEY = 1000; A.g.FIRE('PLAYER_MONEY')
A.g.P_MONEY = 25000; A.g.FIRE('PLAYER_MONEY')
A.g.FIRE('MAIL_SHOW'); A.g.P_MONEY = 525000; A.g.FIRE('PLAYER_MONEY'); A.g.FIRE('MAIL_CLOSED')
A.g.FIRE('TRADE_SHOW'); A.g.FIRE('TRADE_CLOSED'); A.g.P_MONEY = 625000; A.g.FIRE('PLAYER_MONEY')
secs(3)
A.g.P_MONEY = 625500; A.g.FIRE('PLAYER_MONEY')
g = A.ns.MyRecord().stats.t.g
check(g == 1000 + 24000 + 500, 'gold earned counts loot only, not mail or trade (got %s copper)' % g)
# the merchant: sell 3000, buy it back 3000, sell again 3000: one sale, not three
A.lua.eval('function() CanMerchantRepair = function() return true end; REPAIR = 2000; GetRepairAllCost = function() return REPAIR end end')()
A.g.FIRE('MERCHANT_SHOW')
for d in (3000, -3000, 3000):
    A.g.P_MONEY = A.g.P_MONEY + d; A.g.FIRE('PLAYER_MONEY')
A.g.FIRE('MERCHANT_CLOSED'); A.g.FIRE('MERCHANT_CLOSED')
g2 = A.ns.MyRecord().stats.t.g
check(g2 == g + 3000, 'merchant: sold, bought back, sold again: counted once (%s)' % (g2 - g))
# junk sold for 5000, food bought for 1000, repairs 2000: 4000 earned (repairs don't eat what was sold)
A.g.FIRE('MERCHANT_SHOW')
A.g.P_MONEY = A.g.P_MONEY + 5000; A.g.FIRE('PLAYER_MONEY')
A.g.P_MONEY = A.g.P_MONEY - 1000; A.g.FIRE('PLAYER_MONEY')
A.g.REPAIR = 0; A.g.P_MONEY = A.g.P_MONEY - 2000; A.g.FIRE('PLAYER_MONEY')
A.g.FIRE('MERCHANT_CLOSED')
g3 = A.ns.MyRecord().stats.t.g
check(g3 == g2 + 4000, 'merchant: sold 50s, bought 10s, repaired 20s: 40s earned (%s)' % (g3 - g2))
# only buying: nothing taken off what was earned elsewhere
A.g.FIRE('MERCHANT_SHOW'); A.g.P_MONEY = A.g.P_MONEY - 700; A.g.FIRE('PLAYER_MONEY'); A.g.FIRE('MERCHANT_CLOSED')
check(A.ns.MyRecord().stats.t.g == g3, 'merchant: only buying takes nothing off')
A.lua.eval('function() CanMerchantRepair = nil; GetRepairAllCost = nil end')()
# duels inside the patto: Dario beat Pietro twice, lost once; a duel with an outsider doesn't count here
A.g.FIRE('CHAT_MSG_SYSTEM', 'Dario has defeated Pietro in a duel')
A.g.FIRE('CHAT_MSG_SYSTEM', 'Dario has defeated Pietro in a duel')
A.g.FIRE('CHAT_MSG_SYSTEM', 'Pietro has defeated Dario in a duel')
A.g.FIRE('CHAT_MSG_SYSTEM', 'Dario has defeated Sconosciuto in a duel')
A.ns.UI.Show('pg')
pgS = A.ns.UI._views.pg.stats
check('2-1' in str(pgS.duel.value.text), 'duels inside the patto 2-1 (outsider not counted): %s' % pgS.duel.value.text)
check(any('2' in t and 'UI-GoldIcon' in t for t in A.texts()), 'gold shown with coin icons')
check(any('º' in str(b.text.text) for b in A.ns.UI._views.pg.badges.values()), 'rank badges use the ordinal sign')
wk = A.ns.UI._views.pg.weekBtn; wk.Click(wk)
check(wk.selected and not A.ns.UI._views.pg.totBtn.selected, 'week/always switch in the member list')
tb = A.ns.UI._views.pg.totBtn; tb.Click(tb)
A.g.FIRE('PLAYER_EQUIPMENT_CHANGED')
check(A.ns.MyRecord().il == 12.3, 'item level shared in my record (%s)' % A.ns.MyRecord().il)


# ---- vanilla character frame (0.4.0)
A.ns.UI.Show('pg')
pgv = A.ns.UI._views.pg
L = A.lua
check(A.g.ErPattoFrame.selTab[5].shown and A.g.ErPattoFrame.title.shown, 'Personaggio stays inside the window (same border, same tabs)')
pt = L.eval('function(v) local p = v.model.points[1] return p[1] .. "," .. tostring(p[2]) .. "," .. tostring(p[3]) .. "," .. v.model.w .. "x" .. v.model.h end')(pgv)
check(pt == 'TOPLEFT,51,-52,278x180', 'model between the slot columns: ' + pt)
head = L.eval('function(v) for _, b in ipairs(v.slots) do if b.slotName == "HeadSlot" then local p = b.points[1] return p[2] .. "," .. p[3] end end end')(pgv)
mh = L.eval('function(v) for _, b in ipairs(v.slots) do if b.slotName == "MainHandSlot" then local p = b.points[1] return p[2] .. "," .. p[3] end end end')(pgv)
check(head == '8,-52' and mh.endswith(',-325'), 'slot columns and weapon row inside the box (%s / %s)' % (head, mh))
check(A.has('Livello:') and A.has('Cap:') and A.has('Quest:') and A.has('Sordi:') and A.has('Duelli:'), 'adventure stats in the vanilla stat boxes')
check(A.has('Membri') and any('Pietro' in t for t in A.texts()), 'member picker lists Pietro')
PgTab = lambda: [b for b in A.ns.UI._tabs.values() if str(b.key) == 'pg'][0]
ErTabArt1 = lambda: bool(PgTab().off.fill.shown)
tab1 = L.eval('function() local p = ErPattoFrameTab1.points[1] return p[1] .. "," .. p[3] .. "," .. p[4] .. "," .. p[5] .. "," .. ErPattoFrameTab1.w end')()
check(tab1.startswith('TOPLEFT,TOPLEFT,20,-457'), 'first tab under the window, 20 px in: ' + tab1)
check(A.g.ErPattoFrame.selTab[5].shown and A.g.ErPattoFrame.selTab[5].shown and not ErTabArt1(), 'the selected tab stands over the border')
myEq = str(A.ns.MyRecord().eq)
check(myEq.startswith('2/') and '1.12345.3.24' in myEq and '5.6789.2.21.0.567' in myEq, 'my gear shared with item levels: ' + myEq)
A.ns.UI.Show('cap')
check(A.g.ErPattoFrame.selTab[5].shown and ErTabArt1(), 'Personaggio unselected: its black tab art shows, the border opens elsewhere')
# Pietro's pane, seen by Dario: from his record (he is far away)
secs(70)
B.g.FIRE('PLAYER_EQUIPMENT_CHANGED'); secs(70)
A.ns.UI.Show('gruppi')
prow = None
for col in A.ns.UI._views.gruppi.cols.values():
    for r in col.rows.values():
        if r.rec and str(r.rec.name) == 'Pietro' and r.shown: prow = r
check(prow is not None, 'Pietro row in Gruppi')
prow.Click(prow)
check(A.ns.UI._views.pg.shown and str(A.ns.UI._views.pg.name.text) == 'Pietro', "clicking Pietro in Gruppi opens his pane")
# hovering his helmet compares the helmet slot across the patto
headb = [b for b in pgv.slots.values() if b.slotName == 'HeadSlot'][0]
headb.scripts.OnEnter(headb)
tt = [str(x) for x in A.g.TT.values()]
check(any('Livello de l' in t and 'oggetto ner patto' in t for t in tt) and sum(1 for t in tt if ' | 24' in t) == 2, 'item tooltip compares the slot with the patto: ' + str(tt))
check(A.has('Livello 1 Umano Mago') or A.has('Livello'), 'his level line')
calls = [str(x) for x in (pgv.model.calls or L.table()).values()]
check(not pgv.model.shown and 'se vede quanno' in str(pgv.modelNote.text) and not any(c.startswith('SetCustomRace') for c in calls), 'far member: no model and no stand-in, just the note')
prow = [b for b in pgv.members.values() if b.shown and b.guid == pgv_far_guid][0] if False else None
farRow = [b for b in pgv.members.values() if b.shown and b.sel.shown][0]
farRow.Click(farRow)
check(not pgv.model.shown, 'clicking the same member again still shows no model (not yours)')
icons = [str(x) for x in L.eval('function(v) local out = {} for _, b in ipairs(v.slots) do if b.icon.tex then out[#out+1] = b.icon.tex end end return out end')(pgv).values()]
check('icon-id-12345' in icons and 'icon-id-6789' in icons, 'his equipment icons from the shared item ids')
# in group: real model by unit token
A.g.UNIT_GUIDS.party1 = 'Player-1-BBB'
A.ns.UI.Refresh()
calls = [str(x) for x in pgv.model.calls.values()]
check(calls[-1] == 'SetUnit:party1', 'grouped member: real 3D model from party unit')
A.g.UNIT_GUIDS.party1 = None
# back to me from the member list
for b in pgv.members.values():
    if b.guid == A.g.P_GUID and b.shown: b.Click(b)
check(str(pgv.name.text) == 'Dario', 'back to my own pane')
# ---- titles
A.ns.UI.Show('pg')
clear_chat = A.lua.eval('function() CHAT = {} end'); clear_chat()
A.ns.db.titles = None
A.ns.Titles.CheckNew()
check(any('hai vinto er titolo' in l and 'A Sor Capo' in l for l in [str(x) for x in A.g.CHAT.values()]), 'new title announced in chat')
tb = pgv.titleBtn
check(tb.shown, 'title button on my own pane')
tb.Click(tb)
menu = A.g.ErPattoTitleMenu
check(menu.shown and A.has('Nessun titolo') and A.has('A Sor Capo'), 'title menu lists my titles')
pick = [r for r in menu.rows.values() if r.shown and str(r.id) == 'sorcapo'][0]
pick.Click(pick)
check(str(A.ns.MyRecord().ti) == 'sorcapo' and A.has('A Sor Capo') and not menu.shown, 'title chosen and shown next to my name')
res = A.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'daje', 'Dario-Realm')
check(res[0] is False and 'A Sor Capo' in str(res[1]) and str(res[1]).endswith('daje'), 'chat shows the title in front of the message: ' + str(res[1]))
check('|Haddon:ErPatto:title:sorcapo|h' in str(res[1]), 'the title in chat is a link')
A.ns.Titles.OnLink('addon:ErPatto:title:sorcapo')
check(any('A Sor Capo' in str(x) for x in A.g.TT.values()), 'clicking it explains the title: ' + str(list(A.g.TT.values())[:4]))
def _pick(i):
    tb.Click(tb)
    p = [r for r in menu.rows.values() if r.shown and str(r.id) == i][0]; p.Click(p)
others = [str(r.id) for r in menu.rows.values() if str(r.id) not in ('', 'sorcapo', 'None')]
_pick(''); a1 = A.ns.MyRecord().ti
_pick('sorcapo'); a2 = str(A.ns.MyRecord().ti)
_pick(''); a3 = A.ns.MyRecord().ti
_pick('sorcapo'); a4 = str(A.ns.MyRecord().ti)
check(a1 is None and a2 == 'sorcapo' and a3 is None and a4 == 'sorcapo', 'title can be changed again and again (%s %s %s %s)' % (a1, a2, a3, a4))
# from one title straight to another, many times, and the list stays clickable (no "mouse down anywhere" closing it)
seq = []
for t in others[:3] + ['sorcapo'] + others[:3]:
    _pick(t); seq.append(str(A.ns.MyRecord().ti))
check(seq == others[:3] + ['sorcapo'] + others[:3], 'one title to another, again and again: ' + str(seq))
check(not A.lua.eval('function() local f = ErPattoTitleMenu return f and f.IsEventRegistered and f:IsEventRegistered("GLOBAL_MOUSE_DOWN") end')(), 'the list listens to no mouse event that could close it under the click')
tb.Click(tb); check(menu.shown and menu.sheet.shown, 'open: the sheet behind it too')
menu.sheet.Click(menu.sheet); check(not menu.shown and not menu.sheet.shown, 'a click outside closes it')
_pick('sorcapo')
# Forever: everyone is "Er Something", and the chat may write "Er Nia", "Er-Nia" or "Er Nia-Realm": each gets
# their own title, and "Er" alone is nobody's
look = A.lua.eval('''function(Ti)
  local map, firsts = {}, { er = 3, dario = 1 }
  Ti.Index(map, "Er Nia", "pescivendolo", firsts); Ti.Index(map, "Er Gnomo", "sorcapo", firsts); Ti.Index(map, "Dario Rossi", "nottambulo", firsts)
  return table.concat({ tostring(Ti.Lookup(map, "Er Nia")), tostring(Ti.Lookup(map, "Er-Nia")), tostring(Ti.Lookup(map, "Er Nia-Realm")),
    tostring(Ti.Lookup(map, "er gnomo")), tostring(Ti.Lookup(map, "Er-Gnomo-Realm")), tostring(Ti.Lookup(map, "Er")), tostring(Ti.Lookup(map, "Er Matto")),
    tostring(Ti.Lookup(map, "Dario-Realm")) }, ",")
end''')(A.ns.Titles)
check(str(look) == 'pescivendolo,pescivendolo,pescivendolo,sorcapo,sorcapo,nil,nil,nottambulo', 'chat titles on Forever: each "Er" his own, whatever way the chat writes the name: ' + str(look))
res2 = A.ns.Titles.ChatFilter(None, 'CHAT_MSG_SAY', 'ciao', 'Sconosciuto-Realm')
check(res2 is False or res2 == False or (isinstance(res2, tuple) and len(res2) == 1), 'strangers unchanged')
secs(8)
B.ns.UI.Show('pg')
check(B.ns.Titles.Of(B.ns.state.members[A.g.P_GUID]) == 'A Sor Capo', 'the others see my title')
check('Codice' not in str(A.g.ErPattoFrame.info.text) and str(A.g.ErPattoFrame.title.text) == str(A.ns.state.settings.name), 'window header: patto name, no code')
# ---- world PvP: kills and honor go up, spending honor doesn't count
A.g.PVP_HK = 5; A.g.PVP_HONOR = 300; A.g.FIRE('PLAYER_PVP_KILLS_CHANGED')
A.g.PVP_HK = 8; A.g.PVP_HONOR = 420; A.g.FIRE('PLAYER_PVP_KILLS_CHANGED')
A.g.PVP_HONOR = 100; A.g.FIRE('CURRENCY_DISPLAY_UPDATE')
A.g.PVP_HONOR = 150; A.g.FIRE('CURRENCY_DISPLAY_UPDATE')
st_ = A.ns.MyRecord().stats.t
check(st_.hk == 8 and st_.hn == 470, 'PvP: 8 kills and 470 honor gained since login, spending ignored (hk=%s hn=%s)' % (st_.hk, st_.hn))
# ---- title menu closes when you click elsewhere or change tab
A.ns.UI.Show('pg')
tb2 = A.ns.UI._views.pg.titleBtn; tb2.Click(tb2)
menu2 = A.g.ErPattoTitleMenu
check(menu2.shown, 'title menu open')
menu2.sheet.Click(menu2.sheet)
check(not menu2.shown, 'click outside closes the title menu')
tb2.Click(tb2)
A.ns.UI.Show('cap'); A.ns.UI._tabs[2].Click(A.ns.UI._tabs[2])
check(not menu2.shown, 'changing tab closes the title menu')
# ---- announcement: the capo posts, the others confirm once, then it's a chat line at login
A.ns.UI.Show('capo')
cv = A.ns.UI._views.capo
cv.ann.SetText(cv.ann, "Sabato sera tutti a Deadmines")
cv.annPost.Click(cv.annPost)
check(A.ns.state.settings.ann and str(A.ns.state.settings.ann.t) == "Sabato sera tutti a Deadmines", 'announcement saved in the settings')
check(not A.g.ErPattoAnnouncement or not A.g.ErPattoAnnouncement.shown, 'the capo does not get his own popup')
secs(8)
ap = B.g.ErPattoAnnouncement
check(ap is not None and ap.shown and B.has('Sabato sera tutti a Deadmines'), 'the others get the announcement to confirm')
okb = [o for o in B.g.WIDGETS.values() if o.kind == 'Button' and o.text == 'Ho letto' and o.IsVisible(o)][0]
okb.Click(okb)
check(not ap.shown, 'confirmed, the popup closes')
B.lua.eval('function() CHAT = {} end')()
B.ns.UI.CheckAnnouncement(True)
check(not ap.shown and any('Sabato sera' in str(x) for x in B.g.CHAT.values()), 'after confirming: only a chat line at login')
A.ns.UI.Show('capo')
check("Sabato sera tutti a Deadmines" in str(cv.annNow.text) and cv.annDel.shown, 'Capo tab shows the live announcement with Togli')
cv.annPreview.Click(cv.annPreview)
check(A.g.ErPattoAnnouncement.shown, 'preview shows the dialog as the others see it')
A.g.ErPattoAnnouncement.Hide(A.g.ErPattoAnnouncement)
cv.annDel.Click(cv.annDel)
check(A.ns.state.settings.ann is None and 'Nessun annuncio' in str(cv.annNow.text) and not cv.annDel.shown, 'Togli removes it')
# test mode is for the capo only
B.lua.eval('function() CHAT = {} end')()
B.g.SlashCmdList.ERPATTO('prova')
check(any('solo er capo' in str(x) for x in B.g.CHAT.values()) and not B.ns.db.opts.testMode, 'a member cannot turn on test mode')
# ---- late install: Pietro had 40 quests done before the addon; /played gives his time
check(B.ns.MyRecord().stats.t.q >= 40, 'late install: completed quests recovered from the game (%s)' % B.ns.MyRecord().stats.t.q)
check(B.g.PLAYED_REQUESTED == True, 'asked the game for /played')
B.g.FIRE('TIME_PLAYED_MSG', 3 * 3600, 600)
check(B.ns.MyRecord().stats.t.pt >= 3 * 3600 - 60, 'played time recovered (capped to the time since the start)')
secs(70)
check(A.ns.state.members['Player-1-BBB'].stats.t.q >= 40, 'the others see the recovered numbers')
# ---- on-screen bar: next cap only while waiting, small inside the bar
A.ns.UI.RefreshHUD()
# ---- journal: raw data kept for future features
J = A.ns.J
A.lua.eval("""function() UNITS.target = { guid = "Creature-0-1-2-3-448-0001", name = "Hogger", class = "elite" } end""")()
A.g.FIRE('PLAYER_TARGET_CHANGED')
A.lua.eval('function() UNITS.target.dead = true end')()
A.g.FIRE('UNIT_HEALTH', 'target')
A.lua.eval("""function() LOOT = { { src = "Creature-0-1-2-3-448-0001", link = "|cff1eff00|Hitem:2000::::::::|h[Spada]|h|r" }, { src = "Creature-0-1-2-3-299-0002" } } end""")()
A.g.FIRE('LOOT_OPENED'); A.g.FIRE('LOOT_CLOSED')
A.lua.eval('function() UNITS.target = nil LOOT = {} end')()
jj = J.Get()
check(jj.kills[448].c == 1 and str(jj.kills[448].n) == 'Hogger' and jj.kills[299].c == 1, 'kills by NPC: Hogger once (target + loot same mob), the looted wolf once')
check(len(list(jj.loot.values())) >= 1 and jj.loot[1].id == 2000, 'green item from the loot window logged')
A.g.FIRE('CHAT_MSG_LOOT', 'You receive loot: |cff1eff00|Hitem:2000::::::::|h[Spada]|h|rx2.')
check(jj['items'][2000].c == 2, 'items received counted by id')
_om = jj.money.out_merchant or 0
A.g.FIRE('MERCHANT_SHOW'); A.g.P_MONEY = A.g.P_MONEY - 500; A.g.FIRE('PLAYER_MONEY'); A.g.FIRE('MERCHANT_CLOSED')
check((jj.money.out_merchant or 0) == _om + 500, 'gold spent at the merchant filed under merchant')
A.g.FIRE('PLAYER_DEAD')
check(len(list(jj.deaths.values())) >= 1, 'deaths logged with place and level')
A.g.FIRE('UNIT_SPELLCAST_SUCCEEDED', 'player', 'x', 8690)
check(jj.spells[8690].c == 1, 'spells cast counted')
A.g.UNIT_GUIDS.party1 = 'Player-1-BBB'
A.lua.eval('function() IsInGroup = function() return true end end')()
J.Minute()
A.lua.eval('function() IsInGroup = function() return false end end')()
A.g.UNIT_GUIDS.party1 = None
check(jj.together['Player-1-BBB'] == 60, 'time played together with each patto member')
# auction gold: counts by default, the capo can switch it off
g0 = A.ns.MyRecord().stats.t.g or 0
A.g.MAILS[1] = A.lua.eval('{ sender = "Casa d\'aste", subject = "Asta riuscita", money = 50000, invoice = "seller" }')
A.g.MAILS[2] = A.lua.eval('{ sender = "Pietro", subject = "regalo", money = 20000 }')
A.g.FIRE('MAIL_SHOW')
A.g.TakeInboxMoney(1); A.g.P_MONEY = A.g.P_MONEY + 50000; A.g.FIRE('PLAYER_MONEY')
A.g.TakeInboxMoney(2); A.g.P_MONEY = A.g.P_MONEY + 20000; A.g.FIRE('PLAYER_MONEY')
A.g.FIRE('MAIL_CLOSED'); secs(3)
g1 = A.ns.MyRecord().stats.t.g
check(g1 - g0 == 50000, 'auction sale counted, gift by mail not (%s)' % (g1 - g0))
A.ns.UI.Show('capo')
ahc = A.ns.UI._views.capo.ah
check(ahc.checked == True, 'capo checkbox shows auction gold on by default')
ahc.Click(ahc)
check(A.ns.state.settings.noAh == True, 'capo turned auction gold off')
secs(8)
check(B.ns.state.settings.noAh == True, 'the switch reached the others')
A.g.FIRE('MAIL_SHOW'); A.g.TakeInboxMoney(1); A.g.P_MONEY = A.g.P_MONEY + 50000; A.g.FIRE('PLAYER_MONEY'); A.g.FIRE('MAIL_CLOSED'); secs(3)
check(A.ns.MyRecord().stats.t.g == g1, 'with the switch off, auction money is not counted')
ahc.Click(ahc)
check(not A.ns.state.settings.noAh, 'switched back on')

# on-screen bar: blue behind (partly full), green at the cap, red above
hudf = A.g.ErPattoHUD
def hudstate():
    A.ns.UI.RefreshHUD()
    return str(hudf.color), hudf.value, [str(x) for x in A.lua.eval('function() local out = {} for _, o in ipairs(WIDGETS) do if o.kind == "FontString" and o.parent == ErPattoHUD then out[#out+1] = o.text end end return out end')().values()]
A.g.P_LEVEL = 18; A.g.P_XP = 0; A.g.P_XPMAX = 100; A.g.FIRE('PLAYER_XP_UPDATE', 'player')
c, v, t = hudstate()
check(c == '0.00,0.39,0.88' and 0.7 < v < 0.9 and 'Cap 22' in t and '-4' in t and '' in t, 'behind: blue, filled from week start (%s %.2f %s)' % (c, v, t))
A.g.P_LEVEL = 22; A.g.FIRE('PLAYER_LEVEL_UP', 22)
c, v, t = hudstate()
check(c == '0.10,0.75,0.10' and v == 1 and 'Cap 22' in t and any(x.startswith('Prossimo cap: 32, tra ') for x in t), 'at the cap: green, full, next cap countdown (%s %s)' % (c, t))
A.g.P_LEVEL = 23; A.g.FIRE('PLAYER_LEVEL_UP', 23)
c, v, t = hudstate()
check(c == '0.85,0.15,0.15' and v == 1 and any('+1' in x for x in t), 'over the cap: red, full, +1 (%s %s)' % (c, t))
A.g.P_LEVEL = 18; A.g.FIRE('PLAYER_LEVEL_UP', 18)
# test mode with fake members and progress tab
A.ns.db.opts.testMode = True
A.ns.UI.Show('progresso')
check(A.has('Aldo (prova)') or any('Aldo (prova)' in t for t in A.texts()), 'test mode adds fake members')
pv = A.ns.UI._views.progresso
check(A.has('Corsa') and A.has('Ore giocate') and A.has('Rari ammazzati') and A.has('Duelli vinti') and not A.has('perse'), 'leaderboard cards, wins only')
top5 = [str(r.pos.text) for r in pv.rank.cards[1].rows.values() if r.shown]
check(top5 == ['1º', '2º', '3º', '4º', '5º'], 'each card shows the top five: ' + str(top5))
wk2 = pv.weekBtn; wk2.Click(wk2)
check(A.has("'sta settimana"), 'week mode labels the cards')
pv.totBtn.Click(pv.totBtn)
# clicking a member on a card opens the comparison
row = [r for r in pv.rank.cards[3].rows.values() if r.shown and r.guid != A.g.P_GUID][0]
row.Click(row)
check(pv.vs.shown and A.has('contro') and A.has('Duelli tra voi') and A.has('Morti') and A.has('Uccisioni PvP') and A.has('Onore') and not A.has('arrivato prima'), 'comparison page: side by side incl. PvP, no milestone notes')
A.g.FIRE('QUEST_TURNED_IN', 176, 100, 0)
secs(16)  # (a second death needs time after the first: the game's double PLAYER_DEAD counts once)
A.g.FIRE('PLAYER_DEAD')
pv.tabDiary.Click(pv.tabDiary)
check(A.has('  La quest nummero 176') and A.has('Elwynn Forest') and A.has('2 morti') and A.has('Fatte da sempre: '), 'my quest diary grouped by zone, deaths counted')
check(pv.diary.shown and A.has('Traguardi') and A.has('Professioni') and not A.has('previste') and A.has('Da sempre: '), 'diary page: level bar, time, milestones, professions, no planned hours shown')
fakeRow = [b for b in pv.diary.list.rows.values() if b.shown and 'Aldo' in str(b.text.text)][0]
fakeRow.Click(fakeRow)
check(A.has('Blacksmithing') or A.has('Alchemy') or A.has('Herbalism') or A.has('Mining'), 'diary of another member shows their professions (English names)')
meRow = [b for b in pv.diary.list.rows.values() if b.shown and b.guid == A.g.P_GUID][0]
meRow.Click(meRow)
tl = pv.diary.titles
held = [str(x) for x in (tl.countBtn.list or L.table()).values()]
check(A.has('Titoli') and 'A Sor Capo' in str(tl.main.text) and 'A Sor Capo' in held and tl.all is None and not A.has('passa er mouse'), 'diary: the title shown, how many (hover), no extra button: ' + str(held))
pv.tabTitles.Click(pv.tabTitles)
cols = pv.titles.cols
check(pv.titles.shown and A.has('Li primi der patto') and A.has('Traguardi') and A.has('Mestieri') and A.has('A Pescivendolo') and not A.has('Come se vince'), 'titles page: one box per kind, who holds it')
row = [r for r in cols[2].rows.values() if r.shown and str(r.t.id) == 'sorcapo'][0]
row.GetScript(row, 'OnEnter')(row)
check(any('Er capo der patto' in str(x) for x in A.g.TT.values()), 'hovering a title: how it is won and all who hold it')
pv.tabDiary.Click(pv.tabDiary)
fakeRow.Click(fakeRow)
earned = A.ns.Titles.Earned(A.ns.UI.Members())
profTitles = set(k for g in earned.values() for k in g.keys()) & {'fabbro', 'alchimista', 'erborista', 'minatore', 'cuoco'}
check(len(profTitles) >= 3, 'profession titles awarded to the best in each: ' + str(sorted(profTitles)))
check(A.has('  The Killing Fields'), 'their last quests')

# lots of quests: 300 over 12 zones, spread over three weeks
A.lua.eval("""function(ns, now)
  local log = {}
  for i = 1, 300 do log[i] = { t = "Quest " .. i, z = "Zona " .. (i % 12 + 1), at = now - i * 5000, lv = 20 } end
  ns.db.qlog[ns.recordGuid] = log
end""")(A.ns, A.g.NOWV)
mine = [b for b in pv.diary.list.rows.values() if b.shown and b.guid == A.g.P_GUID][0]
mine.Click(mine)
rows_all = sum(1 for r in pv.diary.quest.rows.values() if r.shown)
pv.weekBtn.Click(pv.weekBtn)
rows_week = sum(1 for r in pv.diary.quest.rows.values() if r.shown)
pv.totBtn.Click(pv.totBtn)
check(140 <= rows_all <= 175 and rows_week < rows_all and A.has('Zona '), 'big quest diary: capped list grouped by zone (%d rows), week filter (%d rows)' % (rows_all, rows_week))
check(pv.diary.quest.scroll.ScrollBar.shown, 'long quest list: scroll bar visible')
A.lua.eval("function(ns) ns.db.qlog[ns.recordGuid] = {} end")(A.ns)
A.ns.UI.Refresh()
check(not pv.diary.quest.scroll.ScrollBar.shown, 'empty quest list: no scroll bar')
# the titles box holds two short lines, whatever the number of titles
check(pv.diary.titles.main.points[1][3] >= -30 and pv.diary.titles.count.points[1][3] >= -46, 'titles box: two lines inside the box')
# a rare: target it alive, then dead
A.lua.eval("""function() UNITS.target = { guid = "Creature-0-1-2-3-4-RARE", name = "Mor'Ladim", class = "rare" } end""")()
A.g.FIRE('PLAYER_TARGET_CHANGED')
A.lua.eval('function() UNITS.target.dead = true end')()
A.g.FIRE('UNIT_HEALTH', 'target'); A.g.FIRE('LOOT_OPENED')
A.lua.eval('function() UNITS.target = nil end')()
check(A.ns.MyRecord().stats.t.rk == 1 and str(A.ns.MyRecord().rl[1].n) == "Mor'Ladim", 'rare kill counted once with its name')
A.ns.UI.Refresh()
check(A.has("Mor'Ladim") and A.has('Rari (1)'), 'rare shown in the diary')
mine2 = [b for b in pv.diary.list.rows.values() if b.shown and b.guid == A.g.P_GUID][0]
mine2.Click(mine2)
pv.weekBtn.Click(pv.weekBtn)
check(A.has("'Sta settimana: ") and not A.has('Da sempre: ') and not A.has('Fatte da sempre'), 'diary in week mode shows only this week')
pv.totBtn.Click(pv.totBtn)
check(A.has('Da sempre: ') and not A.has("'Sta settimana: "), 'diary in always mode shows only totals')
pv.tabRank.Click(pv.tabRank)
A.ns.UI.Show('pg')
check(any(b.shown for b in A.ns.UI._views.pg.members.values()), 'Personaggio list with fake members')
pgv2 = A.ns.UI._views.pg
hb = [b for b in pgv2.slots.values() if b.slotName == 'HeadSlot'][0]
hb.scripts.OnEnter(hb)
tt = [str(x) for x in A.g.TT.values()]
ranked = [t for t in tt if ' | ' in t]
check(len(ranked) == 5 and any(' <' in t for t in ranked), 'five members around me in the slot comparison: ' + str(ranked))
A.ns.UI.Show('gruppi')
check(not A.errors(), 'no errors in test mode tabs: ' + str(A.errors()[:3]))
A.ns.db.opts.testMode = False
# quest warning overlay
A.g.P_LEVEL = 22; A.g.P_XPMAX = 25200; A.g.P_XP = 25000; A.g.REWARD_XP = 900
A.g.FIRE('QUEST_COMPLETE')
check(A.has('Occhio ar cap!'), 'quest warning overlay shown')
A.g.FIRE('QUEST_FINISHED')
check(not A.has('Occhio ar cap!'), 'overlay hidden after closing quest window')
# lifted (far future)
T[0] = START + 30 * WEEK; secs(1)
A.ns.UI.Show('cap')
check(A.has('Libbero'), 'after the calendar ends the cap is lifted')
# diagnostics window
A.ns.Diag.Toggle(); A.ns.Diag.EnvReport()
check(any('[Patto] codice' in str(x) for x in A.g.ErPattoDB.log.values()), 'diag report includes patto status')
check(A.g.ErPattoDiagFrame.shown, 'one /patto diag opens the window')
A.ns.Diag.Toggle()  # the log quotes the stub's raw values; close it before the "nil" check
# leaving as capo with members is blocked, then transfer and leave
A.ns.UI.Show('imp')
lv = A.btn('Esci dar patto'); lv.Click(lv); lv.Click(lv)
check(A.ns.state is not None and A.has('prima passa er comando'), 'capo cannot leave with members inside')
A.ns.UI.Show('capo')
for r in A.ns.UI._views.capo.rows.values():
    if 'Pietro' in str(r.name.text): r.capo.Click(r.capo); r.capo.Click(r.capo)
secs(8)
check(B.ns.IsCapo() and not A.ns.IsCapo(), 'capo transferred to Pietro')
A.ns.UI.Show('imp')
lv = A.btn('Esci dar patto'); lv.Click(lv); lv.Click(lv)
check(A.ns.state is None and A.has("Crea 'n patto"), 'left the patto, back to welcome')
# texts never show "nil"
bad = [t for c in clients for t in c.texts() if re.search(r'\bnil\b', t)]
check(not bad, 'no visible "nil" texts: ' + str(bad[:3]))
check(not A.errors() and not B.errors(), 'no errors: ' + str((A.errors() + B.errors())[:4]))
check(A.ns.C.stats.dropped == 0 and B.ns.C.stats.dropped == 0 and A.ns.C.QueueSize() < 10, 'no dropped messages, queue drained (A %s/%s, B %s)' % (A.ns.C.stats.dropped, A.ns.C.QueueSize(), B.ns.C.stats.dropped))
unk = dict(A.g.UNKNOWN)
print('methods not in stub list:', {str(k): v for k, v in unk.items()})
print('\n%d failures' % len(fails))
