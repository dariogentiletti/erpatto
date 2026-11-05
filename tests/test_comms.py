from lupa.lua51 import LuaRuntime
import os, random
random.seed(1)
ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = ['Util.lua', 'Model.lua', 'Patto.lua', 'Comms.lua']
START = 1793833200
class Client:
    def __init__(self, name, guid):
        self.name, self.guid, self.online = name, guid, False
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(open('stub3.lua').read())
        self.lua.execute('math.randomseed(%d)' % random.randint(1, 10**6))
        self.ns = self.lua.table()
        load = self.lua.eval('function(s, n) local f, e = loadstring(s, n); if not f then error(e) end; return f end')
        for f in FILES: load(open(os.path.join(ADDON, f)).read(), f)("ErPatto", self.ns)
        self.g = self.lua.globals()
        self.state = None
    def login(self):
        self.online = True
        self.ns.C.Start(self.state, self.guid, self.name)
    def logout(self):
        self.online = False
        self.ns.C.Stop()
clients = {}
T = [START - 86400]
LOSS = [0]
def step(n=1, dt=0.25):
    for _ in range(n):
        T[0] += dt
        for c in clients.values():
            # the list of the channel comes late on a busy server: nothing until ROSTER_LATE, then the event
            late = c.g.ROSTER_LATE
            if late and T[0] < late:
                c.g.ROSTER = c.lua.table_from([])
            else:
                c.g.ROSTER = c.lua.table_from([c.lua.table_from({'name': d.name, 'guid': d.guid}) for d in clients.values()
                    if d.online and d.g.JOINED and d.g.JOINED == c.g.JOINED])
                if late and c.online:
                    c.g.ROSTER_LATE = None
                    c.ns.C.OnRosterUpdate(1)
            c.g.NOWV = T[0]
            if c.online: c.g.RUN_TIMERS()
        for c in clients.values():
            if not c.online:
                c.g.TAKE_OUTBOX(); continue
            out = list(c.g.TAKE_OUTBOX().values())
            if c.g.REFUSE_CHANNEL and any(m.kind == 'CHANNEL' for m in out):
                c.ns.C.OnChannelNotice('NOT_ALLOWED_IN_CHANNEL', '', '', '7. ' + str(c.g.JOINED), '', '', 0, 7, c.g.JOINED)
            for m in out:
                for d in clients.values():
                    if d is c or not d.online: continue
                    if m.kind == 'CHANNEL' and c.g.REFUSE_CHANNEL:
                        continue
                    if m.kind == 'CHANNEL' and d.g.JOINED and d.g.JOINED == c.g.JOINED:
                        d.ns.C.OnAddonMessage(m.prefix, m.text, 'CHANNEL', c.name, '', 0, 7, d.g.JOINED)
                    elif m.kind in ('PARTY', 'RAID') and c.g.GROUP and d.g.GROUP == c.g.GROUP:
                        d.ns.C.OnAddonMessage(m.prefix, m.text, m.kind, c.name, '', 0, 0, '')
                    elif m.kind == 'BN' and m.target == d.g.BNID:
                        d.ns.C.OnBNAddon(m.prefix, m.text, 'WHISPER', c.g.BNID or 0)
                    elif m.kind == 'WHISPER' and m.target == d.name and d.g.NO_WHISPERS:
                        continue
                    elif m.kind == 'WHISPER' and m.target == d.name:
                        # a full server loses some whispers
                        if LOSS[0] and random.random() < LOSS[0]: continue
                        d.ns.C.OnAddonMessage(m.prefix, m.text, 'WHISPER', c.name, d.name)
def secs(s): step(int(s / 0.25))
def summary(c):
    st = c.state
    mem = sorted([(r.name, r.team, r.lv) for r in st.members.values()])
    return 'sv=%s av=%s members=%s' % (st.settings.v, st.admins.v, mem)
def errs(c): return list(c.g.ERRORS.values())

A = Client('Dario Rossi', 'G-DARIO'); B = Client('Pietro Cesaroni', 'G-PIETRO'); Cc = Client('Jake Neri', 'G-JAKE'); D = Client('Petra Blu', 'G-PETRA')
clients.update({'A': A, 'B': B, 'C': Cc, 'D': D})
for c in clients.values(): c.g.NOWV = T[0]
opts = A.lua.eval('''function(start) return { name = "Er Patto", start = start, h20 = 25, h60 = 190, guid = "G-DARIO", playerName = "Dario Rossi",
  teams = { { name = "I Cesaroni", hours = 12 }, { name = "Carabinieri 8", hours = 30 } }, teamIndex = 2 } end''')(START)
A.state = A.ns.P.Create(opts)
code = A.state.code
print('1) Dario crea il patto', code)
A.login(); secs(5)
B.state = B.ns.P.Join(code, 'G-PIETRO', 'Pietro Cesaroni'); B.login(); secs(15)
print('2) Pietro entra:', summary(B))
B.ns.P.ChooseTeam(B.state, 'G-PIETRO', 't1'); B.ns.C.MarkSelfDirty(); secs(10)
print('   Pietro sceglie I Cesaroni, Dario vede:', summary(A))
A.logout()
Cc.state = Cc.ns.P.Join(code, 'G-JAKE', 'Jake Neri'); Cc.login(); secs(15)
print('3) Jake entra mentre Dario e offline (passaparola da Pietro):', summary(Cc))
Cc.ns.P.ChooseTeam(Cc.state, 'G-JAKE', 't1'); Cc.ns.C.MarkSelfDirty(); secs(8)
Cc.logout(); secs(5)
A.login(); secs(15)
print('4) Dario torna e vede Jake grazie a Pietro:', summary(A))
ok = A.ns.P.SetPace(A.state, 'G-DARIO', 't1', 10); A.ns.C.Send('S', A.state.settings); secs(6)
print('   Dario cambia il ritmo (v%s); Pietro ha v%s' % (A.state.settings.v, B.state.settings.v))
A.logout(); B.logout(); secs(5)
Cc.login(); A.login(); secs(20)
print('   Jake rientra con Dario: settings v%s, ore Cesaroni %s' % (Cc.state.settings.v, Cc.state.settings.teams[1].pace[1].hours))
# lockdown
B.login(); secs(15)
B.g.INSTANCE = True
B.ns.P.UpdateSelf(B.state, 'G-PIETRO', B.lua.table_from({'lv': 9})); B.ns.C.MarkSelfDirty(); secs(10)
print('5) Pietro in dungeon fa ding al 9: Dario vede lv', A.state.members['G-PIETRO'].lv, '| coda trattenuta:', B.ns.C.stats.held)
B.g.INSTANCE = False; B.ns.C.OnZoneChanged(); secs(10)
print('   Pietro esce: Dario vede lv', A.state.members['G-PIETRO'].lv)
# fallback: Petra's channel join fails
D.g.CHANNEL_OK = False
D.state = D.ns.P.Join(code, 'G-PETRA', 'Petra Blu')
# Petra knows nobody yet: seed one known member like a friend would after a first sync via whisper
D.state.members['G-PIETRO'] = D.ns.U.Deserialize(B.ns.U.Serialize(B.state.members['G-PIETRO']))
D.login(); secs(20)
print('6) Petra senza canale (solo sussurri):', D.ns.C.stats.mode, summary(D))
# chunking: big record
for i in range(25):
    B.state.members['G-PIETRO'].h2h['Avversario Numero %d' % i] = B.lua.eval('function(w,l) return {w=w,l=l} end')(i, 1)
B.ns.P.UpdateSelf(B.state, 'G-PIETRO', B.lua.table_from({'lv': 10})); B.ns.C.MarkSelfDirty(); secs(15)
rec = A.state.members['G-PIETRO']
print('7) record grande (%d byte) arriva a pezzi: Dario vede lv %s, duelli registrati %d' % (len(B.ns.U.Serialize(B.state.members['G-PIETRO'])), rec.lv, len(list(rec.h2h.keys()))))
print('8) messaggi al secondo (max per client, limite 10):', {k: c.g.MAX_PER_SECOND() for k, c in clients.items()})
print('   online visti da Dario:', {n: A.ns.C.IsOnline(g) for n, g in [('Pietro','G-PIETRO'),('Jake','G-JAKE'),('Petra','G-PETRA')]})
print('   statistiche Dario:', dict(A.ns.C.stats))
print('errori:', {k: errs(c) for k, c in clients.items()})

# 9) WoW Forever: the channel refuses addon messages; whoever is in it is found on its member list, and whispered
def fails(ok, what): print(('OK   ' if ok else 'FAIL ') + what)
for c in clients.values():
    if c.online: c.logout()
secs(5)
E = Client('Er Gnomo', 'G-GNOMO'); F = Client('Er Nia', 'G-NIA'); G = Client('Er Martellone', 'G-MART')
clients.update({'E': E, 'F': F, 'G': G})
for c in (E, F, G): c.g.NOWV = T[0]; c.g.REFUSE_CHANNEL = True
opts2 = E.lua.eval('''function(start) return { name = "Alien Racers", start = start, h20 = 25, h60 = 190, guid = "G-GNOMO", playerName = "Er Gnomo",
  teams = { { name = "I Cesaroni", hours = 12 } }, teamIndex = 1 } end''')(START)
E.state = E.ns.P.Create(opts2); code2 = E.state.code
E.login(); secs(5)
F.state = F.ns.P.Join(code2, 'G-NIA', 'Er Nia'); F.login(); secs(20)
fails(F.ns.P.HasSettings(F.state) and 'G-NIA' in [str(k) for k in E.state.members.keys()],
      'Forever: Er Nia joins with the code alone and both see each other (%s / %s)' % (summary(F), summary(E)))
fails('sussurri' in str(F.ns.C.stats.mode) and not any(m == 'CHANNEL' for m in []), 'Forever: whispers to who is in the channel: ' + str(F.ns.C.stats.mode))
G.state = G.ns.P.Join(code2, 'G-MART', 'Er Martellone'); G.login(); secs(25)
fails(len(list(G.state.members.keys())) == 3 and len(list(E.state.members.keys())) == 3 and len(list(F.state.members.keys())) == 3,
      'Forever: a third one joins, all three see all three')
# a change in a record goes as the change only, and lands
sizes = []
orig = F.ns.C.SendSelf
F.ns.P.UpdateSelf(F.state, 'G-NIA', F.lua.table_from({'lv': 4, 'zone': 'Mulgore'})); F.ns.C.MarkSelfDirty(0.1); secs(1)
sent = [m for m in []]
secs(10)
fails(E.state.members['G-NIA'].lv == 4 and G.state.members['G-NIA'].zone == 'Mulgore' and (E.ns.C.stats.deltas or 0) >= 1, 'Forever: a ding arrives to both as a change of the record (changes applied: %s)' % E.ns.C.stats.deltas)
fails(F.ns.U.Short('Er Nia-Realm') == 'Er Nia' and F.ns.U.Short('Dario (prova)') == 'Dario', 'names: realm and test mark go, the surname stays')
F.ns.state = F.state
fails(str(F.ns.U.Surnames('|cffc69b6dEr Nia|r 40')) == '|cffc69b6dNia|r 40', 'names: a narrow column keeps the surname, not the first name')
print('errori Forever:', {k: errs(c) for k, c in (('E', E), ('F', F), ('G', G))})

# 10) a busy server: the joiner's channel list comes 40 seconds late; the capo still sees him within seconds of it
H = Client('Er Schizo', 'G-SCHIZO'); clients['H'] = H; H.g.NOWV = T[0]; H.g.REFUSE_CHANNEL = True
H.state = H.ns.P.Join(code2, 'G-SCHIZO', 'Er Schizo')
H.g.ROSTER_LATE = T[0] + 40
H.login(); secs(10)
# he picks his squadra before the list comes (the window asks at once)... and then does nothing more
H.ns.P.ChooseTeam(H.state, 'G-SCHIZO', 't1'); H.ns.C.MarkSelfDirty(0.3, True); secs(20)
secs(10 + 15)
fails(E.state.members['G-SCHIZO'] is not None and E.state.members['G-SCHIZO'].team == 't1' and H.ns.P.HasSettings(H.state),
      'busy server: once the list comes, Er Schizo and his squadra are seen by the capo within seconds')
# 11) a quarter of the whispers lost: a ding still reaches everyone, at worst with the next round of hellos
LOSS[0] = 0.25
for i in range(3):
    H.ns.P.UpdateSelf(H.state, 'G-SCHIZO', H.lua.table_from({'lv': 2 + i})); H.ns.C.MarkSelfDirty(0.1); secs(20)
secs(60)
LOSS[0] = 0
secs(130)
got = {k: (c.state.members['G-SCHIZO'].lv if c.state.members['G-SCHIZO'] else None) for k, c in (('E', E), ('F', F), ('G', G))}
fails(all(v == 4 for v in got.values()), 'lost whispers: everyone ends with Er Schizo at level 4: ' + str(got))
print('   cambi usati', {k: c.ns.C.stats.deltas for k, c in (('E', E), ('F', F), ('G', G))}, 'cambi vecchi', {k: c.ns.C.stats.stale for k, c in (('E', E), ('F', F), ('G', G))})
print('errori 10-11:', {k: errs(c) for k, c in (('E', E), ('F', F), ('G', G), ('H', H))})

# 12) islands: on Forever each internal realm has its own copy of the channel. Er Lontano is on another one: the
# channel never lists him, yet with the code and one name (who invited him) he and the others find each other
I = Client('Er Lontano', 'G-LONT'); clients['I'] = I; I.g.NOWV = T[0]; I.g.REFUSE_CHANNEL = True
I.state = I.ns.P.Join(code2, 'G-LONT', 'Er Lontano')
I.login()
I.g.JOINED = 'altra-copia'  # his channel is another island's
I.ns.C.AddSeed('Er Gnomo')
secs(30)
fails(I.ns.P.HasSettings(I.state) and 'G-LONT' in [str(k) for k in E.state.members.keys()], 'islands: Er Lontano, on another internal realm, joins with the code and Er Gnomo\'s name')
secs(130)
fails(all('G-LONT' in [str(k) for k in c.state.members.keys()] for c in (F, G, H)) and len(list(I.state.members.keys())) >= 5,
      'islands: within a round of hellos everyone sees Er Lontano, and he sees everyone')

# 13) Er Nia loses her WTF folder (or plays on a new PC) and comes back with the code: her record comes back from
# the friends, and her empty one never overwrites theirs
fails(not F.state.members['G-NIA'].fresh and not E.state.members['G-NIA'].fresh, 'after a minute with friends a record is no longer "new on this PC"')
F.state.members['G-NIA'].pts = F.lua.table_from({'t': 57, 'w': 1})
F.ns.P.UpdateSelf(F.state, 'G-NIA', F.lua.table_from({'team': 't1', 'tat': T[0]})); F.ns.C.MarkSelfDirty(0.1); secs(20)
fails(E.state.members['G-NIA'].pts is not None and E.state.members['G-NIA'].pts.t == 57, 'the friends hold Er Nia\'s piotte (57)')
F.logout(); secs(5)
F.state = F.ns.P.Join(code2, 'G-NIA', 'Er Nia')  # everything gone: a new record from nothing
F.ns.P.UpdateSelf(F.state, 'G-NIA', F.lua.table_from({'lv': 5}))
F.login(); secs(40)
mine = F.state.members['G-NIA']
fails(mine.pts is not None and mine.pts.t == 57 and mine.team == 't1' and mine.lv == 5 and not mine.fresh,
      'lost WTF: her record came back from the friends (57 piotte, her squadra), with her level of now (5): %s %s %s' % (mine.pts and mine.pts.t, mine.team, mine.lv))
fails(all(c.state.members['G-NIA'].pts is not None and c.state.members['G-NIA'].pts.t == 57 for c in (E, G)), 'and nobody\'s copy was wiped by the empty one')
print('errori 13:', {k: errs(c) for k, c in (('E', E), ('F', F), ('G', G))})

fails(str(E.ns.P.ParseInvite('98lx8 Er Gnomo')[0]) == '98LX8' and str(E.ns.P.ParseInvite('98lx8 Er Gnomo')[1]) == 'Er Gnomo'
      and E.ns.P.ParseInvite('K7Q 2M')[0] == 'K7Q2M' and E.ns.P.ParseInvite('98LX8')[1] is None, 'the code with the name inside: read right; old codes still work')

# 14) the code alone, as a password: Er Solo is on another internal realm (the channel never sees him), knows no
# name, but he's a Battle.net friend of Er Martellone. He writes the 5 letters and he's in.
J = Client('Er Solo', 'G-SOLO'); clients['J'] = J; J.g.NOWV = T[0]; J.g.REFUSE_CHANNEL = True
# and no whisper reaches him (as Er Cortello in the game): only Battle.net, both ways
J.g.NO_WHISPERS = True; J.g.BNID = 777
G.g.BNID = 4242
J.g.BNFRIENDS = J.lua.table_from([J.lua.table_from({'id': 4242})])
J.state = J.ns.P.Join(code2, 'G-SOLO', 'Er Solo')
J.login()
J.g.JOINED = 'isola-lontana'
secs(30)
fails(J.ns.P.HasSettings(J.state) and 'G-SOLO' in [str(k) for k in G.state.members.keys()],
      'code alone: found through a Battle.net friend, data in, and the friend sees him (%s)' % summary(J))
secs(130)
fails(all('G-SOLO' in [str(k) for k in c.state.members.keys()] for c in (E, F, H)), 'code alone: within a round everyone in the patto sees him')
print('errori 14:', {k: errs(c) for k, c in (('G', G), ('J', J))})

# 15) Er Cortello's case: no whisper reaches him, no Battle.net, but he's in a group with the capo. The group
# carries the search and everything after it; an empty patto elsewhere in the group doesn't mix in
K = Client('Er Cortello', 'G-CORT'); clients['K'] = K; K.g.NOWV = T[0]; K.g.REFUSE_CHANNEL = True; K.g.NO_WHISPERS = True
K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello')
K.login()
K.g.JOINED = 'isola-cortello'
K.g.GROUP = 'g1'; E.g.GROUP = 'g1'
K.g.GROUPMATES = K.lua.table_from(['Er Gnomo']); E.g.GROUPMATES = E.lua.table_from(['Er Cortello'])
secs(30)
fails(K.ns.P.HasSettings(K.state) and 'G-CORT' in [str(k) for k in E.state.members.keys()], 'in a group, no whispers: in through the group (%s)' % summary(K))
K.ns.P.ChooseTeam(K.state, 'G-CORT', 't1'); K.ns.C.MarkSelfDirty(0.3, True); secs(4)
fails(E.state.members['G-CORT'].team == 't1', 'and his squadra reaches the capo in seconds, through the group')
print('errori 15:', {k: errs(c) for k, c in (('E', E), ('K', K))})

# 16) leaving: Er Cortello leaves; the capo (in his group) drops him at once, the others with the next hello,
# and no old copy brings him back. Then he comes back with the code: in again
K.ns.C.SayGoodbye(); step(1); K.logout(); secs(5)  # what ns.LeavePatto does (Main.lua is not in this harness)
fails('G-CORT' not in [str(k) for k in E.state.members.keys()], 'left: the capo drops him at once')
secs(300)
still = [k for k, c in (('E', E), ('F', F), ('G', G), ('H', H), ('J', J)) if 'G-CORT' in [str(x) for x in c.state.members.keys()]]
fails(not still, 'left: within a round nobody has him, and nobody brings him back (%s)' % still)
K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); secs(40)
fails(K.ns.P.HasSettings(K.state) and 'G-CORT' in [str(k) for k in E.state.members.keys()], 'and with the code he\'s back in')
print('errori 16:', {k: errs(c) for k, c in (('E', E), ('K', K))})

# 17) tonight's case: the capo cacciò Er Cortello (Caccia), then invited him again from the menu. He accepts:
# his messages count again (the ban goes), and he's in. Whispers work for him now, and no group
K.g.NO_WHISPERS = False; K.g.GROUP = None; E.g.GROUP = None
K.g.GROUPMATES = K.lua.table_from([]); E.g.GROUPMATES = E.lua.table_from([])
ok = E.ns.P.Ban(E.state, 'G-GNOMO', 'G-CORT'); E.ns.C.Send('B', E.state.bans); secs(10)
fails(ok and E.ns.P.IsBanned(E.state, 'G-CORT') and 'G-CORT' not in [str(k) for k in E.state.members.keys()], 'cacciato: out')
K.ns.C.Stop(); K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); secs(40)
fails('G-CORT' not in [str(k) for k in E.state.members.keys()], 'cacciato: the code alone doesn\'t bring him back')
E.ns.C.Invite('Er Cortello'); secs(2)
K.ns.C.Stop(); K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); K.ns.C.AddSeed('Er Gnomo'); secs(40)
fails(not E.ns.P.IsBanned(E.state, 'G-CORT') and 'G-CORT' in [str(k) for k in E.state.members.keys()] and K.ns.P.HasSettings(K.state),
      'invited again by the capo: the ban goes and he\'s in (%s)' % summary(K))
secs(300)
fails(all(not c.ns.P.IsBanned(c.state, 'G-CORT') and 'G-CORT' in [str(x) for x in c.state.members.keys()] for c in (F, G, H)),
      'and the others take him back too')
print('errori 17:', {k: errs(c) for k, c in (('E', E), ('K', K))})

# 18) Er Cortello's rari: what he did before is never lost. (a) cacciato and invited again: the capo and the others
# kept his record aside, and give it back
def setstat(c, guid, **kw):
    rec = c.state.members[guid]
    for k, v in kw.items(): rec.stats.t[k] = v
    rec.up = rec.up + 5
    c.ns.C.Send('M', rec)
setstat(K, 'G-CORT', rk=1, q=12, nk=1); secs(20)
fails(E.state.members['G-CORT'].stats.t.rk == 1, 'his rare reaches the capo')
E.ns.P.Ban(E.state, 'G-GNOMO', 'G-CORT'); E.ns.C.Send('B', E.state.bans); secs(10)
K.ns.C.Stop(); K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); secs(20)
E.ns.C.Invite('Er Cortello'); secs(2)
K.ns.C.Stop(); K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); K.ns.C.AddSeed('Er Gnomo'); secs(60)
mine = K.state.members['G-CORT']
fails(mine.stats.t.rk == 1 and mine.stats.t.q == 12, 'cacciato and invited again: his rare and his quests are his again (%s %s)' % (mine.stats.t.rk, mine.stats.t.q))
secs(300)
fails(all(c.state.members['G-CORT'] and c.state.members['G-CORT'].stats.t.rk == 1 for c in (E, F, G)), 'and everyone sees them')

# (b) tonight, with the old versions: everyone online lost his record, he started again from zero (not new any
# more), and only Er Mutanda, offline then, still has the old one. When she comes in, it goes back to him
H.logout()  # she goes with his record as it was then: 1 raro, 12 quest
setstat(K, 'G-CORT', rk=2, q=20, nk=2); secs(20)
for c in [c for c in clients.values() if c not in (H, K) and c.state is not None]:
    c.state.members['G-CORT'] = None
    if c.state.prev is not None: c.state.prev['G-CORT'] = None
K.ns.C.Stop(); K.state = K.ns.P.Join(code2, 'G-CORT', 'Er Cortello'); K.login(); secs(400)
mine = K.state.members['G-CORT']
fails(not mine.fresh and (mine.stats.t.rk or 0) == 0, 'the old record is gone everywhere online: he is at zero rari')
K.ns.T.Bump('q', 3) if K.ns.T and K.ns.T.Ready() else setstat(K, 'G-CORT', q=3); secs(10)
H.login(); secs(400)
mine = K.state.members['G-CORT']
fails(mine.stats.t.rk == 1 and mine.stats.t.q == 12 and mine.stats.t.nk == 1,
      'Er Mutanda comes in with his old record: his rari, quests and famous kills are his again (%s %s %s)' % (mine.stats.t.rk, mine.stats.t.q, mine.stats.t.nk))
secs(300)
fails(all(c.state.members['G-CORT'] is not None and c.state.members['G-CORT'].stats.t.rk == 1 for c in (E, F, G, H)), 'and the whole patto sees them')
fails(H.state.prev is None or H.state.prev['G-CORT'] is None, 'and the old copy, given back, is dropped')
print('errori 18:', {k: errs(c) for k, c in (('E', E), ('H', H), ('K', K))})
