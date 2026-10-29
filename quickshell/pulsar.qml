import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Notifications
import Quickshell.Bluetooth

// One window for everything: the bar pill IS the launcher.
// Opening stretches the pill wide, then grows it down into the launcher
// panel; closing collapses it back into the same pill perfectly.
PanelWindow {
    id: root

    anchors {
        top: true
    }

    // Fixed window size: only the pill/panel rectangle inside animates,
    // so the compositor never has to resize/recenter the surface mid-
    // animation (that makes it choppy and jumpy). The window is sized
    // for the LARGEST module — swapping modules (e.g. power -> launcher)
    // must never resize the surface, because a layershell resize makes
    // the compositor stretch the old buffer for a frame (visible as the
    // content being stretched). Smaller bars (power) sit centered in it
    implicitWidth: bar.maxPanelWidth
    implicitHeight: bar.maxPanelHeight + 12
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"
    WlrLayershell.keyboardFocus:
        bar.open && bar.mode !== "notif" && bar.mode !== "osd"
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 50

    // Clicks only land on the pill itself, never on the window padding
    mask: Region {
        item: bar
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: bar

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 10

            // --- GEOMETRY ---
            // baseWidth: the closed pill's width (kept separate from the
            // animated width so the panel target cannot feed back into it)
            readonly property real baseWidth: layout.implicitWidth + 32
            readonly property real baseHeight: 38

            // Uniform black frame around every module's content: this
            // padding strip is part of the island (pure black bar bg)
            readonly property real modulePad: 14

            // Panel width: the launcher and pickers fill the width; the
            // notification capsule and power strip hug their content so
            // the side padding equals the vertical padding, no dead space
            readonly property real powerCardSize: 100
            readonly property real powerGap: 14
            // Notification capsule: big banner, content scales with it
            // Notification capsule: 880 (across) x 75 (down); content
            // scales off the 365x62 reference proportions
            readonly property real notifBannerW: 700   // across
            readonly property real notifBannerH: 75    // down
            readonly property real notifScale: notifBannerH / 62
            readonly property real panelWidth:
                mode === "osd" ? 350 :
                mode === "notif"
                    ? Math.max(notifBannerW, notifRow.width + 2 * modulePad)
                    : mode === "power"
                    ? powerActions.length * powerCardSize
                      + (powerActions.length - 1) * powerGap + 2 * powerGap
                    : Math.max(620, baseWidth)

            // Window footprint: the largest of the modules, so the layershell
            // never resizes when the module changes (fixed window size)
            readonly property real maxPanelWidth:
                Math.max(880, 620, baseWidth) // notification banner too
            readonly property real maxPanelHeight: Math.max(690, 431, 176)
            // Panel height depends on what is open: the app launcher is
            // tall, the theme cards and wallpaper picker are short strips
            readonly property real panelHeight:
                mode === "osd" ? 42 :
                mode === "themes" || mode === "wallpapers" ? 176 :
                mode === "notif" ? notifBannerH :
                mode === "control" ? controlHeight :
                mode === "sound" ? soundPanelH :
                mode === "display" ? displayPanelH :
                mode === "notifHistory" ? notifHistPanelH :
                mode === "wifi" ? wifiPanelH :
                mode === "power" ? powerCardSize + 2 * powerGap
                : appsPanelHeightAnim // app launcher: 5 rows max

            readonly property real searchRowHeight: 60
            readonly property real rowHeight: 54

            // App results are capped at 5 visible rows; the launcher
            // height wraps exactly what it shows and re-morphs (smoothed)
            // as the result count changes while you type
            readonly property real appsPanelHeight:
                searchRowHeight + 12
                + Math.min(5, appList.length) * rowHeight + 18
            property real appsPanelHeightAnim: appsPanelHeight

            Behavior on appsPanelHeightAnim {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack
                }
            }

            // Morph progress: 0 = pill, 1 = launcher panel
            property bool open: false
            property real wp: 0 // width phase
            property real hp: 0 // height phase

            // --- NOTIFICATION MODULE ---
            // A notification morphs the island into a capsule with the
            // same springs as a module, then folds back into the pill
            // after its linger time. One arriving while another module is
            // open waits until the island closes, then morphs in
            property bool pendingNotif: false

            Timer {
                id: notifExpire

                interval: 5000
                repeat: false
                onTriggered: if (bar.open && bar.mode === "notif")
                                 bar.closeIsland()
            }

            function notifIncoming() {
                if (open) {
                    if (mode !== "notif") {
                        // user is inside a module: morph in when it closes
                        pendingNotif = true;
                        return;
                    }
                    // a newer notification: refresh in place
                    notifExpire.restart();
                    return;
                }
                // DND on: no morph, stays in the control center list only
                if (dnd) return;
                openIsland("notif");
            }

            // --- CONTROL MODULE ---
            // Wi-Fi / volume / brightness statuses come live from the OS
            // (NetworkManager, the default Pipewire sink, brightnessctl);
            // Focus / Game mode / DND are shell-side toggles. DND keeps
            // notifications in the control center list without morphing
            readonly property real controlTileH: 52
            readonly property real controlPillH: 26
            readonly property real controlHeight: 354
            readonly property real controlTileW:
                (panelWidth - 2 * modulePad - 14) / 2

            // --- SOUND MODULE (right-click the Sound card) ---
            // device switcher: default sink/source rows + a volume pill for
            // each side and per-app stream sliders, straight from pactl.
            // The panel height mirrors the module's own column (smoothed
            // like the launcher) so it wraps exactly how many rows exist
            readonly property real sndRowH: 42
            property real soundPanelH:
                sndCol.implicitHeight + 2 * modulePad

            Behavior on soundPanelH {
                NumberAnimation {
                    duration: 250  
                    easing.type: Easing.OutBack
                }
            }

            // --- DISPLAY MODULE (right-click the Display card) ---
            // one row per sysfs backlight device (the monitors), each
            // with its own brightness pill like the sound module's
            // volume pills; every device file gets a FileView watcher
            // so keybind/external writes reflect with zero delay. The
            // panel height mirrors the module column (no Input section
            // here: monitors have no microphone counterpart)
            property var briDevices: []
            property var briWatchedDevs: []
            property var briScratch: []
            property string briMonsRaw: ""

            property real displayPanelH:
                dspCol.implicitHeight + 2 * modulePad

            Behavior on displayPanelH {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack
                }
            }

            // --- WIFI MODULE (right-click the wifi tile) ---
            // access points listed from nmcli; the connected network is
            // pulled out of the list into its own "Connected" card, the
            // rest sort by signal strength. Clicking a row joins it with
            // stored credentials (passwords prompt externally)
            // rows live in a ListModel that syncs IN PLACE (set/append/
            // remove only where content differs) - swapping a plain js
            // array recreated every delegate each scan, which blinked
            ListModel {
                id: wifiModel

                dynamicRoles: false
            }
            property var wifiScratch: []   // parse buffer (swapped at end)

            function syncWifiModel(rows) {
                while (wifiModel.count > rows.length)
                    wifiModel.remove(wifiModel.count - 1);
                for (let i = 0; i < rows.length; i++) {
                    const r = rows[i];
                    if (i < wifiModel.count) {
                        const cur = wifiModel.get(i);
                        if (cur.ssid === r.ssid) {
                            if (cur.apSignal !== r.apSignal)
                                wifiModel.setProperty(i, "apSignal",
                                    r.apSignal);
                            if (cur.sec !== r.sec)
                                wifiModel.setProperty(i, "sec", r.sec);
                            continue;
                        }
                        wifiModel.set(i, r);
                    } else {
                        wifiModel.append(r);
                    }
                }
            }
            property string wifiActive: "" // ssid of the connected AP
            property real wifiActiveSig: 0 // its signal percent
            // parse-side staging: the connected card (and its bars) keep
            // the current values until a read's finalize swaps in the
            // fresh ones - clearing mid-read used to blink the card off
            // and on when the post-scan re-read ran while open
            property string wifiActiveScratch: ""
            property real wifiActiveSigScratch: 0
            property string wifiBusy: ""   // ssid currently joining
            property string wifiErr: ""    // join failure note
            property real wifiPanelH:
                wifiCol.implicitHeight + 2 * modulePad

            Behavior on wifiPanelH {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack
                }
            }

            // --- NOTIFICATION HISTORY MODULE ---
            // every notification this session lands in bar.notifHistory:
            // the control center card lists the latest 4 one-line each,
            // the island shows them fully (click a row to dismiss,
            // "Clear all" wipes the session)
            property var notifHistory: []

            function notifHistoryDrop(i) {
                if (i < 0 || i >= notifHistory.length) return;
                notifHistory = notifHistory.filter((_, j) => j !== i);
            }

            function clearNotifs() {
                notifHistory = [];
            }

            // escape < > & so notification text cannot inject markup
            // into the card's StyledText rows
            function notifHtml(s) {
                return String(s)
                    .replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;");
            }

            // history island height: header + section gap + the visible
            // (capped) part of the wrapping list; re-morphs on every drop
            readonly property real notifHistListCap: 350
            property real notifHistPanelH:
                notifHistCol.implicitHeight + 2 * modulePad

            Behavior on notifHistPanelH {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutBack
                }
            }
            property var sndSinks: []
            property var sndSources: []
            property var sndApps: []
            property string sinkName: ""
            property string sourceName: ""
            property real srcPct: 0
            property bool srcDragging: false
            property int appVolIdx: -1
            property real appVolPct: 0
            property bool dnd: false
            property string wifiSsid: ""
            property real briCur: 0
            property real briMax: 1
            property real briTarget: -1
            property bool briDragging: false
            // the pointer position while dragging: the fill follows the
            // cursor instantly; briPct (the real value) catches up after
            // brightnessctl runs
            property real briDragPct: 0
            // which backlight device the watcher path points at (""
            // before discovery): drives the display module's row sync
            property string briWatchedDev: ""            // sysfs watch of the backlight: keybinds reflect instantly
            property string briSysPath: ""
            property real briSysCur: 0

            readonly property real briVisual:
                briDragging ? briDragPct
                : briSysPath !== "" ? briSysPct() : briPct

            function briSysPct() {
                return briMax > 0
                    ? Math.round((briSysCur / briMax) * 100) : 0;
            }

            // parses one freshly-loaded sysfs brightness read into the
            // live slider value
            function parseBriText() {
                const v = parseFloat(String(briWatch.text() || ""));
                if (!isNaN(v) && v > 0) {
                    briSysCur = v;
                    // keybind / external writes pop the OSD (not our own
                    // bar drags: the value is already visible there)
                    if (briDragging) return;
                    if (osdBriSkip) {
                        // post-reload probe of an UNCHANGED brightness
                        osdBriSkip = false;
                    } else {
                        bumpOsd("brightness");
                    }
                    // keep the display module's row of the watched device
                    // in sync with zero-delay external writes
                    if (briWatchedDev !== "")
                        parseRowText(briWatchedDev,
                            String(briWatch.text()));
                }
            }

            readonly property real briPct: briMax > 0
                ? Math.round((briCur / briMax) * 100) : 0

            property real volPct: 0
            property bool volMuted: false
            property real volTarget: -1
            property bool volDragging: false

            function refreshVolume() {
                // direct pactl invocations, no shell: forks per read are
                // the whole pipeline cost, so keep them binary-only
                volGetVol.command = ["pactl", "get-sink-volume",
                    "@DEFAULT_SINK@"];
                volGetVol.running = false;
                volGetVol.running = true;
                volGetMute.command = ["pactl", "get-sink-mute",
                    "@DEFAULT_SINK@"];
                volGetMute.running = false;
                volGetMute.running = true;
            }

            function volumeSet(p) {
                volPct = p;                  // optimistic instant fill
                volMuted = p === 0;
                volSetProc.command = ["pactl", "set-sink-volume",
                    "@DEFAULT_SINK@", Math.round(
                        Math.max(0, Math.min(130, p))) + "%"];
                volSetProc.running = false;
                volSetProc.running = true;
                volMuteProc.command = ["pactl", "set-sink-mute",
                    "@DEFAULT_SINK@", p === 0 ? "yes" : "no"];
                volMuteProc.running = false;
                volMuteProc.running = true;
            }

            // --- OSD (volume / brightness morph) ---
            // NOT a separate popup: every volume or brightness change
            // made OUTSIDE the bar (keybinds, apps) morphs the closed
            // pill into the OSD panel with the same spring as the
            // modules, holds while changes keep firing, then folds
            // back into the pill. Bar-internal drags skip it entirely
            // because the value is already visible in the open module
            property string osdKind: "volume"
            property real osdLastVol: -1  // skip no-op pactl refresh ticks
            property real osdLastBump: 0
            property real osdShownAt: 0
            // theme/wallpaper applies regenerate Colors.qml, which live
            // reloads the whole shell; the initial volume + brightness
            // probes after every (re)load would then pop the OSD with
            // the unchanged values, so both are swallowed: the one-shot
            // skips cover a fresh boot, and a timestamp window covers
            // reload parse storms (loaded + changed can both fire)
            property bool osdVolSkip: true
            property bool osdBriSkip: true
            property real osdReloadAt: Date.now() // boot counts as a reload

            // repeating watchdog: closes when the value has been quiet
            // for 1.7s — restart-spam from delayed pipewire event waves
            // can push a one-shot timer indefinitely, so dismissal is
            // judged on the last CHANGE timestamp, plus an 8s hard cap
            // no matter what
            Timer {
                id: osdHideTimer
                interval: 300
                repeat: true
                running: false
                onTriggered: {
                    const now = Date.now();
                    if ((now - bar.osdLastBump > 1700
                        || now - bar.osdShownAt > 8000)
                        && bar.open && bar.mode === "osd") {
                        running = false;
                        bar.closeIsland();
                    }
                }
            }

            function bumpOsd(kind) {
                // inside the post-reload probe window (1.5 s after a
                // Colors.qml regeneration): never pop
                if (Date.now() - osdReloadAt < 1500) return;
                if (open && mode === "osd") {
                    osdKind = kind; // swap content, hold while events fire
                    osdLastBump = Date.now();
                    osdHideTimer.running = true;
                    return;
                }
                if (open) return; // a real module covers the island
                osdKind = kind;
                osdShownAt = Date.now();
                osdLastBump = osdShownAt;
                openIsland("osd");
                osdHideTimer.running = true;
            }

            function toggleWifi() {
                Networking.wifiEnabled = !Networking.wifiEnabled;
                wifiSsidTimer.restart(); // SSID re-reads once up/down done
            }

            // --- WIFI MODULE PLUMB ---
            function wifiJoin(ssid) {
                if (ssid === wifiBusy) return;
                wifiBusy = ssid;
                wifiErr = "";
                wifiJoinProc.command = ["nmcli", "device", "wifi",
                    "connect", ssid];
                wifiJoinProc.running = false;
                wifiJoinProc.running = true;
            }

            function apLine(line) {
                // nmcli -t -f active,ssid,signal,security rows
                if (line.indexOf("__APS__") !== -1) {        // last row
                    // finalize: merge clones by ssid, drop the connected
                    // one (it lives in its own card), sort by signal, cap
                    // panel rows. Rows parse into wifiScratch and swap in
                    // only here - wifiRows never empties mid-read, so
                    // the panel height holds during a refresh (the island
                    // shape used to jolt when the module opened with an
                    // emptied list mid-open-animation)
                    const seen = {};
                    const merged = [];
                    for (const r of wifiScratch) {
                        if (r.ssid === wifiActiveScratch) continue;
                        const prev = seen[r.ssid];
                        if (prev) {
                            if (r.apSignal > prev.apSignal)
                                prev.apSignal = r.apSignal;
                            if (r.sec) prev.sec = true;
                        } else {
                            seen[r.ssid] = r;
                            merged.push(r);
                        }
                    }
                    merged.sort((a, b) => b.apSignal - a.apSignal);
                    syncWifiModel(merged.slice(0, 14));      // cap panel
                    wifiActive = wifiActiveScratch;          // card swap
                    wifiActiveSig = wifiActiveSigScratch;
                    wifiScratch = [];
                    return;
                }
                const p = line.split(":");
                if (p.length < 4 || !p[1]) return;           // header/blank
                const ssid = p.slice(1, p.length - 2).join(":");
                const sig = p[p.length - 2];
                const sec = p[p.length - 1];
                if (!ssid || ssid === "--") return;
                if (p[0] === "yes") {                        // connected
                    wifiActiveScratch = ssid;
                    wifiActiveSigScratch = +sig;
                    return;                                  // separate card
                }
                const locked = sec !== "" && sec !== "--";
                for (const r of wifiScratch)                 // strongest clone
                    if (r.ssid === ssid) {
                        if (+sig > r.apSignal) r.apSignal = +sig;
                        if (locked) r.sec = true;
                        return;
                    }
                wifiScratch.push({ ssid: ssid, apSignal: +sig,
                    sec: locked });
            }

            // signal percent -> lit bars out of 4 (both the island
            // pill and the wifi module rows use this mapping)
            function sigBarCount(sig) {
                return sig >= 80 ? 4 : sig >= 60 ? 3
                    : sig >= 35 ? 2 : sig >= 10 ? 1 : 0;
            }

            function refreshWifiList() {
                wifiScratch = [];
                wifiActiveScratch = "";
                wifiActiveSigScratch = 0;
                wifiActive = "";
                wifiActiveSig = 0;
                wifiApProc.command = ["sh", "-c",
                    "nmcli -t -f active,ssid,signal,security dev wifi"
                    + " 2>/dev/null; echo __APS__"];
                wifiApProc.running = false;
                wifiApProc.running = true;
            }

            function refreshWifi() {
                wifiScanProc.command = ["nmcli", "device", "wifi",
                    "rescan"];
                wifiScanProc.running = false;
                wifiScanProc.running = true;
                refreshWifiList();
                wifiListTimer.restart();
            }

            Timer {
                id: wifiListTimer

                interval: 1400
                repeat: false
                onTriggered: bar.refreshWifiList()
            }

            function toggleBluetooth() {
                const ad = Bluetooth.defaultAdapter;
                if (ad) ad.enabled = !ad.enabled;
            }

            // pulls fresh Wi-Fi / volume values when control opens
            // (brightness streams via the sysfs watcher; re-discovery here
            // is just a cheap fallback refresh of the device + max)
            function controlRefresh() {
                discoverBrightness();
                refreshWifiName();
                refreshVolume();
            }

            function refreshWifiName() {
                wifiSsid = "";
                wifiSsidProc.command = ["sh", "-c",
                    "nmcli -t -f active,ssid dev wifi 2>/dev/null"
                    + " | grep '^yes:' | cut -d: -f2 | head -1"];
                wifiSsidProc.running = false;
                wifiSsidProc.running = true;
            }

            Timer {
                id: wifiSsidTimer

                interval: 700
                repeat: false
                onTriggered: bar.refreshWifiName()
            }

            // watches the backlight sysfs brightness file: any write
            // (keybind, external tool) lands here instantly
            FileView {
                id: briWatch

                path: bar.briSysPath
                watchChanges: true
                blockLoading: true
                preload: false
                printErrors: false

                onLoadedChanged: if (loaded) bar.parseBriText()
                onTextChanged: bar.parseBriText()
            }

            Process {
                id: wifiSsidProc

                stdout: SplitParser {
                    onRead: data => { if (data) bar.wifiSsid = data; }
                }
            }

            // wifi module: AP list / rescan / join
            Process {
                id: wifiApProc

                stdout: SplitParser {
                    onRead: data => { if (data) bar.apLine(data); }
                }
            }

            Process { id: wifiScanProc }

            Process {
                id: wifiJoinProc

                stdout: SplitParser {
                    onRead: data => {
                        const d = String(data);
                        if (d.indexOf("Secret") !== -1
                            || d.indexOf("password") !== -1
                            || d.indexOf("secret") !== -1)
                            bar.wifiErr = "password required"
                                + " (nmcli agent)";
                    }
                }
                onExited: {
                    bar.wifiBusy = "";
                    bar.refreshWifiName();
                    bar.wifiListTimer.restart();
                }
            }

            // discovers the backlight sysfs nodes once at startup so the
            // watcher streams every external/keybind write instantly
            function discoverBrightness() {
                briProbe.command = ["sh", "-c",
                    "p=$(ls /sys/class/backlight/*/brightness 2>/dev/null"
                    + " | head -1); echo path=$p"
                    + "; [ -n \"$p\" ] && sed 's/^/max=/'"
                    + " \"${p%/brightness}/max_brightness\""];
                briProbe.running = false;
                briProbe.running = true;
            }

            // --- DISPLAY MODULE PLUMB ---
            // one row per /sys/class/backlight device: current + max via
            // sysfs, labels from hyprctl's monitor list when the counts
            // match ("eDP-1 · BOE 0x06F2"), pretty device names otherwise
            function refreshDisplays() {
                briScratch = [];
                briMonsRaw = "";
                briListProc.command = ["sh", "-c",
                    "for d in /sys/class/backlight/*; do"
                    + " [ -e \"$d/brightness\" ] || continue;"
                    + " echo \"dev=$(basename \"$d\")"
                    + ";cur=$(cat \"$d/brightness\")"
                    + ";max=$(cat \"$d/max_brightness\")\"; done;"
                    + " echo \"mons=$(hyprctl -j monitors 2>/dev/null"
                    + " | jq -r '[.[] | (.name + \"|\" + .description)]"
                    + " | join(\",\")' 2>/dev/null || true)\""];
                briListProc.running = false;
                briListProc.running = true;
            }

            function briRowLabel(i, dev, count) {
                const parts = briMonsRaw
                    ? briMonsRaw.split(",") : [];
                if (briMonsRaw !== ""
                    && parts.length === 2 * count)
                    return parts[2 * i] + " · " + parts[2 * i + 1];
                const d = String(dev).replace(/_/g, " ");
                return d.charAt(0).toUpperCase() + d.substring(1);
            }

            // external write landed on a device's sysfs file: push the
            // fresh % into that device's row through the repeater
            function parseRowText(dev, text) {
                const v = parseFloat(String(text || ""));
                if (isNaN(v) || v < 0) return;
                for (let i = 0; i < devRepeater.count; i++) {
                    const row = devRepeater.itemAt(i);
                    if (row && row.rowDev === dev)
                        row.pctVal = row.rowMax > 0
                            ? Math.round(v / row.rowMax * 100) : 0;
                }
            }

            // every device file gets its own FileView watcher (device 0
            // already streams through the shared briWatch); created once
            // per device at discovery
            function buildBriWatchers() {
                if (briDevices.length === 0) return;
                const first = briDevices[0].dev;
                for (const row of briDevices) {
                    if (briWatchedDevs.indexOf(row.dev) !== -1) continue;
                    briWatchedDevs.push(row.dev);
                    if (row.dev === first) continue;
                    try {
                        Qt.createQmlObject(
                            'import Quickshell.Io;\n'
                            + 'FileView { property string dev: "'
                            + row.dev + '"; path: "/sys/class/backlight/'
                            + row.dev
                            + '/brightness"; watchChanges: true;'
                            + ' preload: false; blockLoading: true;'
                            + ' printErrors: false;'
                            + ' onTextChanged: bar.parseRowText(dev, text); }',
                            bar, "briWatcher-" + row.dev);
                    } catch (err) {
                        // watcher creation failed: the row still updates
                        // through drag writes and re-probes
                    }
                }
            }

            // write one device's brightness straight through brightnessctl
            // (it talks to logind for the privilege, no root needed)
            function briRowSet(dev, p) {
                briRowSetProc.command = ["brightnessctl", "-d", dev,
                    "set", Math.round(Math.max(1, p)) + "%"];
                briRowSetProc.running = false;
                briRowSetProc.running = true;
            }
            Process { id: briRowSetProc }

            Process { // lists every backlight device + hyprctl's monitor
                id: briListProc

                stdout: SplitParser {
                    onRead: data => {
                        const s = String(data).trim();
                        if (s.indexOf("mons=") === 0) {
                            bar.briMonsRaw = s.substring(5);
                            bar.briDevices = bar.briScratch.map((row, i) => ({
                                dev: row.dev,
                                cur: row.cur,
                                max: row.max,
                                label: bar.briRowLabel(
                                    i, row.dev, bar.briScratch.length)
                            }));
                            bar.buildBriWatchers();
                            return;
                        }
                        const dev = {};
                        s.split(";").forEach(kv => {
                            const i = kv.indexOf("=");
                            if (i > 0) dev[kv.substring(0, i)] =
                                kv.substring(i + 1);
                        });
                        if (dev.dev) bar.briScratch.push({
                            dev: dev.dev,
                            cur: parseFloat(dev.cur) || 0,
                            max: parseFloat(dev.max) || 1,
                            label: ""
                        });
                    }
                }
            }

            // --- SOUND MODULE PLUMB ---
            // device rows come from pactl's JSON (jq flattens each list to
            // one line) + the default sink/source probe; setters re-query
            function refreshSound() {
                sndSinksProc.command = ["sh", "-c",
                    "pactl -f json list sinks 2>/dev/null"
                    + " | jq -c 'map({name:.name, description:.description,"
                    + " pct:(.volume | to_entries[0].value.value_percent)})'"];
                sndSourcesProc.command = ["sh", "-c",
                    "pactl -f json list sources 2>/dev/null"
                    + " | jq -c 'map(select((.name | test(\"monitor$\")"
                    + " | not)) | {name:.name, description:.description,"
                    + " pct:(.volume | to_entries[0].value.value_percent)})'"];
                sndAppsProc.command = ["sh", "-c",
                    "pactl -f json list sink-inputs 2>/dev/null"
                    + " | jq -c 'map({idx:.index,"
                    + " name:(.properties[\"application.name\"]"
                    + " // .properties[\"node.name\"]"
                    + " // .properties[\"media.name\"] // \"App\"),"
                    + " pct:(.volume | to_entries[0].value.value_percent)})'"];
                sndDefProc.command = ["sh", "-c",
                    "echo sink=$(pactl get-default-sink 2>/dev/null)"
                    + "; echo source=$(pactl get-default-source 2>/dev/null)"];
                sndSinksProc.running = false;
                sndSinksProc.running = true;
                sndSourcesProc.running = false;
                sndSourcesProc.running = true;
                sndAppsProc.running = false;
                sndAppsProc.running = true;
                sndDefProc.running = false;
                sndDefProc.running = true;
                // the sink volume pill reflects reality the moment the
                // module opens (not only on control opens / pipe events)
                refreshVolume();
                refreshSourcePct();
            }

            function refreshSourcePct() {
                sndSrcVolProc.command = ["pactl", "get-source-volume",
                    "@DEFAULT_SOURCE@"];
                sndSrcVolProc.running = false;
                sndSrcVolProc.running = true;
            }

            function sinkSetDefault(name) {
                if (name === bar.sinkName) return;
                sndWriteProc.command = ["sh", "-c",
                    "pactl set-default-sink '" + name + "'"];
                sndWriteProc.running = false;
                sndWriteProc.running = true;
                sinkName = name;
                refreshVolume();
            }

            function sourceSetDefault(name) {
                if (name === bar.sourceName) return;
                sndWriteProc.command = ["sh", "-c",
                    "pactl set-default-source '" + name + "'"];
                sndWriteProc.running = false;
                sndWriteProc.running = true;
                sourceName = name;
            }

            // per-app stream sliders + the mic drag share the debounce
            // pattern: one writer proc, re-queried after it finishes
            Timer {
                id: appLatch

                interval: 130
                onTriggered: {
                    sndAppSetProc.command = ["pactl", "set-sink-input-volume",
                        String(bar.appVolIdx),
                        Math.round(bar.appVolPct) + "%"];
                    sndAppSetProc.running = false;
                    sndAppSetProc.running = true;
                }
            }

            Timer {
                id: srcLatch

                interval: 130
                onTriggered: {
                    sndSrcSetProc.command = ["pactl", "set-source-volume",
                        "@DEFAULT_SOURCE@",
                        Math.max(0, Math.round(bar.srcTarget)) + "%"];
                    sndSrcSetProc.running = false;
                    sndSrcSetProc.running = true;
                }
            }

            property real srcTarget: -1

            Process {
                id: sndAppSetProc

                onExited: bar.refreshSound()
            }

            // accepts new defaults (sink/source) and re-pulls everything
            Process {
                id: sndWriteProc

                onExited: bar.refreshSound()
            }

            Process {
                id: sndSinksProc

                stdout: SplitParser {
                    onRead: data => {
                        try {
                            bar.sndSinks = JSON.parse(String(data)) || [];
                        } catch (err) {
                            bar.sndSinks = [];
                        }
                    }
                }
            }

            Process {
                id: sndSourcesProc

                stdout: SplitParser {
                    onRead: data => {
                        try {
                            bar.sndSources = JSON.parse(String(data)) || [];
                        } catch (err) {
                            bar.sndSources = [];
                        }
                    }
                }
            }

            Process {
                id: sndAppsProc

                stdout: SplitParser {
                    onRead: data => {
                        try {
                            bar.sndApps = JSON.parse(String(data)) || [];
                        } catch (err) {
                            bar.sndApps = [];
                        }
                    }
                }
            }

            Process {
                id: sndDefProc

                stdout: SplitParser {
                    onRead: data => {
                        const s = String(data);
                        if (s.indexOf("sink=") === 0)
                            bar.sinkName = s.substring(5).trim();
                        else if (s.indexOf("source=") === 0)
                            bar.sourceName = s.substring(7).trim();
                    }
                }
            }

            Process {
                id: sndSrcVolProc

                stdout: SplitParser {
                    onRead: data => {
                        if (bar.srcDragging) return;
                        const m = String(data).match(/(\d+)%/);
                        if (m) bar.srcPct = Math.max(0,
                            Math.min(100, parseInt(m[1]) || 0));
                    }
                }
            }

            Process { id: sndSrcSetProc }

            // icon for a device row, guessed from its description
            // Per-glyph ink calibration (JetBrainsMono Nerd Font
            // Propo): pixel size at which each glyph renders with the
            // same ~510 ink units (the wifi@12px = 546 anchor band).
            // Dense glyphs run smaller px, light glyphs bigger - every
            // icon SITE pulls its size through iconPx(text), so even
            // dynamic icons (muted/speaker, device rows, OSD) follow
            readonly property var iconInk: ({
                "\uF002": 12, // search
                "\uF1EB": 12, // wifi
                "\uF294": 15, // bluetooth-b
                "\uF130": 11, // microphone
                "\uF025": 11, // headset
                "\uF26C": 9, // displayport
                "\uF028": 9, // speaker
                "\uF026": 11, // muted
                "\uF185": 10, // sun
                "\uF00C": 17, // check
                "\uF023": 8, // lock
                "\uF08B": 12, // logout
                "\uF021": 11, // reboot
                "\uF011": 11 // power off
            })

            function iconPx(icon) {
                const px = bar.iconInk[String(icon)];
                return px ?? 12;
            }

            function sndIcon(desc, isInput) {
                if (isInput) return "\uF130"; // microphone
                const d = String(desc).toLowerCase();
                if (d.indexOf("headphone") !== -1
                    || d.indexOf("headset") !== -1) return "\uF025";
                if (d.indexOf("hdmi") !== -1
                    || d.indexOf("displayport") !== -1) return "\uF26C";
                return "\uF028"; // speaker
            }

            Process {
                id: briProbe
                stdout: SplitParser {
                    onRead: data => {
                        if (String(data).indexOf("path=") === 0) {
                            bar.briSysPath = data.substring(5);
                            const bi = bar.briSysPath
                                .indexOf("/backlight/");
                            if (bi !== -1)
                                bar.briWatchedDev = bar.briSysPath
                                    .substring(bi + 11,
                                        bar.briSysPath
                                            .indexOf("/brightness"));
                            if (bar.briSysPath !== "" && briWatch.reload)
                                briWatch.reload();
                            return;
                        }
                        if (String(data).indexOf("max=") === 0) {
                            bar.briMax = parseFloat(data.substring(4)) || 1;
                            return;
                        }
                        const p = data.trim().split(" ");
                        if (p.length === 2 && !isNaN(parseFloat(p[0]))) {
                            bar.briCur = parseFloat(p[0]);
                            bar.briMax = parseFloat(p[1]) || 1;
                        }
                    }
                }
            }

            Process {
                id: volGetVol

                stdout: SplitParser {
                    onRead: data => {
                        if (bar.volDragging) return;
                        const m = String(data).match(/(\d+)%/);
                        if (m) bar.volPct =
                            Math.max(0, Math.min(100, parseInt(m[1]) || 0));
                        // keybind / app volume changes pop the OSD
                        if (m && bar.volPct !== bar.osdLastVol) {
                            bar.osdLastVol = bar.volPct;
                            if (bar.osdVolSkip) {
                                // post-reload probe of an UNCHANGED
                                // volume: record it, never show the OSD
                                bar.osdVolSkip = false;
                            } else {
                                bar.bumpOsd("volume");
                            }
                        }
                    }
                }
            }

            Process {
                id: volGetMute

                stdout: SplitParser {
                    onRead: data => {
                        if (bar.volDragging) return;
                        bar.volMuted =
                            String(data).indexOf("yes") !== -1;
                    }
                }
            }

            Process { id: volSetProc }
            Process { id: volMuteProc }

            // catches ANY sink change - including wpctl / pactl keybinds -
            // and pulls the fresh value into the control center
            Process {
                id: volSub

                command: ["pactl", "subscribe"]
                running: true

                stdout: SplitParser {
                    onRead: data => {
                        const d = String(data);
                        // pactl 16 prints bare "Event 'change' on sink #N"
                        if (d.indexOf("on sink") !== -1)
                            bar.refreshVolume();
                        // stream + default-source writes update the mic pill
                        if (d.indexOf("on source") !== -1
                            || d.indexOf("on server") !== -1)
                            bar.refreshSourcePct();
                    }
                }
            }

            // (brightness now streams from the sysfs watcher above; no poll)

            // display brightness writes debounce: only one brightnessctl
            // run per 130ms of dragging, then re-probe for the real value
            Timer {
                id: briLatch

                interval: 130
                repeat: false
                onTriggered: {
                    const t = Math.max(1, Math.round(bar.briTarget));
                    // optimistic value so the bar sits at the target the
                    // moment the write starts, instead of after the write
                    if (bar.briMax > 1) {
                        bar.briCur = bar.briMax * t / 100;
                        bar.briSysCur = bar.briMax * t / 100;
                    }
                    briSetProc.command = ["sh", "-c",
                        "brightnessctl set " + t + "% 2>/dev/null"];
                    briSetProc.running = false;
                    briSetProc.running = true;
                }
            }

            // --- PANEL MODES ---
            // The same pill morphs into three panels: the app launcher,
            // a theme picker and a wallpaper picker - each with the same
            // open/close animation
            //
            //   SUPER+SPACE -> qs ipc call launcher   (apps)
            //   SUPER+T     -> qs ipc call theme      (themes)
            //   SUPER+W     -> qs ipc call wallpaper  (wallpapers)
            property string mode: "apps"

            // Themes = the folders in ~/.config/colorschemes. Applying a
            // theme picks a random wallpaper from that folder, runs
            // matugen on it, records the wallpaper in
            // ~/.cache/current_wallpaper and points hyprlock.conf's
            // background path at it. The wallpaper picker lists the
            // current folder's wallpapers instead.
            readonly property string wallpapersRoot:
                Quickshell.env("HOME") + "/.config/colorschemes"

            property var allThemes: [] // [{name, path}]

            // ════════════ THEME BAR COLORS — EDIT THESE LINES ════════════
            // Folder name (must match ~/.config/colorschemes) -> ONE hex
            // color for that card's bar. Change a hex → the bar changes on
            // the next reload. Missing themes show a muted gray bar.
            readonly property var themeDotColors: ({
                "Catppuccin-Mocha": "#b3c5ff",
                "Everblush":        "#8ad0ef",
                "Everforest":       "#a6d395",
                "Gruvbox":          "#faba72",
                "Midori":           "#2fae9b",
                "Nord":             "#b1c5ff",
                "Oxocarbon":        "#ffb0ca",
                "Rose-Pine":        "#cebdfe",
            })

            // ════════════ THEME CARD BACKGROUNDS — EDIT THESE LINES ════════════
            // Folder name (must match ~/.config/colorschemes) -> ONE hex
            // color for that card's background. Change a hex -> the card
            // background changes on the next reload. Missing themes fall
            // back to pure black (bar.pureBlack).
            readonly property var themeCardColors: ({
                "Catppuccin-Mocha": "#11111b",
                "Everblush":        "#171f24",
                "Everforest":       "#191d17",
                "Gruvbox":          "#1d2021",
                "Midori":           "#0a1512",
                "Nord":             "#2e3440",
                "Oxocarbon":        "#22191c",
                "Rose-Pine":        "#191724",
            })
            property var __foundDirs: [] // build buffer for the finder
            readonly property var themesList: allThemes

            // --- CIRCULAR CAROUSELS ---
            // Both pickers render 3 copies of their list separated by one
            // blank 150px slot, so scrolling past the last card wraps to
            // the looped first card after a visible gap. All slots share
            // the 162px stride, making the wrap math purely periodic.
            property var themeLoopModel: []
            property var wallLoopModel: []

            // index into the tripled models ("inner" index)
            property int themeInner: 0
            property int wallInner: 0

            // true while key-driven slides are animating; hover selection
            // is suppressed for their duration so cards sliding under the
            // stationary cursor cannot re-select themselves (flicker)
            property bool themeSlideBusy: false
            property bool wallSlideBusy: false

            // The theme currently IN USE (from ~/.cache/current_wallpaper's
            // folder) - this one gets the dot, independent of selection
            readonly property string appliedThemeName:
                wallpaperPath
                    ? wallpaperPath.substring(0, wallpaperPath.lastIndexOf("/"))
                        .split("/").pop()
                    : ""

            // one plain copy of the real list (no looping/wrapping)
            function buildLoopModel(list) {
                return list.slice();
            }

            // slot -> real list index (identity without a loop model)
            function realIndexOf(li, n, count) {
                return Math.max(0, Math.min(Math.max(0, n - 1), li));
            }

            // index of the applied theme/wallpaper, for initial selection
            function appliedThemeRealIndex() {
                for (let i = 0; i < themesList.length; i++)
                    if (themesList[i].name === appliedThemeName) return i;
                return 0;
            }

            // The wall cache may still hold legacy ~/Pictures/Wallpapers
            // paths from before the root moved to ~/.config/colorschemes;
            // the same file content lives at both, so swap the prefix
            function canonWallPath(txt) {
                return txt.replace(/\/Pictures\/Wallpapers\//,
                    "/.config/colorschemes/");
            }

            function appliedWallIndex() {
                const i = wallList.findIndex(
                    w => w.path === wallpaperPath);
                return i >= 0 ? i : 0;
            }

            property int themeIndex: 0
            // centering is handled by the StrictlyEnforceRange
            // highlight range - no manual positionViewAtIndex here

            // Wallpaper picker state
            property string wallpaperDir: "" // folder being browsed
            property var wallList: [] // [{name, path}]
            property string wallpaperPath: "" // currently applied wallpaper
            property int wallIndex: 0

            // While set to a folder path, the next (re)load of a folder's
            // file list ends with applying a RANDOM wallpaper from it -
            // used when a theme card is applied
            property string pendingRandomApply: ""

            // PURE BLACK LOOK (user request). One knob for every surface:
            // to revert, restore shell.qml.pre-black.bak, or map the
            // usages back: island -> Colors.bg0; launcher row highlight,
            // selected theme card, idle power card -> Colors.bg2;
            // idle theme card, wallpaper card -> Colors.bg1
            readonly property color pureBlack: "#000000"

            // Power module: the selected card is filled Colors.accent and
            // the idle cards use Colors.accentInactive so they read
            // against the black island (no hardcoded grey needed)

            width: baseWidth + (panelWidth - baseWidth) * wp
            height: baseHeight + (panelHeight - baseHeight) * hp
            // pill 19 -> panel 22; the notification banner's corners are
            // rounder than straight proportional (28 at 75 down)
            radius: 19 + hp * (mode === "notif" ? 9 : 3)

            color: pureBlack
            border.color: Colors.surfaceBorder
            border.width: 0
            clip: true

            // Clicking the closed pill (anywhere not covered by a piece
            // like the workspace dots) opens the control center
            MouseArea {
                anchors.fill: parent
                enabled: !bar.open
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.openIsland("control")
            }

            // --- OPEN ANIMATION ---
            // Width and height grow at the same time with identical easing,
            // so the corner sweeps in a straight diagonal line from the pill
            // to the module's corner — with a slight overshoot-and-settle
            // (spring), so the panel pops a few px past its final size
            // before sitting down. The bar strip content is hidden instantly
            // (openIsland), so every piece is simply revealed
            ParallelAnimation {
                id: openAnim

                NumberAnimation {
                    target: bar
                    property: "wp"
                    to: 1
                    duration: 250
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.6
                }

                NumberAnimation {
                    target: bar
                    property: "hp"
                    to: 1
                    duration: 250
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.6
                }
            }

            // --- CLOSE ANIMATION ---
            // The reverse of the open: height and width collapse together
            // with the same springy easing and the same 260ms, so closing
            // feels identical to opening in timing and spring. The pill
            // pieces (workspaces, clock, wifi, battery) are shown from the
            // very first frame (no fade, no invisible pill) and glide from
            // the module's middle center up to their top-center spot
            ParallelAnimation {
                id: closeAnim

                ScriptAction {
                    script: {
                        layout.opacity = 1;
                    }
                }

                NumberAnimation {
                    target: bar
                    property: "hp"
                    to: 0
                    duration: 250
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.6
                }

                NumberAnimation {
                    target: bar
                    property: "wp"
                    to: 0
                    duration: 250
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.6
                }
            }

            // --- STATE / DATA ---

            property string searchQuery: ""
            onSearchQueryChanged: bar.selectedIndex = 0

            property int selectedIndex: 0
            onSelectedIndexChanged: {
                if (bar.appList.length > 0 && bar.selectedIndex >= 0)
                    listView.positionViewAtIndex(bar.selectedIndex, ListView.Contain);
            }

            // Installed apps (skipping hidden ones), alphabetical, filtered
            // by the search text
            readonly property var appList: {
                const query = searchQuery.trim().toLowerCase();
                let list = DesktopEntries.applications.values.filter(entry =>
                    !!entry.name && !entry.noDisplay);
                if (query)
                    list = list.filter(entry =>
                        (entry.name + " " + (entry.comment ?? "")).toLowerCase().includes(query));
                return list.sort((a, b) =>
                    a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
            }

            function openIsland(target) {
                target = target ?? "apps";
                if (open) {
                    // Already open: switching panels animates the island
                    // from the current size to the new module's size with
                    // the same spring as an open. The trick: re-phrase
                    // wp/hp so bar.width/height stay EXACTLY the old size
                    // this instant, then run the open spring to 1
                    if (mode === target) return;
                    // leaving the notification capsule: expire it so its
                    // clients stop waiting
                    if (mode === "notif") {
                        notifExpire.stop();
                        for (const n of notifServer.trackedNotifications.values)
                            if (n.tracked) n.expire();
                    }
                    const oldW = bar.width, oldH = bar.height;
                    mode = target;
                    openAnim.stop();
                    // straight linear re-phrase: the phase may go negative
                    // when coming from something smaller than the pill
                    // (e.g. the notification capsule) - the spring then
                    // glides through the pill size without any jump
                    wp = (oldW - baseWidth) / (panelWidth - baseWidth);
                    hp = (oldH - baseHeight) / (panelHeight - baseHeight);
                    searchInput.clear();
                    selectedIndex = 0;
                    alignSelectionToApplied();
                    powerIndex = 0;
                    if (target === "sound") refreshSound();
                    if (target === "display") refreshDisplays();
                    if (target === "wifi") refreshWifi();
                    if (target === "apps") searchInput.forceActiveFocus();
                    else if (target !== "notif" && target !== "osd")
                        keyCatcher.forceActiveFocus();
                    openAnim.start();
                    return;
                }
                openAnim.stop();
                closeAnim.stop(); // a mid-collapse reopen must not fight it
                searchInput.clear();
                selectedIndex = 0;
                alignSelectionToApplied();
                powerIndex = 0;
                mode = target;
                if (target === "themes") reloadThemes();
                if (target === "wallpapers") reloadWalls();
                if (target === "control") controlRefresh();
                if (target === "sound") refreshSound();
                if (target === "display") refreshDisplays();
                if (target === "wifi") refreshWifi();
                open = true;
                layout.opacity = 0; // bar strip pieces: gone this instant
                openAnim.start();
                if (target === "notif") notifExpire.restart();
                if (target === "apps") searchInput.forceActiveFocus();
                else if (target !== "notif" && target !== "osd")
                    keyCatcher.forceActiveFocus();
            }

            // Start the pickers on the theme/wallpaper currently in use
            function alignSelectionToApplied() {
                themeIndex = appliedThemeRealIndex();
                themeInner = themeIndex;
                wallIndex = appliedWallIndex();
                wallInner = wallIndex;
                if (themeList.count > 0) {
                    themeList.currentIndex = themeInner;
                    themeList.positionViewAtIndex(themeInner, ListView.Center);
                }
                if (wallGallery.count > 0) {
                    wallGallery.currentIndex = wallInner;
                    wallGallery.positionViewAtIndex(wallInner, ListView.Center);
                }
            }

            function closeIsland() {
                if (!open) return;
                open = false;
                openAnim.stop();
                closeAnim.stop();
                searchInput.focus = false;
                keyCatcher.focus = false;
                // the capsule folds back into the pill: reply to the
                // notification clients so they stop waiting
                if (mode === "notif") {
                    notifExpire.stop();
                    for (const n of notifServer.trackedNotifications.values)
                        if (n.tracked) n.expire();
                }
                closeAnim.start();
                // the same close spring grows straight into a queued
                // notification capsule (morph pill -> capsule, no pause)
                if (pendingNotif) {
                    pendingNotif = false;
                    openIsland("notif");
                }
            }

            function toggleIsland(target) {
                mode === (target ?? "apps") && open
                    ? closeIsland() : openIsland(target);
            }

            // arrow keys: routed by module; the control center and the
            // sound device list are mouse-only, so their arrows do nothing
            function moveKey(dir) {
                if (mode === "control" || mode === "sound"
                    || mode === "display" || mode === "osd"
                    || mode === "notifHistory") return;
                if (mode === "wallpapers") moveWall(dir);
                else if (mode === "power") movePower(dir);
                else moveTheme(dir);
            }

            function pressKey() {
                if (mode === "wallpapers") applyWallSelection();
                else if (mode === "power") invokePower();
                else if (mode !== "control" && mode !== "sound"
                    && mode !== "display" && mode !== "osd"
                    && mode !== "notifHistory")
                    applyThemeSelection();
            }

            function launch(entry) {
                Quickshell.execDetached(entry.command);
                closeIsland();
            }

            // --- THEME / WALLPAPER LIST LOADING ---

            function reloadThemes() {
                __foundDirs = [];
                themeDirsProc.command = [
                    "find", wallpapersRoot,
                    "-mindepth", "1", "-maxdepth", "1",
                    "-type", "d"
                ];
                themeDirsProc.running = false;
                themeDirsProc.running = true;
            }

            // List the walls of a folder; the applied wallpaper is taken
            // from ~/.cache/current_wallpaper, with the last known
            // wallpaperPath as fallback. The FileView only loads once
            // (it does not watch the file), so it is re-read each open;
            // a stale/empty read would list the wallpapers ROOT folder,
            // which has no wallpapers - the module would open empty and
            // only fill in after toggling again
            function wallpaperFolderForOpen() {
                currentWallpaperFile.waitForJob();
                const cached = currentWallpaperFile.text()
                    ? bar.canonWallPath(
                        String(currentWallpaperFile.text() || "").trim())
                    : "";
                if (cached) {
                    const dir = cached.substring(0, cached.lastIndexOf("/"));
                    if (dir && dir !== wallpapersRoot) {
                        wallpaperPath = cached;
                        wallpaperDir = dir;
                        return dir;
                    }
                }
                if (wallpaperPath) {
                    const dir = wallpaperPath.substring(0, wallpaperPath.lastIndexOf("/"));
                    if (dir && dir !== wallpapersRoot) {
                        wallpaperDir = dir;
                        return dir;
                    }
                }
                if (wallpaperDir && wallpaperDir !== wallpapersRoot) {
                    return wallpaperDir;
                }
                if (allThemes.length > 0 && allThemes[0].path) {
                    wallpaperDir = allThemes[0].path;
                    return wallpaperDir;
                }
                return wallpapersRoot;
            }

            function reloadWalls() {
                const targetDir = wallpaperFolderForOpen();
                wallpaperDir = targetDir;
                wallFilesProc.isThemePick = false;
                runWallFilesProc(targetDir);
            }

            // Wallpapers listed on demand; runs are SERIALIZED because
            // opening the wallpaper module right after applying a theme
            // would otherwise race two `find`s in the same Process (the
            // older exit overwrote wallList with partial/empty data -
            // the "sometimes nothing shows" bug). A pending run waits
            // for the current one to exit cleanly and then starts
            property string pendingWallFolder: ""

            function runWallFilesProc(folder) {
                if (!folder || folder === wallpapersRoot) {
                    if (allThemes.length > 0 && allThemes[0].path)
                        folder = allThemes[0].path;
                    else return;
                }
                pendingWallFolder = folder;
                if (wallFilesProc.running) return; // waits for exit
                wallFilesProc.found = [];
                wallFilesProc.command = [
                    "find", folder,
                    "-maxdepth", "1", "-type", "f"
                ];
                wallFilesProc.running = false;
                wallFilesProc.running = true;
                pendingWallFolder = "";
            }

            // --- APPLYING ---

            // Theme applied: load that folder's wallpapers, then apply one
            // at random
            function applyTheme(folderPath) {
                pendingRandomApply = folderPath;
                wallpaperDir = folderPath;
                wallList = [];
                wallFilesProc.isThemePick = true;
                runWallFilesProc(folderPath);
            }

            function isWallpaper(path) {
                const s = path.toLowerCase();
                return s.endsWith(".png") || s.endsWith(".jpg")
                    || s.endsWith(".jpeg") || s.endsWith(".webp");
            }

            // Selection movement for theme cards / wallpaper thumbs. One
            // press = one card of the tripled circular model, skipping the
            // blank wrap slot, so movement wraps around both ends.
            function moveTheme(delta) {
                const n = themesList.length;
                if (n === 0) return;
                let li = Math.max(0, Math.min(n - 1, themeInner + delta));
                if (li === themeInner) return;
                themeSlideBusy = true;
                themeSlideLock.restart();
                themeList.currentIndex = li; // view syncs bar + lock timer
            }

            function applyThemeSelection() {
                if (themeIndex < themesList.length)
                    applyTheme(themesList[themeIndex].path);
            }

            function moveWall(delta) {
                const n = wallList.length;
                if (n === 0) return;
                let li = Math.max(0, Math.min(n - 1, wallInner + delta));
                if (li === wallInner) return;
                wallSlideBusy = true;
                wallSlideLock.restart();
                wallGallery.currentIndex = li;
            }

            function applyWallSelection() {
                if (wallIndex < wallList.length)
                    apply(wallList[wallIndex].path);
            }

            // --- POWER MODULE ---

            readonly property var powerActions: [
                { id: "lock",     name: "Lock",      icon: "\uF023" },
                { id: "logout",   name: "Log Out",   icon: "\uF08B" },
                { id: "reboot",   name: "Reboot",    icon: "\uF021" },
                { id: "poweroff", name: "Power Off", icon: "\uF011" }
            ]

            property int powerIndex: 0

            function movePower(delta) {
                const n = powerActions.length;
                powerIndex = (powerIndex + delta + n) % n;
            }

            function invokePower() {
                if (powerIndex >= powerActions.length) return;
                const id = powerActions[powerIndex].id;
                if (id === "lock") Quickshell.execDetached(["hyprlock"]);
                else if (id === "logout") Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exit()"]);
                else if (id === "reboot") Quickshell.execDetached(["systemctl", "reboot"]);
                else if (id === "poweroff") Quickshell.execDetached(["systemctl", "poweroff"]);
                closeIsland();
            }

            // Runs matugen on the wallpaper, records it in
            // ~/.cache/current_wallpaper and updates hyprlock's conf
            function apply(wallPath) {
                if (!wallPath) return;
                applyProc.command = ["sh", "-c", applyScript, "sh", wallPath];
                applyProc.running = false;
                applyProc.running = true;
                wallpaperPath = wallPath;
                wallpaperDir = wallPath.substring(0, wallPath.lastIndexOf("/"));
                closeIsland();
            }

            // Apply the wallpaper immediately with awww, then matugen
            // (generates the system colors, writes its own configs, runs
            // its post hooks), then save the wallpaper, then point
            // hyprlock's background path at it. The path is sed/pipe safe.
            //
            // matugen spends ~1.7s decoding wallpapers at full size
            // (6MB+), but its colors come out essentially identical on a
            // tiny DCT-scaled JPEG (jpeg-turbo decodes those ~free), so
            // matugen runs on a cached thumbnail and matures THE
            // PALETTE in ~0.25s instead. Non-JPEGs fall back to the
            // full-size image, and a failed thumbnail too.
            readonly property string applyScript: [
                "set -e",
                "wp=\"$1\"",
                "printf '%s\\n' \"$wp\" > \"$HOME/.cache/current_wallpaper\"",
                "thumb=\"$HOME/.cache/current_wallpaper-thumb.jpg\"",
                "mat_src=\"$wp\"",
                "if djpeg -scale 1/8 \"$wp\" 2>/dev/null | cjpeg -quality 90 > \"$thumb\" 2>/dev/null; then",
                "    mat_src=\"$thumb\"",
                "fi",
                "matugen image \"$mat_src\" &",
                "MATUGEN_PID=$!",
                "( pgrep -x awww-daemon >/dev/null 2>&1 || setsid awww-daemon >/dev/null 2>&1 &",
                "  i=0; until awww img \"$wp\" --transition-fps 60 --transition-type center --transition-duration 2 >/dev/null 2>&1; do sleep 0.05; i=$((i+1)); [ $i -gt 20 ] && break; done",
                ") &",
                "esc=$(printf '%s' \"$wp\" | sed 's/[&|]/\\\\&/g')",
                "sed -i \"s|^[[:space:]]*path[[:space:]]*=.*|    path = $esc|\" \"$HOME/.config/hypr/hyprlock.conf\"",
                "wait $MATUGEN_PID"
            ].join("\n")

            // Reads ~/.cache/current_wallpaper (the path of the wallpaper
            // currently in use)
            FileView {
                id: currentWallpaperFile
                path: Quickshell.env("HOME") + "/.cache/current_wallpaper"
                preload: true
                blockLoading: true
                watchChanges: true
                printErrors: false

                onLoaded: {
                    const txt = String(text() || "").trim();
                    const fixed = txt ? bar.canonWallPath(txt) : "";
                    if (!fixed || fixed === bar.wallpaperPath) return;
                    if (fixed) {
                        bar.wallpaperPath = fixed;
                        const dir = fixed.substring(0, fixed.lastIndexOf("/"));
                        if (dir && dir !== bar.wallpapersRoot) {
                            bar.wallpaperDir = dir;
                            if (bar.wallList.length === 0)
                                bar.reloadWalls();
                        }
                    }
                }
            }

            // Folders in ~/.config/colorschemes = the themes
            Process {
                id: themeDirsProc

                stdout: SplitParser {
                    onRead: data => {
                        if (data) bar.__foundDirs.push(data);
                    }
                }

                onExited: {
                    bar.allThemes = bar.__foundDirs
                        .map(path => ({
                            name: path.split("/").pop(),
                            path: path
                        }))
                        .sort((a, b) =>
                            a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
                    bar.themeLoopModel = bar.buildLoopModel(bar.allThemes);
                    bar.alignSelectionToApplied();
                }
            }

            // Files of the folder currently being browsed
            Process {
                id: wallFilesProc

                // Set while reading a theme's folder for a random pick
                property bool isThemePick: false
                property var found: []

                stdout: SplitParser {
                    onRead: data => {
                        if (data) wallFilesProc.found.push(data);
                    }
                }

                onExited: {
                    const walls = wallFilesProc.found
                        .filter(entry => bar.isWallpaper(entry))
                        .map(path => ({
                            name: path.split("/").pop(),
                            path: path
                        }))
                        .sort((a, b) =>
                            a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
                    if (walls.length > 0 || !bar.wallFilesProc.isThemePick) {
                        bar.wallList = walls;
                        bar.wallLoopModel = bar.buildLoopModel(bar.wallList);
                        bar.alignSelectionToApplied();
                    }
                    wallFilesProc.found = [];

                    // Theme card applied: pick a random wallpaper from the
                    // folder that was just listed
                    if (bar.pendingRandomApply) {
                        bar.pendingRandomApply = "";
                        if (bar.wallList.length > 0)
                            bar.apply(bar.wallList[
                                Math.floor(Math.random() * bar.wallList.length)].path);
                    }

                    // start the queued wallpaper listing, if any
                    if (bar.pendingWallFolder) {
                        const next = bar.pendingWallFolder;
                        bar.pendingWallFolder = "";
                        bar.runWallFilesProc(next);
                    }
                }
            }

            // Runs the matugen + cache + hyprlock chain
            Process {
                id: applyProc
            }

            // --- LIVE SYSTEM DATA ---

            // The wifi device (radio) visible to NetworkManager, if any
            readonly property var wifiDevice: {
                for (const device of Networking.devices.values)
                    if (device instanceof WifiDevice) return device;
                return null;
            }

            // The wifi network to show: the connected one if present,
            // otherwise the strongest network currently visible
            readonly property var wifiNetwork: {
                const networks = bar.wifiDevice ? bar.wifiDevice.networks.values : [];
                for (const network of networks)
                    if (network.connected) return network;

                let best = null;
                for (const network of networks)
                    if (best === null || network.signalStrength > best.signalStrength)
                        best = network;
                return best;
            }

            readonly property real wifiStrength: wifiNetwork ? wifiNetwork.signalStrength : 0

            // How many of the 4 bars light up
            readonly property int wifiBars: Math.max(0, Math.min(4, Math.ceil(wifiStrength * 4)))

            // Live-sampled indicators: the Networking/UPower models
            // notify on signal/charge changes, but derived bindings
            // through their snapshots don't always re-fire, so the bar
            // glyphs could freeze at their boot value. These stored
            // values (pushed by a light timer) are what the glyphs read
            property int wifiBarsLive: wifiBars
            property int batteryPctLive: 60

            Timer {
                interval: 4000
                running: true
                repeat: true
                onTriggered: {
                    const net = bar.wifiNetwork;
                    if (Networking.wifiEnabled && net)
                        bar.wifiBarsLive = Math.max(0, Math.min(4,
                            Math.ceil(net.signalStrength * 4)));
                    const dev = UPower.displayDevice;
                    if (dev.ready) {
                        let pct = dev.percentage;
                        if (pct > 1) pct = pct / 100;
                        bar.batteryPctLive = Math.round(
                            Math.max(0, Math.min(1, pct)) * 100);
                    }
                }
            }

            // Battery charge level from UPower (0.0 - 1.0), 80% as a
            // fallback if the UPower daemon is missing or not ready
            readonly property real batteryFill: {
                const device = UPower.displayDevice;
                if (!device.ready) return 0.8;
                let pct = device.percentage;
                if (pct > 1) pct = pct / 100;
                return Math.max(0.05, Math.min(1, pct));
            }

            // Scanning has to be on for signalStrength to be measured
            function enableWifiScanning() {
                for (const device of Networking.devices.values)
                    if (device instanceof WifiDevice && !device.scannerEnabled)
                        device.scannerEnabled = true;
            }

            Component.onCompleted: {
                bar.enableWifiScanning();
                // pick up the currently applied wallpaper once at startup
                // (drives the theme dot and the wallpaper folder
                // fallback); onLoaded applies it off this wait
                currentWallpaperFile.waitForJob();
                // pre-warm the theme list + dot color sampling at shell
                // startup, so opening the panel shows colors instantly
                bar.reloadThemes();
                bar.reloadWalls();
                // wifi module lists too: the first open then has real
                // rows immediately, so the island shape never has to
                // grow into its final height after the open animation
                bar.refreshWifiList();
                // locate the backlight sysfs node so the brightness
                // watcher streams keybind writes with zero latency
                bar.discoverBrightness();
                // read the real sink volume at startup so the pill is
                // correct even before any module has been opened
                bar.refreshVolume();
            }

            Connections {
                target: Networking.devices
                function onValuesChanged() {
                    bar.enableWifiScanning();
                }
            }

            // --- BAR CONTENT ---
            RowLayout {
                id: layout
                // Centered in the bar, which shrinks during close: the
                // pieces start at the module's middle center and glide up
                // to their top-center pill spot as the shape collapses
                anchors.centerIn: parent
                spacing: 20
                opacity: 1

                // 1. WORKSPACES (Left) - Reactive to Hyprland, click to switch
                Row {
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: 5

                        delegate: Rectangle {
                            required property int index
                            property int wsId: index + 1

                            property bool isActive: {
                                let monitor = Hyprland.focusedMonitor;
                                if (!monitor || !monitor.activeWorkspace) return wsId === 1;
                                return monitor.activeWorkspace.id === wsId;
                            }

                            width: isActive ? 10 : 6
                            height: isActive ? 18 : 14
                            // same rounding ratio as the idle dots: the
                            // active pill is taller+wider, so scale the
                            // radius along with it
                            radius: width / 2
                            // Row positioners are top-aligned: keep every
                            // dot vertically centered as heights differ
                            y: (parent.height - height) / 2
                            color: isActive ? Colors.accent : Colors.accentInactive

                            Behavior on width { NumberAnimation { duration: 250 } }
                            Behavior on height { NumberAnimation { duration: 250 } }
                            Behavior on color { ColorAnimation { duration: 250 } }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Hyprland.dispatch(`workspace ${wsId}`);
                                }
                            }
                        }
                    }
                }

                // 2. CLOCK (Center)
                Text {
                    id: clockText
                    text: Qt.formatDateTime(new Date(), "hh:mm")
                    color: Colors.text
                    font.family: "Google Sans Flex"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    Layout.alignment: Qt.AlignVCenter

                    Timer {
                        interval: 1000
                        running: true
                        repeat: true
                        onTriggered: clockText.text = Qt.formatDateTime(new Date(), "hh:mm")
                    }
                }

                // 3. SYSTEM STATUS (Right)
                Row {
                    spacing: 12
                    Layout.alignment: Qt.AlignVCenter

                    // Connection level indicator
                    Row {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: [7, 10, 13, 16]
                            delegate: Rectangle {
                                required property int modelData
                                required property int index

                                width: 3
                                height: modelData
                                radius: 1
                                anchors.bottom: parent.bottom
                                color: index < bar.wifiBars ? Colors.accent : Colors.accentInactive

                                Behavior on color { ColorAnimation { duration: 250 } }
                            }
                        }
                    }

                    // Battery, filled from actual charge via UPower
                    Item {
                        width: 26
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: 2
                            radius: 4
                            color: "transparent"
                            border.color: Colors.accent
                            border.width: 1.5

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    bottom: parent.bottom
                                    margins: 2.5
                                }
                                width: (parent.width - 5) * bar.batteryFill
                                radius: 2
                                color: Colors.accent

                                Behavior on width { NumberAnimation { duration: 250 } }
                            }
                        }

                        Rectangle {
                            width: 2
                            height: 5
                            anchors.left: parent.right
                            anchors.leftMargin: -1.5
                            anchors.verticalCenter: parent.verticalCenter
                            radius: 1
                            color: Colors.accent
                        }
                    }
                }
            }

            // --- LAUNCHER CONTENT ---
            Item {
                id: launcherContent

                // Sized to the FINAL panel and pinned to the same fixed
                // point as the bar (top center): every piece is already at
                // its final position/size in the first instant, and the
                // growing panel merely reveals more of it — nothing is
                // stretched or resized into place
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: bar.panelWidth
                height: bar.panelHeight

                // No fade: the pieces are fully opaque the moment the
                // module opens; the growing panel simply reveals them
                opacity: bar.open ? 1 : 0

                // Keys when no text field has focus (wallpaper
                // picker uses arrows + Enter instead of a search box)
                Item {
                    id: keyCatcher
                    anchors.fill: parent

                    Keys.onEscapePressed: bar.closeIsland()

                    // control center is mouse-only: skip list/keys routing
                    Keys.onLeftPressed: bar.moveKey(-1)
                    Keys.onRightPressed: bar.moveKey(1)
                    Keys.onReturnPressed: bar.pressKey()
                }

                // --- APP LAUNCHER PANEL ---
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "apps"
                    // Search row: magnifier icon + input
                    Text {
                        anchors.right: searchInput.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: searchInput.verticalCenter
                        text: "\uF002" // magnifying-glass
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: bar.iconPx(text)
                        color: Colors.textAlt
                    }

                    TextInput {
                        id: searchInput
                        anchors.left: parent.left
                        anchors.leftMargin: 49
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.top: parent.top
                        anchors.topMargin: 22
                        height: 15
                        clip: true

                        color: Colors.text
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.Medium

                        cursorDelegate: Rectangle {
                            width: 2
                            radius: 1
                            color: Colors.text
                        }

                        onTextChanged: bar.searchQuery = text

                        Keys.priority: Keys.BeforeItem
                        Keys.onEscapePressed: bar.closeIsland()
                        Keys.onReturnPressed: {
                            if (bar.selectedIndex < bar.appList.length)
                                bar.launch(bar.appList[bar.selectedIndex]);
                        }
                        Keys.onDownPressed: {
                            if (bar.appList.length > 0)
                                bar.selectedIndex = (bar.selectedIndex + 1) % bar.appList.length;
                        }
                        Keys.onUpPressed: {
                            if (bar.appList.length > 0)
                                bar.selectedIndex = (bar.selectedIndex - 1 + bar.appList.length) % bar.appList.length;
                        }
                    }

                    Text {
                        visible: searchInput.text.length === 0
                        anchors.left: searchInput.left
                        anchors.leftMargin: 1
                        anchors.top: searchInput.top
                        anchors.topMargin: -0.1

                        text: "Search..."
                        color: Colors.textAlt
                        font.family: "Google Sans Flex"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    Rectangle { // divider, under the search row
                        anchors.left: parent.left
                        anchors.leftMargin: 20
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        y: bar.searchRowHeight - 5
                        height: 1
                        color: Colors.surfaceBorder
                        opacity: 0.45
                    }

                    // App list
                    ListView {
                        id: listView

                        x: 8
                        y: bar.searchRowHeight + 12
                        width: parent.width - 16
                        // 5 rows max; the REVEAL height (the animating bar)
                        // follows answers, so with few results the panel
                        // shrinks around the list rather than leaving void
                        height: Math.min(5, bar.appList.length)
                            * bar.rowHeight
                        model: bar.appList
                        clip: true
                        interactive: true
                        currentIndex: bar.selectedIndex
                        onCountChanged: bar.selectedIndex = Math.max(0, Math.min(bar.selectedIndex, bar.appList.length - 1))

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index

                            width: listView.width
                            height: bar.rowHeight

                            Rectangle { // row highlight: plain rounded
                                x: 8
                                y: 3
                                width: parent.width - 16
                                height: parent.height - 7
                                radius: 12
                                // row highlight kept off the black look:
                                // a grey pill that reads on #000000
                                color: Colors.bg2
                                opacity: row.index === bar.selectedIndex ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 250 }
                                }
                            }

                            Rectangle { // accent bar on the left edge
                                x: 8
                                y: (parent.height - height) / 2
                                width: 4
                                height: 28
                                radius: 2
                                color: Colors.accent
                                opacity: row.index === bar.selectedIndex ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 250 }
                                }
                            }

                            IconImage {
                                x: 22
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 40
                                source: Quickshell.iconPath(row.modelData.icon ?? "", "application-x-executable")
                            }

                            // Name + gray comment line
                            Column {
                                x: 77
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - 16
                                spacing: 3

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight

                                    text: row.modelData.name
                                    color: Colors.text
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: !!(row.modelData.comment ?? "")

                                    text: row.modelData.comment ?? ""
                                    color: Colors.textAlt
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: bar.selectedIndex = row.index
                                onClicked: bar.launch(row.modelData)
                            }
                        }
                    }
                }

                // --- THEME PICKER PANEL ---
                // One card per folder in ~/.config/colorschemes. The dots
                // are a color strip sampled from one of the folder's own
                // wallpapers (running matugen here would rewrite configs,
                // so the preview is sampled from the image itself).
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "themes"

                    Text { // "Themes", top left
                        x: bar.modulePad
                        y: 13
                        text: "Themes"
                        color: Colors.text
                        font.family: "Google Sans Flex"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    // Theme cards
                    ListView {
                        id: themeList

                        x: bar.modulePad
                        // symmetric headroom around the row: the scaled
                        // up (1.22x) selected card needs ~17px above and
                        // below the flat card without being cut by clip;
                        // centered between the title row and the footer
                        // wide vertical range around the flat row: the
                        // scaled (1.22x) selected card extends ~18px past
                        // the 84px card on each side, and this box keeps
                        // ~19px of slack beyond even that on each end so
                        // no clip line can ever touch it
                        y: 30
                        width: parent.width - 2 * bar.modulePad
                        height: 116
                        orientation: ListView.Horizontal
                        spacing: 5
                        // local clip stops the partial edge cards at the
                        // module's padding instead of painting the last
                        // card over the black padding strips
                        clip: true
                        interactive: true
                        model: bar.themeLoopModel

                        // Carousel snap: the "current" slot is kept pinned
                        // to the middle of the module. bar.themeInner is
                        // written imperatively (open/keys/hover); the sync
                        // below reads it back so dragging also selects.
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        // springy snap: short travel + stiffer flick
                        // stop, so the row lands fast with a bite
                        highlightMoveDuration: 250
                        flickDeceleration: 4000
                        preferredHighlightBegin: width / 2 - 75
                        preferredHighlightEnd: width / 2 + 75

                        onCountChanged: {
                            bar.themeIndex = Math.max(0, Math.min(
                                bar.themeIndex, bar.themesList.length - 1));
                            const li = Math.max(0, Math.min(
                                count - 1, bar.themeIndex));
                            if (count > 0 && currentIndex !== li)
                                currentIndex = li;
                        }

                        onCurrentIndexChanged: {
                            if (bar.themesList.length === 0) return;
                            bar.themeInner = currentIndex;
                            bar.themeIndex = bar.realIndexOf(
                                currentIndex, bar.themesList.length, count);
                        }

                        // re-enable hover-select once a key slide settles
                        Timer {
                            id: themeSlideLock
                            interval: 300
                            onTriggered: bar.themeSlideBusy = false
                        }

                        delegate: Item {
                            id: themeCard

                            required property var modelData
                            required property int index

                            readonly property bool isSel:
                                themeCard.index === bar.themeInner

                            // the theme currently IN USE gets the dot,
                            // independent of which card is selectable
                            readonly property bool isApplied:
                                bar.appliedThemeName !== ""
                                    && modelData.name === bar.appliedThemeName

                            // The bar's color: straight from the
                            // hardcoded map below (bar.themeDotColors);
                            // a theme missing from the map = muted gray
                            readonly property string dotColor:
                                typeof bar.themeDotColors[
                                    themeCard.modelData.name] === "string"
                                    ? bar.themeDotColors[
                                          themeCard.modelData.name]
                                    : ""

                            width: 150
                            height: 106
                            z: themeCard.isSel ? 1 : 0

                            // every card but the current one is shaded out
                            opacity: themeCard.isSel ? 1 : 0.45

                            Behavior on opacity {
                                NumberAnimation { duration: 250 }
                            }

                            Item {
                                // the card itself: centered in the
                                // 106px layout slot by its own y (the
                                // view resets the delegate root's y);
                                // the selection is a center-anchored
                                // zoom on the shared center line
                                x: 0
                                y: 11
                                width: 150
                                height: 84

                                scale: themeCard.isSel ? 1.17 : 1

                                // springy zoom: back-out curve blows past
                                // the resting size slightly and settles
                                // back, so switching themes/wallpapers
                                // pops with a little spring; it always
                                // converges to the bound target
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.4
                                    }
                                }

                            Rectangle { // card background
                                anchors.fill: parent
                                radius: 12
                                // per-theme hardcoded color; themes not in
                                // bar.themeCardColors fall back to black
                                color: typeof bar.themeCardColors[
                                    themeCard.modelData.name] === "string"
                                    ? bar.themeCardColors[
                                          themeCard.modelData.name]
                                    : bar.pureBlack
                                border.width: 0
                                border.color: Colors.surfaceBorder
                                opacity: themeCard.isSel ? 1 : 0.75

                                Behavior on color { ColorAnimation { duration: 250 } }
                                Behavior on opacity { NumberAnimation { duration: 250 } }
                            }

                            // "In use" dot, top right corner of the card
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: 6
                                anchors.rightMargin: 6
                                width: 5
                                height: 5
                                radius: 2.5
                                color: Colors.accent
                                opacity: themeCard.isApplied ? 1 : 0
                                z: 2

                                Behavior on opacity {
                                    NumberAnimation { duration: 250 }
                                }
                            }

                            Canvas { // color strip, one solid bar
                                id: colorStrip
                                x: (themeCard.width - width) / 2
                                y: 28
                                width: 65
                                height: 9
                                renderStrategy: Canvas.Immediate
                                renderTarget: Canvas.Image

                                // Qt's canvas lacks ctx.roundRect; build
                                // the pill path the classic way
                                onPaint: {
                                    const ctx = getContext("2d");
                                    const r = height / 2;
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.beginPath();
                                    ctx.moveTo(r, 0);
                                    ctx.arcTo(width, 0, width, height, r);
                                    ctx.arcTo(width, height, 0, height, r);
                                    ctx.arcTo(0, height, 0, 0, r);
                                    ctx.arcTo(0, 0, width, 0, r);
                                    ctx.closePath();

                                    ctx.fillStyle =
                                        themeCard.dotColor !== ""
                                            ? themeCard.dotColor
                                            : String(Colors.accentInactive);
                                    ctx.fill();
                                }

                                // redraw when you edit the map
                                Connections {
                                    target: bar
                                    function onThemeDotColorsChanged() {
                                        colorStrip.requestPaint();
                                    }
                                }
                            }

                            Text { // folder name, lowercase, no dashes
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 56
                                text: themeCard.modelData.name
                                    .replace(/-/g, " ").toLowerCase()
                                color: themeCard.isSel
                                    ? Colors.text : Colors.textAlt
                                font.family: "Google Sans Flex"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                // instant reposition: the hovered card is
                                // already under the cursor, so an animated
                                // centering would flicker
                                onEntered: {
                                    if (themeList.moving
                                        || bar.themeSlideBusy) return;
                                    themeList.currentIndex = themeCard.index
                                    themeList.positionViewAtIndex(
                                        themeCard.index, ListView.Center)
                                }
                                onClicked: bar.applyTheme(
                                    themeCard.modelData.path)
                            }
                        
                    }}
                    }

                    Text { // "1/6  ·  Enter to apply", bottom right
                        anchors.right: parent.right
                        anchors.rightMargin: bar.modulePad
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10

                        text: bar.themesList.length > 0
                            ? (bar.themeIndex + 1) + "/" + bar.themesList.length
                              + "   \u00b7   Enter to apply"
                            : "Enter to apply"
                        color: Colors.textAlt
                        font.family: "Google Sans Flex"
                        font.pixelSize: 11
                    }
                }

                // --- WALLPAPER PICKER PANEL ---
                // Lists the wallpapers of the current theme folder; picking
                // one runs matugen, records it and updates hyprlock
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "wallpapers"

                    Text { // "Wallpaper", top left
                        x: bar.modulePad
                        y: 13
                        text: "Wallpapers"
                        color: Colors.text
                        font.family: "Google Sans Flex"
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }

                    Text { // theme name, top right
                        anchors.right: parent.right
                        anchors.rightMargin: bar.modulePad
                        y: 14

                        text: bar.wallpaperDir.split("/").pop()
                            .replace(/-/g, " ").toLowerCase()
                        color: Colors.textAlt
                        font.family: "Google Sans Flex"
                        font.pixelSize: 12
                    }

                    // Thumbnails
                    ListView {
                        id: wallGallery

                        x: bar.modulePad
                        // symmetric headroom around the row: the scaled
                        // up (1.22x) selected card needs ~17px above and
                        // below the flat card without being cut by clip;
                        // centered between the title row and the footer
                        // wide vertical range around the flat row: the
                        // scaled (1.22x) selected card extends ~18px past
                        // the 84px card on each side, and this box keeps
                        // ~19px of slack beyond even that on each end so
                        // no clip line can ever touch it
                        y: 30
                        width: parent.width - 2 * bar.modulePad
                        height: 116
                        orientation: ListView.Horizontal
                        spacing: 5
                        // viewport spans the whole panel so the 1.22x
                        // zoom of the selected thumb always stays inside
                        // the clip; the row itself is centered by the
                        // delegate's y, not by shrinking this box
                        clip: true
                        interactive: true
                        model: bar.wallLoopModel

                        // Same centered carousel as the theme picker
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        // springy snap: short travel + stiffer flick
                        // stop, so the row lands fast with a bite
                        highlightMoveDuration: 250
                        flickDeceleration: 4000
                        preferredHighlightBegin: width / 2 - 75
                        preferredHighlightEnd: width / 2 + 75

                        onCountChanged: {
                            bar.wallIndex = Math.max(0, Math.min(
                                bar.wallIndex, bar.wallList.length - 1));
                            const li = Math.max(0, Math.min(
                                count - 1, bar.wallIndex));
                            if (count > 0 && currentIndex !== li)
                                currentIndex = li;
                        }

                        onCurrentIndexChanged: {
                            if (bar.wallList.length === 0) return;
                            bar.wallInner = currentIndex;
                            bar.wallIndex = bar.realIndexOf(
                                currentIndex, bar.wallList.length, count);
                        }

                        // re-enable hover-select once a key slide settles
                        Timer {
                            id: wallSlideLock
                            interval: 300
                            onTriggered: bar.wallSlideBusy = false
                        }

                        delegate: Item {
                            id: wallCard

                            required property var modelData
                            required property int index

                            readonly property bool isSel:
                                wallCard.index === bar.wallInner

                            // the wallpaper currently IN USE gets the dot
                            readonly property bool isApplied:
                                wallCard.modelData.path === bar.wallpaperPath

                            width: 150
                            height: 106
                            z: wallCard.isSel ? 1 : 0

                            // every thumb but the current one is shaded out
                            opacity: wallCard.isSel ? 1 : 0.45

                            Behavior on opacity {
                                NumberAnimation { duration: 250 }
                            }

                            Item {
                                // the card itself: centered in the 106px
                                // layout slot by its own y (the view resets
                                // the delegate root's y); the selection is
                                // a center-anchored zoom on the shared
                                // center line
                                x: 0
                                y: 11
                                width: 150
                                height: 84

                                scale: wallCard.isSel ? 1.17 : 1

                                // springy zoom: back-out curve blows past
                                // the resting size slightly and settles
                                // back, so switching themes/wallpapers
                                // pops with a little spring; it always
                                // converges to the bound target
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.4
                                    }
                                }

                                // Backdrop body (same look as a theme
                                // card); the border is constant, selection
                                // is expressed by the zoom alone
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: bar.pureBlack
                                    border.width: 0
                                    border.color: Colors.surfaceBorder
                                    opacity: wallCard.isSel ? 1 : 0.75

                                    Behavior on opacity {
                                        NumberAnimation { duration: 250 }
                                    }
                                }

                                // Thumbnail with genuinely rounded corners:
                                // the image is masked instead of relying on
                                // clip, so it can never cover or cut the ring
                                Item {
                                    anchors.fill: parent

                                    Image {
                                        id: thumbImg
                                        anchors.fill: parent
                                        source: "file://" + wallCard.modelData.path
                                        sourceSize.width: 176
                                        sourceSize.height: 112
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        visible: false
                                    }

                                    OpacityMask {
                                        anchors.fill: parent
                                        source: thumbImg
                                        maskSource: ShaderEffectSource {
                                            sourceItem: Rectangle {
                                                width: 150
                                                height: 84
                                                radius: 12
                                                color: "white"
                                            }
                                            visible: false
                                        }
                                    }
                                }

                                // "In use" dot, top right corner
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: 6
                                    anchors.rightMargin: 6
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: Colors.accent
                                    opacity: wallCard.isApplied ? 1 : 0
                                    z: 2

                                    Behavior on opacity {
                                        NumberAnimation { duration: 250 }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    // instant reposition: the hovered thumb
                                    // is already under the cursor, so an
                                    // animated centering would flicker
                                    onEntered: {
                                        if (wallGallery.moving
                                            || bar.wallSlideBusy) return;
                                        wallGallery.currentIndex =
                                            wallCard.index;
                                        wallGallery.positionViewAtIndex(
                                            wallCard.index, ListView.Center);
                                    }
                                    onClicked:
                                        bar.apply(wallCard.modelData.path)
                                }
                            }
                        }
                    }

                    Text { // selected file name, bottom left
                        x: bar.modulePad
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10

                        text: bar.wallIndex < bar.wallList.length
                            ? bar.wallList[bar.wallIndex].name : ""
                        color: Colors.textAlt
                        font.family: "Google Sans Flex"
                        font.pixelSize: 11
                    }

                    Text { // "1/2  ·  Enter to apply", bottom right
                        anchors.right: parent.right
                        anchors.rightMargin: bar.modulePad
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10

                        text: bar.wallList.length > 0
                            ? (bar.wallIndex + 1) + "/" + bar.wallList.length
                              + "   \u00b7   Enter to apply"
                            : "Enter to apply"
                        color: Colors.textAlt
                        font.family: "Google Sans Flex"
                        font.pixelSize: 11
                    }
                }

                // --- POWER MODULE PANEL ---
                // One big button per action; the selected card is filled
                // with the accent color (dark icon/label on it)
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "power"

                    Row {
                        x: (bar.panelWidth - width) / 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: bar.powerGap

                        Repeater {
                            model: bar.powerActions

                            delegate: Rectangle {
                                id: powerButton

                                required property var modelData
                                required property int index

                                readonly property bool isSel:
                                    powerButton.index === bar.powerIndex

                                width: bar.powerCardSize
                                height: bar.powerCardSize
                                radius: 24
                                color: powerButton.isSel
                                    ? Colors.accent : Colors.accentInactive

                                Behavior on color { ColorAnimation { duration: 250 } }

                                // Icon: a Nerd Fonts glyph (JetBrainsMono
                                // Nerd Font carries the private-use icons);
                                // the label below stays Google Sans Flex
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 22
                                    text: powerButton.modelData.icon
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 19
                                    color: powerButton.isSel
                                        ? bar.pureBlack : Colors.text

                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 62
                                    text: powerButton.modelData.name
                                    color: powerButton.isSel
                                        ? bar.pureBlack : Colors.text
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium

                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: bar.powerIndex = powerButton.index
                                    onClicked: bar.invokePower()
                                }
                            }
                        }
                    }
                }

                // --- NOTIFICATION PANEL ---
                // The island morphs into this capsule when a notification
                // arrives, holds it until the linger timer fires, then
                // folds back into the pill. Click dismisses early; all keys
                // pass it by (no keyboard focus is taken)
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "notif"

                    RowLayout {
                        id: notifRow

                        x: Math.round(14 * bar.notifScale)
                        y: (parent.height - height) / 2
                        spacing: Math.round(11 * bar.notifScale)

                        Rectangle { // app initial bubble, centered on the text
                            Layout.alignment: Qt.AlignVCenter
                            width: Math.round(34 * bar.notifScale)
                            height: Math.round(34 * bar.notifScale)
                            radius: width / 2
                            color: Colors.bg2

                            Text {
                                anchors.centerIn: parent
                                text: notifServer.appLabel.length
                                    ? notifServer.appLabel[0].toUpperCase()
                                    : "N"
                                color: Colors.accent
                                font.family: "Google Sans Flex"
                                font.pixelSize: Math.round(15 * bar.notifScale)
                                font.weight: Font.Bold
                            }
                        }

                        Column {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            // the texts keep their left edge aligned, so
                            // short/long lines never shift the block
                            Text { // app name
                                text: notifServer.appLabel
                                color: Colors.textAlt
                                font.family: "Google Sans Flex"
                                font.pixelSize: Math.round(10 * bar.notifScale)
                            }

                            Text { // summary, bold
                                text: notifServer.title
                                color: Colors.text
                                font.family: "Google Sans Flex"
                                font.pixelSize: Math.round(13 * bar.notifScale)
                                font.weight: Font.Medium
                            }

                            Text { // body, single line, ellipsized
                                text: notifServer.bodyText
                                color: Colors.textAlt
                                font.family: "Google Sans Flex"
                                font.pixelSize: Math.round(11 * bar.notifScale)
                                visible: notifServer.bodyText !== ""
                                width: Math.min(
                                    implicitWidth,
                                    Math.round(260 * bar.notifScale))
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: bar.closeIsland()
                    }
                }

                // --- CONTROL PANEL ---
                // Live tiles: Wi-Fi (NetworkManager), Bluetooth (Bluez),
                // sound (default Pipewire sink), display (brightnessctl),
                // notifications list (the same server keepalives
                // track them); DND still gates notification morphs
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "control"

                    readonly property int tileGap: 14
                    // single tile row fills the middle of the panel
                    // status subline per tile
                    function wifiSub() {
                        return Networking.wifiEnabled
                            ? (bar.wifiSsid || "On") : "Off";
                    }

                    Rectangle { // Wi-Fi tile
                        x: bar.modulePad
                        y: bar.modulePad
                        width: bar.controlTileW
                        height: bar.controlTileH
                        radius: height / 2
                        color: Colors.bg1

                        Row {
                            x: 7
                            y: (parent.height - height) / 2
                            spacing: 9

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: Networking.wifiEnabled
                                    ? Colors.accent : Colors.bg2
                                Behavior on color {
                                    ColorAnimation { duration: 250 }
                                }

                                Text {
                                    anchors.horizontalCenter:
                                        parent.horizontalCenter
                                    y: (parent.height - height) / 2
                                    text: "\uF1EB" // wifi
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: bar.iconPx(text)
                                    color: Networking.wifiEnabled
                                        ? bar.pureBlack : Colors.textAlt
                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenterOffset: -1
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: "Wi-Fi"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Colors.text
                                }

                                Text {
                                    text: Networking.wifiEnabled
                                        ? (bar.wifiSsid || "On") : "Off"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 10
                                    color: Colors.textAlt
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                                | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // left = toggle wifi, right = the wifi module
                            onClicked: mouse.button === Qt.RightButton
                                ? bar.openIsland("wifi")
                                : bar.toggleWifi()
                        }
                    }

                    Rectangle { // Bluetooth tile
                        x: parent.tileGap + bar.modulePad
                            + bar.controlTileW
                        y: bar.modulePad
                        width: bar.controlTileW
                        height: bar.controlTileH
                        radius: height / 2
                        color: Colors.bg1

                        Row {
                            x: 7
                            y: (parent.height - height) / 2
                            spacing: 9

                            Rectangle {
                                width: 34
                                height: 34
                                radius: 17
                                color: Bluetooth.defaultAdapter
                                    && Bluetooth.defaultAdapter.enabled
                                    ? Colors.accent : Colors.bg2
                                Behavior on color {
                                    ColorAnimation { duration: 250 }
                                }

                                Text {
                                    anchors.horizontalCenter:
                                        parent.horizontalCenter
                                    y: (parent.height - height) / 2
                                    text: "\uF294" // bluetooth-b
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: bar.iconPx(text)
                                    color: Bluetooth.defaultAdapter
                                        && Bluetooth.defaultAdapter.enabled
                                        ? bar.pureBlack : Colors.textAlt
                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenterOffset: -1
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: "Bluetooth"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Colors.text
                                }

                                Text {
                                    text: Bluetooth.defaultAdapter
                                        && Bluetooth.defaultAdapter.enabled
                                        ? "On" : "Off"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 10
                                    color: Colors.textAlt
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.toggleBluetooth()
                        }
                    }

                    Rectangle { // Sound card: header + instant fill pill
                        x: bar.modulePad
                        y: bar.modulePad + bar.controlTileH
                            + parent.tileGap
                        width: parent.width - 2 * bar.modulePad
                        height: 62
                        radius: 16
                        color: Colors.bg1

                        readonly property real trackW: width - 28

                        Text {
                            x: 14
                            y: 9
                            text: "Sound"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: Colors.text
                        }

                        Text { // chevron
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 9
                            text: "\uF105" // chevron-right
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 12
                            color: Colors.textAlt
                        }

                        Rectangle { // the fill IS the pill
                            x: 14
                            y: 28
                            width: bar.volMuted
                                ? Math.min(30, parent.trackW)
                                : Math.max(Math.min(
                                    bar.volPct / 100 * parent.trackW,
                                    parent.trackW), 30)
                            height: bar.controlPillH
                            radius: height / 2
                            color: Colors.accent

                            Text {
                                x: 10
                                y: (parent.height - height) / 2
                                text: bar.volMuted ? "\uF026" : "\uF028"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: bar.iconPx(text)
                                color: bar.pureBlack
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // right-click anywhere on the Sound card opens
                            // the device mixer module (the ONLY way in);
                            // a left-click drag keeps setting the volume
                            function apply(m) {
                                bar.volumeSet(Math.round(
                                    Math.min(1, Math.max(0,
                                        (m.x - 14) / parent.trackW))
                                    * 100));
                            }
                            onPressed: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    bar.openIsland("sound");
                                    return;
                                }
                                bar.volDragging = true;
                                apply(mouse);
                            }
                            onPositionChanged: mouse => {
                                if (pressed) apply(mouse);
                            }
                            onReleased: mouse => {
                                if (mouse.button === Qt.RightButton) return;
                                apply(mouse);
                                bar.volDragging = false;
                            }
                            onCanceled: bar.volDragging = false
                        }
                    }

                    Rectangle { // Display card: header + instant fill pill
                        x: bar.modulePad
                        y: bar.modulePad + bar.controlTileH
                            + parent.tileGap + 76 // sound card + gap
                        width: parent.width - 2 * bar.modulePad
                        height: 62
                        radius: 16
                        color: Colors.bg1

                        readonly property real trackW: width - 28

                        Text {
                            x: 14
                            y: 9
                            text: "Display"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: Colors.text
                        }

                        Text { // chevron
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 9
                            text: "\uF105" // chevron-right
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 12
                            color: Colors.textAlt
                        }

                        Rectangle { // the fill IS the pill
                            x: 14
                            y: 28
                            width: Math.max(Math.min(
                                bar.briVisual / 100 * parent.trackW,
                                parent.trackW), 30)
                            height: bar.controlPillH
                            radius: height / 2
                            color: Colors.accent

                            Text {
                                x: 10
                                y: (parent.height - height) / 2
                                text: "\uF185" // sun
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: bar.iconPx(text)
                                color: bar.pureBlack
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // right-click anywhere on the Display card opens
                            // the display module (the ONLY way in); a
                            // left-click drag keeps setting the brightness
                            function apply(m) {
                                const p = Math.round(
                                    Math.min(1, Math.max(0,
                                        (m.x - 14) / parent.trackW))
                                    * 100);
                                bar.briDragPct = p;
                                bar.briTarget = p;
                                briLatch.restart();
                            }
                            onPressed: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    bar.openIsland("display");
                                    return;
                                }
                                bar.briDragging = true;
                                apply(mouse);
                            }
                            onPositionChanged: mouse => {
                                if (pressed) apply(mouse);
                            }
                            onReleased: mouse => {
                                if (mouse.button === Qt.RightButton) return;
                                apply(mouse);
                                bar.briDragging = false;
                            }
                            onCanceled: bar.briDragging = false
                        }
                    }

                    Rectangle { // notifications box
                        x: bar.modulePad
                        y: bar.modulePad + bar.controlTileH
                            + parent.tileGap
                            + 152 // sound row + display card + gap
                        width: parent.width - 2 * bar.modulePad
                        height: 108
                        radius: 16
                        color: Colors.bg1

                        Column {
                            x: 14
                            y: 9
                            spacing: 2
                            width: parent.width - 28

                            Text {
                                text: "Notifications"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: Colors.text
                            }

                            Text { // empty state
                                visible: bar.notifHistory.length === 0
                                text: "No notifications"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 12
                                color: Colors.textAlt
                            }

                            // session history: newest first, app name in
                            // accent followed by summary - body
                            Repeater {
                                model: Math.min(4, bar.notifHistory.length)

                                Text {
                                    required property int index

                                    width: parent.width
                                    text: ("<font color=\""
                                        + Colors.accent + "\">"
                                        + bar.notifHtml(
                                            bar.notifHistory[index].app)
                                        + "</font> "
                                        + bar.notifHtml(
                                            bar.notifHistory[index].sum
                                            + " \u2013 "
                                            + bar.notifHistory[index].body))
                                    textFormat: Text.StyledText
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Colors.text
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            Text { // how many more in the session
                                visible: bar.notifHistory.length > 4
                                text: "+" + (bar.notifHistory.length - 4)
                                      + " more"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 10
                                color: Colors.textAlt
                            }
                        }

                        MouseArea { // open the scrollable history module
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: bar.openIsland("notifHistory")
                        }

                        Text { // chevron affordance, like Sound/Display
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            y: 9
                            text: "\uF105" // chevron-right
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 12
                            color: Colors.textAlt
                        }
                    }
                }

                // --- SOUND MODULE (right-click the Sound card) ---
                // back chevron -> control center, then the device mixer:
                // Output rows (click = default device, checkmarked),
                // a volume pill for the default sink, the same for Input,
                // and per-app stream sliders. All sections flow in one
                // column; the panel height wraps whatever it holds
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "wifi"

                    Column {
                        id: wifiCol

                        x: bar.modulePad
                        y: bar.modulePad
                        width: bar.panelWidth - 2 * bar.modulePad
                        spacing: 14

                        Item { // title row: back chevron + centered label
                            width: parent.width
                            height: 34

                            Text { // back chevron
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                text: "\uF104" // chevron-left
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 12
                                color: Colors.text

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.openIsland("control")
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) / 2
                                text: "Wi-Fi"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: Colors.text
                            }
                        }

                        Rectangle { // wifi on/off switch row
                            width: parent.width
                            height: 44
                            radius: 22
                            color: Colors.bg1

                            Text {
                                x: 18
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Wi-Fi"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: Networking.wifiEnabled
                                    ? Colors.text : Colors.textAlt
                            }

                            Rectangle { // the switch
                                property bool on: Networking.wifiEnabled

                                x: parent.width - 44
                                y: (parent.height - height) / 2
                                width: 30
                                height: 18
                                radius: 9
                                color: on ? Colors.accent
                                    : Colors.accentInactive
                                Behavior on color {
                                    ColorAnimation { duration: 250 }
                                }

                                Rectangle {
                                    x: parent.on ? parent.width - width - 2
                                        : 2
                                    width: 14
                                    radius: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 14
                                    color: parent.on ? bar.pureBlack
                                        : Colors.textAlt
                                    Behavior on x {
                                        NumberAnimation { duration: 250
                                            easing.type: Easing.OutBack }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.toggleWifi()
                                }
                            }
                        }

                        Text { // join error note
                            x: 4
                            visible: bar.wifiErr !== ""
                            text: bar.wifiErr
                            font.family: "Google Sans Flex"
                            font.pixelSize: 10
                            color: Colors.accent
                        }

                        Repeater {
                            model: bar.wifiActive !== "" ? 1 : 0

                            Item { // Connected card (separated section)
                                width: parent.width
                                height: 46

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 14
                                    color: Colors.bg2

                                    Text {
                                        x: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: bar.wifiActive
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        color: Colors.text
                                    }

                                    Row { // signal bars, right corner
                                        x: parent.width - 58
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Repeater {
                                            model: [5, 8, 11, 14]
                                            delegate: Rectangle {
                                                required property int index
                                                required property int modelData
                                                width: 3
                                                height: modelData
                                                radius: 1
                                                anchors.bottom: parent.bottom
                                                color: index < bar.sigBarCount(
                                                    bar.wifiActiveSig)
                                                    ? Colors.accent
                                                    : Colors.accentInactive
                                                Behavior on color {
                                                    ColorAnimation {
                                                        duration: 250 }
                                                }
                                            }
                                        }
                                    }

                                    Text { // connected check
                                        x: parent.width - 96
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\uF00C" // check
                                        font.family:
                                            "JetBrainsMono Nerd Font Propo"
                                        font.pixelSize: bar.iconPx(text)
                                        color: Colors.accent
                                    }
                                }
                            }
                        }

                        Column { // available networks
                            width: parent.width
                            spacing: 2

                            Text { // section label
                                x: 4
                                visible: wifiModel.count > 0
                                text: bar.wifiActive !== ""
                                    ? "Other networks" : "Networks"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 10
                                color: Colors.textAlt
                            }

                            Repeater {
                                model: wifiModel

                                delegate: Rectangle {
                                    id: apRow

                                    required property string ssid
                                    required property int apSignal
                                    required property bool sec
                                    width: wifiCol !== null
                                        ? wifiCol.width : 0
                                    height: 40
                                    radius: 12
                                    color: wifiArea.containsMouse
                                        ? Colors.bg2 : Colors.bg1
                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }

                                    Text {
                                        x: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ssid
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 13
                                        color: Colors.text
                                        elide: Text.ElideRight
                                        width: parent.width - 110
                                    }

                                    Row { // strength bars
                                        id: sigBars
                                        x: parent.width - 62
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Repeater {
                                            model: [5, 8, 11, 14]
                                            delegate: Rectangle {
                                                required property int index
                                                required property int modelData
                                                width: 3
                                                height: modelData
                                                radius: 1
                                                anchors.bottom: parent.bottom
                                                color: index < bar.sigBarCount(
                                                    apRow.apSignal)
                                                    ? Colors.accent
                                                    : Colors.accentInactive
                                            }
                                        }
                                    }

                                    Text { // lock
                                        x: parent.width - 44
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: sec
                                            && bar.wifiBusy
                                                !== ssid
                                        text: "\uF023" // lock
                                        font.family:
                                            "JetBrainsMono Nerd Font Propo"
                                        font.pixelSize: bar.iconPx(text)
                                        color: Colors.textAlt
                                    }

                                    Text {
                                        x: parent.width - 40
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: bar.wifiBusy
                                            === ssid
                                        text: "..."
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 10
                                        color: Colors.textAlt
                                    }

                                    MouseArea {
                                        id: wifiArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: bar.wifiJoin(
                                            ssid)
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "sound"

                    Column {
                        id: sndCol

                        x: bar.modulePad
                        y: bar.modulePad
                        width: bar.panelWidth - 2 * bar.modulePad
                        spacing: 14

                        Item { // title row: back chevron + centered label
                            width: parent.width
                            height: 34

                            Text { // back chevron
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                text: "\uF104" // chevron-left
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 12
                                color: Colors.text

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.openIsland("control")
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) / 2
                                text: "Sound"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: Colors.text
                            }
                        }

                        Text { // "Output" section label
                            x: 4
                            text: "Output"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 10
                            color: Colors.textAlt
                        }

                        Flickable { // output devices (max 5 visible, scrolls)
                            width: parent.width
                            height: bar.sndSinks.length === 0 ? 0
                                : Math.min(5, bar.sndSinks.length) * 48 - 6
                            contentHeight: bars.height
                            clip: true

                            Column {
                                id: bars
                                spacing: 6

                            Repeater {
                                model: bar.sndSinks

                                Rectangle {
                                    id: sinkRow

                                    required property var modelData
                                    readonly property bool isDefault:
                                        bar.sinkName === modelData.name

                                    width: bar.panelWidth - 2 * bar.modulePad
                                    height: bar.sndRowH
                                    radius: 13
                                    color: Colors.bg1

                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }

                                    Rectangle {
                                        x: 6
                                        y: (parent.height - height) / 2
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: sinkRow.isDefault
                                            ? Colors.accent : Colors.bg2

                                        Behavior on color {
                                            ColorAnimation { duration: 250 }
                                        }

                                        Text {
                                            anchors.horizontalCenter:
                                                parent.horizontalCenter
                                            y: (parent.height - height) / 2
                                            text: bar.sndIcon(
                                                sinkRow.modelData.description,
                                                false)
                                            font.family:
                                                "JetBrainsMono Nerd Font Propo"
                                            font.pixelSize: bar.iconPx(text)
                                            color: sinkRow.isDefault
                                                ? bar.pureBlack
                                                : Colors.textAlt
                                        }
                                    }

                                    Text {
                                        x: 44
                                        y: (parent.height - height) / 2
                                        width: parent.width - 44 - 40
                                        text: sinkRow.modelData.description
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 12
                                        color: Colors.text
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text { // check for the default device
                                        visible: sinkRow.isDefault
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        y: (parent.height - height) / 2
                                        text: "\uF00C" // check
                                        font.family: "JetBrainsMono Nerd Font Propo"
                                        font.pixelSize: bar.iconPx(text)
                                        color: Colors.accent
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: bar.sinkSetDefault(
                                            sinkRow.modelData.name)
                                    }
                                }
                            }
                        }
                    }

                        Item { // output volume pill
                            width: parent.width
                            height: 36

                            Rectangle {
                                y: 3
                                width: Math.max(Math.min(
                                    bar.volPct / 100 * (parent.width - 56),
                                    parent.width - 56), 30)
                                height: 30
                                radius: 15
                                color: Colors.accent

                            Text {
                                x: 9
                                y: (parent.height - height) / 2
                                text: bar.volMuted ? "\uF026" : "\uF028"
                                font.family:
                                    "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: bar.iconPx(text)
                                color: bar.pureBlack
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            y: (parent.height - height) / 2
                            text: bar.volPct + "%"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => bar.volumeSet(Math.round(
                                Math.min(1, Math.max(0, mouse.x
                                / (parent.width - 56))) * 100))
                            onPositionChanged: mouse => {
                                if (pressed) bar.volumeSet(Math.round(
                                    Math.min(1, Math.max(0, mouse.x
                                    / (parent.width - 56))) * 100));
                            }
                        }
                    }

                        Text { // "Input" section label
                            x: 4
                            text: "Input"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 10
                            color: Colors.textAlt
                        }

                        Flickable { // input devices (max 3 visible)
                            width: parent.width
                            height: bar.sndSources.length === 0 ? 0
                                : Math.min(3, bar.sndSources.length) * 48 - 6
                            contentHeight: mics.height
                            clip: true

                        Column {
                            id: mics
                            spacing: 6

                            Repeater {
                                model: bar.sndSources

                                Rectangle {
                                    id: srcRow

                                    required property var modelData
                                    readonly property bool isDefault:
                                        bar.sourceName === modelData.name

                                    width: bar.panelWidth - 2 * bar.modulePad
                                    height: bar.sndRowH
                                    radius: 13
                                    color: Colors.bg1

                                    Behavior on color {
                                        ColorAnimation { duration: 250 }
                                    }

                                    Rectangle {
                                        x: 6
                                        y: (parent.height - height) / 2
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: srcRow.isDefault
                                            ? Colors.accent : Colors.bg2

                                        Behavior on color {
                                            ColorAnimation { duration: 250 }
                                        }

                                        Text {
                                            anchors.horizontalCenter:
                                                parent.horizontalCenter
                                            y: (parent.height - height) / 2
                                            text: bar.sndIcon(
                                                srcRow.modelData.description,
                                                true)
                                            font.family:
                                                "JetBrainsMono Nerd Font Propo"
                                            font.pixelSize: bar.iconPx(text)
                                            color: srcRow.isDefault
                                                ? bar.pureBlack
                                                : Colors.textAlt
                                        }
                                    }

                                    Text {
                                        x: 44
                                        y: (parent.height - height) / 2
                                        width: parent.width - 44 - 40
                                        text: srcRow.modelData.description
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 12
                                        color: Colors.text
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Text {
                                        visible: srcRow.isDefault
                                        anchors.right: parent.right
                                        anchors.rightMargin: 16
                                        y: (parent.height - height) / 2
                                        text: "\uF00C" // check
                                        font.family: "JetBrainsMono Nerd Font Propo"
                                        font.pixelSize: bar.iconPx(text)
                                        color: Colors.accent
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: bar.sourceSetDefault(
                                            srcRow.modelData.name)
                                    }
                                }
                            }
                        }
                    }

                        Item { // input volume pill
                            width: parent.width
                            height: 36

                            Rectangle {
                                y: 3
                                width: Math.max(Math.min(
                                    bar.srcPct / 100 * (parent.width - 56),
                                    parent.width - 56), 30)
                                height: 30
                                radius: 15
                                color: Colors.accent

                            Text {
                                x: 9
                                y: (parent.height - height) / 2
                                text: "\uF130" // microphone
                                font.family:
                                    "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: bar.iconPx(text)
                                color: bar.pureBlack
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            y: (parent.height - height) / 2
                            text: bar.srcPct + "%"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 12
                            color: Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function apply(m) {
                                const p = Math.round(Math.min(1,
                                    Math.max(0, m.x
                                    / (parent.width - 56))) * 100);
                                bar.srcPct = p; // instant, like the sink
                                bar.srcDragging = true;
                                bar.srcTarget = p;
                                srcLatch.restart();
                            }
                            onPressed: mouse => apply(mouse)
                            onPositionChanged: mouse => {
                                if (pressed) apply(mouse);
                            }
                            onReleased: mouse => {
                                apply(mouse);
                                bar.srcDragging = false;
                            }
                            onCanceled: bar.srcDragging = false
                        }
                    }

                    Text { // "Apps" section label (hidden when nothing plays)
                        visible: bar.sndApps.length > 0
                        x: 4
                        text: "Apps"
                        font.family: "Google Sans Flex"
                        font.pixelSize: 10
                        color: Colors.textAlt
                    }

                    Flickable { // playing app streams (max 2 visible)
                        visible: bar.sndApps.length > 0
                        width: parent.width
                        height: bar.sndApps.length === 0 ? 0
                            : Math.min(2, bar.sndApps.length) * 62
                                + (Math.min(2, bar.sndApps.length) - 1) * 8
                        contentHeight: streams.height
                        clip: true

                        Column {
                            id: streams
                            spacing: 8

                            Repeater {
                                model: bar.sndApps

                                Rectangle {
                                    id: appRow

                                    required property var modelData
                                    property real pctVal:
                                        parseFloat(modelData.pct) || 0

                                    width: bar.panelWidth
                                        - 2 * bar.modulePad
                                    height: 62
                                    radius: 13
                                    color: Colors.bg1

                                    Text {
                                        x: 12
                                        y: 7
                                        width: parent.width - 120
                                        text: appRow.modelData.name
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        color: Colors.text
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Rectangle {
                                        x: 12
                                        y: 32
                                        width: Math.max(Math.min(
                                            appRow.pctVal / 100
                                            * (parent.width - 110),
                                            parent.width - 110), 26)
                                        height: 22
                                        radius: 11
                                        color: Colors.accent

                                        Text {
                                            x: 7
                                            y: (parent.height - height) / 2
                                            text: "\uF028"
                                            font.family: "JetBrainsMono Nerd Font Propo"
                                            font.pixelSize: bar.iconPx(text)
                                            color: bar.pureBlack
                                        }
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 14
                                        y: (parent.height - height) / 2
                                        text: Math.round(appRow.pctVal)
                                            + "%"
                                        font.family: "Google Sans Flex"
                                        font.pixelSize: 12
                                        color: Colors.text
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        function apply(m) {
                                            const p = Math.round(
                                                Math.min(1, Math.max(0,
                                                    (m.x - 12)
                                                    / (parent.width - 110)))
                                                * 100);
                                            appRow.pctVal = p;
                                            bar.appVolIdx =
                                                appRow.modelData.idx;
                                                bar.appVolPct = p;
                                                appLatch.restart();
                                            }
                                            onPressed: mouse => apply(mouse)
                                            onPositionChanged: mouse => {
                                                if (pressed) apply(mouse);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- DISPLAY MODULE (right-click the Display card) ---
                // back chevron -> control center, then one row per
                // monitor (sysfs backlight device): the row shows the
                // device's label and its own brightness pill slider,
                // exactly like the sound module's volume pills minus
                // the Input section. The panel height wraps the rows
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "display"

                    Column {
                        id: dspCol

                        x: bar.modulePad
                        y: bar.modulePad
                        width: bar.panelWidth - 2 * bar.modulePad
                        spacing: 14

                        Item { // title row: back chevron + centered label
                            width: parent.width
                            height: 34

                            Text { // back chevron
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                text: "\uF104" // chevron-left
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 12
                                color: Colors.text

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.openIsland("control")
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) / 2
                                text: "Display"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: Colors.text
                            }
                        }

                        Text { // "Monitors" section label
                            x: 4
                            visible: bar.briDevices.length > 0
                            text: "Monitors"
                            font.family: "Google Sans Flex"
                            font.pixelSize: 10
                            color: Colors.textAlt
                        }

                        Flickable { // monitor rows (max 5 visible, scrolls)
                            width: parent.width
                            height: bar.briDevices.length === 0 ? 0
                                : Math.min(5, bar.briDevices.length) * 62
                                    + (Math.min(5, bar.briDevices.length)
                                       - 1) * 8
                            contentHeight: devList.height
                            clip: true

                            Column {
                                id: devList
                                spacing: 6

                                Repeater {
                                    id: devRepeater
                                    model: bar.briDevices

                                    delegate: Rectangle {
                                        id: devRow

                                        property string rowDev:
                                            modelData.dev
                                        property string rowLabel:
                                            modelData.label
                                        readonly property int rowMax:
                                            modelData.max
                                        // per-row brightness in %: starts
                                        // bound to the published data;
                                        // drags and external writes then
                                        // re-assign it
                                        property real pctVal:
                                            modelData.max > 0
                                            ? Math.round(modelData.cur
                                                / modelData.max * 100)
                                            : 0

                                        width: bar.panelWidth
                                            - 2 * bar.modulePad
                                        height: 62
                                        radius: 13
                                        color: Colors.bg1

                                        Rectangle { // icon circle
                                            x: 6
                                            y: (parent.height
                                                - height) / 2
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: Colors.bg2

                                            Text {
                                                anchors.horizontalCenter:
                                                    parent.horizontalCenter
                                                y: (parent.height
                                                    - height) / 2
                                                text: "\uF185" // sun
                                                font.family: "JetBrainsMono Nerd Font Propo"
                                                font.pixelSize: bar.iconPx(text)
                                                color: Colors.text
                                            }
                                        }

                                        Text { // monitor label
                                            x: 44
                                            y: 7
                                            width: parent.width - 120
                                            text: devRow.rowLabel
                                            font.family: "Google Sans Flex"
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            color: Colors.text
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Rectangle { // brightness pill
                                            id: briPill

                                            x: 44
                                            y: 32
                                            width: parent.width - 104
                                            height: 22
                                            radius: 11
                                            color: Colors.accent

                                            Text { // sun inside the fill
                                                x: 7
                                                y: (parent.height
                                                    - height) / 2
                                                text: "\uF185"
                                                font.family: "JetBrainsMono Nerd Font Propo"
                                                font.pixelSize: bar.iconPx(text)
                                                color: bar.pureBlack
                                            }
                                        }

                                        Text { // pct right of the pill
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter:
                                                briPill.verticalCenter
                                            text: devRow.pctVal + "%"
                                            font.family: "Google Sans Flex"
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            color: Colors.text
                                        }

                                        MouseArea {
                                            x: 44
                                            y: 32
                                            width: parent.width - 104
                                            height: 22
                                            cursorShape:
                                                Qt.PointingHandCursor

                                            function apply(m) {
                                                const p = Math.round(
                                                    Math.min(1,
                                                        Math.max(0,
                                                            m.x / width))
                                                    * 100);
                                                devRow.pctVal = p;
                                                bar.briRowSet(
                                                    devRow.rowDev, p);
                                            }
                                            onPressed: mouse =>
                                                apply(mouse)
                                            onPositionChanged: mouse => {
                                                if (pressed) apply(mouse);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // --- NOTIFICATION HISTORY MODULE (click a row to dismiss) ---
                // back chevron -> control center, then the full session:
                // app-initial bubble, app name in accent + timestamp on
                // the right, bold summary, 2-line body. The island height
                // wraps the visible (capped) list and re-morphs on drops
                Item {
                    anchors.fill: parent
                    visible: bar.open && bar.mode === "notifHistory"

                    Column {
                        id: notifHistCol

                        x: bar.modulePad
                        y: bar.modulePad
                        width: bar.panelWidth - 2 * bar.modulePad
                        spacing: 14

                        Item { // title row: back chevron + centered label
                            width: parent.width
                            height: 34

                            Text { // back chevron
                                anchors.verticalCenter: parent.verticalCenter
                                x: 0
                                text: "\uF104" // chevron-left
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 12
                                color: Colors.text

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.openIsland("control")
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: (parent.width - width) / 2
                                text: "Notifications"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 16
                                font.weight: Font.Medium
                                color: Colors.text
                            }

                            Text { // wipe the session history
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                text: bar.notifHistory.length === 0 ? ""
                                    : "Clear all"
                                font.family: "Google Sans Flex"
                                font.pixelSize: 11
                                color: Colors.textAlt

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: bar.clearNotifs()
                                }
                            }
                        }

                        Flickable { // scroll once the session passes the cap
                            width: parent.width
                            // explicit: a Flickable does not track a lone
                            // Column child (same as the sound module's
                            // lists), so contentHeight stays 0 otherwise
                            contentHeight: histList.height
                            height: Math.min(contentHeight,
                                bar.notifHistListCap)
                            // expose the visible height to the wrapping
                            // column: a Flickable's own implicitHeight
                            // is 0, so the island would stay header-only
                            implicitHeight: height
                            clip: contentHeight > height

                            Column {
                                id: histList
                                spacing: 14
                                width: parent.width

                                Text { // empty state
                                    visible: bar.notifHistory.length === 0
                                    x: 4
                                    text: "No notifications"
                                    font.family: "Google Sans Flex"
                                    font.pixelSize: 12
                                    color: Colors.textAlt
                                }

                                Repeater {
                                    model: bar.notifHistory

                                    Rectangle {
                                        id: histRow

                                        required property int index
                                        required property var modelData

                                        width: parent.width
                                        height: 14 + histInner.height + 14
                                        radius: 16
                                        color: Colors.bg1

                                        Rectangle { // app initial bubble
                                            x: 14
                                            y: (parent.height
                                                - height) / 2
                                            width: 34
                                            height: 34
                                            radius: 17
                                            color: Colors.bg2

                                            Text {
                                                anchors.centerIn: parent
                                                text: histRow.modelData.app
                                                    ? histRow.modelData.app[
                                                          0].toUpperCase()
                                                    : "?"
                                                font.family:
                                                    "Google Sans Flex"
                                                font.pixelSize: 14
                                                font.weight: Font.Medium
                                                color: Colors.text
                                            }
                                        }

                                        Column {
                                            id: histInner
                                            x: 62
                                            y: 14
                                            width: parent.width - 62 - 14
                                            spacing: 5

                                            Item { // app name + timestamp
                                                width: parent.width
                                                height: 16

                                                Text {
                                                    anchors.left: parent.left
                                                    text: histRow
                                                        .modelData.app
                                                    font.family:
                                                        "Google Sans Flex"
                                                    font.pixelSize: 10
                                                    color: Colors.accent
                                                }

                                                Text {
                                                    anchors.right: parent.right
                                                    text: histRow
                                                        .modelData.time
                                                    font.family:
                                                        "Google Sans Flex"
                                                    font.pixelSize: 10
                                                    color: Colors.textAlt
                                                }
                                            }

                                            Text { // summary, bold
                                                width: parent.width
                                                text: histRow.modelData.sum
                                                font.family:
                                                    "Google Sans Flex"
                                                font.pixelSize: 12
                                                font.weight: Font.Medium
                                                color: Colors.text
                                                wrapMode: Text.WordWrap
                                            }

                                            Text { // body, 2 lines max
                                                visible:
                                                    histRow.modelData.body
                                                        !== ""
                                                width: parent.width
                                                text: histRow.modelData.body
                                                font.family:
                                                    "Google Sans Flex"
                                                font.pixelSize: 11
                                                color: Colors.textAlt
                                                wrapMode: Text.WordWrap
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                            }
                                        }

                                        MouseArea { // click = dismiss
                                            anchors.fill: parent
                                            cursorShape:
                                                Qt.PointingHandCursor
                                            onClicked:
                                                bar.notifHistoryDrop(
                                                    histRow.index)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- OSD PANEL (volume / brightness morph) ---
                // NOT a separate popup: every volume or brightness
                // change made OUTSIDE the bar morphs the closed pill
                // into this with the same spring as every module and
                // folds it back after the hold. Icon + accent track +
                // percentage; pure black, Colors.qml only
                Item {
                    id: osdPanel

                    anchors.fill: parent
                    visible: bar.open && bar.mode === "osd"

                    readonly property real pct:
                        bar.osdKind === "volume"
                            ? (bar.volMuted ? 0 : bar.volPct)
                            : Math.round(bar.briVisual)

                    Text { // kind icon: speaker / sun
                        x: 14
                        y: (parent.height - height) / 2
                        text: bar.osdKind === "volume"
                            ? (bar.volMuted ? "\uF026" : "\uF028")
                            : "\uF185" // sun
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 14
                        color: Colors.text
                    }

                    Rectangle { // track
                        x: 52
                        y: (parent.height - 12) / 2
                        width: parent.width - 52 - 62
                        height: 12
                        radius: 6
                        color: Colors.bg2

                        Rectangle { // accent fill follows the value
                            width: osdPanel.pct <= 0 ? 0
                                : Math.max(parent.height,
                                    osdPanel.pct / 100 * parent.width)
                            height: parent.height
                            radius: parent.radius
                            color: Colors.accent

                            Behavior on width {
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutBack
                                }
                            }
                        }
                    }

                    Text { // percentage on the right
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.osdKind === "volume" && bar.volMuted
                            ? "Muted" : osdPanel.pct + "%"
                        font.family: "Google Sans Flex"
                        font.pixelSize: 12
                        color: Colors.text
                    }
                }

            }

        }


        // Suppress the "quickshell: config reloaded" popup on live
        // reloads (failed reloads still pop up, which is useful)
        Connections {
            target: Quickshell
            function onReloadCompleted() {
                // start the OSD probe-suppression window: the initial
                // volume/brightness parses that follow a live reload
                // (theme/wallpaper apply) must not pop the OSD
                bar.osdReloadAt = Date.now();
                Quickshell.inhibitReloadPopup();
            }
        }

        // ---------- NOTIFICATION SERVER ----------
        // Owns the freedesktop notification D-Bus name. Whenever a
        // notification arrives, the island itself morphs into the capsule
        // (bar.notifIncoming), holds it and folds back into the pill
        NotificationServer {
            id: notifServer

            keepOnReload: true
            bodySupported: true
            bodyMarkupSupported: false
            actionsSupported: false
            inlineReplySupported: false

            property string appLabel: ""
            property string title: ""
            property string bodyText: ""

            onNotification: notification => {
                // app name: where the notification comes from (desktop
                // entry when the app provides one, else the raw name);
                // title + subtitle exactly as the picture: summary bold,
                // body below. No fake placeholders
                appLabel = (notification.desktopEntry
                            || notification.appName || "");
                title = notification.summary;
                bodyText = notification.body;
                // session history (the control center card and the
                // history island list these even after the popups
                // have lingered out); critical ones live longer anyway
                bar.notifHistory = [
                    {
                        app: appLabel || "notifier",
                        sum: title,
                        body: bodyText,
                        time: Qt.formatDateTime(new Date(), "hh:mm")
                    },
                    ...bar.notifHistory
                ].slice(0, 30);
                // critical notifications linger longer
                notifExpire.interval =
                    Number(notification.urgency) === 2 ? 8000 : 5000;
                bar.notifIncoming();
            }
        }

        // Diagnostic out: debugControl writes its state snapshot here
        Process {
            id: debugOut
        }

        // IPC so a keybind can toggle the launcher:
        //   qs ipc call launcher
        IpcHandler {
            target: "pulsar"

            function launcher() {
                bar.toggleIsland("apps");
            }

            function theme() {
                bar.toggleIsland("themes");
            }

            function wallpaper() {
                bar.toggleIsland("wallpapers");
            }

            function power() {
                bar.toggleIsland("power");
            }

            function control() {
                bar.toggleIsland("control");
            }

            function sound() {
                bar.openIsland("sound");
            }

            function display() {
                bar.toggleIsland("display");
            }

            function wifi() {
                bar.toggleIsland("wifi");
            }

            function notifHistory() {
                bar.toggleIsland("notifHistory");
            }

            function clearNotifs() {
                bar.notifHistory = [];
            }

            function close() {
                if (bar.open) bar.closeIsland();
            }

            // temporary diagnostics: writes live control center state to
            // /tmp/diagnostics/dbg when called over IPC
            function debugControl() {
                const msg = "vol=" + bar.volPct
                    + "/" + (bar.volMuted ? "muted" : "unmuted")
                    + " briVisual=" + bar.briVisual.toFixed(0)
                    + "/" + bar.briMax.toFixed(0)
                    + " sysPath=" + bar.briSysPath
                    + " sinks=" + bar.sndSinks.length
                    + " sources=" + bar.sndSources.length
                    + " apps=" + bar.sndApps.length
                    + " defSink=" + bar.sinkName
                    + " defSrc=" + bar.sourceName
                    + " srcPct=" + bar.srcPct
                    + " sysCur=" + bar.briSysCur
                    + " watchTxt=" + (briWatch.path !== ""
                        ? String(briWatch.text() || "EMPTY").trim() : "nopath")
                    + " loaded=" + briWatch.loaded
                    + " ssid=" + bar.wifiSsid
                    + " wifi=" + Networking.wifiEnabled
                    + " bt=" + (Bluetooth.defaultAdapter
                        ? Bluetooth.defaultAdapter.enabled : "?")
                    + " mode=" + bar.mode + " open=" + bar.open
                    + " histN=" + bar.notifHistory.length
                    + " hist0=" + (bar.notifHistory.length
                        ? bar.notifHistory[0].sum : "-");
                debugOut.command = ["sh", "-c",
                    "mkdir -p /tmp/diagnostics; printf '%s' \""
                        + msg + "\" > /tmp/diagnostics/dbg"];
                debugOut.running = false;
                debugOut.running = true;
            }
        }
    }
}
