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
    # new scenic chainage every ~35 s of frame time (first at ~40 s),
    # so one launch photographs ten different places along the line.
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
    # Location tour (quality23): the app teleports to a new chainage
    # every ~35 s of frame time and appends a "TOUR spot=<i>" line to
    # Documents/demo-drive-log.txt on each teleport. Fixed sleeps from
    # launch drifted against the variable-length diagnostics above, so
    # in CI #213 the last five photos were all the same place. Now each
    # shot waits until the log shows that spot's teleport, then gives
    # the view 20 s to finish generating before shooting. Waits are
    # capped per spot (240 s) and overall (1,500 s) so a stalled app
    # cannot hang the job; if a spot never appears, later waits drop
    # to the bare 20 s settle, and if the log never appears at all the
    # loop falls back to fixed 35 s steps.
    # Spots (curve apexes, quality23): 1,654 m R450 / 3,006 m R467 /
    # 4,466 m R324 sharpest / 6,522 m R902 / 9,081 m just before the
    # river bridge / 12,986 m R693 / 17,650 m tunnel portal /
    # 23,475 m R789 / 45,327 m sea R1326 / 58,557 m sea R845.
    TOUR_LOG=""
    if [ -n "$APP_DATA" ] && [ -f "$APP_DATA/Documents/demo-drive-log.txt" ]; then
      TOUR_LOG="$APP_DATA/Documents/demo-drive-log.txt"
    fi
    TOUR_SHOTS="04-tour-01-urban-core 05-tour-02-fringe 06-tour-03-suburb-poles 07-tour-04-river-bridge 08-tour-05-suburb 09-tour-06-tunnel-portal 10-tour-07-station 11-tour-08-fields 12-tour-09-sea 13-tour-10-sea-terminus"
    TOUR_START=$SECONDS
    TOUR_STALLED=0
    TOUR_INDEX=0
    for SHOT in $TOUR_SHOTS; do
      TOUR_INDEX=$((TOUR_INDEX + 1))
      if [ -n "$TOUR_LOG" ] && [ "$TOUR_STALLED" -eq 0 ]; then
        WAITED=0
        while [ "$WAITED" -lt 240 ]; do
          COUNT="$(grep -c 'TOUR spot=' "$TOUR_LOG" 2>/dev/null || true)"
          COUNT="${COUNT:-0}"
          if [ "$COUNT" -ge "$TOUR_INDEX" ]; then break; fi
          if [ $((SECONDS - TOUR_START)) -ge 1500 ]; then break; fi
          sleep 5
          WAITED=$((WAITED + 5))
        done
        COUNT="$(grep -c 'TOUR spot=' "$TOUR_LOG" 2>/dev/null || true)"
        COUNT="${COUNT:-0}"
        if [ "$COUNT" -lt "$TOUR_INDEX" ]; then
          echo "Tour spot $TOUR_INDEX never appeared in the demo log; shooting anyway and shortening later waits."
          TOUR_STALLED=1
        fi
        sleep 20
      elif [ "$TOUR_STALLED" -eq 1 ]; then
        sleep 20
      else
        sleep 35
      fi
      xcrun simctl io "$SIMULATOR_UDID" screenshot "screenshots/$SHOT.png" 2>/dev/null || true
    done
    xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" 2>/dev/null || true
    # Cab check: relaunch in the cab view and let the demo drive the
    # showcase section (origin to Matsubaramachi) so the rebuilt cab
    # is photographed standing at the station and running.
    sleep 3
    xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID" -RMDemoDrive -RMCabView
    # CI #199: 55 s left the cab shot black (scene still loading on the
    # simulator); wait 90 s so the cab has rendered, accepting that the
    # train has just departed by then.
    sleep 90
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/15-cab-station.png 2>/dev/null || true
    sleep 105
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/16-cab-running.png 2>/dev/null || true
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
    xcrun simctl io "$SIMULATOR_UDID" screenshot screenshots/14-home.png 2>/dev/null || true
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
