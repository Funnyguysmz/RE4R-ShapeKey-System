-- RE4R ShapeKey System / 形态键系统 0.3.0 (Claude)
-- Drives the custom shape-key channels of a character mod's head mesh. The mod ships
-- reframework/data/RE4R_ShapeKeySystem_profile.json (key ids, hashes, labels, regions).
-- Channels are bound by engine name hash, never by index. Native Leon channels in the same mesh
-- (zero-delta "taps") are only read, never written.
local VERSION = '0.4.3'
local DIAG_FILE = 'RE4R_ShapeKeySystem_diag.json'
local PROFILE_FILE = 'RE4R_ShapeKeySystem_profile.json'
local SETTINGS_FILE = 'RE4R_ShapeKeySystem_settings.json'
local PRESET_FILE = 'RE4R_ShapeKeySystem_presets.json'
local NATIVE_FILE = 'RE4R_ShapeKeySystem_native_leon.json'     -- Leon facial rig -> ARKit conversion (k07)

local profile, keys, taps, key_by_id = nil, {}, {}, {}
local regions = {}
local S = {enabled = false, force_lod0 = true, auto_alloc = true, show_window = true, page = 1, strength = 1.0, region = {},
    values = {}, preset = '', library = 1, group = 1, filter = '', only_active = false,
    source = 3, native_gain = 1.0, cap_gain = 1.0, cap_smooth = 0.5}          -- source: 1 manual, 2 native animation, 3 native + manual offsets
local SOURCES = {'手动', '原生动画', '原生动画 + 手动微调', '面捕（RhyLive）+ 手动微调', '面捕，断流时回落原生动画'}
-- face capture: read-only snapshot from the RhyLive receiver DLL (global rhylive_native, started from the RhyLive panel)
local cap = {values = {}, active = false, seq = -1, gains = {}, gains_at = -1000, status = '未读取'}
local CAP_TIMEOUT_MS = 500
local native_map, nat = nil, {}           -- conversion table; per-frame native weights by key id
local presets = {}
local bind = nil
local status, last_error = '正在读取配置。', nil
local frame, bind_retry, perf_ms, writes_ok = 0, 0, 0, 0
local compare_neutral, dirty, settings_dirty_at = false, false, nil
local undo, redo, last_push = {}, {}, -1
local sweep = nil                     -- {i, t0, period}
local probe = {custom_max = 0, custom_name = nil, at = 0, taps = {}, idle_frames = 0}
local LIBS = {'全部', 'ARKit', 'MMD'}
local new_name = ''
local sweep_period = 1.2

------------------------------------------------------------------ helpers
local function finite(v) return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge end
local function call(o, name, ...)
    if not o then return nil end
    local args = {...}
    local ok, v = pcall(function() return o:call(name, table.unpack(args)) end)
    if ok then return v end
    return nil
end
local function addr(o)
    if not o then return nil end
    local ok, v = pcall(function() return o:get_address() end)
    return ok and v or nil
end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == 'table' and copy(v) or v end return o end
local function try(fn, ...) local ok, a, b, c = pcall(fn, ...) if ok then return true, a, b, c end return false end

------------------------------------------------------------------ profile / settings
local function load_profile()
    local ok, p = pcall(json.load_file, PROFILE_FILE)
    if not ok or type(p) ~= 'table' or type(p.keys) ~= 'table' then
        status = '未找到形态键配置 ' .. PROFILE_FILE .. '（请启用带形态键的角色 MOD）。'; return false
    end
    profile, keys, taps, key_by_id = p, {}, {}, {}
    for i, k in ipairs(p.keys) do
        local e = {id = k.id, hash = k.hash, label = k.label, name = k.name, library = k.library, group = k.group,
            region = k.region, ch = nil, idx = i, arkit = k.arkit}     -- arkit: {{name, gain}, ...} retarget for non-ARKit keys
        keys[#keys + 1] = e; key_by_id[e.id] = e
    end
    for _, t in ipairs(p.native_taps or {}) do
        taps[#taps + 1] = {name = t.name, short = (t.name:gsub('^Face__geo__p000_cbs%.crct_', '')), hash = t.hash, ch = nil}
    end
    regions = p.regions or {}
    return true
end
local function save_settings()
    local data = {version = VERSION, enabled = S.enabled, auto_alloc = S.auto_alloc, force_lod0 = S.force_lod0, show_window = S.show_window,
        strength = S.strength, region = S.region, values = S.values, preset = S.preset, library = S.library,
        source = S.source, native_gain = S.native_gain, cap_gain = S.cap_gain, cap_smooth = S.cap_smooth}
    try(json.dump_file, SETTINGS_FILE, data)
end
local function load_settings()
    local ok, d = pcall(json.load_file, SETTINGS_FILE)
    if ok and type(d) == 'table' then
        for _, k in ipairs({'auto_alloc', 'force_lod0', 'show_window', 'preset', 'library', 'source', 'native_gain', 'cap_gain', 'cap_smooth'}) do
            if d[k] ~= nil then S[k] = d[k] end
        end
        if finite(d.strength) then S.strength = d.strength end
        if type(d.region) == 'table' then for k, v in pairs(d.region) do if finite(v) then S.region[k] = v end end end
        if type(d.values) == 'table' then for k, v in pairs(d.values) do if finite(v) then S.values[k] = v end end end
    end
    local okn, nm = pcall(json.load_file, NATIVE_FILE)
    if okn and type(nm) == 'table' and type(nm.rules) == 'table' and type(nm.joints) == 'table' then native_map = nm end
    local okp, p = pcall(json.load_file, PRESET_FILE)
    if okp and type(p) == 'table' then presets = p end
end
local function touch_settings() settings_dirty_at = os.clock() end
local function touch() dirty = true; touch_settings() end
local function save_presets() try(json.dump_file, PRESET_FILE, presets) end

------------------------------------------------------------------ binding (same resolution path as ShapeKey Lab, verified in game)
local function component(go, name)
    local ok, r = pcall(function() local ty = sdk.typeof(name); return ty and go:call('getComponent(System.Type)', ty) end)
    return ok and r or nil
end
local function head_candidates()
    local cm = sdk.get_managed_singleton('chainsaw.CharacterManager')
    local ctx = call(cm, 'getPlayerContextRef()')
    if not ctx then return {} end
    local out, seen = {}, {}
    for _, go in ipairs({call(call(call(ctx, 'get_BodyUpdater'), 'get_HeadMotion'), 'get_GameObject') or false,
                         call(ctx, 'get_HeadGameObject') or false}) do
        local id = go and addr(go)
        if id and not seen[id] then
            seen[id] = true
            local mesh = component(go, 'via.render.Mesh')
            if mesh then out[#out + 1] = {go = go, mesh = mesh, go_id = id, mesh_id = addr(mesh)} end
        end
    end
    return out
end
local function read_hashes(mesh)
    local n = tonumber(call(mesh, 'get_BlendShapeChannelNum')) or 0
    local arr = call(mesh, 'get_ChannelNameHash')
    if n <= 0 or not arr or tonumber(call(arr, 'get_Length')) ~= n then return nil, n end
    local map = {}
    for i = 0, n - 1 do
        local h = tonumber(call(arr, 'get_Item', i))
        if not finite(h) then return nil, n end
        map[h] = i
    end
    return map, n
end
local function unbind(reason)
    bind = nil
    for _, k in ipairs(keys) do k.ch = nil; k.mi = nil end
    for _, t in ipairs(taps) do t.ch = nil end
    if reason then status = reason end
end
-- 0.4.0: keys may live on several player meshes (head, body, hair; Shinano). Every key binds by name hash on whichever
-- mesh carries it; bind.meshes[1] is the head (native taps, signals), bind.mesh/count/... mirror it for older code.
local function player_meshes()
    local cm = sdk.get_managed_singleton('chainsaw.CharacterManager')
    local ctx = call(cm, 'getPlayerContextRef()')
    if not ctx then return {} end
    local out, seen = {}, {}
    local function visit(tr, depth)
        if not tr or depth > 6 or #out >= 64 then return end
        local go = call(tr, 'get_GameObject'); local id = go and addr(go)
        if id and not seen[id] then
            seen[id] = true
            local mesh = component(go, 'via.render.Mesh')
            if mesh then out[#out + 1] = {go = go, mesh = mesh, go_id = id, mesh_id = addr(mesh)} end
        end
        local c = call(tr, 'get_Child')
        while c do visit(c, depth + 1); c = call(c, 'get_Next') end
    end
    for _, r in ipairs({call(ctx, 'get_BodyGameObject') or false, call(ctx, 'get_GameObject') or false}) do
        if r then visit(call(r, 'get_Transform'), 0) end
    end
    return out
end
-- setBlendShapeChannelWeightParam writes into an engine array of get_BlendShapeChannelWeightCount entries.
-- v0.2.0 game test: 177-channel mesh reported WeightCount 0 (list length 177) and writing past it crashed the game.
-- Never write a channel >= that count; re-read it periodically in case the engine allocates late (per mesh).
local function refresh_limit()
    if not bind then return end
    for _, e in ipairs(bind.meshes) do
        local wc = tonumber(call(e.mesh, 'get_BlendShapeChannelWeightCount'))
        local wl = call(e.mesh, 'get_ChannelWeightList')
        local wll = wl and tonumber(call(wl, 'get_Length'))
        e.weight_count, e.weight_list = wc, wll
        e.limit = math.min(finite(wc) and wc or 0, finite(wll) and wll or e.count, e.count)
    end
    local p = bind.meshes[1]
    bind.weight_count, bind.weight_list, bind.limit = p.weight_count, p.weight_list, p.limit
    local blocked, unbound = 0, 0
    for _, k in ipairs(keys) do
        if not k.ch then unbound = unbound + 1
        elseif k.ch >= bind.meshes[k.mi].limit then blocked = blocked + 1 end
    end
    bind.blocked, bind.unbound = blocked, unbound
    status = string.format('已绑定：%s，%d 个形态键（头部网格 %d 通道，权重数组 %s/%s）。', profile.title or profile.model or '?',
        #keys - unbound, bind.count, tostring(p.weight_count), tostring(p.weight_list))
    if #bind.meshes > 1 then status = status .. string.format(' 另有 %d 个网格（身体/头发）。', #bind.meshes - 1) end
    if unbound > 0 then status = status .. string.format(' %d 个键未找到所在网格（对应模块未启用？）。', unbound) end
    if blocked > 0 then status = status .. string.format(' 警告：%d 个键超出权重数组，已禁止写入。', blocked) end
end
local function attach_extras()
    if not bind then return end
    local have = {}
    for _, e in ipairs(bind.meshes) do have[e.mesh_id] = true end
    local added = false
    for _, c in ipairs(player_meshes()) do
        if not have[c.mesh_id] then
            local need = false
            for _, k in ipairs(keys) do if not k.ch then need = true; break end end
            if not need then break end
            local map, n = read_hashes(c.mesh)
            if map then
                local hit = false
                for _, k in ipairs(keys) do if not k.ch and map[k.hash] then hit = true end end
                if hit then
                    local e = {go = c.go, mesh = c.mesh, go_id = c.go_id, mesh_id = c.mesh_id, count = n, written = {}, limit = 0}
                    bind.meshes[#bind.meshes + 1] = e; have[c.mesh_id] = true; added = true
                    for _, k in ipairs(keys) do if not k.ch and map[k.hash] then k.ch, k.mi = map[k.hash], #bind.meshes end end
                end
            end
        end
    end
    if added then refresh_limit() end
end
local function try_bind()
    if not profile then return end
    for _, c in ipairs(head_candidates()) do
        local map, n = read_hashes(c.mesh)
        if map then
            local found = 0
            for _, k in ipairs(keys) do if map[k.hash] ~= nil then found = found + 1 end end
            if found > 0 then
                for _, k in ipairs(keys) do k.ch = map[k.hash]; k.mi = k.ch and 1 or nil end
                for _, t in ipairs(taps) do t.ch = map[t.hash] end
                local e = {go = c.go, mesh = c.mesh, go_id = c.go_id, mesh_id = c.mesh_id, count = n, written = {}, limit = 0}
                bind = {go = c.go, mesh = c.mesh, go_id = c.go_id, mesh_id = c.mesh_id, count = n, written = e.written, limit = 0, meshes = {e}}
                if found < #keys then attach_extras() end
                refresh_limit()
                return
            end
        end
    end
    status = '未找到带本配置形态键的玩家头部（是否启用了对应角色 MOD？）。'
end
local function still_valid()
    if not bind then return false end
    for _, c in ipairs(head_candidates()) do
        if c.go_id == bind.go_id and c.mesh_id == bind.mesh_id then return true end
    end
    return false
end

------------------------------------------------------------------ weights
local function region_gain(k) return S.region[k.region] or 1.0 end
local function target_weight(k)
    if compare_neutral then return 0 end
    if sweep then return sweep.i == k.idx and sweep.w or 0 end
    local w = 0
    local src = S.source
    if src == 5 then src = cap.active and 4 or 3 end
    if src ~= 2 then w = w + (S.values[k.id] or 0) end
    -- native animation and face capture both produce ARKit values; ARKit keys take them 1:1,
    -- other keys (e.g. MMD) combine them through the profile's retarget list
    local function arkit(name)
        if src == 2 or src == 3 then return (nat[name] or 0) * S.native_gain end
        if src == 4 then return (cap.values[name] or 0) * S.cap_gain end
        return 0
    end
    if src ~= 1 then
        if k.library == 'ARKit' then w = w + arkit(k.name)
        elseif k.arkit then
            for _, m in ipairs(k.arkit) do w = w + arkit(m[1]) * (m[2] or 1) end
        end
    end
    return clamp(w * S.strength * region_gain(k), 0, 1)
end
-- Size an extra mesh's weight array to its channel count (what the debug button did by hand in the 0.4.1 test).
-- Only when the managed weight list already has every channel; true when the count now covers all channels.
local function allocate_mesh(e)
    local wl = call(e.mesh, 'get_ChannelWeightList'); local n = wl and tonumber(call(wl, 'get_Length'))
    if not finite(n) or n < e.count then return false end
    local ok, err = pcall(function() e.mesh:call('set_BlendShapeChannelWeightCount', e.count) end)
    if not ok then last_error = 'set_BlendShapeChannelWeightCount 失败：' .. tostring(err); return false end
    local wc = tonumber(call(e.mesh, 'get_BlendShapeChannelWeightCount'))
    return finite(wc) and wc >= e.count
end
local function allocate_extras(force)
    if not bind then return 0 end
    local done = 0
    for mi, e in ipairs(bind.meshes) do
        local wc = tonumber(call(e.mesh, 'get_BlendShapeChannelWeightCount'))
        if mi > 1 and (not finite(wc) or wc < e.count) and (force or (S.auto_alloc and frame >= (e.next_alloc or 0))) then
            e.next_alloc = frame + 60
            if allocate_mesh(e) then done = done + 1 end
        end
    end
    if done > 0 then refresh_limit() end
    return done
end
local function write_all(force_zero)
    if not bind then return end
    local t0 = os.clock()
    -- The weight array is allocated lazily (0 right after entering a level, full size a little later; 2026-10-11
    -- game test). Re-check it every frame immediately before writing so a write can never land outside it.
    -- Only Leon's head has chainsaw.FacialController_cha0, which sizes the weight array; body / hair meshes stay 0.
    -- 0.4.3: 0.4.2 tried once against a cached list length (still 0 at bind time) and never again; now the list
    -- length is read live and the attempt repeats every second while the count is short.
    allocate_extras(false)
    for _, e in ipairs(bind.meshes) do
        local wc = tonumber(call(e.mesh, 'get_BlendShapeChannelWeightCount'))
        if not finite(wc) then wc = 0 end
        if wc ~= e.weight_count then refresh_limit() end
        if wc < e.limit then e.limit = wc end
    end
    for _, k in ipairs(keys) do
        local e = k.ch and bind.meshes[k.mi]
        if e then
            local w = force_zero and 0 or target_weight(k)
            if k.ch < e.limit and (w ~= 0 or e.written[k.ch] ~= 0) then
                local ok = pcall(function() e.mesh:call('setBlendShapeChannelWeightParam', k.ch, w) end)
                if not ok then unbind('写入失败，已解除绑定，稍后自动重试。'); return end
                e.written[k.ch] = w
            end
        end
    end
    writes_ok = writes_ok + 1
    perf_ms = perf_ms * 0.9 + (os.clock() - t0) * 1000 * 0.1
end
local function zero_written()
    if bind then pcall(write_all, true) end
end
local function push_undo()
    local now = os.clock()
    if now - last_push < 0.6 then return end
    last_push = now
    undo[#undo + 1] = {values = copy(S.values), strength = S.strength, region = copy(S.region)}
    if #undo > 60 then table.remove(undo, 1) end
    redo = {}
end
local function restore_state(st) S.values = copy(st.values); S.strength = st.strength; S.region = copy(st.region); touch() end

------------------------------------------------------------------ native signal observation (read only)
-- The test head is skinned to Head only, but the native facial animation still poses Leon's face joints and writes
-- the 91 native channels. Record them so a native-animation -> shape-key conversion can be calibrated offline.
local SIG_JOINTS = {'C_Jaw', 'C_Mouth', 'C_Chin', 'C_UpperLip', 'C_LowerLip', 'L_MouthCorner', 'R_MouthCorner',
    'L_UpperLip02', 'R_UpperLip02', 'L_LowerLip02', 'R_LowerLip02',
    'L_U_Eyelid1', 'L_U_Eyelid2', 'L_U_Eyelid3', 'L_U_Eyelid4', 'R_U_Eyelid1', 'R_U_Eyelid2', 'R_U_Eyelid3', 'R_U_Eyelid4',
    'L_D_Eyelid3', 'R_D_Eyelid3', 'L_Eye', 'R_Eye', 'L_I_Eyebrow', 'R_I_Eyebrow', 'L_O_Eyebrow', 'R_O_Eyebrow',
    'L_UI_Eyebrow_01', 'R_UI_Eyebrow_01', 'L_Cheek', 'R_Cheek', 'L_NoseCorner', 'R_NoseCorner', 'Tongue01', 'Tongue03'}
local SIG_LIVE = {{'下巴', 'C_Jaw', 'rot'}, {'嘴', 'C_Mouth', 'rot'}, {'左上眼皮', 'L_U_Eyelid3', 'any'}, {'右上眼皮', 'R_U_Eyelid3', 'any'},
    {'左下眼皮', 'L_D_Eyelid3', 'any'}, {'左嘴角', 'L_MouthCorner', 'pos'}, {'右嘴角', 'R_MouthCorner', 'pos'},
    {'上唇', 'C_UpperLip', 'pos'}, {'下唇', 'C_LowerLip', 'pos'}, {'左眉内', 'L_I_Eyebrow', 'pos'}, {'右眉内', 'R_I_Eyebrow', 'pos'},
    {'左眉外', 'L_O_Eyebrow', 'pos'}, {'左颊', 'L_Cheek', 'pos'}, {'左眼球', 'L_Eye', 'rot'}, {'舌', 'Tongue01', 'rot'}}
local sig = {joints = {}, found = 0, owner = nil, mesh_id = nil, base = nil, cur = {}, peak = {}, rec = nil, label = '',
    saved = {}, next_t = 0}
local function sig_resolve()
    sig.joints, sig.found, sig.owner, sig.mesh_id = {}, 0, nil, bind and bind.mesh_id
    sig.base, sig.cur, sig.peak = nil, {}, {}
    if not bind then return end
    local cm = sdk.get_managed_singleton('chainsaw.CharacterManager')
    local ctx = call(cm, 'getPlayerContextRef()')
    local owners = {{'头部', bind.go}, {'HeadMotion', call(call(call(ctx, 'get_BodyUpdater'), 'get_HeadMotion'), 'get_GameObject')},
        {'身体', call(ctx, 'get_BodyGameObject')}, {'角色', call(ctx, 'get_GameObject')}}
    for _, o in ipairs(owners) do
        local tr = o[2] and call(o[2], 'get_Transform')
        if tr and call(tr, 'getJointByName', 'C_Jaw') then
            for _, n in ipairs(SIG_JOINTS) do
                local j = call(tr, 'getJointByName', n)
                if j then sig.joints[n] = j; sig.found = sig.found + 1 end
            end
            sig.owner = o[1]; return
        end
    end
end
local function r5(x) return math.floor(x * 100000 + 0.5) / 100000 end
local function sig_metric(name, kind)
    local b, c = sig.base and sig.base[name], sig.cur[name]
    if not b or not c then return nil end
    local d = math.sqrt((c[1] - b[1]) ^ 2 + (c[2] - b[2]) ^ 2 + (c[3] - b[3]) ^ 2) * 1000          -- mm
    local dot = math.abs(c[4] * b[4] + c[5] * b[5] + c[6] * b[6] + c[7] * b[7])
    local a = 2 * math.acos(math.min(1, dot)) * 180 / math.pi                                       -- degrees
    if kind == 'pos' then return d, 'mm' elseif kind == 'rot' then return a, '°' end
    if a >= d then return a, '°' end
    return d, 'mm'
end
local function sig_save()
    local r = sig.rec; sig.rec = nil
    if not r or #r.samples == 0 then return end
    local n = #sig.saved + 1
    local name = string.format('RE4R_ShapeKeySystem_signals_%02d.json', n)
    local data = {version = VERSION, label = r.label, owner = sig.owner, joints = SIG_JOINTS, base = sig.base,
        tap_names = r.tap_names, rate_hz = 20, duration = r.samples[#r.samples].t, samples = r.samples,
        note = 'j = per joint local pos xyz + rot quat xyzw (order = joints); taps = native channel weights > 0.001'}
    local ok = try(json.dump_file, name, data)
    sig.saved[#sig.saved + 1] = {file = name, label = r.label, n = #r.samples, ok = ok}
    status = ok and ('已保存信号录制：' .. name) or '信号录制保存失败。'
end
local function sig_sample()
    if not bind then return end
    if sig.mesh_id ~= bind.mesh_id then sig_resolve() end
    if sig.found == 0 then return end
    for n, j in pairs(sig.joints) do
        local p, q = call(j, 'get_LocalPosition'), call(j, 'get_LocalRotation')
        if p and q then sig.cur[n] = {p.x, p.y, p.z, q.x, q.y, q.z, q.w} end
    end
    if not sig.base and next(sig.cur) then sig.base = copy(sig.cur) end
    for _, l in ipairs(SIG_LIVE) do
        local v = sig_metric(l[2], l[3])
        if v and v > (sig.peak[l[2]] or 0) then sig.peak[l[2]] = v end
    end
    local r = sig.rec
    if r and os.clock() >= sig.next_t then
        sig.next_t = os.clock() + 0.05
        local t = os.clock() - r.t0
        local s = {t = r5(t), j = {}, taps = {}}
        for _, n in ipairs(SIG_JOINTS) do
            local c = sig.cur[n]
            if c then for i = 1, 7 do s.j[#s.j + 1] = r5(c[i]) end else for _ = 1, 7 do s.j[#s.j + 1] = 0 end end
        end
        for _, tp in ipairs(taps) do
            if tp.ch then
                local w = tonumber(call(bind.mesh, 'getBlendShapeChannelWeightParam', tp.ch)) or 0
                if w > 0.001 then s.taps[tp.short] = r5(w) end
            end
        end
        r.samples[#r.samples + 1] = s
        if t >= 90 then sig_save() end
    end
end

------------------------------------------------------------------ native animation -> ARKit conversion
-- Joint signal = component along the recorded principal axis, relative to Leon's idle median pose
-- (degrees for rotations, millimetres for translations). Tap signal = max of the listed native channel weights.
-- weight = clamp((signal - lo) / (hi - lo)) * gain, summed per key (k07 table).
local function joint_signal(name)
    local jm = native_map.joints[name]
    local c = jm and sig.cur[jm.bone or name]          -- 'bone': several fixed-axis signals on one joint (eye yaw/pitch)
    if not jm or not c then return nil end
    local n, a = jm.neutral, jm.axis
    if jm.kind == 'pos' then
        return ((c[1] - n[1]) * a[1] + (c[2] - n[2]) * a[2] + (c[3] - n[3]) * a[3]) * 1000
    end
    -- q_rel = conj(n) * c, then log map (degrees)
    local ax, ay, az, aw = -n[4], -n[5], -n[6], n[7]
    local bx, by, bz, bw = c[4], c[5], c[6], c[7]
    local x = aw * bx + ax * bw + ay * bz - az * by
    local y = aw * by - ax * bz + ay * bw + az * bx
    local z = aw * bz + ax * by - ay * bx + az * bw
    local w = aw * bw - ax * bx - ay * by - az * bz
    if w < 0 then x, y, z, w = -x, -y, -z, -w end
    local s = math.sqrt(x * x + y * y + z * z)
    if s < 1e-9 then return 0 end
    local ang = 2 * math.atan(s, w) * 180 / math.pi
    return (x * a[1] + y * a[2] + z * a[3]) / s * ang
end
local tap_cache = {mesh_id = nil, ch = {}}
local function native_convert()
    nat = {}
    if not native_map or not bind or S.source == 1 then return end
    if tap_cache.mesh_id ~= bind.mesh_id then
        tap_cache.mesh_id, tap_cache.ch = bind.mesh_id, {}
        for _, tp in ipairs(taps) do if tp.ch then tap_cache.ch[tp.short] = tp.ch end end
    end
    local tapv = {}
    for _, r in ipairs(native_map.rules) do
        local s
        if r.joint then
            s = joint_signal(r.joint)
        else
            for _, tn in ipairs(r.taps) do
                local v = tapv[tn]
                if v == nil then
                    local ch = tap_cache.ch[tn]
                    v = ch and tonumber(call(bind.mesh, 'getBlendShapeChannelWeightParam', ch)) or 0
                    tapv[tn] = v
                end
                if not s or v > s then s = v end
            end
        end
        if s and finite(s) then
            local v = clamp((s - r.lo) / (r.hi - r.lo), 0, 1) * (r.gain or 1)
            nat[r.key] = clamp((nat[r.key] or 0) + v, 0, 1)                    -- keyed by ARKit name
        end
    end
end

------------------------------------------------------------------ face capture (RhyLive ARKit 52, direct 1:1 to ARKit keys)
local function capture_poll()
    if S.source ~= 4 and S.source ~= 5 then return end
    local nat_dll = rawget(_G, 'rhylive_native')
    if not nat_dll then cap.active = false; cap.status = '未找到 RhyLive 接收器（RhyLiveFace.dll 未加载）'; return end
    -- reuse the per-channel gains the user tuned in the RhyLive panel
    if frame - cap.gains_at > 120 then
        cap.gains_at = frame
        local ok, s = pcall(json.load_file, 'RhyLiveFace_settings.json')
        cap.gains = ok and type(s) == 'table' and type(s.gains) == 'table' and s.gains or {}
    end
    local ok, snap = pcall(nat_dll.poll)
    if not ok or type(snap) ~= 'table' then cap.active = false; cap.status = '读取接收器失败'; return end
    cap.active = snap.running and (snap.sequence or 0) > 0 and (snap.age_ms or 1e9) <= CAP_TIMEOUT_MS
    if not snap.running then cap.status = '接收器未启动（在 RhyLive 面板点“启动接收”）'
    elseif (snap.sequence or 0) == 0 then cap.status = '接收器已启动，等待手机数据'
    elseif not cap.active then cap.status = '面捕数据中断'
    else cap.status = '面捕数据正常' end
    if not cap.active then
        for n, v in pairs(cap.values) do cap.values[n] = v * 0.85 end          -- ease back to neutral on dropout
        return
    end
    if snap.sequence ~= cap.seq then
        cap.seq = snap.sequence
        local a = clamp(S.cap_smooth, 0.05, 1)
        for name, raw in pairs(snap.values or {}) do                       -- all 52 ARKit names
            local g = finite(cap.gains[name]) and cap.gains[name] or 1
            local v = clamp((tonumber(raw) or 0) * g, 0, 1)
            local f = cap.values[name] or v
            cap.values[name] = f + (v - f) * a
        end
    end
end

------------------------------------------------------------------ engine callbacks
local function active() return S.enabled and bind ~= nil end
local function lod0()
    if active() and S.force_lod0 then
        for _, e in ipairs(bind.meshes) do pcall(function() e.mesh:call('set_LodLevel', 0) end) end
    end
end
re.on_pre_application_entry('UpdateMotion', function() pcall(lod0) end)
re.on_pre_application_entry('PrepareRendering', function() pcall(lod0) end)
re.on_application_entry('LateUpdateBehavior', function()
    local ok, err = pcall(function()
        if sweep then
            local t = os.clock() - sweep.t0
            local phase = t / sweep.period
            if phase >= 1 then
                sweep.i = sweep.i + 1; sweep.t0 = os.clock(); phase = 0
                if sweep.i > #keys then sweep = nil; status = '逐键巡检结束。' end
            end
            if sweep then sweep.w = math.sin(math.pi * clamp(phase, 0, 1)) end
        end
        sig_sample()                       -- same-frame native signal, before our own writes
        native_convert()
        capture_poll()
        if active() then write_all(false) end
    end)
    if not ok then last_error = tostring(err) end
end)
re.on_application_entry('PrepareRendering', function()
    local ok, err = pcall(function()
        frame = frame + 1
        if not profile then
            if frame % 120 == 1 then load_profile() end
            return
        end
        if not bind then
            if frame >= bind_retry then bind_retry = frame + 90; try_bind() end
        elseif frame % 60 == 0 and not still_valid() then
            unbind('玩家头部已变化，正在重新绑定。'); bind_retry = frame + 10
        elseif frame % 60 == 30 then
            refresh_limit()
            allocate_extras(false)         -- also while driving is off, so sliders work as soon as it is enabled
        elseif frame % 300 == 170 and (bind.unbound or 0) > 0 then   -- 170: not a % 60 == 0/30 frame
            attach_extras()                -- body / hair meshes can load after the head
        end
        -- read-only probe: native tap activity and whether anything else writes our custom channels
        if bind and frame % 10 == 0 then
            local tl = {}
            for _, t in ipairs(taps) do
                if t.ch then
                    local w = tonumber(call(bind.mesh, 'getBlendShapeChannelWeightParam', t.ch)) or 0
                    if w > 0.01 then tl[#tl + 1] = {t.short, w} end
                end
            end
            table.sort(tl, function(a, b) return a[2] > b[2] end)
            probe.taps = tl
            if not S.enabled then
                local mx, who = 0, nil
                for _, k in ipairs(keys) do
                    local w = k.ch and tonumber(call(bind.meshes[k.mi].mesh, 'getBlendShapeChannelWeightParam', k.ch)) or 0
                    if w > mx then mx, who = w, k.label end
                end
                probe.custom_max, probe.custom_name, probe.idle_frames = mx, who, probe.idle_frames + 10
            else
                probe.idle_frames = 0
            end
        end
        if settings_dirty_at and os.clock() - settings_dirty_at > 1.0 then settings_dirty_at = nil; save_settings() end
    end)
    if not ok then last_error = tostring(err) end
end)
re.on_script_reset(function() zero_written(); save_settings() end)

------------------------------------------------------------------ UI
local function progress(frac, overlay)
    if not try(imgui.progress_bar, clamp(frac, 0, 1), Vector2f.new(-1, 0), overlay) then
        imgui.text(string.rep('|', math.floor(clamp(frac, 0, 1) * 30)) .. ' ' .. (overlay or ''))
    end
end
local function region_live(rid)
    local mx = 0
    for _, k in ipairs(keys) do if k.region == rid then mx = math.max(mx, target_weight(k)) end end
    return mx
end
local function slider(label, v, a, b)
    local changed, nv = imgui.slider_float(label, v, a, b, '%.2f')
    if changed then push_undo(); touch() end
    return changed and nv or v
end
local function tab_buttons()
    local pages = {'表情', '形态键', '巡检', '调试', '信号'}
    for i, name in ipairs(pages) do
        if i > 1 then imgui.same_line() end
        if imgui.button((S.page == i and '[' .. name .. ']' or name) .. '##sks_tab' .. i) then S.page = i end
    end
    imgui.separator()
end
local function page_expression()
    imgui.text('配置：' .. (profile and (profile.title or profile.model) or '-'))
    local cs, src = imgui.combo('表情来源##sks_src', S.source, SOURCES)
    if cs then S.source = src; touch_settings() end
    if S.source == 4 or S.source == 5 then
        imgui.text((cap.active and '● ' or '○ ') .. '面捕：' .. cap.status)
        local c3, g3 = imgui.slider_float('面捕强度##sks_cgain', S.cap_gain, 0, 2, '%.2f')
        if c3 then S.cap_gain = g3; touch_settings() end
        local c4, g4 = imgui.slider_float('面捕跟随速度（越小越平滑）##sks_csm', S.cap_smooth, 0.05, 1, '%.2f')
        if c4 then S.cap_smooth = g4; touch_settings() end
        imgui.text('单通道增益沿用 RhyLive 面板里的设置。RhyLive 面板只需“启动接收”，不要开它的骨骼驱动。')
        local top = {}
        for n, v in pairs(cap.values) do if v > 0.05 then top[#top + 1] = {n, v} end end
        table.sort(top, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(6, #top) do
            local k = key_by_id['SK__arkit.' .. top[i][1]]; parts[#parts + 1] = string.format('%s %.2f', k and k.label or top[i][1], top[i][2])
        end
        imgui.text('面捕当前：' .. (#parts > 0 and table.concat(parts, '  ') or '（中性）'))
    end
    if S.source == 2 or S.source == 3 or S.source == 5 then
        if not native_map then
            imgui.text_colored('缺少原生换算表 ' .. NATIVE_FILE .. '，原生动画来源不可用。', 0xFF5555FF)
        elseif sig.found == 0 then
            imgui.text_colored('还没读到里昂的面部骨骼（进入关卡后自动查找）。', 0xFF4FA3FF)
        else
            local c2, g = imgui.slider_float('原生动画强度##sks_ngain', S.native_gain, 0, 2, '%.2f')
            if c2 then S.native_gain = g; touch_settings() end
            local top = {}
            for id, v in pairs(nat) do if v > 0.02 then top[#top + 1] = {id, v} end end
            table.sort(top, function(a, b) return a[2] > b[2] end)
            local parts = {}
            for i = 1, math.min(6, #top) do
                local k = key_by_id['SK__arkit.' .. top[i][1]]; parts[#parts + 1] = string.format('%s %.2f', k and k.label or top[i][1], top[i][2])
            end
            imgui.text('原生动画当前：' .. (#parts > 0 and table.concat(parts, '  ') or '（中性）'))
        end
    end
    if not S.enabled then imgui.text_colored('提示：勾选上方“启用驱动”后才会写入形态键。', 0xFF4FA3FF) end
    S.strength = slider('表情强度##sks_str', S.strength, 0, 1.5)
    imgui.separator()
    for _, r in ipairs(regions) do
        imgui.push_id('sks_r_' .. r.id)
        S.region[r.id] = slider(r.label .. ' 强度', S.region[r.id] or 1.0, 0, 1.5)
        progress(region_live(r.id), string.format('%s 实时 %.2f', r.label, region_live(r.id)))
        imgui.pop_id()
    end
    imgui.separator()
    if imgui.button('全部归零##sks_zero_e') then push_undo(); S.values = {}; touch() end
    imgui.same_line()
    local c; c, compare_neutral = imgui.checkbox('对比初始（临时显示无表情）##sks_cmp', compare_neutral)
end
local function visible(k)
    if S.library == 2 and k.library ~= 'ARKit' then return false end
    if S.library == 3 and k.library ~= 'MMD' then return false end
    if S.only_active and (S.values[k.id] or 0) == 0 then return false end
    if S.filter ~= '' then
        local f = S.filter:lower()
        if not (k.label:lower():find(f, 1, true) or k.name:lower():find(f, 1, true)) then return false end
    end
    return true
end
local function page_keys()
    -- presets row
    local names = {}
    for n in pairs(presets) do names[#names + 1] = n end
    table.sort(names)
    local cur = 1
    for i, n in ipairs(names) do if n == S.preset then cur = i end end
    if #names > 0 then
        local ch, idx = imgui.combo('预设##sks_preset', cur, names)
        if ch then S.preset = names[idx] end
        imgui.same_line()
        if imgui.button('载入##sks_load') and presets[S.preset] then
            push_undo(); restore_state(presets[S.preset]); dirty = false
        end
        imgui.same_line()
        if imgui.button('保存##sks_save') and S.preset ~= '' then
            presets[S.preset] = {values = copy(S.values), strength = S.strength, region = copy(S.region)}; save_presets(); dirty = false
        end
        imgui.same_line()
        if imgui.button('删除##sks_del') and presets[S.preset] then presets[S.preset] = nil; save_presets(); S.preset = '' end
    end
    local c1; c1, new_name = imgui.input_text('##sks_newname', new_name)
    imgui.same_line()
    if imgui.button('另存为新预设##sks_saveas') and new_name ~= '' then
        presets[new_name] = {values = copy(S.values), strength = S.strength, region = copy(S.region)}
        S.preset = new_name; new_name = ''; save_presets(); dirty = false
    end
    if dirty then imgui.text_colored('有未保存的修改', 0xFF4FA3FF) end
    imgui.separator()
    -- filters + history
    local c2; c2, S.filter = imgui.input_text('搜索##sks_filter', S.filter)
    local c3, lib = imgui.combo('库##sks_lib', S.library, LIBS); if c3 then S.library = lib end
    imgui.same_line()
    local c4; c4, S.only_active = imgui.checkbox('只看非零##sks_onlyact', S.only_active)
    if imgui.button('撤销##sks_undo') and #undo > 0 then
        redo[#redo + 1] = {values = copy(S.values), strength = S.strength, region = copy(S.region)}
        restore_state(table.remove(undo)); last_push = -1
    end
    imgui.same_line()
    if imgui.button('重做##sks_redo') and #redo > 0 then
        undo[#undo + 1] = {values = copy(S.values), strength = S.strength, region = copy(S.region)}
        restore_state(table.remove(redo))
    end
    imgui.same_line()
    if imgui.button('归零##sks_zero') then push_undo(); S.values = {}; touch() end
    imgui.same_line()
    if imgui.button('重置为预设##sks_reset') and presets[S.preset] then push_undo(); restore_state(presets[S.preset]); dirty = false end
    imgui.same_line()
    local c5; c5, compare_neutral = imgui.checkbox('对比初始##sks_cmp2', compare_neutral)
    imgui.separator()
    -- key list grouped
    local child = try(imgui.begin_child_window, 'sks_list', Vector2f.new(0, 380), true)
    local last_group = nil
    for _, k in ipairs(keys) do
        if visible(k) then
            local g = k.library .. ' · ' .. k.group
            if g ~= last_group then imgui.text_colored(g, 0xFF66CCFF); last_group = g end
            imgui.push_id('sks_k' .. k.idx)
            local v = S.values[k.id] or 0
            local changed, nv = imgui.slider_float(k.label .. '  (' .. k.name .. ')', v, 0, 1, '%.2f')
            if changed then push_undo(); S.values[k.id] = nv ~= 0 and nv or nil; touch() end
            imgui.same_line()
            if imgui.button('0') then push_undo(); S.values[k.id] = nil; touch() end
            imgui.same_line()
            if imgui.button('1') then push_undo(); S.values[k.id] = 1; touch() end
            imgui.pop_id()
        end
    end
    if child then try(imgui.end_child_window) end
end
local function page_sweep()
    imgui.text('依次把每个形态键从 0 推到 1 再回到 0，用来快速检查所有键是否正常。')
    local c, p = imgui.slider_float('每个键时长（秒）##sks_sp', sweep_period, 0.4, 3.0, '%.1f')
    if c then sweep_period = p end
    if not sweep then
        if imgui.button('开始逐键巡检##sks_sw') then sweep = {i = 1, t0 = os.clock(), period = sweep_period, w = 0} end
    else
        local k = keys[sweep.i]
        imgui.text(string.format('第 %d / %d 个：%s  (%s · %s)', sweep.i, #keys, k and k.label or '-', k and k.library or '', k and k.name or ''))
        progress(sweep.w or 0, string.format('%.2f', sweep.w or 0))
        if imgui.button('上一个##sks_prev') then sweep.i = math.max(1, sweep.i - 1); sweep.t0 = os.clock() end
        imgui.same_line()
        if imgui.button('下一个##sks_next') then sweep.i = math.min(#keys, sweep.i + 1); sweep.t0 = os.clock() end
        imgui.same_line()
        if imgui.button('停止##sks_swstop') then sweep = nil end
    end
end
-- 0.4.1: Shinano game test showed body / hair meshes bound but their weight array never allocated (head 159/159).
-- Dump what differs between the head and the extra meshes: components, blend-shape related getters, Mesh methods.
local function dump_diag()
    local out = {version = VERSION, meshes = {}, mesh_methods = {}}
    local td = sdk.find_type_definition and sdk.find_type_definition('via.render.Mesh')
    if td then
        try(function()
            for _, m in ipairs(td:get_methods()) do
                local n = m:get_name()
                if n:find('Blend') or n:find('Weight') or n:find('Morph') or n:find('Shape') then out.mesh_methods[#out.mesh_methods + 1] = n end
            end
        end)
    end
    for mi, e in ipairs(bind and bind.meshes or {}) do
        local d = {index = mi, name = tostring(call(e.go, 'get_Name')), channels = e.count, getters = {}, components = {}}
        for _, g in ipairs({'get_BlendShapeChannelWeightCount', 'get_BlendShapeChannelNum', 'get_UseBlendShapeNormal',
            'get_LodLevel', 'get_Enabled', 'get_DrawDefault', 'get_Mesh', 'get_Motion'}) do
            local v = call(e.mesh, g); d.getters[g] = v ~= nil and tostring(v) or 'nil'
        end
        local wl = call(e.mesh, 'get_ChannelWeightList'); d.getters.ChannelWeightList_Length = tostring(wl and call(wl, 'get_Length'))
        try(function()
            local comps = e.go:call('get_Components')
            local n = comps and comps:call('get_Count') or (comps and #comps) or 0
            for i = 0, (tonumber(n) or 0) - 1 do
                local c = comps:call('get_Item', i)
                d.components[#d.components + 1] = c and c:get_type_definition():get_full_name() or '?'
            end
        end)
        if #d.components == 0 then
            try(function() for _, c in ipairs(e.go:call('get_Components'):get_elements()) do d.components[#d.components + 1] = c:get_type_definition():get_full_name() end end)
        end
        out.meshes[#out.meshes + 1] = d
    end
    local ok = try(json.dump_file, DIAG_FILE, out)
    status = ok and ('已导出诊断：' .. DIAG_FILE) or '诊断导出失败。'
end
local function page_debug()
    imgui.text('状态：' .. status)
    if last_error then imgui.text_colored('错误：' .. last_error, 0xFF5555FF) end
    if bind then
        imgui.text(string.format('通道总数 %d | 自定义键 %d | 原生通道 %d | LOD=%s | UseBlendShapeNormal=%s',
            bind.count, #keys, #taps, tostring(call(bind.mesh, 'get_LodLevel')), tostring(call(bind.mesh, 'get_UseBlendShapeNormal'))))
        imgui.text(string.format('写入耗时 %.3f ms/帧 | 已写入 %d 帧', perf_ms, writes_ok))
    end
    local c1; c1, S.force_lod0 = imgui.checkbox('驱动时强制 LOD0（形态键只在 LOD0 生效）##sks_lod', S.force_lod0)
    if c1 then touch_settings() end
    if imgui.button('重新扫描头部##sks_rescan') then unbind(nil); bind_retry = 0 end
    local c2; c2, S.auto_alloc = imgui.checkbox('身体/头发网格：自动分配权重数组##sks_autoalloc', S.auto_alloc)
    if c2 then touch_settings() end
    if bind then
        imgui.text(string.format('被禁止的键=%d', bind.blocked or 0))
        for mi, e in ipairs(bind.meshes) do
            imgui.text(string.format('  网格 %d %s：通道 %d，WeightCount=%s，WeightList=%s，可写上限=%d，LOD=%s', mi,
                tostring(call(e.go, 'get_Name') or '?'), e.count, tostring(e.weight_count), tostring(e.weight_list), e.limit or 0,
                tostring(call(e.mesh, 'get_LodLevel'))))
            if (e.limit or 0) < e.count then
                imgui.same_line()
                if imgui.button(string.format('手动：设置 WeightCount = 通道数##sks_setwc%d', mi)) then
                    local ok, err = pcall(function() e.mesh:call('set_BlendShapeChannelWeightCount', e.count) end)
                    if not ok then last_error = 'set_BlendShapeChannelWeightCount 失败：' .. tostring(err) end
                    refresh_limit()
                end
            end
        end
        if imgui.button('导出网格诊断到 reframework/data/' .. DIAG_FILE .. '##sks_diag') then dump_diag() end
    end
    imgui.separator()
    imgui.text('原生动画写入的原版通道（只读，权重 > 0.01）：')
    if #probe.taps == 0 then imgui.text('  （当前没有）') end
    for i = 1, math.min(10, #probe.taps) do
        imgui.text(string.format('  %-40s %.3f', probe.taps[i][1], probe.taps[i][2]))
    end
    imgui.separator()
    imgui.text('通道归属测试：取消“启用驱动”后，看原生动画会不会写我们的自定义键。')
    if S.enabled then
        imgui.text('  （驱动启用中，暂不检测）')
    elseif probe.idle_frames < 60 then
        imgui.text('  检测中……')
    elseif probe.custom_max < 0.001 then
        imgui.text_colored('  自定义键全部保持 0：原生动画不写它们。', 0xFF66FF66)
    else
        imgui.text_colored(string.format('  有自定义键被写入：%s = %.3f', probe.custom_name or '?', probe.custom_max), 0xFF5555FF)
    end
end
local function page_signal()
    imgui.text('原生动画信号（只读）：游戏原生动画仍在驱动里昂的面部骨骼和原版通道，这里实时显示并可录制，用来做换算。')
    if not bind then imgui.text('  未绑定头部。'); return end
    imgui.text(string.format('面部骨骼：找到 %d / %d（来自%s）', sig.found, #SIG_JOINTS, sig.owner or '-'))
    if sig.found == 0 then
        if imgui.button('重新查找骨骼##sks_sigres') then sig.mesh_id = nil end
        return
    end
    if imgui.button('设为中性（当前姿态）##sks_sigbase') then sig.base = copy(sig.cur); sig.peak = {} end
    imgui.same_line()
    if imgui.button('清空峰值##sks_sigpeak') then sig.peak = {} end
    imgui.separator()
    for _, l in ipairs(SIG_LIVE) do
        local v, unit = sig_metric(l[2], l[3])
        if v then
            local full = unit == '°' and 20 or 8
            progress(v / full, string.format('%s %s  %.2f%s   峰值 %.2f', l[1], l[2], v, unit, sig.peak[l[2]] or 0))
        end
    end
    imgui.separator()
    imgui.text('原版通道（权重 > 0.01）：')
    for i = 1, math.min(6, #probe.taps) do imgui.text(string.format('  %-36s %.3f', probe.taps[i][1], probe.taps[i][2])) end
    imgui.separator()
    if not sig.rec then
        local c; c, sig.label = imgui.input_text('场景说明##sks_siglabel', sig.label)
        imgui.text('建议录：① 待机 30 秒（眨眼、呼吸）② 对话 / 过场（口型）③ 受伤、瞄准、奔跑')
        if imgui.button('开始录制（最长 90 秒）##sks_sigrec') then
            local names = {}
            for _, tp in ipairs(taps) do names[#names + 1] = tp.short end
            sig.rec = {label = sig.label, t0 = os.clock(), samples = {}, tap_names = names}; sig.next_t = 0
        end
    else
        imgui.text_colored(string.format('录制中：%s  %.1f 秒，%d 帧', sig.rec.label, os.clock() - sig.rec.t0, #sig.rec.samples), 0xFF5555FF)
        if imgui.button('停止并保存##sks_sigstop') then sig_save() end
    end
    for _, s in ipairs(sig.saved) do
        imgui.text(string.format('  %s  [%s]  %d 帧 %s', s.file, s.label, s.n, s.ok and '' or '（保存失败）'))
    end
end
local function draw_body()
    local c; c, S.enabled = imgui.checkbox('启用驱动##sks_en', S.enabled)
    if c then
        if not S.enabled then zero_written(); probe.idle_frames = 0 end
        touch_settings()
    end
    imgui.same_line()
    imgui.text(bind and ('● ' .. status) or ('○ ' .. status))
    tab_buttons()
    if S.page == 1 then page_expression()
    elseif S.page == 2 then page_keys()
    elseif S.page == 3 then page_sweep()
    elseif S.page == 5 then page_signal()
    else page_debug() end
end
re.on_draw_ui(function()
    if imgui.tree_node('形态键系统 / ShapeKey System ' .. VERSION) then
        local c; c, S.show_window = imgui.checkbox('独立窗口显示##sks_win', S.show_window)
        if c then touch_settings() end
        if not S.show_window then
            local ok, err = pcall(draw_body)
            if not ok then last_error = tostring(err) end
        end
        imgui.tree_pop()
    end
end)
re.on_frame(function()
    if not S.show_window or not reframework:is_drawing_ui() then return end
    try(imgui.set_next_window_size, Vector2f.new(760, 680), 4)
    local open = imgui.begin_window('形态键系统 ShapeKey System##sks_window', true, 0)
    local ok, err = pcall(draw_body)
    if not ok then last_error = tostring(err) end
    imgui.end_window()
    if open == false then S.show_window = false; touch_settings() end
end)

-- 0.4.3 public interface for other REFramework scripts (e.g. the desktop GUI bridge):
--   local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
--   api.mesh_status()            -> { {index, name, channels, weight_count, weight_list, limit, ready}, ... } (index 1 = head)
--   api.allocate_weights(i)      -> number of meshes now sized; i = mesh index (> 1), nil = all body / hair meshes
--   api.get_auto_allocate() / api.set_auto_allocate(bool)   (saved in the settings file)
RE4R_ShapeKeySystem_api = {
    version = VERSION,
    mesh_status = function()
        local out = {}
        for mi, e in ipairs(bind and bind.meshes or {}) do
            local wc = tonumber(call(e.mesh, 'get_BlendShapeChannelWeightCount'))
            local wl = call(e.mesh, 'get_ChannelWeightList')
            out[mi] = {index = mi, name = tostring(call(e.go, 'get_Name') or '?'), channels = e.count, weight_count = wc,
                weight_list = wl and tonumber(call(wl, 'get_Length')), limit = e.limit or 0, ready = finite(wc) and wc >= e.count}
        end
        return out
    end,
    allocate_weights = function(i)
        if not bind then return 0 end
        if i == nil then return allocate_extras(true) end
        local e = bind.meshes[i]
        if not e or i == 1 then return 0 end
        local ok = allocate_mesh(e); refresh_limit(); return ok and 1 or 0
    end,
    get_auto_allocate = function() return S.auto_alloc end,
    set_auto_allocate = function(v) S.auto_alloc = v and true or false; touch_settings() end,
}

load_profile()
load_settings()
