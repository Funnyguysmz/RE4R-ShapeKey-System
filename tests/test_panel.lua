-- Stub-harness test for RE4R_ShapeKeySystem.lua (no game). Usage: lua.exe test_panel.lua <panel.lua> <fixture.lua>
local panel_path, fixture_path = arg[1], arg[2]
local F = dofile(fixture_path)
local T = 0; os.clock = function() return T end
local pass, fail = 0, 0
local function check(c, msg) if c then pass = pass + 1 else fail = fail + 1; print('FAIL: ' .. msg) end end

-- mock engine objects ------------------------------------------------------------------------
local function obj(methods, address)
    return {call = function(self, name, ...) local f = methods[name]; if not f then error('no method ' .. name) end; return f(...) end,
            get_address = function() return address end}
end
local weights, lod, writes = {}, 1, {}
for i = 0, #F.order - 1 do weights[i] = 0 end
local hash_array = obj({get_Length = function() return #F.order end, get_Item = function(i) return F.order[i + 1] end}, 9)
local mesh_present = true
local mesh = obj({
    get_BlendShapeChannelNum = function() return #F.order end,
    get_ChannelNameHash = function() return hash_array end,
    setBlendShapeChannelWeightParam = function(i, w) weights[i] = w; writes[#writes + 1] = {i, w} end,
    getBlendShapeChannelWeightParam = function(i) return weights[i] end,
    set_LodLevel = function(v) lod = v end, get_LodLevel = function() return lod end,
    get_UseBlendShapeNormal = function() return true end,
    get_BlendShapeChannelWeightCount = function() return WEIGHT_COUNT or #F.order end,
    set_BlendShapeChannelWeightCount = function(n) WEIGHT_COUNT = n end,
    get_ChannelWeightList = function() return obj({get_Length = function() return WEIGHT_COUNT or #F.order end}, 300) end}, 200)
JOINT = {}
local function joint(name)
    JOINT[name] = JOINT[name] or {p = {x = 0, y = 0, z = 0}, q = {x = 0, y = 0, z = 0, w = 1}}
    return obj({get_LocalPosition = function() return JOINT[name].p end, get_LocalRotation = function() return JOINT[name].q end}, 500)
end
local transform = obj({getJointByName = function(n) if n:find('^[LRC]_') or n:find('^Tongue') then return joint(n) end end}, 400)
local head_go = obj({['getComponent(System.Type)'] = function() return mesh_present and mesh or nil end, get_Name = function() return 'head' end,
    get_Transform = function() return transform end}, 100)
local head_motion = obj({get_GameObject = function() return head_go end}, 101)
local body = obj({get_HeadMotion = function() return head_motion end}, 102)
local ctx = obj({get_BodyUpdater = function() return body end, get_HeadGameObject = function() return head_go end}, 103)
local cm = obj({['getPlayerContextRef()'] = function() return ctx end}, 104)
sdk = {get_managed_singleton = function() return cm end, typeof = function(n) return n end}
local files = {}
json = {load_file = function(p) if p == 'RE4R_ShapeKeySystem_profile.json' then return F.profile end return files[p] end,
        dump_file = function(p, d) files[p] = d; return true end}
Vector2f = {new = function(x, y) return {x, y} end}
reframework = {is_drawing_ui = function() return true end}
local cb = {pre = {}, post = {}, draw = {}, frame = {}, reset = {}}
re = {on_pre_application_entry = function(n, f) cb.pre[n] = f end, on_application_entry = function(n, f) cb.post[n] = f end,
      on_draw_ui = function(f) cb.draw[#cb.draw + 1] = f end, on_frame = function(f) cb.frame[#cb.frame + 1] = f end,
      on_script_reset = function(f) cb.reset[#cb.reset + 1] = f end}
-- scripted imgui: actions[label_substring] = value to return as "changed"
local actions, seen = {}, {}
local function act(label) for k, v in pairs(actions) do if label:find(k, 1, true) then actions[k] = nil; return true, v end end return false end
imgui = {
    tree_node = function() return true end, tree_pop = function() end, separator = function() end, same_line = function() end,
    text = function(t) seen[#seen + 1] = t end, text_colored = function(t) seen[#seen + 1] = t end,
    push_id = function() end, pop_id = function() end,
    button = function(l) local c = act(l); return c end,
    checkbox = function(l, v) local c, nv = act(l); if c then return true, nv end return false, v end,
    slider_float = function(l, v) local c, nv = act(l); if c then return true, nv end return false, v end,
    combo = function(l, i) local c, nv = act(l); if c then return true, nv end return false, i end,
    input_text = function(l, v) local c, nv = act(l); if c then return true, nv end return false, v end,
    progress_bar = function(_, _, o) seen[#seen + 1] = o or '' end, begin_child_window = function() return true end, end_child_window = function() end,
    set_next_window_size = function() end, begin_window = function() return true end, end_window = function() end,
}
local function frame_tick(n)
    for _ = 1, n or 1 do
        T = T + 1 / 60
        cb.pre.UpdateMotion(); cb.post.LateUpdateBehavior(); cb.pre.PrepareRendering(); cb.post.PrepareRendering()
    end
end
local function draw() seen = {}; for _, f in ipairs(cb.draw) do f() end; for _, f in ipairs(cb.frame) do f() end end
local function seen_has(s) for _, t in ipairs(seen) do if t:find(s, 1, true) then return true end end return false end

-- run ------------------------------------------------------------------------------------------
files['RE4R_ShapeKeySystem_native_leon.json'] = F.native
files['RE4R_ShapeKeySystem_settings.json'] = {source = 1}      -- manual-only for the first part
dofile(panel_path)
frame_tick(3)
draw()
check(seen_has('已绑定'), 'binds to the head mesh by hash')
local jaw_ch; for i, h in ipairs(F.order) do if h == (function() for _, k in ipairs(F.profile.keys) do if k.id == 'SK__arkit.jawOpen' then return k.hash end end end)() then jaw_ch = i - 1 end end
check(jaw_ch == 149, 'jawOpen resolves to channel 149 (got ' .. tostring(jaw_ch) .. ')')
check(lod == 1, 'no LOD change and no writes before the user enables driving')
check(#writes == 0, 'nothing written before enabling')
actions['启用驱动##sks_en'] = true; draw(); frame_tick(1)
check(lod == 0, 'LOD forced to 0 while enabled')
-- native taps must never be written
writes = {}
-- set jawOpen via the key page
actions['[形态键]'] = nil
actions['形态键##sks_tab2'] = true; draw()
actions['张嘴  (jawOpen)'] = 0.8; draw()
frame_tick(2)
check(math.abs(weights[jaw_ch] - 0.8) < 1e-9, 'jawOpen slider writes 0.8 (got ' .. tostring(weights[jaw_ch]) .. ')')
local tap_written = false
for _, w in ipairs(writes) do if w[1] < 91 then tap_written = true end end
check(not tap_written, 'never writes native tap channels')
-- global strength and mouth region strength scale it
actions['表情##sks_tab1'] = true; draw()
actions['表情强度##sks_str'] = 0.5; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.4) < 1e-9, 'expression strength scales weight (got ' .. tostring(weights[jaw_ch]) .. ')')
T = T + 1
actions['嘴 强度'] = 0.5; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.2) < 1e-9, 'region strength scales weight (got ' .. tostring(weights[jaw_ch]) .. ')')
-- compare neutral
actions['对比初始'] = true; draw(); frame_tick(1)
check(weights[jaw_ch] == 0, 'compare-neutral shows zero')
actions['对比初始'] = false; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.2) < 1e-9, 'compare-neutral off restores')
-- undo restores previous region strength
actions['形态键##sks_tab2'] = true; draw()
T = T + 1
actions['撤销##sks_undo'] = true; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.4) < 1e-9, 'undo restores region strength (got ' .. tostring(weights[jaw_ch]) .. ')')
actions['重做##sks_redo'] = true; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.2) < 1e-9, 'redo re-applies (got ' .. tostring(weights[jaw_ch]) .. ')')
-- presets
actions['##sks_newname'] = 'smile'; draw()
actions['另存为新预设'] = true; draw()
check(files['RE4R_ShapeKeySystem_presets.json'] and files['RE4R_ShapeKeySystem_presets.json'].smile ~= nil, 'save-as writes preset file')
actions['归零##sks_zero'] = true; draw(); frame_tick(1)
check(weights[jaw_ch] == 0, 'zero clears weights')
actions['载入##sks_load'] = true; draw(); frame_tick(1)
check(math.abs(weights[jaw_ch] - 0.2) < 1e-9, 'load preset restores (got ' .. tostring(weights[jaw_ch]) .. ')')
-- disable: zeros written, ownership probe reads 0 when nothing else writes
actions['启用驱动##sks_en'] = false; draw(); frame_tick(80)
check(weights[jaw_ch] == 0, 'disable zeros custom channels')
actions['调试##sks_tab4'] = true; draw()
check(seen_has('原生动画不写它们'), 'ownership probe reports untouched custom keys')
weights[jaw_ch] = 0.33; frame_tick(12); draw()
check(seen_has('有自定义键被写入'), 'ownership probe detects a foreign write')
weights[jaw_ch] = 0
-- native tap readout
weights[18] = 0.5; frame_tick(12); draw()
check(seen_has('jaw') or seen_has('0.500'), 'native tap activity listed')
weights[18] = 0
-- re-enable and sweep
actions['启用驱动##sks_en'] = true; draw()
actions['巡检##sks_tab3'] = true; draw()
actions['开始逐键巡检'] = true; draw()
frame_tick(36)       -- ~0.6 s of a 1.2 s period -> first key near peak
local first = F.order[92]; local first_ch = 91
check(weights[first_ch] > 0.9, 'sweep drives first key to ~1 (got ' .. tostring(weights[first_ch]) .. ')')
check(weights[jaw_ch] == 0, 'sweep isolates one key')
frame_tick(60)
check(weights[first_ch] < 0.2, 'sweep moves on from first key')
actions['停止##sks_swstop'] = true; draw(); frame_tick(1)
-- head swap -> rebinding
mesh_present = false; frame_tick(70); draw()
check(seen_has('变化') or seen_has('未找到'), 'detects head change')
mesh_present = true; frame_tick(100); draw()
check(seen_has('已绑定'), 'rebinds after head returns')
-- script reset zeros
frame_tick(2)
for _, f in ipairs(cb.reset) do f() end
local nonzero = false
for i = 91, #F.order - 1 do if weights[i] ~= 0 then nonzero = true end end
check(not nonzero, 'script reset zeros all custom channels')
check(files['RE4R_ShapeKeySystem_settings.json'] ~= nil, 'settings saved')
-- engine weight array shorter than channel table: writes past it must be refused
WEIGHT_COUNT = 91
actions['重新扫描头部'] = true; actions['调试##sks_tab4'] = true; draw(); frame_tick(100); draw()
check(seen_has('超出权重数组'), 'warns when keys exceed the weight array')
writes = {}
actions['形态键##sks_tab2'] = true; draw(); actions['张嘴  (jawOpen)'] = 1; draw(); frame_tick(3)
local beyond = false
for _, w in ipairs(writes) do if w[1] >= 91 then beyond = true end end
check(not beyond, 'never writes past the weight array')
-- periodic re-read + experimental resize lifts the block
WEIGHT_COUNT = 0; frame_tick(70); actions['调试##sks_tab4'] = true; draw()
check(seen_has('被禁止的键=86'), 'WeightCount 0 blocks all keys (re-read periodically)')
actions['手动：设置 WeightCount'] = true; draw(); frame_tick(2)
check(WEIGHT_COUNT == #F.order, 'manual button resizes weight array')
writes = {}; frame_tick(2)
local wrote_jaw = false
for _, w in ipairs(writes) do if w[1] == 149 then wrote_jaw = true end end
check(wrote_jaw, 'writes resume after resize')
-- lazy allocation: count drops to 0 between refreshes -> the very next write batch must be skipped
WEIGHT_COUNT = 0; writes = {}; frame_tick(1)
check(#writes == 0, 'per-frame check skips writes when the array shrinks to 0')
WEIGHT_COUNT = #F.order; frame_tick(2)
local resumed = false
for _, w in ipairs(writes) do if w[1] == 149 then resumed = true end end
check(resumed, 'writes resume as soon as the array is allocated')
-- native signal page: joints resolved, jaw rotation measured, recording saved with taps
actions['信号##sks_tab5'] = true; draw(); frame_tick(2); draw()
check(seen_has('找到 35 / 35'), 'signal page finds the 35 face joints')
JOINT.C_Jaw.q = {x = math.sin(math.rad(5)), y = 0, z = 0, w = math.cos(math.rad(5))}   -- 10 degrees
frame_tick(2); draw()
local jaw_seen = false
for _, t in ipairs(seen) do if t:find('C_Jaw', 1, true) and t:find('10.00', 1, true) then jaw_seen = true end end
check(jaw_seen, 'jaw rotation shown as 10 degrees')
actions['##sks_siglabel'] = 'idle'; draw()
actions['开始录制'] = true; draw()
weights[18] = 0.35
frame_tick(60)       -- ~1 s at 60 fps -> ~20 samples
actions['停止并保存'] = true; draw()
local rec = files['RE4R_ShapeKeySystem_signals_01.json']
check(rec and #rec.samples >= 15 and #rec.samples <= 25, 'recording ~20 Hz (got ' .. tostring(rec and #rec.samples) .. ')')
check(rec and #rec.samples[1].j == 35 * 7 and rec.label == 'idle', 'sample holds 35 joints x 7 values and the label')
check(rec and rec.samples[5].taps['jaw_openExtreme'] == 0.35, 'native tap weights recorded')
weights[18] = 0
-- native animation source: put the rig at its recorded neutral, then close the left eyelid by 20.5 deg
actions['启用驱动##sks_en'] = true; draw()
actions['归零##sks_zero'] = true; actions['形态键##sks_tab2'] = true; draw()
for n, jm in pairs(F.native.joints) do
    local p = jm.neutral
    JOINT[n] = {p = {x = p[1], y = p[2], z = p[3]}, q = {x = p[4], y = p[5], z = p[6], w = p[7]}}
end
actions['表情##sks_tab1'] = true; draw()
actions['表情来源##sks_src'] = 2; draw()
actions['表情强度##sks_str'] = 1.0; draw(); T = T + 1
actions['眼 强度'] = 1.0; draw(); T = T + 1
actions['嘴 强度'] = 1.0; draw()
frame_tick(2)
local blink_ch, jaw_id
for i, h in ipairs(F.order) do for _, k in ipairs(F.profile.keys) do if k.hash == h and k.id == 'SK__arkit.eyeBlinkLeft' then blink_ch = i - 1 end end end
check(weights[blink_ch] == 0, 'neutral rig -> no native blink (got ' .. tostring(weights[blink_ch]) .. ')')
do  -- rotate L_U_Eyelid3 about its principal axis by 20.5 deg relative to neutral: q = n * dq
    local jm = F.native.joints['L_U_Eyelid3']; local a, n = jm.axis, jm.neutral
    local h = math.rad(20.5) / 2; local dx, dy, dz, dw = a[1] * math.sin(h), a[2] * math.sin(h), a[3] * math.sin(h), math.cos(h)
    local x = n[7] * dx + n[4] * dw + n[5] * dz - n[6] * dy
    local y = n[7] * dy - n[4] * dz + n[5] * dw + n[6] * dx
    local z = n[7] * dz + n[4] * dy - n[5] * dx + n[6] * dw
    local w = n[7] * dw - n[4] * dx - n[5] * dy - n[6] * dz
    JOINT.L_U_Eyelid3.q = {x = x, y = y, z = z, w = w}
end
frame_tick(2)
check(math.abs(weights[blink_ch] - 0.7) < 0.01, 'eyelid 20.5 deg -> eyeBlinkLeft 0.70 (got ' .. tostring(weights[blink_ch]) .. ')')
weights[18] = 0.5 + 0.02   -- jaw_openExtreme tap above rest
frame_tick(1)
local jaw = 149
check(weights[jaw] > 0.4, 'native jaw_openExtreme tap drives jawOpen (got ' .. tostring(weights[jaw]) .. ')')
actions['表情来源##sks_src'] = 1; draw(); frame_tick(2)
check(weights[blink_ch] == 0 and weights[jaw] == 0, 'manual source ignores native animation')
-- face capture source: RhyLive snapshot -> ARKit keys 1:1, RhyLive gains reused, dropout handling
local SNAP = {running = true, sequence = 0, age_ms = 10, values = {}}
rhylive_native = {poll = function() return SNAP end}
files['RhyLiveFace_settings.json'] = {gains = {jawOpen = 1.5}}
actions['表情来源##sks_src'] = 4; draw()
for i = 1, 12 do SNAP.sequence = SNAP.sequence + 1; SNAP.values = {jawOpen = 0.6, eyeBlinkLeft = 0.8}; frame_tick(1) end
check(math.abs(weights[jaw] - 0.9) < 0.01, 'capture jawOpen 0.6 x RhyLive gain 1.5 -> 0.9 (got ' .. tostring(weights[jaw]) .. ')')
check(math.abs(weights[blink_ch] - 0.8) < 0.01, 'capture eyeBlinkLeft 1:1 (got ' .. tostring(weights[blink_ch]) .. ')')
draw(); check(seen_has('面捕数据正常'), 'capture status shown')
SNAP.age_ms = 5000; frame_tick(40)
check(weights[jaw] < 0.05, 'capture dropout eases back to neutral (got ' .. tostring(weights[jaw]) .. ')')
actions['表情来源##sks_src'] = 5; draw(); frame_tick(2)
check(math.abs(weights[blink_ch] - 0.7) < 0.01, 'source 5 falls back to native animation while capture is down (got ' .. tostring(weights[blink_ch]) .. ')')
SNAP.age_ms = 10
for i = 1, 12 do SNAP.sequence = SNAP.sequence + 1; SNAP.values = {eyeBlinkLeft = 0.1}; frame_tick(1) end
check(math.abs(weights[blink_ch] - 0.1) < 0.02, 'source 5 uses capture again when it resumes (got ' .. tostring(weights[blink_ch]) .. ')')
SNAP.running = false; frame_tick(1); draw()
check(seen_has('接收器未启动'), 'receiver-stopped status shown')
-- 0.4.4 api: cap_smooth get/set
do
    local api = rawget(_G, 'RE4R_ShapeKeySystem_api')
    check(api.version == '0.4.4', 'api.version 0.4.4 (got ' .. tostring(api.version) .. ')')
    check(math.abs(api.get_cap_smooth() - 0.5) < 1e-9, 'cap_smooth default 0.5 (got ' .. tostring(api.get_cap_smooth()) .. ')')
    check(api.set_cap_smooth(0.8) == true and math.abs(api.get_cap_smooth() - 0.8) < 1e-9, 'set_cap_smooth 0.8')
    api.set_cap_smooth(5); check(api.get_cap_smooth() == 1, 'set_cap_smooth clamps high to 1')
    api.set_cap_smooth(-1); check(api.get_cap_smooth() == 0.05, 'set_cap_smooth clamps low to 0.05')
    api.set_cap_smooth(0.3)
    check(api.set_cap_smooth(0/0) == false and api.set_cap_smooth(math.huge) == false and api.set_cap_smooth('x') == false and api.set_cap_smooth(nil) == false,
        'set_cap_smooth rejects NaN/inf/non-number')
    check(math.abs(api.get_cap_smooth() - 0.3) < 1e-9, 'rejected values leave setting unchanged')
    frame_tick(70)
    check(files['RE4R_ShapeKeySystem_settings.json'].cap_smooth == 0.3, 'API smoothing value persists to settings')
    actions['表情##sks_tab1'] = true; draw()
    actions['面捕跟随速度（越小越平滑）##sks_csm'] = 0.65; draw()
    check(api.get_cap_smooth() == 0.65, 'panel slider updates the API smoothing value')
    frame_tick(70)
    check(files['RE4R_ShapeKeySystem_settings.json'].cap_smooth == 0.65, 'panel smoothing value persists to settings')
end
print(string.format('PANEL_TESTS %d passed, %d failed', pass, fail))
if fail > 0 then os.exit(1) end
