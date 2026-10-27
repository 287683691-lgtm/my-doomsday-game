﻿# gen-audio.ps1：预生成 APK 内置语音＋音效（voice/*.wav）
# 台词用阿里云百炼 qwen3-tts-flash 大模型配音（同目录 gen-voice-qwen.py，密钥在项目根 .env）；
# 音效按游戏里 tone()/noise() 的同一套参数用数学渲染；BGM 用同目录 bgm_master.wav（CC0 素材叠加的氛围版）直接复制。
# 改台词后重跑本脚本，再跑 build-apk.ps1 即可。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'voice'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ---------- 1) 台词（qwen3-tts-flash 大模型配音 → 24kHz 单声道 WAV） ----------
# 音色：全局 Ryan（甜茶）；首页 4 句（mymd/tagline/char_thin/char_fat）用 Andre（安德雷）。
# 下面的 $lines 键表是台词唯一真源，由 gen-voice-qwen.py 解析后逐句合成；改台词只改这里。
$lines = [ordered]@{
  'mymd'        = '我的末日'
  'tagline'     = '方块人大战方块僵尸，嵇焕宸和爸爸的第一个小游戏'
  'char_thin'   = '迷彩小战士，焕宸'
  'char_fat'    = '冲锋战士，焕宸爸爸'
  'bg_forest'   = '发光森林'
  'bg_city'     = '破破城市'
  'bg_desert'   = '太阳沙漠'
  'bg_valley'   = '丧尸山谷'
  'bg_lava'     = '熔岩谷'
  'bg_bone'     = '白骨地'
  'bg_ice'      = '寒冰谷'
  'bg_rift'     = '合体山谷'
  'bg_junk'     = '机甲坟场'
  'bg_neon'     = '霓虹流水线'
  'bg_dome'     = '峡谷旧油库'
  'bg_core'     = '机核深渊'
  'bg_ruin'     = '落日废墟城'
  'bg_giant'    = '巨兽白骨地'
  'bg_wreck'    = '机甲残骸长廊'
  'bg_throne'   = '世界尽头的王座'
  'boss_forest' = '藤蔓僵王'
  'boss_city'   = '铁皮僵王'
  'boss_desert' = '沙暴僵王'
  'boss_furnace'= '背炉火柱王'
  'boss_hammer' = '骨锤独腿王'
  'boss_drag'   = '拖地长臂王'
  'boss_finale' = '三王合体'
  'boss_piston' = '活塞重锤王'
  'boss_drill'  = '钻头臂王'
  'boss_hangar' = '机库王'
  'boss_trio3'  = '三机王合体'
  'boss_overlord' = '末日总王'
  'unite'       = '三只大王合在一起啦！只有头顶光环的会开枪！'
  'unite3'      = '三台机甲王合体啦！只有头顶光环的会开枪！'
  'allok'       = '丧尸山谷全部打完！你就是末日小英雄！'
  'allok3'      = '机核深渊全部打完！你就是末日小英雄！'
  'allok4'      = '世界尽头全部打完！你就是真正的末日小英雄！'
  'choosewin'   = '选一个吧：回藏宝图，看看新的一块战场！'
  'chooseend'   = '选一个吧：回藏宝图，整个末日都被你打完啦！'
  'coming'      = '来啦！它会发射子弹，看到冒烟就赶紧换路躲开！'
  'warn_furnace'= '它没有手，靠背上的炉子喷火：看到冒烟和地上发红，马上换路！'
  'warn_hammer' = '它只会一跳一跳，锤子举高高就是要砸，赶紧跑远一点！'
  'warn_drag'   = '它的手拖在地上从右边扫到左边，看到路面压暗就换到没暗的那条路！'
  'warn_piston' = '它的活塞臂越压越长，橙光一闪就是要砸脚下那条路，提前换路！砸完杆子卡住，趁那一下打它的头！'
  'warn_drill'  = '它的地面钻头会扫两条路，看到路面压暗就换到没暗的那条！扫完收回那一下打它背上的散热眼！'
  'warn_hangar' = '它背上的库门开红光时，躲远子弹，趁门开着打库里的控制台！它会放浮游探针！'
  'warn_overlord' = '总王又砸锤又扫长臂，背上的炉子还喷火烧脚底下！路面发暗发红赶紧换路，它脑门红宝石一亮就使劲打！'
  'zhugong'     = '现在是它主攻！盯住它头顶的光环！'
  'zb_fire'     = '会炸火的火焰丧尸，别站太近！'
  'zb_hole'     = '破了个洞的丧尸，走得慢，血多！'
  'zb_notch'    = '缺牙丧尸，走路扭来扭去会换路！'
  'zb_oneeye'   = '独眼丧尸，会突然加速冲过来！'
  'zb_ice'      = '冰封丧尸，血最厚，用寒冰球冻它！'
  'zb_weld'     = '电焊兵，打死它会炸一圈焊花，别贴着它开枪！'
  'zb_armor'    = '重甲机兵，血厚走得慢，用大火球火箭弹揍它！'
  'zb_chain'    = '链锯突击兵，锯盘转快就会冲，血不多，冲之前解决它！'
  'zb_drone'    = '浮游探针，悬在天上乱换路，盯子弹别盯它！'
  'zb_kvine'    = '藤蔓大王当小兵啦，走路扭来扭去会换路！'
  'zb_ksteel'   = '铁皮大王当小兵啦，又硬又慢，用寒冰球冻它更划算！'
  'zb_ksand'    = '沙暴大王当小兵啦，攒一会儿劲会猛地冲过来！'
  'zb_kfurnace' = '火柱大王当小兵啦，打死它会炸一团火，别贴着它开枪！'
  'zb_khammer'  = '骨锤大王当小兵啦，块头大血又多，一梭子打不死它！'
  'zb_kdrag'    = '长臂大王当小兵啦，走两步就换路，看准了再打！'
  'zb_kpiston'  = '活塞大王当小兵啦，先慢慢走，然后猛地加速冲！'
  'zb_kdrill'   = '钻头大王当小兵啦，血厚还会换路，趁它离得远先揍它！'
  'zb_khangar'  = '机库大王当小兵啦，最硬最慢，用大火球火箭弹揍它！'
  'lock_ruin'   = '落日废墟城那一关！'
  'lock_giant'  = '巨兽白骨地那一关！'
  'lock_wreck'  = '机甲残骸长廊那一关！'
  'rage1'       = '小心！'
  'rage2'       = '狂暴啦！'
  'unlock'      = '还没解锁，先打赢'
  'di'          = '第'
  'guanwin'     = '关打赢啦！马上进入第'
  'guan'        = '关'
  'next'        = '马上进入下一关'
  'congrats'    = '恭喜你！打败了'
  'choose'      = '选一个吧：回首页，或者进下一关！'
  'over'        = '游戏结束，你得了'
  'fen'         = '分'
  'test'        = '一二三，语音测试'
  'star1'       = '送你一颗星星！'
  'star2'       = '送你两颗星星！'
  'star3'       = '送你三颗星星！'
  'welcome'     = '欢迎来到武器库！'
  'w_star'      = '星星飞镖'
  'w_bullet'    = '小子弹'
  'w_shot'      = '散弹枪'
  'w_fast'      = '快快飞镖'
  'w_triple'    = '二连飞镖'
  'w_boomer'    = '回旋镖'
  'w_ice'       = '寒冰球'
  'w_bolt'      = '雷电球'
  'w_fire'      = '大火球'
  'w_rocket'    = '火箭弹'
  'w_bomb'      = '魔法炸弹'
  'w_laser'     = '超级激光'
  'w_shield'    = '防护盾'
  'shieldup'    = '防护盾撑开啦，帮你挡三下！'
  'gift'        = '宝藏开箱啦！四十个金币，还有一面防护盾！'
  'unlock_a'    = '山谷游侠的衣服解锁啦！去首页给焕宸换上！'
  'unlock_b'    = '裂谷星铠的衣服解锁啦！去首页给焕宸换上！'
  'unlock_c'    = '星核机甲的衣服解锁啦！去首页给焕宸换上！'
  'unlock_d'    = '末日王铠的衣服解锁啦！去首页给焕宸换上！'
  'uf_ranger'   = '山谷游侠，焕宸！'
  'uf_rift'     = '裂谷星铠，焕宸！'
  'uf_mecha'    = '星核机甲，焕宸！'
  'uf_king'     = '末日王铠，焕宸！'
  'uf_only'     = '衣服是给焕宸穿的，爸爸还是老样子！'
  'zaidian'     = '再点一下就买啦'
  'maidaola'    = '买到啦'
  'jixu'        = '买好啦，继续加油！'
  'huancha'     = '还差'
  'gejb'        = '个金币'
  'n0' = '零'; 'n1' = '一'; 'n2' = '二'; 'n3' = '三'; 'n4' = '四'
  'n5' = '五'; 'n6' = '六'; 'n7' = '七'; 'n8' = '八'; 'n9' = '九'
  'n10' = '十'; 'n20' = '二十'; 'n30' = '三十'
  'n40' = '四十'; 'n50' = '五十'; 'n60' = '六十'; 'n70' = '七十'; 'n80' = '八十'; 'n90' = '九十'
}
# 台词合成＋头尾静音裁剪统一在 gen-voice-qwen.py 里做（裁剪参数沿用旧 Trim-WavSilence：尾留 0.12s、头留 0.05s。
# 台词按 clip 连播，playClip 靠 ended 事件接续，头尾静音累加就是「第……2……关」之间明显的停顿，必须裁）。
# 音效是整段数学渲染的，BGM 是成品素材，节奏本身都是准的，都不裁剪、不受影响。
& python (Join-Path $PSScriptRoot 'gen-voice-qwen.py')
if ($LASTEXITCODE -ne 0) { throw '台词生成失败（qwen3-tts-flash）' }
Write-Host ('台词：' + $lines.Count + ' 句已生成')

# ---------- 2) 音效（按 tone()/noise() 同参数数学渲染 → 22.05kHz 单声道 WAV） ----------
$SR = 22050
$rnd = New-Object System.Random 20260928

function Add-Tone($buf, $len, $o) {
  $dur = [double]$o.dur
  $atk = 0.012; if ($o.Contains('atk')) { $atk = [double]$o.atk }
  $f1 = [double]$o.f; $f2 = 0.0; if ($o.Contains('f2')) { $f2 = [double]$o.f2 }
  $vol = 0.2; if ($o.Contains('vol')) { $vol = [double]$o.vol }
  $t0 = 0.0; if ($o.Contains('delay')) { $t0 = [double]$o.delay }
  $type = 'square'; if ($o.Contains('type')) { $type = $o.type }
  $n = [int][math]::Ceiling($dur * $SR)
  $ph = 0.0; $tp = 2 * [math]::PI
  for ($i = 0; $i -lt $n; $i++) {
    $t = $i / $SR
    if ($f2 -gt 0) { $fr = $f1 * [math]::Pow($f2 / $f1, $t / $dur) } else { $fr = $f1 }
    $ph += $tp * $fr / $SR
    if ($t -lt $atk) { $env = 0.0001 * [math]::Pow($vol / 0.0001, $t / $atk) }
    else { $env = $vol * [math]::Pow(0.0001 / $vol, (($t - $atk) / ($dur - $atk))) }
    if ($type -eq 'sine') { $w = [math]::Sin($ph) }
    elseif ($type -eq 'triangle') { $w = 2 / [math]::PI * [math]::Asin([math]::Sin($ph)) }
    elseif ($type -eq 'sawtooth') { $x = ($ph / $tp) % 1; $w = 2 * $x - 1 }
    else { if ([math]::Sin($ph) -ge 0) { $w = 1.0 } else { $w = -1.0 } }
    $idx = [int][math]::Floor($t0 * $SR) + $i
    if ($idx -ge 0 -and $idx -lt $len) { $buf[$idx] += $w * $env }
  }
}
function Add-Noise($buf, $len, $o) {
  $dur = [double]$o.dur
  $vol = 0.18; if ($o.Contains('vol')) { $vol = [double]$o.vol }
  $t0 = 0.0; if ($o.Contains('delay')) { $t0 = [double]$o.delay }
  $fc = [double]$o.f; $ft = 'lowpass'; if ($o.Contains('ftype')) { $ft = $o.ftype }
  $n = [int][math]::Ceiling($dur * $SR)
  $xs = New-Object double[] $n
  for ($i = 0; $i -lt $n; $i++) { $xs[$i] = ($rnd.NextDouble() * 2 - 1) * (1 - $i / $n) }
  # RBJ 双二阶滤波（Q=1，同 WebAudio BiquadFilter 默认）
  $w0 = 2 * [math]::PI * $fc / $SR; $cw = [math]::Cos($w0); $al = [math]::Sin($w0) / 2
  if ($ft -eq 'highpass') { $b0 = (1 + $cw) / 2; $b1 = -(1 + $cw); $b2 = (1 + $cw) / 2 }
  else { $b0 = (1 - $cw) / 2; $b1 = 1 - $cw; $b2 = (1 - $cw) / 2 }
  $a0 = 1 + $al; $a1 = -2 * $cw; $a2 = 1 - $al
  $b0 /= $a0; $b1 /= $a0; $b2 /= $a0; $a1 /= $a0; $a2 /= $a0
  $x1 = 0.0; $x2 = 0.0; $y1 = 0.0; $y2 = 0.0
  for ($i = 0; $i -lt $n; $i++) {
    $x = $xs[$i]
    $y = $b0 * $x + $b1 * $x1 + $b2 * $x2 - $a1 * $y1 - $a2 * $y2
    $x2 = $x1; $x1 = $x; $y2 = $y1; $y1 = $y
    $env = $vol * [math]::Pow(0.0001 / $vol, $i / $n)
    $idx = [int][math]::Floor($t0 * $SR) + $i
    if ($idx -ge 0 -and $idx -lt $len) { $buf[$idx] += $y * $env }
  }
}
function Write-Wav($path, $buf, $len) {
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)
  $enc = [System.Text.Encoding]::ASCII
  $bw.Write($enc.GetBytes('RIFF')); $bw.Write([UInt32](36 + $len * 2)); $bw.Write($enc.GetBytes('WAVE'))
  $bw.Write($enc.GetBytes('fmt ')); $bw.Write([UInt32]16); $bw.Write([UInt16]1); $bw.Write([UInt16]1)
  $bw.Write([UInt32]$SR); $bw.Write([UInt32]($SR * 2)); $bw.Write([UInt16]2); $bw.Write([UInt16]16)
  $bw.Write($enc.GetBytes('data')); $bw.Write([UInt32]($len * 2))
  for ($i = 0; $i -lt $len; $i++) {
    $v = $buf[$i]; if ($v -gt 1) { $v = 1 }; if ($v -lt -1) { $v = -1 }
    $bw.Write([Int16][math]::Round($v * 32767))
  }
  $bw.Flush(); [System.IO.File]::WriteAllBytes($path, $ms.ToArray()); $bw.Close()
}
function Gen-Sfx($name, $lenSec, $segs) {
  $len = [int][math]::Ceiling($lenSec * $SR)
  $buf = New-Object double[] $len
  foreach ($s in $segs) { if ($s.Contains('noise')) { Add-Noise $buf $len $s } else { Add-Tone $buf $len $s } }
  Write-Wav (Join-Path $out ('s_' + $name + '.wav')) $buf $len
}

# 参数与游戏 SFX 表一一对应（vol/f/dur 照抄）
Gen-Sfx 'click' 0.22 @(@{noise=1;dur=0.05;vol=0.20;f=3400;ftype='highpass'}, @{dur=0.09;f=520;f2=360;type='triangle';vol=0.20})
Gen-Sfx 'shoot' 0.20 @(@{noise=1;dur=0.06;vol=0.075;f=2600;ftype='highpass'}, @{dur=0.09;f=220;f2=120;type='triangle';vol=0.11})
Gen-Sfx 'bossshoot' 0.38 @(@{dur=0.26;f=200;f2=62;type='sawtooth';vol=0.15;atk=0.01}, @{noise=1;dur=0.20;vol=0.11;f=600})
Gen-Sfx 'hit' 0.32 @(@{dur=0.22;f=190;f2=60;type='sine';vol=0.26;atk=0.006}, @{noise=1;dur=0.10;vol=0.15;f=900})
Gen-Sfx 'boss' 0.62 @(@{dur=0.50;f=120;f2=44;type='sine';vol=0.30;atk=0.008}, @{noise=1;dur=0.26;vol=0.18;f=520})
Gen-Sfx 'hurt' 0.56 @(@{dur=0.46;f=240;f2=70;type='sine';vol=0.26;atk=0.008}, @{noise=1;dur=0.16;vol=0.12;f=600;delay=0.02})
Gen-Sfx 'win' 0.85 @(
  @{dur=0.20;f=196;f2=137;type='sine';vol=0.24;atk=0.006;delay=0.00}, @{noise=1;dur=0.05;vol=0.07;f=4000;ftype='highpass';delay=0.00},
  @{dur=0.20;f=247;f2=173;type='sine';vol=0.24;atk=0.006;delay=0.14}, @{noise=1;dur=0.05;vol=0.07;f=4000;ftype='highpass';delay=0.14},
  @{dur=0.20;f=294;f2=206;type='sine';vol=0.24;atk=0.006;delay=0.28}, @{noise=1;dur=0.05;vol=0.07;f=4000;ftype='highpass';delay=0.28},
  @{dur=0.20;f=392;f2=274;type='sine';vol=0.24;atk=0.006;delay=0.42}, @{noise=1;dur=0.05;vol=0.07;f=4000;ftype='highpass';delay=0.42})
Gen-Sfx 'over' 1.10 @(
  @{dur=0.26;f=180;f2=108;type='sine';vol=0.24;atk=0.008;delay=0.00},
  @{dur=0.26;f=150;f2=90;type='sine';vol=0.24;atk=0.008;delay=0.22},
  @{dur=0.26;f=120;f2=72;type='sine';vol=0.24;atk=0.008;delay=0.44},
  @{dur=0.26;f=90;f2=54;type='sine';vol=0.24;atk=0.008;delay=0.66})
Gen-Sfx 'fw' 0.26 @(@{dur=0.16;f=620;f2=150;type='triangle';vol=0.08}, @{noise=1;dur=0.07;vol=0.05;f=2400;ftype='highpass'})
Gen-Sfx 'coin' 0.32 @(@{dur=0.09;f=1319;type='sine';vol=0.13;atk=0.004}, @{dur=0.16;f=1760;type='sine';vol=0.11;atk=0.004;delay=0.07})
Gen-Sfx 'boom' 0.62 @(@{dur=0.50;f=130;f2=32;type='sine';vol=0.32;atk=0.006}, @{noise=1;dur=0.34;vol=0.22;f=700})
Gen-Sfx 'laserz' 0.42 @(@{dur=0.30;f=1800;f2=240;type='sawtooth';vol=0.12;atk=0.008}, @{noise=1;dur=0.16;vol=0.07;f=3200;ftype='highpass'})
Gen-Sfx 'freeze' 0.40 @(@{dur=0.18;f=988;f2=1976;type='sine';vol=0.13;atk=0.006}, @{dur=0.22;f=1480;f2=2349;type='sine';vol=0.10;atk=0.006;delay=0.06})
# 小兵吐弹：张嘴前的上行"呜——"预警 ＋ 吐出的"噗"
Gen-Sfx 'spitwarn' 0.32 @(@{dur=0.20;f=430;f2=900;type='triangle';vol=0.12;atk=0.008}, @{noise=1;dur=0.10;vol=0.05;f=2000;ftype='highpass';delay=0.02})
Gen-Sfx 'spit' 0.22 @(@{dur=0.10;f=300;f2=110;type='sine';vol=0.13;atk=0.005}, @{noise=1;dur=0.07;vol=0.08;f=1400})
# 防护盾：撑开的上行"嗡——" ＋ 挡下那一下的金属"叮！"
Gen-Sfx 'shield' 0.42 @(@{dur=0.30;f=330;f2=880;type='sine';vol=0.16;atk=0.02}, @{dur=0.26;f=495;f2=1320;type='triangle';vol=0.10;atk=0.02;delay=0.05}, @{noise=1;dur=0.18;vol=0.05;f=3000;ftype='highpass';delay=0.04})
Gen-Sfx 'block' 0.28 @(@{dur=0.10;f=1568;type='square';vol=0.13;atk=0.003}, @{dur=0.16;f=2093;f2=1568;type='sine';vol=0.11;atk=0.003;delay=0.03}, @{noise=1;dur=0.06;vol=0.06;f=4200;ftype='highpass'})

# BGM：末日氛围版成品素材（同目录 bgm_master.wav → voice/bgm.wav，28.9s 循环 / 22.05kHz 单声道 16bit）。
# 素材：Freesound CC0 —— burning-mir《action music loop with dark ambient drones》打底，
#       goulven《dark ambient loop》压低 4dB 叠在上面；接缝做过 0.12s 交叉淡化，RMS 归一到 -19 dBFS。
# 换曲子只要把新的循环 wav 覆盖 bgm_master.wav（格式必须是 22050 / mono / 16bit PCM）。
Copy-Item (Join-Path $PSScriptRoot 'bgm_master.wav') (Join-Path $out 'bgm.wav') -Force

# ---------- 3) 同步到运行时目录 ----------
# voice/ 是源，www/voice 与 android assets 的 public/voice 才是 APK 真正打包的副本；
# 音效/BGM 不在 gen-voice-qwen.py 的同步范围内（它只同步台词键），必须在这里补齐，
# 否则改了参数重跑脚本，APK 里还是旧声音。
foreach ($d in @((Join-Path $PSScriptRoot 'www\voice'), (Join-Path $PSScriptRoot 'android\app\src\main\assets\public\voice'))) {
  if (-not (Test-Path $d)) { continue }
  Copy-Item (Join-Path $out 'bgm.wav') (Join-Path $d 'bgm.wav') -Force
  foreach ($f in (Get-ChildItem $out -Filter 's_*.wav')) { Copy-Item $f.FullName (Join-Path $d $f.Name) -Force }
}

$files = Get-ChildItem $out -Filter *.wav
$mb = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 2)
Write-Host ('音效/BGM：' + (Get-ChildItem $out -Filter 's_*.wav').Count + ' 个音效 ＋ 1 个 BGM 已就绪（含 www / android 同步）')
Write-Host ('合计 ' + $files.Count + ' 个 wav，' + $mb + ' MB → ' + $out)
