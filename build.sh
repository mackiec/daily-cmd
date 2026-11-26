#!/bin/zsh
# builds cmd.app into ~/Applications and restarts it (adapted from baa's build.sh)
set -e
cd "${0:A:h}"
APP=build/cmd.app
INSTALLED=$HOME/Applications/cmd.app
BINARY=$INSTALLED/Contents/MacOS/cmd
AGENT=$HOME/Library/LaunchAgents/xyz.mackiec.cmd.plist
SERVICE=gui/$(id -u)/xyz.mackiec.cmd
rm -rf $APP && mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 -parse-as-library -target "$(uname -m)-apple-macos15" -o $APP/Contents/MacOS/cmd Sources/**/*.swift
cp Info.plist $APP/Contents/
codesign --force -s - $APP

# Stop the login service before replacing its executable, then stop any copy
# launched directly. Otherwise the old process can keep a second menu item.
managed=0
if launchctl print "$SERVICE" >/dev/null 2>&1; then
  managed=1
  launchctl bootout "$SERVICE"
fi
was_running=0
if /usr/bin/pgrep -u "$(id -u)" -f -x "$BINARY" >/dev/null; then
  was_running=1
  /usr/bin/pkill -TERM -u "$(id -u)" -f -x "$BINARY" || true
  for attempt in {1..20}; do
    /usr/bin/pgrep -u "$(id -u)" -f -x "$BINARY" >/dev/null || break
    sleep 0.1
  done
  if /usr/bin/pgrep -u "$(id -u)" -f -x "$BINARY" >/dev/null; then
    if (( managed )); then
      launchctl bootstrap "gui/$(id -u)" "$AGENT"
      launchctl kickstart -k "$SERVICE"
    fi
    echo "could not stop the old cmd process" >&2
    exit 1
  fi
fi

mkdir -p ~/Applications && rm -rf "$INSTALLED" && cp -R "$APP" ~/Applications/
if (( managed )); then
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  launchctl kickstart -k "$SERVICE"
elif (( was_running )); then
  open -a "$INSTALLED"
fi
echo "built $INSTALLED"
