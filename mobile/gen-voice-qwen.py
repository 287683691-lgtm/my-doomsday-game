# gen-voice-qwen.py：批量生成台词配音（voice/<key>.wav，24000Hz/mono/16bit）
# 台词表唯一真源 = gen-audio.ps1 里的 $lines 键表，本脚本直接解析它，不另抄一份。
# 三条音色通路（route()）：
#   Andre  —— 首页 4 句；Ryan —— 报幕/旁白（地图名 bg_*、僵尸图鉴 zb_*、衣服 uf_*、test）。
#   龙火火 —— 游戏内战斗播报，走 qwen-audio-3.1-tts-flash + instruction 带情绪。
#     为什么连 BOSS 名、武器名、数字也归它：say() 是多个 clip 连播成一句话的
#     （如 ['di',n,'guanwin',n,'guan']＝「第 2 关打赢啦马上进入第 3 关」），
#     一条链里换嗓子就是句子中间变声，所以整条链必须同音色。
# 头尾静音裁剪与原 Trim-WavSilence 同参数（尾留 0.12s、头留 0.05s），保证 say() 连播不留长停顿。
# 用法（cwd=项目根）：python mobile/gen-voice-qwen.py [--only k1,k2] [--no-sync] [--routes]
import argparse, concurrent.futures, json, os, re, shutil, struct, sys, time
import array
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILL_SCRIPTS = Path.home() / '.trae-cn' / 'skills' / 'qwencloud-audio-tts' / 'scripts'
sys.path.insert(0, str(SKILL_SCRIPTS))
os.chdir(ROOT)  # 让 qwencloud_lib 从项目根读到 .env

VOICE_MAIN = 'Ryan'
VOICE_MENU = 'Andre'
VOICE_HERO = 'longhuohuo_v3.1'
MENU_KEYS = {'mymd', 'tagline', 'char_thin', 'char_fat'}
MODEL = 'qwen3-tts-flash'
MODEL_HERO = 'qwen-audio-3.1-tts-flash'
# 报幕/旁白保持 Ryan：地图名、僵尸图鉴按前缀整族排除，衣服与语音测试单独列
NARRATOR_PREFIX = ('bg_', 'zb_')
NARRATOR_KEYS = {'uf_ranger', 'uf_rift', 'uf_mecha', 'uf_king', 'uf_only', 'test'}
# 情绪档：instruction 只在龙火火通路上生效，flat＝不传指令（报幕片段混在各种句子里，中性读法最稳）
EMU = {
    'cheer': '用非常开心、兴奋的语气说，音调上扬，像在欢呼，语速稍快',
    'low': '用低沉、心疼的语气说，音量放轻、语速放慢，最后带一点鼓励',
    'tense': '用紧张急迫的警报语气说，短促有力，音调先压低再骤然上扬',
    'bright': '用轻快热情、笑意盈盈的语气说，语调活泼，语速中等偏快',
    'snap': '像在报数一样快速清晰地读，语速快，尾音立刻收住，不要有任何停顿',
    'flat': '',
}
EMO_MAP = {
    **{k: 'cheer' for k in ('guanwin', 'next', 'congrats', 'allok', 'allok3', 'allok4', 'gift')},
    # 拼接片段（第/关/分/数字/量词）单独念时会被拖长（'di' 实测 0.43s→1.31s），统一报数式快读
    **{k: 'snap' for k in ('di', 'guan', 'fen', 'gejb', 'huancha',
                           *[f'n{i}' for i in (*range(10), 10, 20, 30, 40, 50, 60, 70, 80, 90)])},
    **{k: 'bright' for k in ('welcome', 'choose', 'choosewin', 'chooseend', 'zaidian', 'maidaola',
                             'jixu', 'shieldup', 'star1', 'star2', 'star3',
                             'unlock_a', 'unlock_b', 'unlock_c', 'unlock_d')},
    **{k: 'tense' for k in ('coming', 'zhugong', 'rage1', 'rage2', 'unite', 'unite3',
                            'warn_furnace', 'warn_hammer', 'warn_drag', 'warn_piston',
                            'warn_drill', 'warn_hangar', 'warn_overlord')},
    'over': 'low',
}
TAIL_SEC, HEAD_SEC = 0.12, 0.05
SYNC_DIRS = [ROOT / 'mobile' / 'www' / 'voice',
             ROOT / 'mobile' / 'android' / 'app' / 'src' / 'main' / 'assets' / 'public' / 'voice']
OUT = ROOT / 'voice'


def load_lines():
    """从 gen-audio.ps1 解析 $lines = [ordered]@{...} 键表。"""
    text = (ROOT / 'mobile' / 'gen-audio.ps1').read_text(encoding='utf-8-sig')
    m = re.search(r"\$lines\s*=\s*\[ordered\]@\{(.*?)\n\}", text, re.S)
    if not m:
        raise RuntimeError('gen-audio.ps1 里没找到 $lines 键表')
    pairs = re.findall(r"'([^']+)'\s*=\s*'([^']*)'", m.group(1))
    lines = dict(pairs)
    if len(lines) != 133:
        raise RuntimeError(f'键表数量异常：{len(lines)}（应为 133）')
    return lines


def route(key):
    """键 → (音色, 模型, 情绪档)。"""
    if key in MENU_KEYS:
        return VOICE_MENU, MODEL, ''
    if key.startswith(NARRATOR_PREFIX) or key in NARRATOR_KEYS:
        return VOICE_MAIN, MODEL, ''
    return VOICE_HERO, MODEL_HERO, EMO_MAP.get(key, 'flat')


def check_routes(lines):
    """EMO_MAP 打错一个字母就会静默漏掉一句情绪，这里硬校验；顺带返回各通路键数。"""
    unknown = sorted(set(EMO_MAP) - set(lines))
    if unknown:
        raise RuntimeError(f'EMO_MAP 里有台词表不存在的键：{unknown}')
    stat = {}
    for k in lines:
        v, _, e = route(k)
        stat[f'{v}/{e or "—"}'] = stat.get(f'{v}/{e or "—"}', 0) + 1
    return stat


# ---------- WAV：解析 / 裁剪 / 重写 ----------
def wav_parse(data):
    """返回 (sr, ch, bits, samples_offset, samples_len)；失败返回 None。"""
    if len(data) < 44 or data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        return None
    pos, sr, ch, bits, off, ln = 12, 0, 0, 0, -1, 0
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        sz = struct.unpack('<I', data[pos + 4:pos + 8])[0]
        if cid == b'fmt ':
            fmt = data[pos + 8:pos + 24]
            _, ch, sr = struct.unpack('<HHI', fmt[:8])
            bits = struct.unpack('<H', fmt[14:16])[0]
        elif cid == b'data':
            off = pos + 8
            ln = min(sz, len(data) - off)
            break
        pos += 8 + sz + (sz & 1)
    if off < 0 or sr <= 0 or ch < 1 or bits != 16:
        return None
    return sr, ch, bits, off, ln


def wav_write(path, sr, ch, samples):
    raw = samples.tobytes()
    hdr = (b'RIFF' + struct.pack('<I', 36 + len(raw)) + b'WAVE'
           + b'fmt ' + struct.pack('<IHHIIHH', 16, 1, ch, sr, sr * ch * 2, ch * 2, 16)
           + b'data' + struct.pack('<I', len(raw)))
    path.write_bytes(hdr + raw)


def trim_file(path):
    """裁头尾静音，返回 (时长s, 峰值, 是否异常)。"""
    data = path.read_bytes()
    info = wav_parse(data)
    if not info:
        return -1.0, 0, '格式异常'
    sr, ch, _, off, ln = info
    sm = array.array('h')
    sm.frombytes(data[off:off + ln - (ln % 2)])
    n = len(sm)
    if n == 0:
        return 0.0, 0, '空音频'
    peak = max(max(sm), -min(sm))
    if peak == 0:
        return n / sr, 0, '全静音'
    thr = max(48, int(peak * 0.02))
    win = max(1, sr // 500)  # 2ms 窗口
    first, last = -1, -1
    for i in range(0, n - win + 1, win):
        seg = sm[i:i + win]
        if max(seg) > thr or -min(seg) > thr:
            if first < 0:
                first = i
            last = i + win
    if first < 0:
        return n / sr, peak, '全静音'
    ks = max(0, first - int(sr * HEAD_SEC))
    ke = min(n, last + int(sr * TAIL_SEC))
    if ks or ke < n:
        wav_write(path, sr, ch, sm[ks:ke])
    return (ke - ks) / sr, peak, ''


# ---------- TTS ----------
def synth(key, text, api_key, urls):
    voice, model, emo = route(key)
    inp = {'text': text, 'voice': voice}
    if model == MODEL:
        inp['language_type'] = 'Chinese'
    else:                       # 龙火火走 SpeechSynthesizer：得显式声明落盘格式，情绪只写在 instruction 里
        inp['format'], inp['sample_rate'] = 'wav', 24000
        if EMU[emo]:
            inp['instruction'] = EMU[emo]
    payload, url = {'model': model, 'input': inp}, urls[model]
    from qwencloud_lib import http_request, download_file
    tmp = OUT / f'_tmp_{key}.wav'
    dst = OUT / f'{key}.wav'
    err = ''
    for attempt in range(3):
        try:
            resp = http_request('POST', url, api_key, payload, timeout=90)
            audio_url = (resp.get('output') or {}).get('audio', {}).get('url')
            if not audio_url:
                raise RuntimeError(f'响应无 audio.url: {json.dumps(resp, ensure_ascii=False)[:200]}')
            download_file(audio_url, tmp)
            dur, peak, flag = trim_file(tmp)
            if flag:
                raise RuntimeError(flag)
            os.replace(tmp, dst)
            return {'key': key, 'voice': voice, 'emo': emo or '—',
                    'dur': round(dur, 2), 'peak': peak, 'ok': True}
        except Exception as e:
            err = str(e)[:160]
            time.sleep(1.5 * (attempt + 1))
    if tmp.exists():
        tmp.unlink()
    return {'key': key, 'voice': voice, 'emo': emo or '—', 'ok': False, 'err': err}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='仅重生成这些键（逗号分隔）')
    ap.add_argument('--no-sync', action='store_true', help='不同步到 mobile/www 与 android assets')
    ap.add_argument('--routes', action='store_true', help='只打印音色/情绪分流表，不调接口')
    args = ap.parse_args()

    lines = load_lines()
    stat = check_routes(lines)
    if args.routes:
        for k in sorted(stat):
            print(f'{stat[k]:4d}  {k}')
        print(f'合计 {sum(stat.values())} 句')
        return

    from qwencloud_lib import require_api_key, native_base_url
    api_key = require_api_key(script_file=__file__, domain='TTS')
    base = native_base_url()
    urls = {MODEL: base + '/services/aigc/multimodal-generation/generation',
            MODEL_HERO: base + '/services/audio/tts/SpeechSynthesizer'}

    keys = [k.strip() for k in args.only.split(',')] if args.only else list(lines)
    OUT.mkdir(exist_ok=True)
    t0 = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        futs = [ex.submit(synth, k, lines[k], api_key, urls) for k in keys]
        for i, f in enumerate(concurrent.futures.as_completed(futs), 1):
            r = f.result()
            results.append(r)
            tag = 'OK ' if r['ok'] else 'FAIL'
            print(f"[{i}/{len(keys)}] {tag} {r['key']:13s} {r['voice']}/{r['emo']:6s} "
                  f"{'%.2fs' % r['dur'] if r['ok'] else r['err']}", flush=True)

    # 校验产物：全量读一遍格式
    bad = []
    for r in results:
        p = OUT / f"{r['key']}.wav"
        if not r['ok'] or not p.exists():
            bad.append(r['key'])
            continue
        info = wav_parse(p.read_bytes())
        if not info or info[0] != 24000 or info[1] != 1 or r['dur'] < 0.15:
            bad.append(f"{r['key']}(fmt={info[:3] if info else None} dur={r['dur']})")
    fails = [r for r in results if not r['ok']]
    durs = sorted(r['dur'] for r in results if r['ok'])
    print(f"\n完成 {len(results) - len(fails)}/{len(results)}，用时 {time.time() - t0:.0f}s")
    if durs:
        print(f"时长 min={durs[0]:.2f}s med={durs[len(durs)//2]:.2f}s max={durs[-1]:.2f}s")
    if bad:
        print('异常清单：', ', '.join(map(str, bad)))

    report = Path(os.environ.get('TEMP', '.')) / 'mymd' / 'regen_report.json'
    report.parent.mkdir(exist_ok=True)
    report.write_text(json.dumps(sorted(results, key=lambda x: x['key']), ensure_ascii=False, indent=1),
                      encoding='utf-8')

    # 同步三处目录（只覆盖本次生成的台词键，音效/BGM 不动）
    if not args.no_sync and not fails:
        for d in SYNC_DIRS:
            d.mkdir(parents=True, exist_ok=True)
            for k in keys:
                shutil.copy2(OUT / f'{k}.wav', d / f'{k}.wav')
            print(f"已同步 {len(keys)} 句 → {d.relative_to(ROOT)}")
    if fails:
        sys.exit(1)


if __name__ == '__main__':
    main()
