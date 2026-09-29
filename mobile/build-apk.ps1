﻿# 一键出 APK：复制最新游戏 -> www -> cap sync -> gradle 构建
# 用法：在 mobile/ 目录下执行  powershell -ExecutionPolicy Bypass -File build-apk.ps1
$ErrorActionPreference = 'Stop'
$mobile = $PSScriptRoot
$root = Split-Path -Parent $mobile

# 1) 同步最新游戏文件为应用首页
Copy-Item (Join-Path $root '我的末日-方块人大战方块僵尸.html') (Join-Path $mobile 'www\index.html') -Force

# 1.5) 内置语音/音效（voice/*.wav，由 gen-audio.ps1 生成）
Copy-Item (Join-Path $root 'voice') (Join-Path $mobile 'www\voice') -Recurse -Force

# 2) 原生工程用 ASCII 入口路径（AGP 拒绝中文路径）：junction 指向 mobile/
$junction = 'D:\AndroidTools\mydoomsday-mobile'
if (-not (Test-Path $junction)) {
    New-Item -ItemType Junction -Path $junction -Target $mobile | Out-Null
}

# 3) 便携式构建环境
$env:JAVA_HOME = 'D:\AndroidTools\jdk-21.0.12.1+1'
$env:ANDROID_HOME = 'D:\AndroidTools\android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:GRADLE_OPTS = '-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7897 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7897'

# 4) cap sync（Node CLI 不怕中文路径，从真实工程根跑；junction 会让它误判平台未添加）
Push-Location $mobile
npx cap sync android
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'cap sync failed' }
Pop-Location

# 5) gradle 构建（AGP 拒绝中文路径，必须从 junction 入口跑）
Push-Location (Join-Path $junction 'android')
& (Join-Path $junction 'android\gradlew.bat') assembleDebug --console=plain
if ($LASTEXITCODE -ne 0) { Pop-Location; throw 'gradle build failed' }
Pop-Location

# 6) 复制产物到项目根目录
$apk = Join-Path $junction 'android\app\build\outputs\apk\debug\app-debug.apk'
$dest = Join-Path $root '我的末日-装机包.apk'
Copy-Item $apk $dest -Force
Write-Host ""
Write-Host "==== APK 已生成: $dest ===="
Write-Host "大小: $([math]::Round((Get-Item $dest).Length/1MB,2)) MB"
