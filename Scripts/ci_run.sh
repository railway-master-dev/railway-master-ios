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
      CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ENABLE_TESTABILITY=YES \
      | tee build.log
    build_status=$?
    if [ "$build_status" -ne 0 ]; then exit "$build_status"; fi
    xcodebuild test \
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
    # -RMDemoDrive -RMTour: the app teleports the standing train to a
    # new scenic chainage every ~35 s of wall time (first at ~25 s),
    # so one launch photographs sixteen different places along the
    # line (the showcase section's P1-P7 points, then line-wide).
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour
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
    # Documents/tour-ack-<i>.txt — which the script does right
    # after each screenshot — or 150 s pass. quality24's READY-only
    # version still drifted (CI #232: 7 of 16 spots at their
    # labelled positions, three black frames, six duplicates of
    # one stretch of coast) because the app teleported on its own
    # 35 s schedule while a loaded simulator took tens of seconds
    # per simctl screenshot: by the time a capture executed, the
    # train had moved on. Now the train cannot move on. Each shot
    # below waits for its spot's READY (per-spot cap 300 s, tour
    # cap 2,400 s), settles 5 s, shoots, then writes the ACK that
    # releases the app to the next spot. If a READY never comes,
    # the shot is taken anyway with a warning (the app times out
    # and advances on its own; the ACK write below is still
    # attempted, and later waits drop to the bare settle); if the
    # log never appears at all, the loop falls back to fixed 35 s
    # steps and still writes ACKs when the container is known.
    # Spots (tourSpotsM in SimulatorModel.swift, in order): the
    # quality24 showcase photo points P1-P7 first — 100 m departure
    # / 500 m viaduct start / 1,000 m catenary rhythm / 1,300 m
    # transition curve / 1,654 m curve apex R450 / 1,800 m station
    # approach / 1,856 m stop position — then the line-wide tour:
    # 3,006 m R467 / 4,466 m R324 sharpest / 6,522 m R902 /
    # 9,081 m just before the river bridge / 12,986 m R693 /
    # 17,650 m tunnel portal / 23,475 m R789 / 45,327 m sea R1326 /
    # 58,557 m sea R845.
    TOUR_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
      TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
    fi
    TOUR_SHOTS="04-tour-p1-departure 05-tour-p2-viaduct-start 06-tour-p3-catenary-rhythm 07-tour-p4-transition 08-tour-p5-apex 09-tour-p6-station-approach 10-tour-p7-stop-position 11-tour-3006-curve 12-tour-4466-sharpest 13-tour-6522 14-tour-9081-river-bridge 15-tour-12986 16-tour-17650-tunnel-portal 17-tour-23475 18-tour-45327-sea 19-tour-58557-sea"
    TOUR_START=$SECONDS
    TOUR_STALLED=0
    TOUR_INDEX=0
    # quality26 tour-hardening state: consecutive empty captures
    # and the one-shot relaunch guard used after the screenshot
    # below (see the comments there).
    EMPTY_STREAK=0
    TOUR_RELAUNCHED=0
    : > screenshots/tour-progress.txt
    for SHOT in $TOUR_SHOTS; do
      SPOT=$TOUR_INDEX
      TOUR_INDEX=$((TOUR_INDEX + 1))
      if [ -z "$TOUR_LOG" ] && [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
        TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
      fi
      if [ -n "$TOUR_LOG" ] && [ "$TOUR_STALLED" -eq 0 ]; then
        WAITED=0
        READY_SEEN=0
        while [ "$WAITED" -lt 300 ]; do
          MAXREADY="$(grep -o 'READY spot=[0-9]*' "$TOUR_LOG" 2>/dev/null | grep -o '[0-9]*$' | sort -n | tail -1)"
          if [ -n "$MAXREADY" ] && [ "$MAXREADY" -ge "$SPOT" ]; then READY_SEEN=1; break; fi
          if [ $((SECONDS - TOUR_START)) -ge 2400 ]; then break; fi
          sleep 5
          WAITED=$((WAITED + 5))
        done
        if [ "$READY_SEEN" -eq 0 ]; then
          echo "READY for tour spot $SPOT never appeared in the demo log; shooting anyway and shortening later waits."
          TOUR_STALLED=1
        fi
        sleep 5
      elif [ "$TOUR_STALLED" -eq 1 ]; then
        sleep 5
      else
        sleep 35
      fi
      xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$SHOT.png" 2>/dev/null || true
      # quality26: a wedged capture can leave a missing or 0-byte
      # file — CI #238 lost every shot from spot 8 onward that way
      # and kept no usable tour log to diagnose it with. Retry an
      # empty capture once after a short wait, record every shot's
      # outcome in tour-progress.txt, and snapshot the demo log
      # after each spot so the freshest partial log survives even
      # if the run wedges later.
      SHOT_SIZE=0
      if [ -f "screenshots/$SHOT.png" ]; then
        SHOT_SIZE=$(stat -f %z "screenshots/$SHOT.png" 2>/dev/null || echo 0)
      fi
      if [ "$SHOT_SIZE" -eq 0 ]; then
        echo "tour-progress: spot $SPOT $SHOT empty after first attempt; retrying in 10 s" >> screenshots/tour-progress.txt
        sleep 10
        xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$SHOT.png" 2>/dev/null || true
        if [ -f "screenshots/$SHOT.png" ]; then
          SHOT_SIZE=$(stat -f %z "screenshots/$SHOT.png" 2>/dev/null || echo 0)
        fi
      fi
      echo "tour-progress: spot $SPOT $SHOT elapsed=$((SECONDS - TOUR_START))s size=${SHOT_SIZE}B" >> screenshots/tour-progress.txt
      if [ -n "$TOUR_LOG" ]; then
        cp "$TOUR_LOG" screenshots/demo-drive-log-snapshot.txt 2>/dev/null || true
      fi
      # quality26 recovery: two empty shots in a row mean the app
      # or the simulator has wedged, not a slow frame. Relaunch
      # the tour once and pre-ACK every already-photographed spot
      # (tour-ack-0 .. tour-ack-(SPOT-1)) so the restarted app
      # races through them — it still spends its ~4 s of sim time
      # at each — and holds again at the current spot. The normal
      # ACK write below then releases it onward as usual.
      if [ "$SHOT_SIZE" -eq 0 ]; then
        EMPTY_STREAK=$((EMPTY_STREAK + 1))
      else
        EMPTY_STREAK=0
      fi
      if [ "$EMPTY_STREAK" -ge 2 ] && [ "$TOUR_RELAUNCHED" -eq 0 ]; then
        TOUR_RELAUNCHED=1
        EMPTY_STREAK=0
        echo "tour-progress: spot $SPOT $SHOT two consecutive empty shots; relaunching the app once" >> screenshots/tour-progress.txt
        xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
        sleep 3
        xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMTour || true
        if [ -n "$APP_DATA" ]; then
          ACK_SPOT=0
          while [ "$ACK_SPOT" -lt "$SPOT" ]; do
            printf 'ack %s\n' "$ACK_SPOT" > "$APP_DATA/Documents/tour-ack-$ACK_SPOT.txt" 2>/dev/null || true
            ACK_SPOT=$((ACK_SPOT + 1))
          done
        fi
      fi
      # Release the app to the next spot (see the tour comment
      # above). APP_DATA is the app's data container on this host,
      # so writing the ACK file here is writing into the app's
      # Documents, which is exactly where the app polls for it.
      if [ -n "$APP_DATA" ]; then
        printf 'ack %s\n' "$SPOT" > "$APP_DATA/Documents/tour-ack-$SPOT.txt" 2>/dev/null || true
      fi
    done
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
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
    # CI #199: 55 s left the cab shot black (scene still loading on
    # the simulator); wait 90 s so the cab has rendered and the
    # train is under way.
    sleep 90
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/20-cab-running.png 2>/dev/null || true
    CAB_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log-cab.txt" ]; then
      CAB_LOG="$APP_DATA/Documents/demo-drive-log-cab.txt"
    fi
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
