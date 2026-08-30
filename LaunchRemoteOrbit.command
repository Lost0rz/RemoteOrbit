#!/bin/zsh
set -euo pipefail

APP="/Applications/RemoteOrbit.app"
DRIVER="/Library/Audio/Plug-Ins/HAL/RemoteOrbitAudio.driver"

if [[ ! -d "$APP" ]]; then
  APP="$HOME/Applications/RemoteOrbit.app"
fi

if [[ ! -d "$DRIVER" ]]; then
  print "缺少 RemoteOrbit Mic 2ch 驱动：$DRIVER"
  print "请先安装驱动，再启动 RemoteOrbit。"
  read -k 1 "?按任意键关闭…"
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  print "找不到已安装应用：$APP"
  print "请先运行 remote-orbit/install-app.sh 安装应用。"
  read -k 1 "?按任意键关闭…"
  exit 3
fi

open "$APP"
print "RemoteOrbit 已启动。菜单栏出现控制图标后即可使用。"
