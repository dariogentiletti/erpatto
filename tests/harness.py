# Shared test harness: loads the addon files into Lua 5.1 with a fake WoW API.
from lupa.lua51 import LuaRuntime
import os
ADDON = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def new_runtime(files, stub=True, ns=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    if stub: lua.execute(open(os.path.join(os.path.dirname(__file__), 'stub2.lua')).read())
    ns = ns or lua.table()
    load = lua.eval('function(s, name) local f, e = loadstring(s, name); if not f then error(e) end; return f end')
    for f in files:
        load(open(os.path.join(ADDON, f)).read(), f)("ErPatto", ns)
    return lua, ns
