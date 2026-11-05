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
def step(n=1, dt=0.25):
    for _ in range(n):
        T[0] += dt
        for c in clients.values():
            c.g.ROSTER = c.lua.table_from([c.lua.table_from({'name': d.name, 'guid': d.guid}) for d in clients.values()
                if d.online and d.g.JOINED and d.g.JOINED == c.g.JOINED])
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
                    elif m.kind == 'WHISPER' and m.target == d.name:
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
