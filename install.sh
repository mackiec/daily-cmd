#!/bin/zsh
# builds cmd and starts it at login (adapted from baa's install.sh)
set -e
cd "${0:A:h}"
./build.sh

AGENT=~/Library/LaunchAgents/xyz.mackiec.cmd.plist
cat > $AGENT <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>xyz.mackiec.cmd</string>
  <key>ProgramArguments</key><array><string>$HOME/Applications/cmd.app/Contents/MacOS/cmd</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>/tmp/cmd.err</string>
</dict>
</plist>
PLIST
launchctl bootout gui/$(id -u)/xyz.mackiec.cmd 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $AGENT
launchctl kickstart -k gui/$(id -u)/xyz.mackiec.cmd
echo "⌘ cmd is running in your menu bar"
