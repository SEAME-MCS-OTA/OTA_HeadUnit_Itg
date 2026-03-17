#!/bin/sh
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-wayland}
export QT_LOGGING_RULES="qt.qpa.*=false;qt.scenegraph.general=true"
if command -v qml >/dev/null 2>&1; then
  exec qml /usr/share/headunit/main.qml
else
  echo "[headunit] 'qml' not found. Ensure qtdeclarative-tools is installed." >&2
  sleep 2
fi
