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
    xcrun simctl io "$SIMULATOR_UDID" recordVideo --codec=h264 screenshots/launch-video.mov &
    VIDEO_PID=$!
    sleep 4
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/01-launch.png || true
    sleep 8
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/02-main.png || true
    sleep 14
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/03-settled.png || true
    kill -INT "$VIDEO_PID" 2>/dev/null || true
    wait "$VIDEO_PID" 2>/dev/null || true
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
    # spot; a spot whose captures all fail escalates recovery
    # (app relaunch, then simulator reboot) before one final ACK
    # releases the app anyway.
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
    # 2026-11-11 tour-hardening state: recovery escalation stage
    # for wedged captures (0 = none yet, 1 = app relaunched,
    # 2 = simulator rebooted). CI #409 attempt 1 lost every shot
    # from spot 3 onward to persistent 0-byte captures that the
    # old one-shot app relaunch could not clear.
    RECOVERY_STAGE=0
    : > screenshots/tour-progress.txt
    # One capture with up to 3 attempts; sets TOUR_SIZE to the
    # resulting file size (0 when every attempt came back empty).
    tour_try_capture() {
      TOUR_SIZE=0
      local tries=0
      while [ "$tries" -lt 3 ]; do
        xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$1.png" 2>/dev/null || true
        TOUR_SIZE=0
        if [ -f "screenshots/$1.png" ]; then
          TOUR_SIZE=$(stat -f %z "screenshots/$1.png" 2>/dev/null || echo 0)
        fi
        if [ "$TOUR_SIZE" -gt 0 ]; then return 0; fi
        tries=$((tries + 1))
        if [ "$tries" -lt 3 ]; then sleep 8; fi
      done
      return 1
    }
    # 2026-11-12: wait until the demo log shows READY for spot $1
    # (or a later one), up to $2 seconds; also stops at the
    # 2,400 s tour cap. Sets READY_SEEN.
    tour_wait_ready() {
      READY_SEEN=0
      local WANT="$1"; local CAP="$2"; local WAITED=0
      while [ "$WAITED" -lt "$CAP" ]; do
        if [ -n "$TOUR_LOG" ]; then
          local MAXREADY="$(grep -o 'READY spot=[0-9]*' "$TOUR_LOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
          if [ -n "$MAXREADY" ] && [ "$MAXREADY" -ge "$WANT" ]; then READY_SEEN=1; return 0; fi
        fi
        if [ $((SECONDS - TOUR_START)) -ge 2400 ]; then return 0; fi
        sleep 5
        WAITED=$((WAITED + 5))
      done
    }
    # 2026-11-12: escalating recovery for a wedged tour (app
    # relaunch, then simulator reboot — CI #409's wedge survived
    # a relaunch), then wait for the current spot's READY again.
    # Pre-ACKs every earlier spot so the restarted app races
    # through them and holds at the current one.
    tour_do_recovery() {
      local SPOT="$1"
      if [ "$RECOVERY_STAGE" -lt 2 ]; then
        RECOVERY_STAGE=$((RECOVERY_STAGE + 1))
        if [ "$RECOVERY_STAGE" -eq 1 ]; then
          echo "tour-progress: spot $SPOT recovery stage 1: relaunching the app" >> screenshots/tour-progress.txt
          xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
          sleep 3
          xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour || true
        else
          echo "tour-progress: spot $SPOT recovery stage 2: rebooting the simulator" >> screenshots/tour-progress.txt
          xcrun simctl shutdown "$SIMULATOR_UDID" 2>/dev/null || true
          sleep 5
          xcrun simctl boot "$SIMULATOR_UDID" || true
          xcrun simctl bootstatus "$SIMULATOR_UDID" -b || true
          APP_DATA="$(xcrun simctl get_app_container "$SIMULATOR_UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
          if [ -n "$APP_DATA" ]; then
            TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
          fi
          xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour || true
        fi
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
      if [ -n "$TOUR_LOG" ]; then
        tour_wait_ready "$SPOT" 420
      fi
      if [ "$READY_SEEN" -eq 0 ] && [ $((SECONDS - TOUR_START)) -lt 2400 ]; then
        echo "READY for tour spot $SPOT did not appear; recovering once before skipping the spot."
        tour_do_recovery "$SPOT"
      fi
      if [ "$READY_SEEN" -eq 1 ]; then
        sleep 5
        tour_try_capture "$SHOT"
        if [ "$TOUR_SIZE" -eq 0 ]; then
          # Capture wedge (CI #409): recover and try once more.
          tour_do_recovery "$SPOT"
          if [ "$READY_SEEN" -eq 1 ]; then
            sleep 5
            tour_try_capture "$SHOT"
          fi
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
          while [ "$WAITED" -lt 240 ]; do
            local MAXREADY="$(grep -o 'READY spot=[0-9]*' "$SLOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
            if [ -n "$MAXREADY" ] && [ "$MAXREADY" -ge "$IDX" ]; then SHORT_READY=1; break; fi
            sleep 5; WAITED=$((WAITED + 5))
          done
          sleep 5
        else
          sleep 35
        fi
        if [ "$SHORT_READY" -eq 1 ]; then
          tour_try_capture "$SHOT"
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
    if [ -n "$APP_DATA" ]; then
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
    # pos >= 1,850, capped at 900 s so the job keeps a total
    # budget; if it never arrives, the shot is taken anyway with a
    # warning and the log copied below shows how far it got.
    sleep 3
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMCabView
    CAB_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log-cab.txt" ]; then
      CAB_LOG="$APP_DATA/Documents/demo-drive-log-cab.txt"
    fi
    # CI #199: 55 s left the cab shot black (scene still loading on
    # the simulator). 2026-11-12: instead of the old fixed 90 s
    # sleep, wait until the cab log shows the demo drive actually
    # moving (pos > 30 m), capped at 420 s. In CI #412 the fixed
    # sleep photographed a train that had not departed — and
    # barely ever did within the job — so both cab shots were
    # void. The shot is still taken after the cap with a warning:
    # the cab check is diagnostic, and the copied log shows how
    # far the drive actually got.
    CAB_MOVE_WAITED=0
    CAB_MOVING=0
    while [ "$CAB_MOVE_WAITED" -lt 420 ]; do
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
      echo "Cab drive did not start moving (pos > 30) within 420 s; shooting the running shot anyway."
    fi
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/20-cab-running.png 2>/dev/null || true
    CAB_WAITED=0
    CAB_ARRIVED=0
    while [ "$CAB_WAITED" -lt 900 ]; do
      if [ -n "$CAB_LOG" ]; then
        CAB_POS="$(grep -o ' pos=[0-9.]*' "$CAB_LOG" 2>/dev/null | tail -1 | grep -o '[0-9.]*$')"
        CAB_POS_INT="${CAB_POS%.*}"
        if [ -n "$CAB_POS_INT" ] && [ "$CAB_POS_INT" -ge 1850 ]; then CAB_ARRIVED=1; break; fi
      fi
      sleep 10
      CAB_WAITED=$((CAB_WAITED + 10))
    done
    if [ "$CAB_ARRIVED" -eq 0 ]; then
      echo "Cab drive did not reach Matsubaracho (pos >= 1850) within 900 s; shooting anyway."
    fi
    sleep 5
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/21-cab-station.png 2>/dev/null || true
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
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
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/22-home.png 2>/dev/null || true
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
