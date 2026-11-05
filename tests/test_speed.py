# Er Patto: how fast the news travels on WoW Forever (no channel, every message whispered, 7 friends each on their
# own island, nobody grouped), with records of a real size (about 2 KB each) and everyone playing (XP, quests, zones)
# for ten minutes. Then someone dings, someone dies: how many seconds before every other friend knows.
src = open('test_comms.py').read()
exec(src[:src.index("A = Client('Dario Rossi'")])
random.seed(11)
import statistics

def fails(ok, what): print(('OK   ' if ok else 'FAIL ') + what)

NAMES = ['Er Gnomo', 'Er Nia', 'Er Canaro', 'Er Mutanda', 'Er Matto', 'Er Schizo', 'Er Cortello']
cl = []
for i, n in enumerate(NAMES):
    c = Client(n, 'G-%d' % i); c.g.NOWV = T[0]; c.g.REFUSE_CHANNEL = True
    clients[n] = c; cl.append(c)
capo = cl[0]
opts = capo.lua.eval('''function(start) return { name = "Alien Racers", start = start, h20 = 25, h60 = 190, guid = "G-0", playerName = "Er Gnomo",
  teams = { { name = "Er Gnomi", hours = 12 }, { name = "Li Morti", hours = 12 } }, teamIndex = 1 } end''')(START)
capo.state = capo.ns.P.Create(opts); code = capo.state.code
capo.login(); secs(3)
for i, c in enumerate(cl[1:], 1):
    c.state = c.ns.P.Join(code, c.guid, c.name); c.login(); c.g.JOINED = 'isola-%d' % i
    c.ns.C.AddSeed('Er Gnomo'); secs(2)
capo.g.JOINED = 'isola-0'

# a record of a real size: what two hours of play leave in it
FILL = '''function(rec, i)
  rec.lv = 11; rec.xp = 1299; rec.xpm = 8800; rec.cls = "WARLOCK"; rec.race = "Scourge"; rec.zone = "Tirisfal Glades"
  rec.stats.t = { q = 42, nk = 3, rk = 3, g = 7645, dt = 28, pt = 26160, ding = 10, gp = 25020, tr = 62766, em = 8 }
  rec.stats.w = { [1] = { q = 42, nk = 3, rk = 3, g = 7645, dt = 28, pt = 24960, ding = 10, gp = 24960, tr = 59895, em = 8 } }
  rec.eq = "2/5.1433.0.7/6.3370.0.8/7.281283.2.11/8.1427.0.10/9.3641.1.8/10.3275.1.5/15.3833.1.8/16.2138.0.7"
  rec.lq = { { at = 1793861899, t = "At War With The Scarlet Crusade", z = "Tirisfal Glades" }, { at = 1793861889, t = "Seeking Refuge", z = "Tirisfal Glades" }, { at = 1793857622, t = "The Argent Emissary", z = "Tirisfal Glades" } }
  rec.rl = { { at = 1793859477, z = "Tirisfal Glades", n = "Bayne" }, { at = 1793856655, z = "Tirisfal Glades", n = "Tormented Spirit" }, { at = 1793851051, z = "Tirisfal Glades", n = "Tormented Spirit" } }
  rec.nkl = { { c = 2, n = "Tormented Spirit" }, { c = 1, n = "Bayne" } }
  rec.pr = { { m = 75, l = 3, n = "Herbalism" }, { m = 75, l = 44, n = "First Aid" }, { m = 75, l = 1, n = "Cooking" } }
  rec.zq = { ["Tirisfal Glades"] = 42 }; rec.zqw = { ["Tirisfal Glades"] = 42 }
  rec.ed = { at = 1793853909, k = "cascato", z = "Tirisfal Glades" }
  rec.rip = {}
  for j = 1, 10 do rec.rip[j] = { at = 1793860000 + j, k = "mostro", z = "Tirisfal Glades", lv = 10 } end
  rec.team = (i % 2 == 0) and "t1" or "t2"; rec.tat = 1793836720
  rec.up = rec.up + 1
end'''
for i, c in enumerate(cl):
    c.lua.eval(FILL)(c.state.members[c.guid], i)
    c.ns.C.MarkSelfDirty(1)
secs(120)
size = len(cl[1].ns.U.Serialize(cl[1].state.members[cl[1].guid]))
known = min(len(list(c.state.members.keys())) for c in cl)
print('record of %d bytes; after two minutes the one who knows least knows %d of 7' % (size, known))

# ten minutes of play: XP every 20 s, a quest every two minutes, a zone now and then
def play(seconds):
    for _ in range(int(seconds / 5)):
        for c in cl:
            if random.random() < 0.25:
                r = c.state.members[c.guid]
                c.ns.P.UpdateSelf(c.state, c.guid, c.lua.table_from({'xp': (r.xp or 0) + random.randint(50, 200)}), 'xp')
                c.ns.C.MarkSelfDirty(60)
            if random.random() < 0.04:
                r = c.state.members[c.guid]
                r.stats.t.q = (r.stats.t.q or 0) + 1; r.up = r.up + 1
                c.ns.C.MarkSelfDirty(4)
        secs(5)
play(600)

def lag(who, field, value, kind):
    """seconds before every other friend sees `field` at `value` on `who`"""
    t0 = T[0]; seen = {}
    while T[0] - t0 < 600 and len(seen) < len(cl) - 1:
        step(1)
        for c in cl:
            if c is who or c.name in seen: continue
            r = c.state.members[who.guid]
            v = r and (r.lv if field == 'lv' else r.stats.t[field])
            if field == 'dt' and v is not None and (r.lr is None or str(r.lr.by) != 'Lightning Hide'): v = None
            if v is not None and v >= value: seen[c.name] = T[0] - t0
        # the others keep playing meanwhile
        if int((T[0] - t0) * 4) % 20 == 0:
            for c in cl:
                if c is not who and random.random() < 0.2:
                    r = c.state.members[c.guid]
                    c.ns.P.UpdateSelf(c.state, c.guid, c.lua.table_from({'xp': (r.xp or 0) + 77}), 'xp'); c.ns.C.MarkSelfDirty(60)
    times = sorted(seen.values())
    worst = times[-1] if len(times) == len(cl) - 1 else None
    print('%s: everyone in %s s (first %.1f s, median %.1f s); queue of the one it happened to: %d' % (kind,
          ('%.1f' % worst) if worst is not None else 'MAI (dopo 600)', times[0] if times else -1,
          statistics.median(times) if times else -1, len(list(who.ns.C.Queue().values())) if hasattr(who.ns.C, 'Queue') and who.ns.C.Queue else -1))
    return worst

who = cl[3]
lv = who.state.members[who.guid].lv + 1
who.ns.P.UpdateSelf(who.state, who.guid, who.lua.table_from({'lv': lv, 'xp': 0}), 'level'); who.ns.C.MarkSelfDirty(0.3, True)
w1 = lag(who, 'lv', lv, 'ding')
play(60)
who = cl[5]
dt = (who.state.members[who.guid].stats.t.dt or 0) + 1
who.state.members[who.guid].stats.t.dt = dt; who.state.members[who.guid].up = who.state.members[who.guid].up + 1
# the gravestone with its last words: the flash goes in two messages then
who.state.members[who.guid].lr = who.lua.eval('function(at) return { at = at, lv = 12, k = "mostro", by = "Lightning Hide", z = "Durotar", w = "mo me sarvo, tranquilli, ce l\'ho sotto controllo sto lucertolone" } end')(int(T[0]))
who.ns.C.MarkSelfDirty(0.3, True)
w2 = lag(who, 'dt', dt, 'death')
# someone new comes in with the code while everyone plays: how long before he has the patto, and they have him
nu = Client('Er Novo', 'G-NEW'); nu.g.NOWV = T[0]; nu.g.REFUSE_CHANNEL = True; clients['Er Novo'] = nu
nu.state = nu.ns.P.Join(code, 'G-NEW', 'Er Novo'); nu.login(); nu.g.JOINED = 'isola-nova'; nu.ns.C.AddSeed('Er Gnomo')
t0 = T[0]; tin = tall = tthem = None
while T[0] - t0 < 600 and (tin is None or tall is None or tthem is None):
    step(1)
    if tin is None and nu.ns.P.HasSettings(nu.state): tin = T[0] - t0
    if tall is None and len(list(nu.state.members.keys())) >= 8: tall = T[0] - t0
    if tthem is None and all(c.state.members['G-NEW'] is not None for c in cl): tthem = T[0] - t0
print('a new one: the patto in %s s, all 7 friends in %s s, all of them see him in %s s' % (tin, tall, tthem))
print('sent per client in all:', {c.name: c.ns.C.stats.sent for c in cl})
print('stale deltas:', {c.name: c.ns.C.stats.stale or 0 for c in cl})
fails(w1 is not None and w1 <= 5, 'a ding reaches all six friends within 5 seconds (%s)' % w1)
fails(w2 is not None and w2 <= 5, 'a death reaches all six friends within 5 seconds (%s)' % w2)
fails(tin is not None and tin <= 10, 'a new one with the code has the patto within 10 seconds (%s)' % tin)
fails(tthem is not None and tthem <= 30, 'and every friend sees him within 30 seconds (%s)' % tthem)
fails(tall is not None and tall <= 90, 'and he sees all seven within a minute and a half (%s)' % tall)
print('errori:', {c.name: errs(c) for c in cl if errs(c)})
