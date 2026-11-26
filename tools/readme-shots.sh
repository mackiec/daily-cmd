#!/bin/zsh
# Rebuilds docs/screenshots/*.png from made-up data, so no real projects, notes or processes appear.
# Runs the installed app in demo mode (CMD_DEMO=1) against a throwaway home folder (CMD_HOME), with its
# own settings store. The normal cmd is stopped while this runs and started again afterwards.
# Needs Accessibility permission for the terminal (tools/shot.sh opens the panel).
set -e
cd "${0:A:h}/.."
APP=$HOME/Applications/cmd.app/Contents/MacOS/cmd
SERVICE=gui/$(id -u)/xyz.mackiec.cmd
AGENT=$HOME/Library/LaunchAgents/xyz.mackiec.cmd.plist
OUT=docs/screenshots
H=$(realpath $(mktemp -d /tmp/cmd-demo.XXXXXX))   # resolved: /tmp is really /private/tmp, and paths must match
P=$H/Projects
[[ -x $APP ]] || { echo "build and install cmd first (./install.sh)" >&2; exit 1; }

demo_pid=""
cleanup() {
  [[ -n $demo_pid ]] && kill $demo_pid 2>/dev/null || true
  rm -rf $H
  defaults delete xyz.mackiec.cmd.demo >/dev/null 2>&1 || true
  if [[ -f $AGENT ]]; then launchctl bootstrap gui/$(id -u) $AGENT 2>/dev/null || true; fi
}
trap cleanup EXIT

# --- fake projects: name, minutes since the last omp session (0 = none) ---
stamp() { date -v-${1}M +%Y%m%d%H%M; }
project() {
  local name=$1 session=$2 touched=$3
  mkdir -p $P/$name/.cmd
  if (( session > 0 )); then
    mkdir -p $H/.omp/agent/sessions/-Projects-$name
    touch -t $(stamp $session) $H/.omp/agent/sessions/-Projects-$name/session.jsonl
  fi
  echo $touched > $P/$name/.touched
}
project garden-journal 120 300
project studio-site 1500 2000
project film-scanner 4400 5000
project tide-clock 20160 20000
project recipe-box 0 9000
project field-notes 0 15000
project darkroom-timer 0 30000
project zine-press 0 45000

today=$(date +%Y-%m-%d)
cat > $P/garden-journal/.cmd/todo.md <<EOF
# To-do
- [ ] Fix the photo grid on mobile · $today
- [ ] Write the March entry · $today
EOF
cat > $P/garden-journal/.cmd/refs.md <<EOF
# References
- [USDA Plant Hardiness Zone Map](https://planthardiness.ars.usda.gov) · $today
  for the seed planner
EOF
cat > $P/studio-site/.cmd/todo.md <<EOF
# To-do
- [ ] Swap the hero image for the spring series · $today
EOF
cat > $P/film-scanner/.cmd/refs.md <<EOF
# References
- [Negative Lab Pro guide](https://www.negativelabpro.com/guide/) · $today
  colour settings to try
EOF
mkdir -p $H/.cmd
cat > $H/.cmd/todo.md <<EOF
# To-do
- [ ] Renew the domain before May · $today
- [ ] Reply to the print lab · $today
- [x] Order more film · $today → $today
EOF
cat > $H/.cmd/refs.md <<EOF
# References
- [Japanese Gradients (For UI) — Nuevo.Tokyo](https://www.nuevo.tokyo/japanese-gradients-for-ui) · $today
  palette ideas
EOF
# project folders' own "last touched" times, set last because writing files above changes them
for d in $P/*(/); do t=$(cat $d/.touched); rm $d/.touched; touch -t $(stamp $t) $d; done

# --- demo settings ---
defaults delete xyz.mackiec.cmd.demo >/dev/null 2>&1 || true
defaults write xyz.mackiec.cmd.demo projectsRoot -string $P
defaults write xyz.mackiec.cmd.demo agent -string omp
defaults write xyz.mackiec.cmd.demo terminal -string terminal
defaults write xyz.mackiec.cmd.demo tab -string projects

# --- swap the normal cmd for the demo ---
launchctl bootout $SERVICE 2>/dev/null || true
pkill -f "$APP" 2>/dev/null || true
sleep 1
run_demo() {
  CMD_DEMO=1 CMD_HOME=$H $APP >/dev/null 2>&1 &
  demo_pid=$!
  sleep 2.5
}
stop_demo() { kill $demo_pid; wait $demo_pid 2>/dev/null || true; demo_pid=""; sleep 1; }

mkdir -p $OUT
run_demo
tools/shot.sh $OUT/welcome.png >/dev/null
stop_demo

defaults write xyz.mackiec.cmd.demo setupDone -bool true
defaults write xyz.mackiec.cmd.demo pinned -array $P/studio-site
run_demo
tools/shot.sh /tmp/cmd-readme.png 1 2 3 4 >/dev/null
mv /tmp/cmd-readme-1.png $OUT/projects.png
mv /tmp/cmd-readme-2.png $OUT/todo.png
mv /tmp/cmd-readme-3.png $OUT/refs.png
mv /tmp/cmd-readme-4.png $OUT/mac.png
item=$(osascript -e 'tell application "System Events" to tell process "cmd" to get {position, size} of menu bar item 1 of menu bar 2' | tr -d ' ')
screencapture -x -R$item $OUT/menubar.png
ls -1 $OUT
