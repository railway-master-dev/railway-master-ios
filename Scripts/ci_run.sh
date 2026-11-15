#!/usr/bin/env bash
# RAILWAY MASTER - CI step implementations, called from .github/workflows/ios-ci.yml
# Usage: bash Scripts/ci_run.sh [static|build|packages|screenshots]
set -u
mode="${1:-}"
# 2026-11-13: the borrowed Mac is Intel (x86_64); GitHub runners are
# Apple Silicon (arm64). ci_run.sh used to hardcode ARCHS=arm64, which
# builds a test bundle the Intel simulator cannot run (rc=70, "does not
# support any of ...'s architectures: x86_64"). Detect the host arch so
# the same script works on both.
HOST_ARCH="$(uname -m)"

pick_simulator() {
  python3 - << 'PY'
import json, re, subprocess, sys
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
def version_key(runtime):
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
runtimes = [r for r in data["devices"] if "iOS" in r]
runtimes.sort(key=version_key, reverse=True)
for runtime in runtimes:
    for device in data["devices"][runtime]:
        if device.get("name", "").startswith("iPhone") and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit("No available iPhone simulator found on this runner")
PY
}

case "$mode" in
  static)
    python3 -m pip install -r Scripts/requirements.txt
    python3 Scripts/validate_project.py
    python3 Scripts/validate_generated_3d_assets.py
    python3 Scripts/generate_package_inventory.py --check
    ;;
  build)
    xcodebuild -version
    swift --version
    xcrun simctl list runtimes
    SIMULATOR_UDID="$(pick_simulator)" || exit 1
    # quality27: on Codemagic's virtual Macs, CoreAudio initialization
    # deadlocks and the watchdog aborts the app (and with it the test
    # host) seconds after launch. SIMCTL_CHILD_ propagates this into
    # every app xcodebuild/simctl starts on the simulator, and the app
    # then skips building its audio graph entirely (CI runs are silent
    # anyway). Real-device and local runs are unaffected.
    export SIMCTL_CHILD_RM_DISABLE_AUDIO=1
    echo "Using simulator UDID: $SIMULATOR_UDID"
    xcodebuild -resolvePackageDependencies \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1
    set -o pipefail
    # 2026-11-12: build-for-testing + test-without-building run
    # ONE build pass instead of two. CI #412's build job hit the
    # 60-minute job cap during the test phase after a full second
    # build; the tests themselves are unchanged.
    xcodebuild build-for-testing \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
      CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH" ENABLE_TESTABILITY=YES \
      | tee build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    # 2026-11-13: test-without-building refuses an existing
    # -resultBundlePath (00:55 chain: rc=64, tests never ran).
    # The watcher's manual test rerun left one behind, so clear it.
    rm -rf TestResults.xcresult
    xcodebuild test-without-building \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
      -resultBundlePath TestResults.xcresult \
      CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH" ENABLE_TESTABILITY=YES \
      | tee test.log
    test_status=$?
    # Extract per-test failure details (assertion messages) as plain text.
    # The raw .xcresult bundle cannot be read off-runner, and the plain
    # xcodebuild log omits the assertion lines, so dump them here into
    # test.log (already uploaded as an artifact) and the job log.
    {
      echo '===== xcresult test summary ====='
      xcrun xcresulttool get test-results summary --path TestResults.xcresult 2>&1 || true
      echo '===== failed tests (details) ====='
      xcrun xcresulttool get test-results tests --path TestResults.xcresult > test-results-tests.json 2>/dev/null || true
      python3 - << 'PYEOF' || true
import json
try:
    data = json.load(open("test-results-tests.json"))
except Exception as e:
    print("could not parse test-results-tests.json:", e)
    raise SystemExit(0)

def walk(node, depth=0):
    if isinstance(node, dict):
        result = node.get("result")
        ntype = node.get("nodeType", "")
        name = node.get("name", "")
        if ntype == "Test Case" and result == "Failed":
            print("FAILED TEST:", name)
            print(json.dumps(node, ensure_ascii=False, indent=1)[:6000])
            print("-----")
        for v in node.values():
            walk(v, depth + 1)
    elif isinstance(node, list):
        for item in node:
            walk(item, depth + 1)

walk(data)
PYEOF
    } > test-failures.txt 2>&1 || true
    cat test-failures.txt || true
    cat test-failures.txt >> test.log || true
    exit "$test_status"
    ;;
  screenshots)
    xcodebuild -version
    SIMULATOR_UDID="$(pick_simulator)" || exit 1
    # quality27: see the build mode — keep the app alive on Codemagic
    # by disabling its audio graph for this CI run.
    export SIMCTL_CHILD_RM_DISABLE_AUDIO=1
    echo "Using simulator UDID: $SIMULATOR_UDID"
    xcodebuild -resolvePackageDependencies \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1
    set -o pipefail
    xcodebuild build \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
      -derivedDataPath build/DerivedData \
      CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH" \
      | tee screenshots-build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    APP_PATH="$(find build/DerivedData/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' | head -n 1)"
    if [ -z "$APP_PATH" ]; then echo "Built .app not found" >&2; exit 1; fi
    echo "Built app: $APP_PATH"
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
    echo "Bundle ID: $BUNDLE_ID"
    mkdir -p screenshots
    # batch7 (2026-11-12): overall job budget clock. The
    # screenshots job is capped at 60 minutes; CI #413's tour
    # consumed all of it and the short tours and cab check
    # never ran. Later stages below check this clock and skip
    # themselves (logged) instead of being cut off mid-flight.
    # batch9 (CI #415): the stakes are higher than a skipped
    # stage — when the job hit its 60-minute timeout in #415
    # the runner was torn down BEFORE the workflow's
    # always() upload step ran, so the entire tour's evidence
    # (photos, progress log, demo log) was lost even though
    # the script had been working for over an hour. The stage
    # budgets are therefore retuned so this script RETURNS
    # with minutes to spare in the worst case: main tour cap
    # 1,500 s, short tours start only before 1,800 s and abort
    # at 2,100 s, cab check starts only before 2,100 s. Note
    # JOB_START is set after this script's own build phase
    # (~15 min of the job), which the margins absorb.
    # batch44 (2026-11-14): the short-tour gates above starved
    # the zoo/park tours two chains in a row — a degraded main
    # tour (frozen app, recovery cycles) burned past 1,800 s
    # and both short tours were SKIPPED while the cab check
    # and the (then 540 s) audio wait still ran. The short
    # tours now run UNCONDITIONALLY immediately after the main
    # tour, before the cab check and the audio step, under
    # their own 900 s deadline (SHORT_TOUR_DEADLINE, set where
    # they are invoked below); the cab check keeps its own
    # 2,100 s gate and skips itself if the short tours ran
    # long, as designed.
    JOB_START=$SECONDS
    xcrun simctl boot "$SIMULATOR_UDID" || true
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b
    xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
    # Resolve the app data container now (before launch) so the tour
    # photography below can poll the demo log the app writes there.
    APP_DATA="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    # 2026-11-11: clear any stale tour ACKs and demo log left in
    # the container by an earlier run or attempt. A leftover
    # tour-ack-<i>.txt releases the app's hold the moment it
    # arrives at spot i, before the script has photographed it —
    # one of the ways CI #409's script raced ahead of the app.
    if [ -n "$APP_DATA" ]; then
      rm -f "$APP_DATA/Documents"/tour-ack-*.txt 2>/dev/null || true
      rm -f "$APP_DATA/Documents/demo-drive-log.txt" 2>/dev/null || true
    fi
    # 2026-11-13 (Mac photo verdict): the title screen (batch12/13)
    # was never photographed — the demo launch below bypasses it
    # (-RMDemoDrive) and the launch video came back a stale
    # home-screen file from an earlier chain. Launch once WITHOUT
    # demo args and photograph the rotating title photos first,
    # then terminate and continue with the demo tour. This block
    # runs before capture_still/shot_with_timeout are defined, so
    # it uses a small local screenshot helper with the same
    # 45 s timeout discipline.
    title_shot() {
      local NAME="$1"
      # 2026-11-13 (Mac photo verdict): the first title shots were
      # pure black (20 KB PNGs) — the app takes well over 10 s
      # after process start to first render on this Mac, and a
      # one-shot screenshot in that window captures a black
      # screen. Retry until the frame is non-black: a black frame
      # is ~20 KB, a real title photo is several hundred KB.
      # A failed capture leaves an honest gap, never a black file.
      local ATTEMPT=0
      while [ "$ATTEMPT" -lt 10 ]; do
        ATTEMPT=$((ATTEMPT + 1))
        rm -f "screenshots/$NAME.tmp.png"
        xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$NAME.tmp.png" 2>/dev/null &
        local PID=$!
        local T0=$SECONDS
        while kill -0 "$PID" 2>/dev/null; do
          if [ $((SECONDS - T0)) -ge 45 ]; then kill -9 "$PID" 2>/dev/null || true; break; fi
          sleep 2
        done
        wait "$PID" 2>/dev/null || true
        local SZ=0
        if [ -s "screenshots/$NAME.tmp.png" ]; then SZ=$(stat -f %z "screenshots/$NAME.tmp.png" 2>/dev/null || echo 0); fi
        if [ "$SZ" -gt 100000 ]; then
          mv "screenshots/$NAME.tmp.png" "screenshots/$NAME.png"
          echo "title shot $NAME ok (attempt $ATTEMPT, ${SZ}B)"
          rm -f "screenshots/$NAME.tmp.png"
          return 0
        fi
        echo "title shot $NAME attempt $ATTEMPT black/empty (${SZ}B), retrying"
        sleep 10
      done
      rm -f "screenshots/$NAME.tmp.png"
      echo "title shot $NAME FAILED (no non-black frame — honest gap, not a stale file)"
    }
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    TITLE_WAIT=0
    while [ "$TITLE_WAIT" -lt 120 ]; do
      if xcrun simctl spawn "$SIMULATOR_UDID" launchctl list 2>/dev/null | grep -qi 'railwaymaster'; then break; fi
      sleep 5; TITLE_WAIT=$((TITLE_WAIT + 5))
    done
    # 2026-11-13: first render takes well over 10 s on this Mac,
    # so give the title screen 20 s before the first attempt
    # (title_shot retries anyway until the frame is non-black).
    sleep 20
    title_shot 01-title
    sleep 8
    title_shot 02-title
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    # -RMDemoDrive -RMTour: the app teleports the standing train to a
    # new scenic chainage every ~35 s of wall time (first at ~25 s),
    # so one launch photographs sixteen different places along the
    # line (the showcase section's P1-P7 points, then line-wide).
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour
    # 2026-11-12: wait until the app is actually ticking (its
    # demo log has state lines) before the launch shots and the
    # video. On a loaded runner the first frame can take minutes;
    # CI #412's 01-03 were one identical black frame because they
    # were taken on fixed sleeps while the app was still starting.
    APP_TICK_WAIT=0
    while [ "$APP_TICK_WAIT" -lt 240 ]; do
      if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ] && grep -q '^t=' "$APP_DATA/Documents/demo-drive-log.txt" 2>/dev/null; then break; fi
      sleep 5; APP_TICK_WAIT=$((APP_TICK_WAIT + 5))
    done
    # batch7 (2026-11-12, CI #413): every screenshot runs
    # under a hard timeout. In #413 single simctl screenshot
    # calls blocked for 5-14 minutes (inferred afterwards from
    # file timestamps) and returned 0 bytes; nothing in the
    # script could see it happening. shot_with_timeout <name>
    # <timeout-seconds> captures to a temp file in the
    # background, kills the call past the timeout, and moves
    # only a non-empty result into place. Sets SHOT_OK (1/0)
    # and SHOT_SECONDS.
    shot_with_timeout() {
      local NAME="$1"; local LIMIT="${2:-45}"
      SHOT_OK=0; SHOT_SECONDS=0
      rm -f "screenshots/$NAME.tmp.png"
      local T0=$SECONDS
      xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$NAME.tmp.png" 2>/dev/null &
      local PID=$!
      while kill -0 "$PID" 2>/dev/null; do
        if [ $((SECONDS - T0)) -ge "$LIMIT" ]; then
          kill -9 "$PID" 2>/dev/null || true
          break
        fi
        sleep 2
      done
      wait "$PID" 2>/dev/null || true
      SHOT_SECONDS=$((SECONDS - T0))
      if [ -f "screenshots/$NAME.tmp.png" ]; then
        local SZ=0
        SZ=$(stat -f %z "screenshots/$NAME.tmp.png" 2>/dev/null || echo 0)
        if [ "$SZ" -gt 0 ]; then
          mv "screenshots/$NAME.tmp.png" "screenshots/$NAME.png"
          SHOT_OK=1
        fi
      fi
      rm -f "screenshots/$NAME.tmp.png"
    }
    # batch8 (2026-11-12, CI #414): stills are extracted from
    # VIDEO frames. simctl screenshots returned 0 bytes for
    # every single capture in #414 (fast 2 s empties after the
    # first two 45 s timeouts), while recordVideo worked in
    # both #413 and #414 — under runner starvation the video
    # path keeps streaming frames that the one-shot capture
    # path cannot composite. extract_frame <mov> <png> <sec>
    # tries, in order: ffmpeg, qlmanage (first frame), and a
    # small AVFoundation script (written below, last resort).
    # If all three fail the caller keeps the .mov in the
    # artifact so frames can be extracted after the run.
    cat > screenshots/extract_frame.swift << 'SWIFT_EOF'
import AVFoundation
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 4 else { exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
let seconds = Double(args[3]) ?? 1.0
let time = CMTime(seconds: seconds, preferredTimescale: 600)
var actualTime = CMTime.zero
do {
    let image = try generator.copyCGImage(at: time, actualTime: &actualTime)
    let outURL = URL(fileURLWithPath: args[2]) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(outURL, "public.png" as CFString, 1, nil) else { exit(3) }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { exit(4) }
} catch {
    exit(1)
}
SWIFT_EOF
    # batch41 (2026-11-14): duration probe for the %-offset mode
    # below. Prints the clip length in seconds (AVFoundation via
    # a tiny script; no ffmpeg dependency on the Mac).
    cat > screenshots/mov_duration.swift << 'SWIFT_EOF'
import AVFoundation
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { exit(2) }
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let seconds = CMTimeGetSeconds(asset.duration)
if seconds.isFinite && seconds > 0 {
    print(seconds)
} else {
    exit(1)
}
SWIFT_EOF
    extract_frame() {
      local MOV="$1"; local PNG="$2"; local SEC="$3"
      rm -f "$PNG"
      # batch41: SEC may be "%NN" — a percentage of the clip's
      # own length. capture_still records ~8 s clips, but under
      # runner load the finalized .mov stretches well past that,
      # and a fixed late offset (the old 5 s) can land after the
      # scene has already changed: the tour teleporting on, or —
      # this morning — the demo drive's results sheet, whose
      # frame 20-cab-running then kept. The middle of the clip
      # is the frame most certain to show the intended held
      # scene. Percentage mode resolves the offset from the
      # measured duration (ffprobe if present, else the
      # AVFoundation probe above) and tries the timed extractors
      # before the qlmanage first-frame fallback, which cannot
      # honour an offset at all.
      local PCT=""
      case "$SEC" in
        \%*) PCT="${SEC#\%}" ;;
      esac
      if [ -n "$PCT" ]; then
        local DUR=""
        if command -v ffprobe >/dev/null 2>&1; then
          DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MOV" 2>/dev/null || true)"
        fi
        if [ -z "$DUR" ] && [ -f screenshots/mov_duration.swift ]; then
          DUR="$(xcrun swift screenshots/mov_duration.swift "$MOV" 2>/dev/null || true)"
        fi
        if [ -n "$DUR" ]; then
          SEC="$(awk -v d="$DUR" -v p="$PCT" 'BEGIN{ if (d > 0) printf "%.2f", d * p / 100 }')"
        fi
        case "$SEC" in
          %*|"0.00"|"") SEC=4 ;;
        esac
        if command -v ffmpeg >/dev/null 2>&1; then
          ffmpeg -y -v error -ss "$SEC" -i "$MOV" -frames:v 1 "$PNG" 2>/dev/null || true
        fi
        if [ ! -s "$PNG" ] && [ -f screenshots/extract_frame.swift ]; then
          xcrun swift screenshots/extract_frame.swift "$MOV" "$PNG" "$SEC" 2>/dev/null || true
        fi
        if [ ! -s "$PNG" ]; then
          local QD="$(mktemp -d)"
          qlmanage -t -s 1600 -o "$QD" "$MOV" >/dev/null 2>&1 || true
          local QF="$(ls "$QD"/*.png 2>/dev/null | head -n 1)"
          if [ -n "$QF" ]; then cp "$QF" "$PNG" 2>/dev/null || true; fi
          rm -rf "$QD"
        fi
        [ -s "$PNG" ]
        return
      fi
      if command -v ffmpeg >/dev/null 2>&1; then
        ffmpeg -y -v error -ss "$SEC" -i "$MOV" -frames:v 1 "$PNG" 2>/dev/null || true
      fi
      if [ ! -s "$PNG" ]; then
        local QD="$(mktemp -d)"
        qlmanage -t -s 1600 -o "$QD" "$MOV" >/dev/null 2>&1 || true
        local QF="$(ls "$QD"/*.png 2>/dev/null | head -n 1)"
        if [ -n "$QF" ]; then cp "$QF" "$PNG" 2>/dev/null || true; fi
        rm -rf "$QD"
      fi
      if [ ! -s "$PNG" ] && [ -f screenshots/extract_frame.swift ]; then
        xcrun swift screenshots/extract_frame.swift "$MOV" "$PNG" "$SEC" 2>/dev/null || true
      fi
      [ -s "$PNG" ]
    }
    # 2026-11-13: remove any stale launch video first — the
    # 00:55 Mac chain's 01/02/03 were extracted from a 00:17 file
    # left by the failed 00:07 chain (home screen throughout),
    # because recordVideo never overwrote it. A failed recording
    # now leaves an honest gap instead of a stale home screen.
    rm -f screenshots/launch-video.mov
    xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 screenshots/launch-video.mov &
    VIDEO_PID=$!
    sleep 4
    sleep 8
    sleep 14
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
    # batch8: the launch stills are frames of the launch video
    # (at ~4 s, ~12 s and ~24 s), not separate screenshot calls.
    # 2026-11-13: if the video is missing (recording failed),
    # extract_frame leaves no file — an honest gap, never a stale
    # frame from an earlier chain (see the rm -f above).
    extract_frame screenshots/launch-video.mov screenshots/01-launch.png 4 || true
    extract_frame screenshots/launch-video.mov screenshots/02-main.png 12 || true
    extract_frame screenshots/launch-video.mov screenshots/03-settled.png 24 || true
    # Diagnostics: is the app process alive? did it crash? what did it log?
    {
      echo '== app process (launchctl) =='
      xcrun simctl spawn "$SIMULATOR_UDID" launchctl list 2>/dev/null | grep -i 'railwaymaster' || echo 'app process not found'
    } > screenshots/diagnostics.txt 2>&1 || true
    cp -f ~/Library/Logs/DiagnosticReports/RailwayMasterPhase1* screenshots/ 2>/dev/null || true
    xcrun simctl spawn "$SIMULATOR_UDID" log show --style compact --last 6m --predicate 'process == "RailwayMasterPhase1"' 2>/dev/null | tail -c 150000 > screenshots/device-log.txt || true
    # Location tour (quality25): a two-way handshake. The app
    # teleports to a spot, appends "READY spot=<i> pos=<m>" to
    # Documents/demo-drive-log.txt once simulation time is at
    # least 4 s past the teleport with the train standing at the
    # spot (model and view share the main runloop, so sim time
    # advancing means frames at the new location have been
    # presented), and then HOLDS that spot until the script writes
    # Documents/tour-ack-<i>.txt — which the script does only
    # after a successful screenshot — or 900 s pass (2026-11-11:
    # raised from 150 s after CI #409, where single captures
    # blocked longer than the hold). quality24's READY-only
    # version still drifted (CI #232: 7 of 16 spots at their
    # labelled positions, three black frames, six duplicates of
    # one stretch of coast) because the app teleported on its own
    # 35 s schedule while a loaded simulator took tens of seconds
    # per simctl screenshot: by the time a capture executed, the
    # train had moved on. Now the train cannot move on. Each shot
    # below waits for its spot's READY (per-spot cap 420 s, tour
    # cap 2,400 s), settles 5 s, shoots (up to 3 attempts), and
    # only then writes the ACK that releases the app to the next
    # spot; a spot whose captures all fail triggers recovery
    # (app relaunch) before one final ACK releases the app
    # anyway.
    # batch7 (2026-11-12, CI #413): the numbers below are the
    # batch7 budgets — per-spot READY cap 240 s, tour cap
    # 1,800 s, captures are timed (shot_with_timeout, 2 attempts
    # of 45 s) with every attempt's duration and size logged to
    # tour-progress.txt, and recovery is an app relaunch only
    # (at most twice per tour). #413's stage-2 simulator reboot
    # cost ~10 minutes and cleared nothing, so it is gone.
    # 2026-11-12 (CI #412): the old "if a READY never comes, shoot
    # anyway" fallback is REMOVED. With the app starved to ~1/30
    # of real time it fired on spot 2 and the script then raced
    # ahead writing ACKs, producing 32 station files containing
    # three scenes. A spot is now photographed ONLY after its
    # READY has been seen. On a READY timeout or a failed capture
    # the recovery escalates once and the wait/capture is
    # retried; a spot that still fails is logged FAILED and
    # SKIPPED (the ACK is still written so the tour continues,
    # and the app's 900 s hold also releases itself). An honest
    # gap in the set, never a photograph of the wrong place under
    # the right name. If the log never appears at all, spots fail
    # the same way instead of falling back to blind fixed steps.
    # Spots (tourSpotsM in SimulatorModel.swift, in order): the
    # quality40 station survey: all 32 stations in route order,
    # each shot 20 m before the station centre (S01 Kaibukuro at
    # 5 m — the line starts there). Mainline centres 0-60,000 m,
    # then the branch in through-frame chainages 62,000-68,000 m.
    # batch41 (2026-11-14): tourSpotsM gained three stop-marker
    # close-ups at its tail in batch37 (8,279 Ishigamiike /
    # 28,505 Tsudaike / 44,085 Katsunuma) but this fixed name
    # list was never extended, so the tour ended at
    # 38-akimizu-fan and the close-ups were silently never
    # photographed. The 39-marker* names below restore the
    # 1:1 correspondence with tourSpotsM (38 names total).
    # batch47 (2026-11-14): tourSpotsM gained two more tail
    # spots — 27,470 (the Touou depot's stabled consists) and
    # 28,432 (the guaranteed opposing-train meet at S14) — and
    # 50-depot-stabled / 51-meet-loop below extend the list to
    # 40 names, keeping the 1:1 correspondence.
    TOUR_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
      TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
    fi
    TOUR_SHOTS="04-st01-kaibukuro 05-st02-asanuma 06-st03-oginuma 07-st04-ohara 08-st05-ishigamiike 09-st06-hibarigaoka 10-st07-akimizu 11-st08-wakakusadai 12-st09-higashimurakawa 13-st10-nishitachikawa 14-st11-hihara 15-st12-tououchihara 16-st13-makufu 17-st14-tsudaike 18-st15-mikkaido 19-st16-misagi 20-st17-touousahara 21-st18-shigeno 22-st19-kazusaninomiya 23-st20-togane 24-st21-katsunuma 25-st22-kisaragawa 26-st23-namihana 27-st24-ohno 28-st25-mihama 29-st26-tatekawa 30-st27-chikura 31-st28-kamogawa 32-st29-kuruno 33-st30-ohbitsu 34-st31-hirayama 35-st32-kazusaryuzan 36-crossing-6495 37-crossing-7970 38-akimizu-fan 39-marker1-ishigamiike 39-marker2-tsudaike 39-marker3-katsunuma 50-depot-stabled 51-meet-loop"
    TOUR_START=$SECONDS
    TOUR_INDEX=0
    # batch7: count of app-relaunch recoveries used so far in
    # this tour (at most 2). CI #409 attempt 1 lost every shot
    # from spot 3 onward to persistent 0-byte captures, and CI
    # #413 showed the follow-up reboot stage costs ~10 minutes
    # without clearing the wedge — so recovery is relaunch-only
    # now, and every capture is individually timed instead.
    RECOVERY_STAGE=0
    : > screenshots/tour-progress.txt
    # batch8 (CI #414): one capture = one 8 s video clip of the
    # held spot plus a frame extraction (see extract_frame).
    # simctl screenshots are demoted to a last-resort fallback:
    # in #414 every screenshot attempt came back 0 bytes while
    # recordVideo worked. On extraction success the clip is
    # deleted; if extraction fails the clip stays in the
    # artifact so the frame can still be recovered after the
    # run. Sets TOUR_SIZE (0 when nothing usable was captured).
    capture_still() {
      TOUR_SIZE=0
      local NAME="$1"
      rm -f "screenshots/$NAME.png" "screenshots/$NAME.mov"
      xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 "screenshots/$NAME.mov" 2>/dev/null &
      local RPID=$!
      sleep 8
      kill -INT "$RPID" 2>/dev/null || true
      wait "$RPID" 2>/dev/null || true
      if [ -s "screenshots/$NAME.mov" ]; then
        # batch41: take the clip's middle frame (50%), not a
        # fixed 5 s — see the %-offset mode in extract_frame.
        if extract_frame "screenshots/$NAME.mov" "screenshots/$NAME.png" "%50"; then
          TOUR_SIZE=$(stat -f %z "screenshots/$NAME.png" 2>/dev/null || echo 0)
          if [ "$TOUR_SIZE" -ge 30000 ]; then
            rm -f "screenshots/$NAME.mov"
            echo "tour-progress: capture $NAME via video ok size=${TOUR_SIZE}B" >> screenshots/tour-progress.txt
            return 0
          fi
          # batch15 (2026-11-13 diagnosis): a pure-black frame
          # extracts "successfully" too — the loop-2 cab shots
          # were byte-identical 20,976 B black PNGs that this
          # function happily reported as ok. A real frame of
          # this scene is >100 KB; anything under 30 KB is
          # treated as a black/blank capture and falls back to
          # a still screenshot, keeping the video frame only
          # if the screenshot also fails.
          echo "tour-progress: capture $NAME video frame tiny/black size=${TOUR_SIZE}B, trying screenshot" >> screenshots/tour-progress.txt
          mv "screenshots/$NAME.png" "screenshots/$NAME-video.png"
          shot_with_timeout "$NAME" 45
          if [ "$SHOT_OK" -eq 1 ]; then
            TOUR_SIZE=$(stat -f %z "screenshots/$NAME.png" 2>/dev/null || echo 0)
            rm -f "screenshots/$NAME.mov" "screenshots/$NAME-video.png"
            echo "tour-progress: capture $NAME via screenshot after black video frame size=${TOUR_SIZE}B" >> screenshots/tour-progress.txt
            return 0
          fi
          mv "screenshots/$NAME-video.png" "screenshots/$NAME.png"
          TOUR_SIZE=$(stat -f %z "screenshots/$NAME.png" 2>/dev/null || echo 0)
          echo "tour-progress: capture $NAME kept tiny video frame size=${TOUR_SIZE}B (screenshot failed too)" >> screenshots/tour-progress.txt
          return 0
        fi
        echo "tour-progress: capture $NAME video kept, frame extraction failed" >> screenshots/tour-progress.txt
      fi
      shot_with_timeout "$NAME" 45
      if [ "$SHOT_OK" -eq 1 ]; then
        TOUR_SIZE=$(stat -f %z "screenshots/$NAME.png" 2>/dev/null || echo 0)
        echo "tour-progress: capture $NAME via screenshot fallback size=${TOUR_SIZE}B" >> screenshots/tour-progress.txt
        return 0
      fi
      echo "tour-progress: capture $NAME FAILED (video and screenshot)" >> screenshots/tour-progress.txt
      return 1
    }
    # 2026-11-12: wait until the demo log shows READY for spot $1
    # (or a later one), up to $2 seconds; also stops at the
    # 1,500 s tour cap (batch9; 1,800 in batch7/8). Sets READY_SEEN, and LOG_GREW
    # (batch8: 1 when the log's simulation time advanced during
    # the wait — the app is alive, just slow; CI #414's spots
    # 2-3 each burned ~490 s on relaunch cycles against an app
    # that was still booting and racing through pre-ACKed
    # spots, which a "log still advancing" signal distinguishes
    # from a genuinely wedged app).
    tour_wait_ready() {
      READY_SEEN=0
      LOG_GREW=0
      local WANT="$1"; local CAP="$2"; local WAITED=0
      local T_START=""
      if [ -n "$TOUR_LOG" ]; then
        T_START="$(grep -o '^t=[0-9]*' "$TOUR_LOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
      fi
      while [ "$WAITED" -lt "$CAP" ]; do
        if [ -n "$TOUR_LOG" ]; then
          local MAXREADY="$(grep -o 'READY spot=[0-9]*' "$TOUR_LOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
          if [ -n "$MAXREADY" ] && [ "$MAXREADY" -ge "$WANT" ]; then READY_SEEN=1; return 0; fi
          local T_NOW="$(grep -o '^t=[0-9]*' "$TOUR_LOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
          if [ -n "$T_NOW" ] && [ -n "$T_START" ] && [ "$T_NOW" -gt "$T_START" ]; then LOG_GREW=1; fi
        fi
        if [ $((SECONDS - TOUR_START)) -ge 1500 ]; then return 0; fi
        sleep 5
        WAITED=$((WAITED + 5))
      done
    }
    # batch7: recovery for a wedged tour is an app relaunch
    # ONLY, at most twice per tour (CI #413's simulator-reboot
    # stage cost ~10 minutes and cleared nothing), then wait
    # for the current spot's READY again. batch8: the re-wait
    # is 420 s — a relaunched app on the starved runner needs
    # minutes just to boot and race through the pre-ACKed
    # spots (CI #414). Even once the relaunch budget is spent,
    # earlier spots are still pre-ACKed so a restarted app
    # races through them and holds at the current one, and
    # the wait still runs.
    tour_do_recovery() {
      local SPOT="$1"
      if [ "$RECOVERY_STAGE" -lt 2 ]; then
        RECOVERY_STAGE=$((RECOVERY_STAGE + 1))
        echo "tour-progress: spot $SPOT recovery relaunch $RECOVERY_STAGE of 2" >> screenshots/tour-progress.txt
        xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
        sleep 3
        xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour || true
      fi
      if [ -n "$APP_DATA" ]; then
        local ACK_SPOT=0
        while [ "$ACK_SPOT" -lt "$SPOT" ]; do
          printf 'ack %s\n' "$ACK_SPOT" > "$APP_DATA/Documents/tour-ack-$ACK_SPOT.txt" 2>/dev/null || true
          ACK_SPOT=$((ACK_SPOT + 1))
        done
      fi
      tour_wait_ready "$SPOT" 420
    }
    PREV_MD5=""
    PREV_SHOT=""
    for SHOT in $TOUR_SHOTS; do
      SPOT=$TOUR_INDEX
      TOUR_INDEX=$((TOUR_INDEX + 1))
      if [ -z "$TOUR_LOG" ] && [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
        TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
      fi
      # 2026-11-12 capture protocol: a spot is photographed ONLY
      # after its READY has been seen in the demo log, and the ACK
      # is written only after a non-empty capture (or as the final
      # fallback for a skipped spot, below). CI #409 showed why
      # ACK discipline matters — each pre-written ACK released the
      # app's hold before it even arrived, and the filenames
      # drifted away from the content — and CI #412 showed that
      # shooting without READY is just as destructive. The app
      # holds a spot for 900 s, far longer than any sequence here.
      READY_SEEN=0
      LOG_GREW=0
      if [ -n "$TOUR_LOG" ]; then
        tour_wait_ready "$SPOT" 240
      fi
      if [ "$READY_SEEN" -eq 0 ] && [ "$LOG_GREW" -eq 1 ] && [ $((SECONDS - TOUR_START)) -lt 1500 ]; then
        # batch8 (CI #414): the app is alive — its log advanced
        # during the wait — it is simply slow (and after a
        # relaunch it needs minutes to boot and race through
        # the pre-ACKed spots). One extended wait instead of a
        # relaunch the app does not need.
        echo "tour-progress: spot $SPOT no-ready yet but log advancing; extending the wait" >> screenshots/tour-progress.txt
        tour_wait_ready "$SPOT" 240
      fi
      if [ "$READY_SEEN" -eq 0 ] && [ $((SECONDS - TOUR_START)) -lt 1500 ]; then
        echo "READY for tour spot $SPOT did not appear; recovering once before skipping the spot."
        tour_do_recovery "$SPOT"
      fi
      if [ "$READY_SEEN" -eq 1 ]; then
        sleep 5
        capture_still "$SHOT"
        if [ "$TOUR_SIZE" -eq 0 ]; then
          # batch8: a failed capture no longer triggers a
          # relaunch — CI #414 showed relaunches cannot fix a
          # broken capture path, and each one cost minutes of
          # tour budget. One plain retry, then skip the spot.
          sleep 10
          capture_still "$SHOT"
        fi
        if [ "$TOUR_SIZE" -gt 0 ]; then
          SHOT_MD5="$(md5 -q "screenshots/$SHOT.png" 2>/dev/null || md5sum "screenshots/$SHOT.png" 2>/dev/null | awk '{print $1}')"
          DUP_NOTE=""
          if [ -n "$SHOT_MD5" ] && [ "$SHOT_MD5" = "$PREV_MD5" ]; then
            DUP_NOTE=" DUPLICATE-CONTENT of $PREV_SHOT"
          fi
          PREV_MD5="$SHOT_MD5"
          PREV_SHOT="$SHOT"
          echo "tour-progress: spot $SPOT $SHOT elapsed=$((SECONDS - TOUR_START))s size=${TOUR_SIZE}B$DUP_NOTE" >> screenshots/tour-progress.txt
        else
          echo "tour-progress: spot $SPOT $SHOT FAILED capture elapsed=$((SECONDS - TOUR_START))s size=0B" >> screenshots/tour-progress.txt
        fi
        if [ -n "$TOUR_LOG" ]; then
          cp "$TOUR_LOG" screenshots/demo-drive-log-snapshot.txt 2>/dev/null || true
        fi
      else
        echo "tour-progress: spot $SPOT $SHOT FAILED no-ready elapsed=$((SECONDS - TOUR_START))s" >> screenshots/tour-progress.txt
      fi
      # Release the app to the next spot. On success this is the
      # handshake working as designed; for a skipped spot it is
      # the final fallback so one failure cannot stall the tour
      # (the app's own 900 s hold also releases itself).
      # APP_DATA is the app's data container on this host, so
      # writing the ACK file here is writing into the app's
      # Documents, which is exactly where the app polls for it.
      if [ -n "$APP_DATA" ]; then
        printf 'ack %s\n' "$SPOT" > "$APP_DATA/Documents/tour-ack-$SPOT.txt" 2>/dev/null || true
      fi
    done
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    # Short-line tours (quality41): the zoo and theme park lines are
    # separate routes the main tour never visits, so each gets its
    # own launch with its own argument and spot list, using the same
    # READY/ACK handshake. Stale ACK files and the previous demo log
    # are cleared first so the handshake starts clean.
    run_short_tour() {
      local EXTRA_ARG="$1"; shift
      local SHOTS="$*"
      rm -f "$APP_DATA/Documents"/tour-ack-*.txt 2>/dev/null || true
      rm -f "$APP_DATA/Documents/demo-drive-log.txt" 2>/dev/null || true
      xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour "$EXTRA_ARG" || true
      local SLOG=""
      local WAITLOG=0
      while [ "$WAITLOG" -lt 90 ]; do
        if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then SLOG="$APP_DATA/Documents/demo-drive-log.txt"; break; fi
        sleep 3; WAITLOG=$((WAITLOG + 3))
      done
      local IDX=0
      for SHOT in $SHOTS; do
        # batch9: hard deadline inside the short tour — stop
        # starting new spots once the tour's own budget is
        # spent, so this function returns in time for the
        # stages after it. batch44: the deadline is now
        # SHORT_TOUR_DEADLINE (set just before the zoo tour is
        # invoked below) instead of a JOB_START-relative gate
        # the main tour could starve — see the batch44 note at
        # the zoo/park invocation.
        if [ "$SECONDS" -ge "$SHORT_TOUR_DEADLINE" ]; then
          echo "tour-progress: short $EXTRA_ARG aborted at spot $IDX (short-tour budget)" >> screenshots/tour-progress.txt
          break
        fi
        # 2026-11-12: same rule as the main tour — no READY, no
        # photograph; the spot is logged FAILED and skipped (the
        # ACK below still releases the app). When the log never
        # appeared at all, fall back to the fixed step and shoot,
        # since there is nothing to verify against.
        local SHORT_READY=1
        if [ -n "$SLOG" ]; then
          SHORT_READY=0
          local WAITED=0
          while [ "$WAITED" -lt 150 ]; do
            local MAXREADY="$(grep -o 'READY spot=[0-9]*' "$SLOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
            if [ -n "$MAXREADY" ] && [ "$MAXREADY" -ge "$IDX" ]; then SHORT_READY=1; break; fi
            sleep 5; WAITED=$((WAITED + 5))
          done
          sleep 5
        else
          sleep 35
        fi
        if [ "$SHORT_READY" -eq 1 ]; then
          capture_still "$SHOT"
          echo "tour-progress: short $EXTRA_ARG spot $IDX $SHOT size=${TOUR_SIZE}B" >> screenshots/tour-progress.txt
        else
          echo "tour-progress: short $EXTRA_ARG spot $IDX $SHOT FAILED no-ready" >> screenshots/tour-progress.txt
        fi
        if [ -n "$APP_DATA" ]; then
          printf 'ack %s\n' "$IDX" > "$APP_DATA/Documents/tour-ack-$IDX.txt" 2>/dev/null || true
        fi
        IDX=$((IDX + 1))
      done
      xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
      sleep 3
    }
    # batch44 (2026-11-14): the short tours run here — directly
    # after the main tour and BEFORE the cab check and the audio
    # step — and they run unconditionally, no longer gated on
    # the JOB_START clock. The batch7/batch9 gate (start only
    # before 1,800 s) skipped BOTH tours two chains in a row
    # whenever the main tour degraded: its failure modes (READY
    # waits, relaunch recoveries) legitimately consume the
    # 1,500 s tour cap, by which time the 1,800 s gate had
    # already closed, while later stages (cab, audio) still
    # ran. The pair now shares its own 900 s deadline from the
    # moment this block starts (observed healthy cost is
    # ~35 s per spot, 10 spots plus two launches ≈ 400 s), so
    # the zoo and park photographs exist even if everything
    # after this block fails or is skipped.
    if [ -n "$APP_DATA" ]; then
      SHORT_TOUR_DEADLINE=$((SECONDS + 900))
      run_short_tour -RMZooTour 40-zoo-approach 41-zoo-penguins 42-zoo-lion 43-zoo-tiger 44-zoo-elephant 45-zoo-terminal
      run_short_tour -RMParkTour 46-park-entrance 47-park-grounds 48-park-wheel 49-park-terminal
    fi
    # Cab check: relaunch in the cab view and let the demo drive the
    # showcase section (origin to Matsubaracho, 1,856 m) so the
    # rebuilt cab is photographed running and standing at the
    # station. CI #221's fixed 195 s window left the drive at
    # pos 335 m — it never got near the station, and the station
    # stop-margin question stayed unverifiable. Now the arrival
    # shot waits until the cab log (demo-drive-log-cab.txt) reports
    # pos >= 1,850, capped at 300 s (batch9; 420 in batch7/8, 900 before) so the job
    # keeps a total budget; if it never arrives, the shot is taken
    # anyway with a warning and the log copied below shows how
    # far it got.
    # batch7: the whole cab check runs only while the job still
    # has budget (elapsed < 2,100 s, batch9); otherwise it is skipped and
    # logged, instead of being cut off by the 60-minute cap.
    if [ $((SECONDS - JOB_START)) -lt 2100 ]; then
    sleep 3
    # batch32 (2026-11-14): keeper-still wrapper for the cab
    # check. The wave-2 cab stills (20/21/22) and meet-1..3 all
    # came back byte-identical black (20,624 B) while meet-6 —
    # the same capture_still minutes later — rendered the cab
    # fine: the app shows a black screen until its first real
    # render, which on this loaded simulator can take many
    # minutes after launch, and every fixed wait expired inside
    # that black window. capture_still accepts a black frame
    # whenever the screenshot fallback returns any non-empty
    # file, so re-check the final PNG here: a real frame of
    # this scene is >100 KB; anything under 30 KB is a black
    # capture — wait and shoot again.
    # batch38 (2026-11-14): the size test was not enough — the
    # next failure mode was a pale blue-grey VOID frame (the
    # app past its black window but not yet rendering the
    # world) weighing 407-717 KB, which sailed through both
    # the >100 KB probe and the >=30 KB keeper test; 21-cab-
    # station and 22-home even came back byte-identical. The
    # keeper test is now CONTENT, calibrated on those very
    # frames: downscale with sips, parse the BMP in python3
    # (stdlib only), and sample the centre crop (the 3D view,
    # clear of the HUD panels). VOID frames measured
    # distinct<=54 quantized colours and adjdiff<=0.67; real
    # frames (meet-6, the station and zoo tours) measured
    # distinct>=711 and adjdiff>=6.04. PASS needs
    # distinct>=200 AND adjdiff>=2.5, an order-of-magnitude
    # margin both ways. A frame byte-identical to the
    # previous cab still is rejected too (frozen screen).
    # Every rejection logs CAB_CAPTURE_SUSPECT to stdout and
    # tour-progress.txt; if all tries fail, the last frame
    # stays on disk but is flagged, never silently "ok".
    CAB_LAST_STILL_MD5=""
    cab_png_verdict() {
      local FILE="$1"
      local BMP="/tmp/cabcheck-$$.bmp"
      rm -f "$BMP"
      if ! sips -s format bmp -z 656 301 "$FILE" --out "$BMP" >/dev/null 2>&1; then
        echo "SUSPECT(sips-failed)"
        return 0
      fi
      local OUT=""
      python3 - "$BMP" > "/tmp/cabcheck-$$.txt" <<'PYEOF' || true
import struct, sys

# batch41 (2026-11-14): the batch38 parser assumed the one BMP
# variant the local stub produced (40-byte header, BI_RGB) and
# rejected every frame of the first real chain run with
# "unsupported BMP": the borrowed Mac's sips writes a different
# variant. This parser is header-driven instead — data offset
# (@10), header size (@14), signed width/height (@18/@22),
# planes (@26), bpp (@28) and compression (@30) all come from
# the file itself; 24/32bpp, BI_RGB (0) and BI_BITFIELDS (3),
# bottom-up and top-down (negative height) are all accepted.
# Anything else raises with the header values it actually read
# in the message, so the next failure is diagnosable from the
# verdict string alone.
def read_bmp(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 54 or data[:2] != b"BM":
        raise ValueError("not a BMP (len=%d)" % len(data))
    data_off = struct.unpack_from("<I", data, 10)[0]
    header_size = struct.unpack_from("<I", data, 14)[0]
    if header_size < 40:
        raise ValueError(
            "unsupported BMP headerSize=%d len=%d" % (header_size, len(data)))
    width, height = struct.unpack_from("<ii", data, 18)
    planes, bpp = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]
    if (planes != 1 or bpp not in (24, 32) or compression not in (0, 3)
            or width <= 0 or height == 0):
        raise ValueError(
            "unsupported BMP headerSize=%d bpp=%d compression=%d "
            "width=%d height=%d planes=%d dataOff=%d"
            % (header_size, bpp, compression, width, height, planes, data_off))
    # Channel masks: BI_BITFIELDS stores them right after the
    # 40-byte info header (also where the V4/V5 headers keep
    # them); BI_RGB uses the standard BGR(A) byte order. Either
    # way a pixel is read as one little-endian integer and the
    # masks pick the channels out of it.
    rmask, gmask, bmask = 0xFF << 16, 0xFF << 8, 0xFF
    if compression == 3 and len(data) >= 66:
        rmask, gmask, bmask = struct.unpack_from("<III", data, 54)
        if rmask == 0 or gmask == 0 or bmask == 0:
            rmask, gmask, bmask = 0xFF << 16, 0xFF << 8, 0xFF
    def channel(value, mask):
        if mask == 0:
            return 0
        shift = (mask & -mask).bit_length() - 1
        raw = (value & mask) >> shift
        top = mask >> shift
        return (raw * 255) // top if top else 0
    if data_off == 0 or data_off >= len(data):
        data_off = 14 + header_size + (12 if compression == 3 and header_size == 40 else 0)
    top_down = height < 0
    height = abs(height)
    stride = ((bpp * width + 31) // 32) * 4
    pxb = bpp // 8
    rows = []
    for y in range(height):
        src_y = y if top_down else (height - 1 - y)
        base = data_off + src_y * stride
        row = []
        for x in range(width):
            off = base + x * pxb
            value = int.from_bytes(data[off:off + pxb], "little")
            row.append((channel(value, rmask), channel(value, gmask),
                        channel(value, bmask)))
        rows.append(row)
    return width, height, rows

try:
    w, h, rows = read_bmp(sys.argv[1])
    x0, x1 = int(w * 0.30), int(w * 0.92)
    y0, y1 = int(h * 0.25), int(h * 0.62)
    colours = set()
    diff_sum = 0
    diff_n = 0
    for y in range(y0, y1):
        row = rows[y]
        prev = None
        for x in range(x0, x1):
            r, g, b = row[x]
            colours.add((r >> 3, g >> 3, b >> 3))
            if prev is not None:
                diff_sum += abs(r - prev[0]) + abs(g - prev[1]) + abs(b - prev[2])
                diff_n += 3
            prev = (r, g, b)
    distinct = len(colours)
    adjdiff = diff_sum / max(diff_n, 1)
    if distinct >= 200 and adjdiff >= 2.5:
        print("PASS")
    else:
        print("SUSPECT distinct=%d adjdiff=%.2f" % (distinct, adjdiff))
except Exception as exc:
    print("SUSPECT(python: %s)" % exc)
PYEOF
      OUT=$(cat "/tmp/cabcheck-$$.txt" 2>/dev/null || echo "")
      rm -f "$BMP" "/tmp/cabcheck-$$.txt"
      if [ -z "$OUT" ]; then OUT="SUSPECT(no-output)"; fi
      echo "$OUT"
    }
    # batch41 (2026-11-14): retry budget trimmed 5 tries x 20 s
    # -> 3 tries x 10 s. This morning every verdict came back
    # "unsupported BMP" (a parser bug, not bad frames), so all
    # the cab stills burned their full 5 tries and the cab
    # phase ate the job budget — the zoo/park short tours were
    # SKIPPED. Worst case per still is now ~3 x (8 s recording
    # + extraction + verdict + 10 s) instead of ~5 x (...+20 s);
    # with the parser fixed, a genuinely rendered frame passes
    # on the first try, and a still that fails 3 content checks
    # is a scene problem, not a capture-timing one.
    capture_cab_still() {
      local NAME="$1"; local TRIES="${2:-3}"; local TRY=0
      while [ "$TRY" -lt "$TRIES" ]; do
        TRY=$((TRY + 1))
        capture_still "$NAME"
        local F="screenshots/$NAME.png"
        local SZ=0
        if [ -s "$F" ]; then SZ=$(stat -f %z "$F" 2>/dev/null || echo 0); fi
        if [ "$SZ" -lt 30000 ]; then
          echo "tour-progress: cab still $NAME black try=$TRY size=${SZ}B, waiting and retrying" >> screenshots/tour-progress.txt
          sleep 10
          continue
        fi
        local MD5=""
        MD5=$(md5 -q "$F" 2>/dev/null || echo "")
        if [ -n "$MD5" ] && [ "$MD5" = "$CAB_LAST_STILL_MD5" ]; then
          echo "CAB_CAPTURE_SUSPECT $NAME try=$TRY reason=identical-to-previous-still"
          echo "tour-progress: CAB_CAPTURE_SUSPECT $NAME try=$TRY reason=identical-to-previous-still" >> screenshots/tour-progress.txt
          sleep 10
          continue
        fi
        local VERDICT=""
        VERDICT=$(cab_png_verdict "$F")
        if [ "$VERDICT" != "PASS" ]; then
          echo "CAB_CAPTURE_SUSPECT $NAME try=$TRY reason=content verdict=$VERDICT size=${SZ}B"
          echo "tour-progress: CAB_CAPTURE_SUSPECT $NAME try=$TRY reason=content verdict=$VERDICT size=${SZ}B" >> screenshots/tour-progress.txt
          sleep 10
          continue
        fi
        CAB_LAST_STILL_MD5="$MD5"
        echo "tour-progress: cab still $NAME ok try=$TRY size=${SZ}B" >> screenshots/tour-progress.txt
        return 0
      done
      echo "CAB_CAPTURE_SUSPECT $NAME gave up after $TRIES tries; last frame kept on disk, NOT verified"
      echo "tour-progress: CAB_CAPTURE_SUSPECT $NAME gave up after $TRIES tries; last frame kept, NOT verified" >> screenshots/tour-progress.txt
      return 1
    }
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMCabView
    # batch32: probe with cheap screenshots until the app
    # actually renders a non-black frame (cap 600 s) before
    # trusting the drive log or taking keeper stills.
    CAB_PHASE_START=$SECONDS
    RENDER_OK=0
    while [ $((SECONDS - CAB_PHASE_START)) -lt 600 ]; do
      shot_with_timeout cab-probe 45
      if [ "$SHOT_OK" -eq 1 ]; then
        PROBE_SIZE=$(stat -f %z screenshots/cab-probe.png 2>/dev/null || echo 0)
        # batch38: size alone passed the 407-717 KB void frames;
        # the probe now also needs the content verdict (see
        # cab_png_verdict above).
        if [ "$PROBE_SIZE" -ge 30000 ]; then
          PROBE_VERDICT=$(cab_png_verdict screenshots/cab-probe.png)
          if [ "$PROBE_VERDICT" = "PASS" ]; then RENDER_OK=1; break; fi
          echo "tour-progress: cab probe content $PROBE_VERDICT size=${PROBE_SIZE}B" >> screenshots/tour-progress.txt
        fi
      fi
      sleep 15
    done
    rm -f screenshots/cab-probe.png
    echo "tour-progress: cab render probe ok=$RENDER_OK after $((SECONDS - CAB_PHASE_START))s" >> screenshots/tour-progress.txt
    if [ "$RENDER_OK" -eq 0 ]; then
      echo "CAB_CAPTURE_SUSPECT probe: no content-verified frame within 600 s"
      echo "tour-progress: CAB_CAPTURE_SUSPECT probe never verified within 600 s" >> screenshots/tour-progress.txt
    fi
    CAB_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log-cab.txt" ]; then
      CAB_LOG="$APP_DATA/Documents/demo-drive-log-cab.txt"
    fi
    # CI #199: 55 s left the cab shot black (scene still loading on
    # the simulator). 2026-11-12: instead of the old fixed 90 s
    # sleep, wait until the cab log shows the demo drive actually
    # moving (pos > 30 m), capped at 240 s (batch7). In CI #412 the fixed
    # sleep photographed a train that had not departed — and
    # barely ever did within the job — so both cab shots were
    # void. The shot is still taken after the cap with a warning:
    # the cab check is diagnostic, and the copied log shows how
    # far the drive actually got.
    CAB_MOVE_WAITED=0
    CAB_MOVING=0
    while [ "$CAB_MOVE_WAITED" -lt 240 ]; do
      if [ -z "$CAB_LOG" ] && [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log-cab.txt" ]; then
        CAB_LOG="$APP_DATA/Documents/demo-drive-log-cab.txt"
      fi
      if [ -n "$CAB_LOG" ]; then
        CAB_NOW_POS="$(grep -o ' pos=[0-9.]*' "$CAB_LOG" 2>/dev/null | tail -1 | grep -o '[0-9.]*$')"
        CAB_NOW_INT="${CAB_NOW_POS%.*}"
        if [ -n "$CAB_NOW_INT" ] && [ "$CAB_NOW_INT" -gt 30 ]; then CAB_MOVING=1; break; fi
      fi
      sleep 10
      CAB_MOVE_WAITED=$((CAB_MOVE_WAITED + 10))
    done
    if [ "$CAB_MOVING" -eq 0 ]; then
      echo "Cab drive did not start moving (pos > 30) within 240 s; shooting the running shot anyway."
    fi
    capture_cab_still 20-cab-running
    CAB_WAITED=0
    CAB_ARRIVED=0
    while [ "$CAB_WAITED" -lt 300 ]; do
      if [ -n "$CAB_LOG" ]; then
        CAB_POS="$(grep -o ' pos=[0-9.]*' "$CAB_LOG" 2>/dev/null | tail -1 | grep -o '[0-9.]*$')"
        CAB_POS_INT="${CAB_POS%.*}"
        if [ -n "$CAB_POS_INT" ] && [ "$CAB_POS_INT" -ge 1850 ]; then CAB_ARRIVED=1; break; fi
      fi
      sleep 10
      CAB_WAITED=$((CAB_WAITED + 10))
    done
    if [ "$CAB_ARRIVED" -eq 0 ]; then
      echo "Cab drive did not reach Matsubaracho (pos >= 1850) within 300 s; shooting anyway."
    fi
    sleep 5
    capture_cab_still 21-cab-station
    # 2026-11-13: 22-home used to be captured AFTER the terminate
    # below, so it only ever showed the iOS home screen. Capture
    # it while the app is still running (cab view at the station,
    # end of the drive).
    capture_cab_still 22-home
    # batch19: meet hunt. 798 diagram trains are the product's
    # headline, yet no tour photo has ever caught an opposing
    # train: the tour teleports and holds still, and the two cab
    # stills are single 8 s windows. The demo drive keeps running
    # past Matsubaracho, so spend up to ~2.5 more minutes taking
    # a still every ~20 s; an opposing pass is visible through
    # the windshield for several seconds, and six windows give
    # it a fair chance to land in one. Guarded by the job budget
    # like the rest of the cab check.
    MEET_N=0
    while [ "$MEET_N" -lt 6 ] && [ $((SECONDS - JOB_START)) -lt 2550 ]; do
      MEET_N=$((MEET_N + 1))
      capture_cab_still "23-meet-$MEET_N" 2 || true
      sleep 8
    done
    echo "tour-progress: meet hunt took $MEET_N stills" >> screenshots/tour-progress.txt
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    else
      echo "tour-progress: cab check SKIPPED (job budget)" >> screenshots/tour-progress.txt
    fi
    # Demo-drive state log (the app writes it in -RMDemoDrive mode).
    APP_DATA="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
      cp "$APP_DATA/Documents/demo-drive-log.txt" screenshots/ || true
    fi
    # CI #199: the cab relaunch now writes its own log file; keep it too.
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log-cab.txt" ]; then
      cp "$APP_DATA/Documents/demo-drive-log-cab.txt" screenshots/ || true
    fi
    # quality39: the world writes the level-crossing chainages it
    # placed; keep the list so tour spots can be aimed exactly.
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/rm-crossings.txt" ]; then
      cp "$APP_DATA/Documents/rm-crossings.txt" screenshots/ || true
    fi
    sleep 3
    # 2026-11-13: 22-home is now captured before the cab terminate
    # above (see there); nothing to shoot after the app is gone.
    # quality26: capture the device log once more at the very
    # end. The device-log.txt capture near the top only covers
    # the first minutes of the run; in CI #238 everything
    # interesting happened half an hour later and was gone.
    xcrun simctl spawn "$SIMULATOR_UDID" log show --style compact --last 10m --predicate 'process == "RailwayMasterPhase1"' 2>/dev/null | tail -c 150000 > screenshots/device-log-final.txt || true
    # batch33 (2026-11-14): drive-audio capture, at the user's
    # request (音も確認したい). Everything above ran with
    # RM_DISABLE_AUDIO=1 (the CoreAudio safeguard), so this is a
    # separate, final launch with the audio engine enabled. With
    # RM_RECORD_AUDIO=1 the app taps its own main mixer and writes
    # Documents/rm_drive_audio.caf, auto-stopping after 400 s and
    # dropping an rm_drive_audio.done marker; the demo drive covers
    # departure chime -> acceleration -> cruise -> braking ->
    # arrival -> door chime. TTS station announcements bypass the
    # app mixer and are NOT in the recording. Every step is
    # best-effort so a failure here can never fail the photo run.
    echo "tour-progress: audio capture starting" >> screenshots/tour-progress.txt
    export SIMCTL_CHILD_RM_DISABLE_AUDIO=0
    export SIMCTL_CHILD_RM_RECORD_AUDIO=1
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 2
    APP_DATA="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
    if [ -n "$APP_DATA" ]; then
      rm -f "$APP_DATA/Documents/rm_drive_audio.caf" "$APP_DATA/Documents/rm_drive_audio.done" "$APP_DATA/Documents/rm_drive_audio_status.txt" 2>/dev/null || true
    fi
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMCabView || true
    # batch44 (2026-11-14): the wait is capped at 120 s, not
    # 540 s. In the batch40+41 chain the recorder's status file
    # stopped at "recorder created" — the audio engine hung in
    # init around engine.prepare() (the known simulator
    # CoreAudio deadlock documented in RailwayAudioEngine.swift)
    # before the tap was ever attempted, and the remaining
    # ~9 minutes of waiting could not change that. 120 s is
    # ample for the engine to come up and the tap to install
    # when it is going to; a recording already in progress
    # still leaves a .caf the fallback below salvages after
    # the terminate.
    AUDIO_WAIT_START=$SECONDS
    while [ $((SECONDS - AUDIO_WAIT_START)) -lt 120 ]; do
      if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/rm_drive_audio.done" ]; then break; fi
      sleep 15
    done
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 2
    # batch41: the recorder now narrates every step into
    # Documents/rm_drive_audio_status.txt (created / format /
    # file creation error / first buffer / stop bytes). Pick it
    # up unconditionally so a failed capture explains itself in
    # the artifact instead of just "no recording file".
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/rm_drive_audio_status.txt" ]; then
      cp "$APP_DATA/Documents/rm_drive_audio_status.txt" screenshots/rm-drive-audio-status.txt || true
    fi
    if [ -n "$APP_DATA" ] && [ -s "$APP_DATA/Documents/rm_drive_audio.caf" ]; then
      rm -f screenshots/rm-drive-audio.m4a
      if afconvert -f m4af -d aac@48000 -b 128000 "$APP_DATA/Documents/rm_drive_audio.caf" screenshots/rm-drive-audio.m4a 2>/dev/null; then
        echo "tour-progress: audio capture ok (m4a)" >> screenshots/tour-progress.txt
      else
        cp "$APP_DATA/Documents/rm_drive_audio.caf" screenshots/rm-drive-audio.caf || true
        echo "tour-progress: audio capture ok (caf fallback)" >> screenshots/tour-progress.txt
      fi
    elif [ -f screenshots/rm-drive-audio-status.txt ] \
        && grep -q "recorder created" screenshots/rm-drive-audio-status.txt \
        && ! grep -q "tap start attempt" screenshots/rm-drive-audio-status.txt \
        && ! grep -q "tap installed" screenshots/rm-drive-audio-status.txt; then
      # batch44: the recorder was created but its tap was never
      # even attempted — the engine hung during init (around
      # engine.prepare()) before start(on:) could run. Name it
      # in the progress log instead of a bare "no recording
      # file", so the failure is diagnosable from tour-progress
      # alone (the full status file is collected above either
      # way).
      echo "tour-progress: audio capture FAILED (audio engine init hang (known simulator CoreAudio deadlock) - recorder created but tap never attempted; see rm-drive-audio-status.txt)" >> screenshots/tour-progress.txt
    else
      echo "tour-progress: audio capture FAILED (no recording file)" >> screenshots/tour-progress.txt
    fi
    export SIMCTL_CHILD_RM_DISABLE_AUDIO=1
    export SIMCTL_CHILD_RM_RECORD_AUDIO=0
    ls -la screenshots/
    ;;
  packages)
    xcodebuild -version
    swift --version
    SIMULATOR_UDID="$(pick_simulator)" || exit 1
    # quality27: same CoreAudio safeguard as the build mode.
    export SIMCTL_CHILD_RM_DISABLE_AUDIO=1
    echo "Using simulator UDID: $SIMULATOR_UDID"
    FAILED=""
    for manifest in Packages/*/Package.swift; do
      dir=$(dirname "$manifest")
      name=$(sed -n 's/.*name: *"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
      echo "::group::swift package: $name ($dir)"
      # Packages without a test target have no scheme configured for the test
      # action, so build them instead of testing them.
      if grep -q '\.testTarget' "$manifest"; then
        (cd "$dir" && xcodebuild test \
          -scheme "$name" \
          -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
          CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH") 2>&1 | tee "package-test-$name.log"
        status=${PIPESTATUS[0]}
        # A few packages declare a test target but their autogenerated scheme
        # is still not configured for the test action; fall back to a build
        # for that specific failure only (real test failures still fail).
        if [ "$status" -ne 0 ] && grep -q "is not currently configured for the test action" "package-test-$name.log"; then
          echo "Scheme $name is not configured for the test action; falling back to xcodebuild build."
          (cd "$dir" && xcodebuild build \
            -scheme "$name" \
            -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
            CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH") 2>&1 | tee -a "package-test-$name.log"
          status=${PIPESTATUS[0]}
        fi
      else
        echo "No test target in $manifest; running xcodebuild build instead of test."
        (cd "$dir" && xcodebuild build \
          -scheme "$name" \
          -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
          CODE_SIGNING_ALLOWED=NO ARCHS="$HOST_ARCH") 2>&1 | tee "package-test-$name.log"
        status=${PIPESTATUS[0]}
      fi
      echo "::endgroup::"
      if [ "$status" -ne 0 ]; then
        FAILED="$FAILED $name"
      fi
    done
    if [ -n "$FAILED" ]; then
      echo "FAILED packages:$FAILED"
      exit 1
    fi
    echo "All local packages passed."
    ;;
  ipa)
    # Unsigned device build, packaged as an .ipa so the owner can sign it
    # with a free Apple ID on their own Windows PC (Sideloadly) and install
    # it on their iPhone. Free provisioning expires after 7 days.
    xcodebuild -version
    xcodebuild -resolvePackageDependencies \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1
    # Device IPA is always arm64 (iPhones are arm64); HOST_ARCH is the
    # *simulator* arch and must NOT be used here — on the Intel Mac it
    # would build an x86_64 device binary no iPhone can run.
    # Release, not Debug: the Debug build's synchronous launch-time world
    # build exceeded the 20 s scene-create watchdog on a real iPhone
    # (0x8BADF00D kill, 2026-11-15). Do not switch this back to Debug.
    set -o pipefail
    xcodebuild build \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Release \
      -destination 'generic/platform=iOS' \
      -derivedDataPath build/DerivedDataIPA \
      CODE_SIGNING_ALLOWED=NO ARCHS="arm64" \
      | tee ipa-build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    APP_PATH="$(find build/DerivedDataIPA/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -n 1)"
    if [ -z "$APP_PATH" ]; then echo "Built .app not found" >&2; exit 1; fi
    echo "Built app: $APP_PATH"
    rm -rf Payload RailwayMaster.ipa
    mkdir -p Payload
    cp -R "$APP_PATH" Payload/
    zip -qry RailwayMaster.ipa Payload
    ls -la RailwayMaster.ipa
    ;;
  *)
    echo "usage: ci_run.sh [static|build|packages|screenshots|ipa]" >&2
    exit 2
    ;;
esac
