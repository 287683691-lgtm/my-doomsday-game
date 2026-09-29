﻿# gen-audio.ps1：预生成 APK 内置语音＋音效（voice/*.wav）
# 台词用 Windows 自带中文语音（SAPI）合成；音效/BGM 按游戏里 tone()/noise() 的同一套参数用数学渲染，
# 保证 APK 里听到的和桌面浏览器完全同款。改台词后重跑本脚本，再跑 build-apk.ps1 即可。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'voice'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# ---------- 1) 台词（SAPI 中文语音 → 16kHz 单声道 WAV） ----------
Add-Type -AssemblyName System.Speech
$syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
$zh = $syn.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture -and $_.VoiceInfo.Culture.Name -like 'zh*' } | Select-Object -First 1
if (-not $zh) { throw '本机没装中文语音（SAPI），无法生成台词' }
$syn.SelectVoice($zh.VoiceInfo.Name)
$syn.Rate = -1; $syn.Volume = 100
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)

$lines = [ordered]@{
  'mymd'        = '我的末日'
  'tagline'     = '方块人大战方块僵尸，嵇焕宸和爸爸的第一个小游戏'
  'char_thin'   = '迷彩小战士，焕宸'
  'char_fat'    = '冲锋战士，焕宸爸爸'
  'bg_forest'   = '发光森林'
  'bg_city'     = '破破城市'
  'bg_desert'   = '太阳沙漠'
  'boss_forest' = '藤蔓僵王'
  'boss_city'   = '铁皮僵王'
  'boss_desert' = '沙暴僵王'
  'coming'      = '来啦！它会发射子弹，看到冒烟就赶紧换路躲开！'
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
  'n0' = '零'; 'n1' = '一'; 'n2' = '二'; 'n3' = '三'; 'n4' = '四'
  'n5' = '五'; 'n6' = '六'; 'n7' = '七'; 'n8' = '八'; 'n9' = '九'
  'n10' = '十'; 'n20' = '二十'; 'n30' = '三十'
}
foreach ($k in $lines.Keys) {
  $p = Join-Path $out ($k + '.wav')
  $syn.SetOutputToWaveFile($p, $fmt)
  $syn.Speak([string]$lines[$k])
  $syn.SetOutputToNull()
}
$syn.Dispose()
Write-Host ('台词：' + $lines.Count + ' 句已生成')

# ---------- 2) 音效/BGM（按 tone()/noise() 同参数数学渲染 → 22.05kHz 单声道 WAV） ----------
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

# BGM：8 步旋律循环（与 MELO 一致）。尾巴折回头部，保证 loop 拼接无断口
$loopLen = [int](2.4 * $SR)
$tmpLen = $loopLen + [int](1.0 * $SR)
$bgm = New-Object double[] $tmpLen
$notes = @(196, 0, 262, 0, 196, 0, 294, 262)
for ($i = 0; $i -lt 8; $i++) {
  $f = $notes[$i]; if ($f -eq 0) { continue }
  Add-Tone $bgm $tmpLen @{dur=0.48;f=$f;type='triangle';vol=0.10;atk=0.03;delay=($i * 0.3)}
  Add-Noise $bgm $tmpLen @{dur=0.04;vol=0.022;f=5200;ftype='highpass';delay=($i * 0.3)}
}
for ($j = $loopLen; $j -lt $tmpLen; $j++) { $bgm[$j - $loopLen] += $bgm[$j]; $bgm[$j] = 0.0 }
Write-Wav (Join-Path $out 'bgm.wav') $bgm $loopLen

$files = Get-ChildItem $out -Filter *.wav
$mb = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 2)
Write-Host ('音效/BGM：10 个已生成')
Write-Host ('合计 ' + $files.Count + ' 个 wav，' + $mb + ' MB → ' + $out)
