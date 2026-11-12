#!/usr/bin/env bash
# RAILWAY MASTER - CI step implementations, called from .github/workflows/ios-ci.yml
# Usage: bash Scripts/ci_run.sh [static|build|packages|screenshots]
set -u
mode="${1:-}"

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
      CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ENABLE_TESTABILITY=YES \
      | tee build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    xcodebuild test-without-building \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Debug \
      -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
      -resultBundlePath TestResults.xcresult \
      CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ENABLE_TESTABILITY=YES \
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
      CODE_SIGNING_ALLOWED=NO ARCHS=arm64 \
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
    extract_frame() {
      local MOV="$1"; local PNG="$2"; local SEC="$3"
      rm -f "$PNG"
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
    xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 screenshots/launch-video.mov &
    VIDEO_PID=$!
    sleep 4
    sleep 8
    sleep 14
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
    # batch8: the launch stills are frames of the launch video
    # (at ~4 s, ~12 s and ~24 s), not separate screenshot calls.
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
    TOUR_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
      TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
    fi
    TOUR_SHOTS="04-st01-kaibukuro 05-st02-asanuma 06-st03-oginuma 07-st04-ohara 08-st05-ishigamiike 09-st06-hibarigaoka 10-st07-akimizu 11-st08-wakakusadai 12-st09-higashimurakawa 13-st10-nishitachikawa 14-st11-hihara 15-st12-tououchihara 16-st13-makufu 17-st14-tsudaike 18-st15-mikkaido 19-st16-misagi 20-st17-touousahara 21-st18-shigeno 22-st19-kazusaninomiya 23-st20-togane 24-st21-katsunuma 25-st22-kisaragawa 26-st23-namihana 27-st24-ohno 28-st25-mihama 29-st26-tatekawa 30-st27-chikura 31-st28-kamogawa 32-st29-kuruno 33-st30-ohbitsu 34-st31-hirayama 35-st32-kazusaryuzan 36-crossing-17965 37-crossing-3605 38-akimizu-fan"
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
        if extract_frame "screenshots/$NAME.mov" "screenshots/$NAME.png" 5; then
          TOUR_SIZE=$(stat -f %z "screenshots/$NAME.png" 2>/dev/null || echo 0)
          rm -f "screenshots/$NAME.mov"
          echo "tour-progress: capture $NAME via video ok size=${TOUR_SIZE}B" >> screenshots/tour-progress.txt
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
    # 1,800 s tour cap (batch7). Sets READY_SEEN, and LOG_GREW
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
        if [ $((SECONDS - TOUR_START)) -ge 1800 ]; then return 0; fi
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
      if [ "$READY_SEEN" -eq 0 ] && [ "$LOG_GREW" -eq 1 ] && [ $((SECONDS - TOUR_START)) -lt 1800 ]; then
        # batch8 (CI #414): the app is alive — its log advanced
        # during the wait — it is simply slow (and after a
        # relaunch it needs minutes to boot and race through
        # the pre-ACKed spots). One extended wait instead of a
        # relaunch the app does not need.
        echo "tour-progress: spot $SPOT no-ready yet but log advancing; extending the wait" >> screenshots/tour-progress.txt
        tour_wait_ready "$SPOT" 240
      fi
      if [ "$READY_SEEN" -eq 0 ] && [ $((SECONDS - TOUR_START)) -lt 1800 ]; then
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
    # batch7: each short tour starts only while the job still
    # has budget (elapsed < 2,400 s); a skipped tour is logged
    # instead of being cut off by the 60-minute job cap.
    if [ -n "$APP_DATA" ]; then
      if [ $((SECONDS - JOB_START)) -lt 2400 ]; then
        run_short_tour -RMZooTour 40-zoo-approach 41-zoo-penguins 42-zoo-lion 43-zoo-tiger 44-zoo-elephant 45-zoo-terminal
      else
        echo "tour-progress: zoo short tour SKIPPED (job budget)" >> screenshots/tour-progress.txt
      fi
      if [ $((SECONDS - JOB_START)) -lt 2400 ]; then
        run_short_tour -RMParkTour 46-park-entrance 47-park-grounds 48-park-wheel 49-park-terminal
      else
        echo "tour-progress: park short tour SKIPPED (job budget)" >> screenshots/tour-progress.txt
      fi
    fi
    # Cab check: relaunch in the cab view and let the demo drive the
    # showcase section (origin to Matsubaracho, 1,856 m) so the
    # rebuilt cab is photographed running and standing at the
    # station. CI #221's fixed 195 s window left the drive at
    # pos 335 m — it never got near the station, and the station
    # stop-margin question stayed unverifiable. Now the arrival
    # shot waits until the cab log (demo-drive-log-cab.txt) reports
    # pos >= 1,850, capped at 420 s (batch7; was 900 s) so the job
    # keeps a total budget; if it never arrives, the shot is taken
    # anyway with a warning and the log copied below shows how
    # far it got.
    # batch7: the whole cab check runs only while the job still
    # has budget (elapsed < 2,700 s); otherwise it is skipped and
    # logged, instead of being cut off by the 60-minute cap.
    if [ $((SECONDS - JOB_START)) -lt 2700 ]; then
    sleep 3
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMCabView
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
    capture_still 20-cab-running
    CAB_WAITED=0
    CAB_ARRIVED=0
    while [ "$CAB_WAITED" -lt 420 ]; do
      if [ -n "$CAB_LOG" ]; then
        CAB_POS="$(grep -o ' pos=[0-9.]*' "$CAB_LOG" 2>/dev/null | tail -1 | grep -o '[0-9.]*$')"
        CAB_POS_INT="${CAB_POS%.*}"
        if [ -n "$CAB_POS_INT" ] && [ "$CAB_POS_INT" -ge 1850 ]; then CAB_ARRIVED=1; break; fi
      fi
      sleep 10
      CAB_WAITED=$((CAB_WAITED + 10))
    done
    if [ "$CAB_ARRIVED" -eq 0 ]; then
      echo "Cab drive did not reach Matsubaracho (pos >= 1850) within 420 s; shooting anyway."
    fi
    sleep 5
    capture_still 21-cab-station
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
    capture_still 22-home
    # quality26: capture the device log once more at the very
    # end. The device-log.txt capture near the top only covers
    # the first minutes of the run; in CI #238 everything
    # interesting happened half an hour later and was gone.
    xcrun simctl spawn "$SIMULATOR_UDID" log show --style compact --last 10m --predicate 'process == "RailwayMasterPhase1"' 2>/dev/null | tail -c 150000 > screenshots/device-log-final.txt || true
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
          CODE_SIGNING_ALLOWED=NO ARCHS=arm64) 2>&1 | tee "package-test-$name.log"
        status=${PIPESTATUS[0]}
        # A few packages declare a test target but their autogenerated scheme
        # is still not configured for the test action; fall back to a build
        # for that specific failure only (real test failures still fail).
        if [ "$status" -ne 0 ] && grep -q "is not currently configured for the test action" "package-test-$name.log"; then
          echo "Scheme $name is not configured for the test action; falling back to xcodebuild build."
          (cd "$dir" && xcodebuild build \
            -scheme "$name" \
            -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
            CODE_SIGNING_ALLOWED=NO ARCHS=arm64) 2>&1 | tee -a "package-test-$name.log"
          status=${PIPESTATUS[0]}
        fi
      else
        echo "No test target in $manifest; running xcodebuild build instead of test."
        (cd "$dir" && xcodebuild build \
          -scheme "$name" \
          -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
          CODE_SIGNING_ALLOWED=NO ARCHS=arm64) 2>&1 | tee "package-test-$name.log"
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
    set -o pipefail
    xcodebuild build \
      -project RailwayMasterPhase1.xcodeproj \
      -scheme RailwayMasterPhase1 \
      -configuration Debug \
      -destination 'generic/platform=iOS' \
      -derivedDataPath build/DerivedDataIPA \
      CODE_SIGNING_ALLOWED=NO ARCHS=arm64 \
      | tee ipa-build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    APP_PATH="$(find build/DerivedDataIPA/Build/Products/Debug-iphoneos -maxdepth 1 -name '*.app' | head -n 1)"
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
