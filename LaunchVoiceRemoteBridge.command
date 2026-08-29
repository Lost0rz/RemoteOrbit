#!/bin/zsh
set -euo pipefail

APP="$HOME/Applications/VoiceRemoteBridge.app"
DRIVER="/Library/Audio/Plug-Ins/HAL/VoiceRemoteAudio.driver"

if [[ ! -d "$DRIVER" ]]; then
  print "缺少 VoiceRemote Mic 2ch 驱动：$DRIVER"
  print "请先安装驱动，再启动 Voice Remote Bridge。"
  read -k 1 "?按任意键关闭…"
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  print "找不到已安装应用：$APP"
  print "请先运行 voice-remote-bridge/install-app.sh 安装应用。"
  read -k 1 "?按任意键关闭…"
  exit 3
fi

open "$APP"
print "Voice Remote Bridge 已启动。菜单栏出现 🎤 后即可使用。"
