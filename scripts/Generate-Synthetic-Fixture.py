"""Generate public synthetic mouth9 test data and validate bundled map contracts (stdlib only)."""
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
def hash_name(text):
    data = text.encode('utf-16-le'); h = 0xffffffff
    rotate = lambda x, r: ((x << r) | (x >> (32-r))) & 0xffffffff
    for i in range(len(data)//4):
        k = struct.unpack_from('<I', data, i*4)[0]
        k = rotate(k*0xcc9e2d51 & 0xffffffff,15)*0x1b873593 & 0xffffffff
        h = (rotate(h^k,13)*5+0xe6546b64) & 0xffffffff
    tail = data[len(data)//4*4:]
    if tail:
        k = sum(v << (8*i) for i,v in enumerate(tail))
        h ^= rotate(k*0xcc9e2d51 & 0xffffffff,15)*0x1b873593 & 0xffffffff
    h ^= len(data); h ^= h>>16; h = h*0x85ebca6b & 0xffffffff
    h ^= h>>13; h = h*0xc2b2ae35 & 0xffffffff; h ^= h>>16
    return h

assert hash_name('Face__geo__p000_cbs.crct_brow_lateral_L') == 3678951475
full = json.loads((ROOT/'data/RE4R_ShapeKeySystem_native_leon.json').read_text(encoding='utf-8-sig'))
small = json.loads((ROOT/'data/RE4R_ShapeKeySystem_native_leon_mouth9.json').read_text(encoding='utf-8-sig'))
assert len(full['rules']) == 48 and len(small['rules']) == 19
assert full['joints'] == small['joints']
assert [r for r in full['rules'] if 'joint' in r] == [r for r in small['rules'] if 'joint' in r]
for rule in small['rules']:
    assert any({k:v for k,v in rule.items() if k!='taps'} == {k:v for k,v in original.items() if k!='taps'}
        and set(rule.get('taps',[])) <= set(original.get('taps',[])) for original in full['rules'])
assert len([r for r in small['rules'] if 'joint' in r]) == 16
taps = ['jaw_openExtreme'] + ['mouth_'+kind+'_'+side+'_'+height
    for kind in ['purse','funnel'] for side in ['L','R'] for height in ['U','D']]
assert {t for r in small['rules'] for t in r.get('taps', [])} == set(taps)
for table in [full, small]:
    for rule in table['rules']:
        assert rule['lo'] != rule['hi']
        assert ('joint' in rule) != ('taps' in rule)
        if 'joint' in rule: assert rule['joint'] in table['joints']
profile = dict(format=1, model='SyntheticDemo', title='Synthetic demo (not a model)',
    native_map_file='RE4R_ShapeKeySystem_native_leon_mouth9.json',
    regions=[dict(id='mouth',label='Mouth')],
    native_taps=[dict(name='Face__geo__p000_cbs.crct_'+t,
        hash=hash_name('Face__geo__p000_cbs.crct_'+t)) for t in taps],
    keys=[dict(id=f'SK__mmd.demo{i:02d}',hash=hash_name(f'SK__mmd.demo{i:02d}'),
        label=f'Demo {i:02d}',name=f'demo{i:02d}',library='MMD',group='Demo',region='mouth',
        arkit=[['jawOpen',0.9]] if i==0 else []) for i in range(85)])
def lua(v):
    if isinstance(v,dict): return '{'+','.join('['+lua(k)+']='+lua(w) for k,w in v.items())+'}'
    if isinstance(v,list): return '{'+','.join(map(lua,v))+'}'
    if isinstance(v,str): return json.dumps(v,ensure_ascii=False)
    return repr(v)
fixture=dict(profile=profile,native=small,order=[k['hash'] for k in profile['keys']]+[t['hash'] for t in profile['native_taps']])
(ROOT/'tests/fixture_mouth9_synthetic.lua').write_text('return '+lua(fixture)+'\n',encoding='utf-8')
(ROOT/'examples').mkdir(exist_ok=True)
(ROOT/'examples/profile_mouth9_synthetic.json').write_text(json.dumps(profile,indent=2)+'\n',encoding='utf-8')
print('MAP_CONTRACT_PASS: full 48; mouth9 19; 16 unchanged bone rules; 9 tap names; synthetic fixture')
