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
fails(dsent2 < dsent1, 'and costs fewer messages (%d against %d)' % (dsent2, dsent1))
fails(all(m == 'gilda' for m in m2), 'the mode says gilda: ' + str(m2))
# one of them not in the guild (yet): he still gets everything, by whisper
k3, took3, sent3, ding3, dsent3, e3, m3 = run(True, outside=7)
print('guild, Er Barajin outside: knew %d; back in %s s; ding in %s s (%d messages)' % (k3, took3, ding3, dsent3))
fails(k3 == 12 and took3 is not None and ding3 is not None and ding3 <= 5, 'one outside the guild still has and gets everything (%s, %s)' % (took3, ding3))
print('errori:', e1, e2, e3)
