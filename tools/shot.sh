#!/bin/zsh
# Opens cmd's panel, captures just that window, then closes it. Needs Accessibility permission
# for the terminal running it.
#   tools/shot.sh [out.png]            capture whatever tab is showing
#   tools/shot.sh [out.png] 1 2 3 4    press ⌘N for each tab and capture out-N.png
# Keys are only sent once cmd is the frontmost app, so they never land in another window.
set -e
out=${1:-/tmp/cmd-shot.png}
(( $# )) && shift
dir=$(mktemp -d)
trap 'rm -rf $dir' EXIT
cat > $dir/click.swift <<'EOF'
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
let p = CGPoint(x: a[0] + a[2] / 2, y: a[1] + a[3] / 2)
for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
}
EOF
cat > $dir/win.swift <<'EOF'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "cmd" {
    let b = w["kCGWindowBounds"] as! [String: Any]
    if (b["Height"] as! Double) > 100 { print(w["kCGWindowNumber"]!) }
}
EOF
# ⌘<digit>, posted straight to cmd's process so it can never land in another app
cat > $dir/key.swift <<'EOF'
import CoreGraphics
import Foundation
let pid = pid_t(CommandLine.arguments[1])!, digit = Int(CommandLine.arguments[2])!
let codes: [Int: CGKeyCode] = [1: 18, 2: 19, 3: 20, 4: 21]
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: codes[digit]!, keyDown: down)!
    e.flags = .maskCommand
    e.postToPid(pid)
    usleep(40_000)
}
EOF
pos=(${(s:, :)$(osascript -e 'tell application "System Events" to tell process "cmd" to get {position, size} of menu bar item 1 of menu bar 2')})
[[ -n $(swift $dir/win.swift) ]] || { swift $dir/click.swift $pos; sleep 1.5; }
id=$(swift $dir/win.swift | head -1)
[[ -n $id ]] || { echo "panel didn't open" >&2; exit 1; }
if (( $# )); then
  pid=$(pgrep -f 'cmd.app/Contents/MacOS/cmd' | head -1)
  for n in $@; do
    swift $dir/key.swift $pid $n
    sleep 1.2
    screencapture -x -o -l $id ${out%.png}-$n.png
    echo ${out%.png}-$n.png
  done
else
  screencapture -x -o -l $id $out
  echo $out
fi
swift $dir/click.swift $pos
