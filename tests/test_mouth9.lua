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
    get_BlendShapeChannelNum = function() return CHANNEL_NUM or #F.order end,
    get_ChannelNameHash = function() return hash_array end,
    setBlendShapeChannelWeightParam = function(i, w) weights[i] = w; writes[#writes + 1] = {i, w} end,
    getBlendShapeChannelWeightParam = function(i) if READ_FAIL == i then error('mock read failure') end; assert(i < (WEIGHT_COUNT or #F.order) and i < (LIST_LEN or #F.order), 'unsafe read'); return weights[i] end,
    set_LodLevel = function(v) lod = v end, get_LodLevel = function() return lod end,
    get_UseBlendShapeNormal = function() return true end,
    get_BlendShapeChannelWeightCount = function() return WEIGHT_COUNT or #F.order end,
    set_BlendShapeChannelWeightCount = function(n) WEIGHT_COUNT = n end,
    get_ChannelWeightList = function() return obj({get_Length = function() return LIST_LEN or #F.order end}, 300) end}, 200)
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

files[F.profile.native_map_file] = F.native
files['RE4R_ShapeKeySystem_settings.json'] = {source = 1}
dofile(panel_path); frame_tick(4)
local api = RE4R_ShapeKeySystem_api
check(api.native_map_status().file == F.profile.native_map_file and api.native_map_status().loaded, 'selects optional mapping')
check(#api.native_tap_status() == 9, 'only selected nine receivers diagnosed')
local function channel(hash) for i,h in ipairs(F.order) do if h == hash then return i-1 end end end
local tap_ch = channel(F.profile.native_taps[1].hash)
local target = F.profile.keys[1]
local custom_ch = channel(target.hash)
for _, t in ipairs(api.native_tap_status()) do check(t.bound and t.state == 'ok' and t.value == 0, 'confirmed zero: '..t.short) end
weights[tap_ch] = 0.2
check(api.native_tap_status()[1].value == 0.2, 'reads selected receiver at hash-bound index')
READ_FAIL = tap_ch
check(api.native_tap_status()[1].state == 'read_failed' and api.native_tap_status()[1].value == nil, 'read failure distinct from zero')
READ_FAIL = nil
WEIGHT_COUNT = 0
check(api.native_tap_status()[1].state == 'out_of_bounds', 'zero WeightCount blocks receiver reads')
actions['启用驱动##sks_en'] = true; draw(); writes = {}; frame_tick(2)
check(#writes == 0, 'zero WeightCount blocks all custom writes')
LIST_LEN = 0; actions['调试##sks_tab4'] = true; draw()
actions['手动：设置 WeightCount'] = true; draw()
check(WEIGHT_COUNT == 0, 'manual allocation rejected before weight list ready')
LIST_LEN = #F.order; actions['手动：设置 WeightCount'] = true; draw()
check(WEIGHT_COUNT == #F.order, 'manual allocation succeeds with full list')
actions['形态键##sks_tab2'] = true; draw()
actions[target.label .. '  (' .. target.name .. ')'] = 0.6; draw(); frame_tick(2)
check(math.abs(weights[custom_ch] - 0.6) < 1e-6, 'manual custom key remains available')
LIST_LEN = 0; writes = {}; frame_tick(1)
check(#writes == 0 and not api.mesh_status()[1].ready, 'shrinking WeightList immediately blocks writes and readiness')
LIST_LEN = #F.order
-- Same mesh address, new channel order: do not retain stale tap indices.
F.order[1], F.order[#F.order] = F.order[#F.order], F.order[1]
actions['调试##sks_tab4'] = true; draw(); actions['重新扫描头部'] = true; draw(); frame_tick(100)
tap_ch = channel(F.profile.native_taps[1].hash)
weights[tap_ch] = 0.25
check(api.native_tap_status()[1].channel == tap_ch and api.native_tap_status()[1].value == 0.25, 'rebind follows hash after index changes')
-- Lose a selected tap: report unbound; unselected original channels are irrelevant.
F.order[tap_ch+1] = 1234567
actions['重新扫描头部'] = true; draw(); frame_tick(100)
check(api.native_tap_status()[1].state == 'unbound' and not api.native_tap_status()[1].bound, 'selected missing receiver reported unbound')
F.order[tap_ch+1] = F.profile.native_taps[1].hash
actions['重新扫描头部'] = true; draw(); frame_tick(100)
-- Native jaw synthesis: bone signal 0.25 plus tap 0.25, unchanged gain, no NoTap multiplier.
for name, jm in pairs(F.native.joints) do
    local p = jm.neutral
    JOINT[jm.bone or name] = {p={x=p[1],y=p[2],z=p[3]},q={x=p[4],y=p[5],z=p[6],w=p[7]}}
end
local chin = F.native.joints.C_Chin
local rule; for _, r in ipairs(F.native.rules) do if r.joint == 'C_Chin' and r.key == 'jawOpen' then rule=r end end
local signal = rule.lo + (rule.hi-rule.lo)*0.25
JOINT.C_Chin.p = {x=chin.neutral[1]+chin.axis[1]*signal/1000,y=chin.neutral[2]+chin.axis[2]*signal/1000,z=chin.neutral[3]+chin.axis[3]*signal/1000}
actions['归零##sks_zero'] = true; draw()
actions['表情##sks_tab1'] = true; draw(); actions['表情来源##sks_src'] = 2; draw(); frame_tick(3)
local jaw, jaw_gain; for _, k in ipairs(F.profile.keys) do if k.arkit then for _, m in ipairs(k.arkit) do if m[1]=='jawOpen' then jaw=k; jaw_gain=m[2] end end end end
check(jaw and math.abs(weights[channel(jaw.hash)] - 0.5*jaw_gain)<0.002, 'jaw bone plus tap synthesis retains profile gain, without extra 3x')
writes = {}; frame_tick(3)
local native_write=false
for _,w in ipairs(writes) do for _,t in ipairs(F.profile.native_taps) do if w[1]==channel(t.hash) then native_write=true end end end
check(not native_write, 'no receiver weights written')
CHANNEL_NUM = 0; writes={}; frame_tick(1)
check(#writes==0 and api.native_tap_status()[1].state=='out_of_bounds', 'ChannelNum shrink blocks reads and writes')
CHANNEL_NUM = nil
-- Face capture still targets the custom semantic key on the mouth9 model.
rhylive_native={poll=function() return {running=true,age_ms=10,sequence=frame_seq or 1,values={jawOpen=0.2}} end}
actions['表情来源##sks_src']=4; draw()
for i=1,20 do frame_seq=i; frame_tick(1) end
check(math.abs(weights[channel(jaw.hash)]-0.2*jaw_gain)<0.002, 'RhyLive snapshot drives mouth9 custom key')
-- Defensive profile: even a key accidentally listed as a native receiver is never written.
F.profile.keys[#F.profile.keys+1]={id=F.profile.native_taps[1].name,hash=F.profile.native_taps[1].hash,name='jawOpen',library='ARKit',label='bad native key',region='mouth'}
cb={pre={},post={},draw={},frame={},reset={}}; dofile(panel_path); frame_tick(4)
actions['启用驱动##sks_en']=true; draw(); writes={}; frame_tick(3)
native_write=false
for _,w in ipairs(writes) do for _,t in ipairs(F.profile.native_taps) do if w[1]==channel(t.hash) then native_write=true end end end
check(not native_write, 'profile overlap cannot write a native receiver')
table.remove(F.profile.keys)
-- Missing selected map must not silently load legacy mapping.
F.profile.native_map_file = 'missing.json'; files['RE4R_ShapeKeySystem_native_leon.json']=F.native
cb = {pre={},post={},draw={},frame={},reset={}}; dofile(panel_path)
check(not RE4R_ShapeKeySystem_api.native_map_status().loaded, 'missing selected map never falls back silently')
-- NoTap profile remains valid and old default is retained when optional selection is omitted.
F.profile.native_taps={}; F.profile.native_map_file=nil
cb = {pre={},post={},draw={},frame={},reset={}}; dofile(panel_path); frame_tick(4)
check(#RE4R_ShapeKeySystem_api.native_tap_status()==0 and RE4R_ShapeKeySystem_api.native_map_status().loaded, 'NoTap and legacy default map compatibility')
actions['启用驱动##sks_en']=true; draw(); writes={}; frame_tick(3)
check(#writes>0, 'NoTap profile still writes only custom keys')
print(string.format('MOUTH9_TESTS %d passed, %d failed',pass,fail))
if fail>0 then os.exit(1) end

