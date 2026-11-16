# Er Patto: the guild as the patto's channel. Twelve friends on WoW Forever (no channel, each on his own island),
# records of a real size. One logs out for a while; the others level up meanwhile. He logs back in: how long
# before he sees everyone's level of now, without a guild (whispers) and with everyone in the same guild. Then a
# ding while all are online, and how many messages each costs.
src = open('test_comms.py').read()
exec(src[:src.index("A = Client('Dario Rossi'")])
random.seed(21)

def fails(ok, what): print(('OK   ' if ok else 'FAIL ') + what)

NAMES = ['Er Gnomo', 'Er Nia', 'Er Canaro', 'Er Mutanda', 'Er Matto', 'Er Schizo', 'Er Cortello', 'Er Barajin',
         'Er Burrasca', 'Er Krokodyle', 'Er Brillante', 'Er Piromane']
FILL = '''function(rec, i)
  rec.lv = 15; rec.xp = 1299; rec.xpm = 8800; rec.cls = "WARLOCK"; rec.race = "Scourge"; rec.zone = "Tirisfal Glades"
  rec.stats.t = { q = 42, nk = 3, rk = 3, g = 7645, dt = 28, pt = 26160, ding = 10, gp = 25020, tr = 62766, em = 8 }
  rec.stats.w = { [1] = { q = 42, nk = 3, rk = 3, g = 7645, dt = 28, pt = 24960, ding = 10, gp = 24960, tr = 59895, em = 8 } }
  rec.eq = "2/5.1433.0.7/6.3370.0.8/7.281283.2.11/8.1427.0.10/9.3641.1.8/10.3275.1.5/15.3833.1.8/16.2138.0.7"
  rec.lq = { { at = 1793861899, t = "At War With The Scarlet Crusade", z = "Tirisfal Glades" }, { at = 1793861889, t = "Seeking Refuge", z = "Tirisfal Glades" } }
  rec.pr = { { m = 75, l = 3, n = "Herbalism" }, { m = 75, l = 44, n = "First Aid" } }
  rec.rip = {}
  for j = 1, 6 do rec.rip[j] = { at = 1793860000 + j, k = "mostro", z = "Tirisfal Glades", lv = 10 } end
  rec.team = (i % 2 == 0) and "t1" or "t2"; rec.tat = 1793836720
  rec.up = rec.up + 1
end'''

def play(cl, seconds, skip=None, every=5):
    for _ in range(max(1, int(seconds / every))):
        for c in cl:
            if c is skip or not c.online: continue
            if random.random() < 0.25 * every / 5:
                r = c.state.members[c.guid]
                c.ns.P.UpdateSelf(c.state, c.guid, c.lua.table_from({'xp': (r.xp or 0) + random.randint(50, 200)}), 'xp')
                c.ns.C.MarkSelfDirty(60)
        secs(every)

DEATH = [None]
def run(guild, outside=None):
    global clients
    clients.clear()
    T[0] = START + 86400
    cl = []
    for i, n in enumerate(NAMES):
        c = Client(n, 'G-%02d' % i); c.g.NOWV = T[0]; c.g.REFUSE_CHANNEL = True
        if guild and i != outside: c.g.GUILDNAME = 'Alien Racers'
        clients[n] = c; cl.append(c)
    capo = cl[0]
    opts = capo.lua.eval('''function(start) return { name = "Alien Racers", start = start, h20 = 25, h60 = 190, guid = "G-00", playerName = "Er Gnomo",
      teams = { { name = "Er Gnomi", hours = 12 }, { name = "Li Morti", hours = 12 } }, teamIndex = 1 } end''')(START)
    capo.state = capo.ns.P.Create(opts); code = capo.state.code
    capo.login(); capo.g.JOINED = 'isola-0'; secs(3)
    for i, c in enumerate(cl[1:], 1):
        c.state = c.ns.P.Join(code, c.guid, c.name); c.login(); c.g.JOINED = 'isola-%d' % i
        c.ns.C.AddSeed('Er Gnomo'); secs(2)
    for i, c in enumerate(cl):
        c.lua.eval(FILL)(c.state.members[c.guid], i); c.ns.C.MarkSelfDirty(1)
    secs(300)
    known = min(len(list(c.state.members.keys())) for c in cl)
    # Er Mutanda goes away; meanwhile everyone else dings twice
    away = cl[3]
    away.logout()
    secs(60)
    for c in cl:
        if c is away: continue
        r = c.state.members[c.guid]
        c.ns.P.UpdateSelf(c.state, c.guid, c.lua.table_from({'lv': r.lv + 2, 'xp': 0}), 'level'); c.ns.C.MarkSelfDirty(0.3, True)
    play(cl, 240, away)
    want = {c.guid: c.state.members[c.guid].lv for c in cl if c is not away}
    sent0 = sum(c.ns.C.stats.sent for c in cl)
    away.login()
    t0 = T[0]; took = None
    while T[0] - t0 < 900:
        play(cl, 1, away, every=1)
        if all(away.state.members[g] is not None and away.state.members[g].lv == lv for g, lv in want.items()):
            took = T[0] - t0; break
    sent = sum(c.ns.C.stats.sent for c in cl) - sent0
    # a ding with everyone online: seconds before all eleven see it, and messages it cost
    secs(120)
    who = cl[5]
    lv = who.state.members[who.guid].lv + 1
    s0 = sum(c.ns.C.stats.sent for c in cl)
    who.ns.P.UpdateSelf(who.state, who.guid, who.lua.table_from({'lv': lv, 'xp': 0}), 'level'); who.ns.C.MarkSelfDirty(0.3, True)
    t1 = T[0]; ding = None
    while T[0] - t1 < 300:
        step(1)
        if all(c.state.members[who.guid].lv == lv for c in cl):
            ding = T[0] - t1; break
    secs(30)
    dingSent = sum(c.ns.C.stats.sent for c in cl) - s0
    # a death with everyone online: the stone (with its count) on every screen
    dead = cl[8]
    stone = dead.lua.eval('function(at, n) return { at = at, lv = 12, k = "mostro", by = "Lightning Hide", z = "Durotar", n = n, w = "tranquilli, ce l\'ho" } end')(int(T[0]), 99)
    dead.ns.P.UpdateSelf(dead.state, dead.guid, dead.lua.table_from({'lr': stone}), 'rip'); dead.ns.C.MarkSelfDirty(0.3, True)
    t2 = T[0]; DEATH[0] = None
    while T[0] - t2 < 300:
        step(1)
        if all(c.state.members[dead.guid].lr is not None and c.state.members[dead.guid].lr.n == 99 for c in cl): DEATH[0] = T[0] - t2; break
    errs_ = {c.name: errs(c) for c in cl if errs(c)}
    return known, took, sent, ding, dingSent, errs_, [str(c.ns.C.stats.mode) for c in cl[:3]]

k1, took1, sent1, ding1, dsent1, e1, m1 = run(False)
print('whispers: everyone knew %d; back after a while: all levels in %s s (%d messages); a ding seen by all in %s s (%d messages); %s' % (k1, took1, sent1, ding1, dsent1, m1))
k2, took2, sent2, ding2, dsent2, e2, m2 = run(True)
print('guild:    everyone knew %d; back after a while: all levels in %s s (%d messages); a ding seen by all in %s s (%d messages); %s' % (k2, took2, sent2, ding2, dsent2, m2))
fails(k2 == 12, 'with the guild everyone knows all twelve')
fails(took2 is not None and took2 <= 30, 'with the guild, back after a while: every level of now within 30 seconds (%s)' % took2)
fails(took1 is None or took2 < took1, 'faster than with whispers (%s against %s)' % (took2, took1))
fails(ding2 is not None and ding2 <= 5, 'a ding reaches all eleven within 5 seconds (%s)' % ding2)
fails(DEATH[0] is not None and DEATH[0] <= 5, 'a death (its stone, with how many in all) reaches all eleven within 5 seconds (%s)' % DEATH[0])
fails(dsent2 < dsent1, 'and costs fewer messages (%d against %d)' % (dsent2, dsent1))
fails(all(m == 'gilda' for m in m2), 'the mode says gilda: ' + str(m2))
# one of them not in the guild (yet): he still gets everything, by whisper
k3, took3, sent3, ding3, dsent3, e3, m3 = run(True, outside=7)
print('guild, Er Barajin outside: knew %d; back in %s s; ding in %s s (%d messages)' % (k3, took3, ding3, dsent3))
fails(k3 == 12 and took3 is not None and ding3 is not None and ding3 <= 5, 'one outside the guild still has and gets everything (%s, %s)' % (took3, ding3))

# ---- the record of one who's offline, from one who's online: Er Brillante says "ce sto" and logs off; Dario
# (away meanwhile) comes in with only three of the patto online: he gets it from them, quickly, and every other
# change the three have
def scenario(guild):
    clients.clear()
    T[0] = START + 86400
    cl = []
    for i, n in enumerate(NAMES):
        c = Client(n, 'G-%02d' % i); c.g.NOWV = T[0]; c.g.REFUSE_CHANNEL = True
        if guild: c.g.GUILDNAME = 'Alien Racers'
        clients[n] = c; cl.append(c)
    capo = cl[0]
    opts = capo.lua.eval('''function(start) return { name = "Alien Racers", start = start, h20 = 25, h60 = 190, guid = "G-00", playerName = "Er Gnomo",
      teams = { { name = "Er Gnomi", hours = 12 }, { name = "Li Morti", hours = 12 } }, teamIndex = 1 } end''')(START)
    capo.state = capo.ns.P.Create(opts); code = capo.state.code
    capo.login(); capo.g.JOINED = 'isola-0'; secs(3)
    for i, c in enumerate(cl[1:], 1):
        c.state = c.ns.P.Join(code, c.guid, c.name); c.login(); c.g.JOINED = 'isola-%d' % i
        c.ns.C.AddSeed('Er Gnomo'); secs(2)
    for i, c in enumerate(cl):
        c.lua.eval(FILL)(c.state.members[c.guid], i); c.ns.C.MarkSelfDirty(1)
    secs(300)
    dario = cl[0]
    dario.logout(); secs(60)
    # everyone else changes something while Dario is away (many records newer than his copies)
    for c in cl[1:]:
        c.ns.P.UpdateSelf(c.state, c.guid, c.lua.table_from({'zone': 'Barrens ' + c.name}), 'zone'); c.ns.C.MarkSelfDirty(0.3, True)
    secs(60)
    # Er Brillante says "ce sto" (a field), then everyone but Re Puma (cl[5]) logs off
    br = cl[10]
    br.ns.P.UpdateSelf(br.state, br.guid, br.lua.table_from({'ea': br.lua.table_from([br.lua.table_from({'i': 'X1', 'a': 1, 'at': T[0]})])}), 'lunario'); br.ns.C.MarkSelfDirty(0.3, True)
    secs(60)
    puma = cl[5]
    for c in cl[1:]:
        if c is not puma and c is not cl[6] and c is not cl[7]: c.logout()
    secs(30)
    s0 = sum(c.ns.C.stats.sent for c in cl)
    dario.login()
    t0 = T[0]; got = None; zones = None
    while T[0] - t0 < 900:
        secs(1)
        m = dario.state.members[br.guid]
        if m and m.ea is not None and got is None: got = T[0] - t0
        z = sum(1 for c in cl[1:] if dario.state.members[c.guid] and str(dario.state.members[c.guid].zone).startswith('Barrens'))
        if z == 11 and zones is None: zones = T[0] - t0
        if got is not None and zones is not None: break
    known = [c for c in cl[1:] if any(o.online and o is not dario and o.state.members[c.guid].up == c.state.members[c.guid].up for o in cl)]
    have = sum(1 for c in known if dario.state.members[c.guid].up == c.state.members[c.guid].up)
    LAST[:] = [cl, dario, br]
    return got, have, len(known), sum(c.ns.C.stats.sent for c in cl) - s0

LAST = []
gotG, haveG, knownG, msgG = scenario(True)
cl_, dario_, br_ = LAST
# ---- an older version had thrown away the caciare (fields it didn't know): Dario's copy of Er Brillante's record
# has the same date as everyone's but no "ce sto". With the new version, once, every record is asked again whole
dario_.logout()
dario_.state.members[br_.guid].ea = None
dario_.ns.P.MarkStale(dario_.state, dario_.guid)  # (what Main does at login when the version is new)
secs(5)
dario_.login()
t0 = T[0]; back = None
while T[0] - t0 < 300:
    secs(1)
    if dario_.state.members[br_.guid].ea is not None: back = T[0] - t0; break
fails(back is not None and back <= 60, 'after updating, what the old version threw away comes back (%s s)' % back)
def left_(): return len(list(dario_.state.stale.keys())) if dario_.state.stale else 0
while T[0] - t0 < 300 and left_() > 0: secs(1)
fails(left_() == 0, 'and all eleven records asked again come back whole (in %s s, %d left)' % (T[0] - t0, left_()))
gotW, haveW, knownW, msgW = scenario(False)
print('offline record: guild %s s (%d/%d, %d messages); whispers %s s (%d/%d, %d messages)' % (gotG, haveG, knownG, msgG, gotW, haveW, knownW, msgW))
fails(gotG is not None and gotG <= 60, 'through the guild, the "ce sto" of one offline arrives within a minute (%s s)' % gotG)
fails(gotW is not None and gotW <= 300, 'by whispers, within five minutes (%s s)' % gotW)
fails(haveG == knownG and haveW == knownW, 'and every change the ones online have (%d/%d, %d/%d)' % (haveG, knownG, haveW, knownW))
print('errori:', e1, e2, e3)
