pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.containers
import qs.services

ShellRoot {
    id: root

    readonly property string aiAgent: Paths.home + "/.local/bin/caelestia-ai-agent"
    readonly property string aiSettings: Paths.home + "/.local/bin/caelestia-ai-settings"

    property bool open: false
    property string status: qsTr("Ready")
    property string activeModel: Quickshell.env("OPENROUTER_MODEL") || "qwen/qwen-2.5-coder-32b-instruct"
    property string customInstructions: "You are a concise AI helper embedded in a Hyprland desktop panel. Chat only. Do not claim to run commands, edit files, or inspect the system."
    property int maxContextMessages: 18
    property bool busy: false
    property bool settingsOpen: false
    property string settingsStatus: ""
    property bool settingsApiKeySet: false
    property bool settingsClearApiKey: false
    property string settingsModelText: activeModel
    property string settingsTemperatureText: "0.4"
    property string settingsContextText: "18"
    property string settingsInstructionsText: customInstructions
    property string settingsApiKeyText: ""
    property string approvedCommand: ""
    property string approvalBusyCommand: ""
    property int approvalMessageIndex: -1
    property bool scrollToEndPending: false
    property int scrollToEndPasses: 0
    property var historyView: null
    property var inputField: null

    function showPanel(): void {
        hideTimer.stop();
        open = true;
        focusInput();
    }

    function closePanel(): void {
        open = false;
    }

    function requestHide(): void {
        if (settingsOpen)
            return;
        hideTimer.restart();
    }

    function focusInput(): void {
        Qt.callLater(() => {
            if (open && !settingsOpen && inputField)
                inputField.forceActiveFocus();
        });
    }

    function openSettings(): void {
        settingsOpen = true;
        settingsStatus = qsTr("Loading settings");
        settingsProc.action = "load";
        settingsProc.exec([root.aiSettings]);
    }

    function closeSettings(): void {
        settingsOpen = false;
        settingsStatus = "";
        settingsApiKeyText = "";
        settingsClearApiKey = false;
    }

    function saveSettings(): void {
        settingsStatus = qsTr("Saving settings");
        settingsProc.action = "save";
        settingsProc.exec([root.aiSettings]);
    }

    function applySettings(settings: var): void {
        activeModel = settings.model || activeModel;
        customInstructions = settings.customInstructions || customInstructions;
        maxContextMessages = settings.maxContextMessages || maxContextMessages;
        settingsModelText = activeModel;
        settingsTemperatureText = String(settings.temperature ?? 0.4);
        settingsContextText = String(maxContextMessages);
        settingsInstructionsText = customInstructions;
        settingsApiKeyText = "";
        settingsApiKeySet = !!settings.apiKeySet;
        settingsClearApiKey = false;
    }

    function pushMessage(role: string, content: string): void {
        messages.append({
            role,
            content,
            pending: false
        });
        scheduleScrollToEnd();
    }

    function historyMaxY(): real {
        const view = historyView;
        if (!view)
            return 0;
        return Math.max(historyMinY(), historyMinY() + view.contentHeight - view.height);
    }

    function historyMinY(): real {
        const view = historyView;
        if (!view)
            return 0;
        return view.originY || 0;
    }

    function isHistoryNearBottom(threshold: real): bool {
        const view = historyView;
        if (!view)
            return true;
        return historyMaxY() - view.contentY <= threshold;
    }

    function clampHistoryScroll(): void {
        const view = historyView;
        if (!view)
            return;
        const minY = historyMinY();
        const maxY = historyMaxY();
        const clamped = root.clamp(view.contentY, minY, maxY);
        if (Math.abs(view.contentY - clamped) > 0.5)
            view.contentY = clamped;
    }

    function scheduleClampHistoryScroll(): void {
        Qt.callLater(() => root.clampHistoryScroll());
    }

    function scrollHistoryToEnd(): void {
        const view = historyView;
        if (!view)
            return;
        view.forceLayout();
        if (messages.count > 0)
            view.positionViewAtIndex(messages.count - 1, ListView.End);
        else
            view.positionViewAtEnd();
        view.positionViewAtEnd();
        view.contentY = historyMaxY();
        if (scrollToEndPasses > 0)
            scrollToEndPasses -= 1;
        scrollToEndPending = scrollToEndPasses > 0;
        if (scrollToEndPending && typeof scrollEndTimer !== "undefined")
            scrollEndTimer.restart();
    }

    function scheduleScrollToEnd(): void {
        scrollToEndPending = true;
        scrollToEndPasses = Math.max(scrollToEndPasses, 6);
        Qt.callLater(() => {
            if (root.historyView)
                root.scrollHistoryToEnd();
        });
        if (typeof scrollEndTimer !== "undefined")
            scrollEndTimer.restart();
    }

    function scheduleScrollToEndIfNearBottom(): void {
        if (isHistoryNearBottom(96))
            scheduleScrollToEnd();
        else
            scheduleClampHistoryScroll();
    }

    function requestMessages(): var {
        const out = [{
            role: "system",
            content: "You are a local AI helper panel running inside the user's Hyprland/Caelestia desktop. The local user is kensa, HOME is " + Paths.home + ", and the default working directory is " + Paths.home + ". You have access to a small local tool bridge for shell commands, text file reads, directory listings, screenshots, web search, image search, and read-only hyprctl queries. Use tools when they directly help answer the user, and prefer one focused tool call over many broad ones. Destructive commands, package operations, sudo, service changes, and write-heavy commands require an explicit user approval card before they run. If approval is required, say what the command will do and wait for the user to approve it in the panel. Screenshots and image-search results are rendered inline by the panel. Do not emit XML, DSML, raw function-call markup, or hidden control syntax; the panel will render tool results for you.\n\nUser instructions:\n" + customInstructions
        }];

        const start = Math.max(0, messages.count - maxContextMessages);
        for (let i = start; i < messages.count; i++) {
            const item = messages.get(i);
            if (!item.pending && item.role !== "error")
                out.push({
                    role: item.role,
                    content: item.content
                });
        }

        return out;
    }

    function clamp(value: real, min: real, max: real): real {
        return Math.max(min, Math.min(max, value));
    }

    function decodeEntities(text: string): string {
        return text.replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&");
    }

    function encodeEntities(text: string): string {
        return (text || "").replace(/&/g, "&amp;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&apos;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function imageSource(src: string): string {
        const value = (src || "").trim();
        if (!value)
            return "";
        if (/^(https?:|file:|qrc:)/.test(value))
            return value;
        if (value.startsWith("/"))
            return "file://" + value;
        return value;
    }

    function approveCommand(command: string, messageIndex: var): void {
        const trimmed = (command || "").trim();
        if (!trimmed || approvalBusyCommand)
            return;
        approvedCommand = trimmed;
        approvalBusyCommand = trimmed;
        approvalMessageIndex = typeof messageIndex === "number" ? messageIndex : -1;
        status = qsTr("Running approved command");
        approvedTimeoutTimer.restart();
        approvedProc.exec([root.aiAgent, "--approved-shell-command", trimmed]);
    }

    function rejectCommand(command: string, messageIndex: var): void {
        const trimmed = (command || "").trim();
        const content = root.toolResultCard(qsTr("Command approval declined"), trimmed, qsTr("The command was not run."), "declined");
        if (typeof messageIndex === "number" && messageIndex >= 0 && messageIndex < messages.count) {
            messages.set(messageIndex, {
                role: "assistant",
                content,
                pending: false
            });
            scheduleScrollToEnd();
        } else {
            pushMessage("assistant", content);
        }
    }

    function approvalCard(command: string, output: string): string {
        return toolResultCard(qsTr("Command needs approval"), command, output, "approval");
    }

    function toolResultCard(title: string, command: string, output: string, cardStatus: string): string {
        return `<|CAELESTIA|tool_result title="${encodeEntities(title)}" status="${encodeEntities(cardStatus)}"><|CAELESTIA|command>${encodeEntities(command)}</|CAELESTIA|command><|CAELESTIA|output>${encodeEntities(output)}</|CAELESTIA|output></|CAELESTIA|tool_result>`;
    }

    function normaliseToolMarkup(text: string): string {
        return text.replace(/<\s*\|\s*DSML\s*\|\s*/g, "<|DSML|")
            .replace(/<\/\s*\|\s*DSML\s*\|\s*/g, "</|DSML|");
    }

    function parseCaelestiaToolResults(parts: var, text: string): string {
        const resultRe = /<\|CAELESTIA\|tool_result\s+([^>]*)>([\s\S]*?)<\/\|CAELESTIA\|tool_result>/g;
        let cleaned = "";
        let last = 0;
        let match;

        function attr(attrs: string, name: string, fallback: string): string {
            const re = new RegExp(name + "=\"([^\"]*)\"");
            const m = re.exec(attrs);
            return m ? root.decodeEntities(m[1]) : fallback;
        }

        while ((match = resultRe.exec(text)) !== null) {
            cleaned += text.slice(last, match.index);
            const attrs = match[1];
            const body = match[2];
            const commandMatch = /<\|CAELESTIA\|command>([\s\S]*?)<\/\|CAELESTIA\|command>/.exec(body);
            const outputMatch = /<\|CAELESTIA\|output>([\s\S]*?)<\/\|CAELESTIA\|output>/.exec(body);
            const images = [];
            const imageRe = /<\|CAELESTIA\|image\s+([^>]*)><\/\|CAELESTIA\|image>/g;
            let imageMatch;
            while ((imageMatch = imageRe.exec(body)) !== null) {
                images.push({
                    src: attr(imageMatch[1], "src", ""),
                    title: attr(imageMatch[1], "title", "")
                });
            }
            parts.push({
                type: "result",
                name: "tool",
                description: attr(attrs, "title", "Tool result"),
                status: attr(attrs, "status", "ok"),
                command: commandMatch ? root.decodeEntities(commandMatch[1].trim()) : "",
                output: outputMatch ? root.decodeEntities(outputMatch[1].trim()) : "",
                images
            });
            last = resultRe.lastIndex;
        }

        cleaned += text.slice(last);
        return cleaned;
    }

    function looksLikeCommand(line: string): bool {
        const s = line.trim();
        if (!s || s.length > 240)
            return false;
        if (s.startsWith("$ "))
            return true;
        if (/[;&|]|\$\(|`|>|<|2>&1/.test(s))
            return true;
        return /^(sudo|doas|env|cd|ls|cat|grep|rg|find|sed|awk|git|gh|npm|pnpm|yarn|bun|node|python|python3|pip|pipx|cargo|go|make|cmake|meson|ninja|systemctl|journalctl|hyprctl|qs|caelestia|neofetch|fastfetch|btop|htop|top|df|du|free|uname|echo|curl|wget)\b/.test(s);
    }

    function appendTextAndCommandParts(parts: var, text: string): void {
        const source = text.trim();
        if (!source)
            return;
        parts.push({
            type: "text",
            text: source
        });
    }

    function messageParts(text: string): var {
        const parts = [];
        const source = normaliseToolMarkup(parseCaelestiaToolResults(parts, text));
        const tail = source
            .replace(/<\/?\|DSML\|tool_calls>/g, "")
            .replace(/<\|DSML\|invoke\b[\s\S]*?<\/\|DSML\|invoke>/g, "")
            .trim();
        appendTextAndCommandParts(parts, tail);

        if (parts.length === 0)
            parts.push({
                type: "text",
                text
            });

        return parts;
    }

    function send(text: string): bool {
        const prompt = text.trim();
        if (!prompt || busy)
            return false;

        pushMessage("user", prompt);
        messages.append({
            role: "assistant",
            content: "Thinking...",
            pending: true
        });
        scheduleScrollToEnd();

        busy = true;
        status = qsTr("Thinking");
        requestTimeoutTimer.restart();
        requestProc.exec([root.aiAgent]);
        return true;
    }

    function findPendingMessage(): int {
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).pending)
                return i;
        }
        return -1;
    }

    function failPendingRequest(message: string): void {
        requestTimeoutTimer.stop();
        if (requestProc.running)
            requestProc.running = false;
        busy = false;
        const pendingIndex = findPendingMessage();
        if (pendingIndex >= 0) {
            messages.set(pendingIndex, {
                role: "error",
                content: message,
                pending: false
            });
        } else {
            pushMessage("error", message);
        }
        status = qsTr("Needs attention");
        scheduleScrollToEnd();
    }

    function completeRequest(exitCode: int): void {
        requestTimeoutTimer.stop();
        busy = false;

        const pendingIndex = findPendingMessage();

        let response = {};
        try {
            response = JSON.parse(stdout.text || "{}");
        } catch (error) {
            response = {
                ok: false,
                error: "Assistant response was not valid JSON."
            };
        }

        const ok = exitCode === 0 && response.ok;
        const content = ok ? response.content : (response.error || stderr.text || "OpenRouter request failed.");
        if (pendingIndex >= 0) {
            messages.set(pendingIndex, {
                role: ok ? "assistant" : "error",
                content,
                pending: false
            });
        } else {
            pushMessage(ok ? "assistant" : "error", content);
        }

        activeModel = response.model || activeModel;
        status = ok ? qsTr("OpenRouter connected") : qsTr("Needs attention");
        scheduleScrollToEnd();
    }

    function completeApprovedCommand(exitCode: int): void {
        approvedTimeoutTimer.stop();
        let response = {};
        try {
            response = JSON.parse(approvedStdout.text || "{}");
        } catch (error) {
            response = {
                ok: false,
                error: "Approved command response was not valid JSON."
            };
        }

        const ok = exitCode === 0 && response.ok;
        const role = ok ? "assistant" : "error";
        const content = ok ? response.content : (response.error || approvedStderr.text || "Approved command failed.");
        if (approvalMessageIndex >= 0 && approvalMessageIndex < messages.count) {
            messages.set(approvalMessageIndex, {
                role,
                content,
                pending: false
            });
            scheduleScrollToEnd();
        } else {
            pushMessage(role, content);
        }
        approvalBusyCommand = "";
        approvedCommand = "";
        approvalMessageIndex = -1;
        status = ok ? qsTr("Command complete") : qsTr("Needs attention");
    }

    function failApprovedCommand(message: string): void {
        approvedTimeoutTimer.stop();
        if (approvedProc.running)
            approvedProc.running = false;
        const command = approvedCommand || approvalBusyCommand;
        const content = root.toolResultCard(qsTr("Approved command failed"), command, message, "error");
        if (approvalMessageIndex >= 0 && approvalMessageIndex < messages.count) {
            messages.set(approvalMessageIndex, {
                role: "error",
                content,
                pending: false
            });
            scheduleScrollToEnd();
        } else {
            pushMessage("error", content);
        }
        approvalBusyCommand = "";
        approvedCommand = "";
        approvalMessageIndex = -1;
        status = qsTr("Needs attention");
    }

    ListModel {
        id: messages

        ListElement {
            role: "assistant"
            content: "Hey. I am wired for chat through OpenRouter. Use the gear to set your key, model, and instructions."
            pending: false
        }
    }

    IpcHandler {
        function submit(text: string): bool {
            root.showPanel();
            return root.send(text);
        }

        function messagesJson(): string {
            const out = [];
            for (let i = 0; i < messages.count; i++) {
                const item = messages.get(i);
                out.push({
                    role: item.role,
                    content: item.content,
                    pending: item.pending
                });
            }
            return JSON.stringify(out);
        }

        function approveLastApproval(): bool {
            for (let i = messages.count - 1; i >= 0; i--) {
                const parts = root.messageParts(messages.get(i).content);
                for (const part of parts) {
                    if (part.status === "approval" && part.command) {
                        root.approveCommand(part.command, i);
                        return true;
                    }
                }
            }
            return false;
        }

        function declineLastApproval(): bool {
            for (let i = messages.count - 1; i >= 0; i--) {
                const parts = root.messageParts(messages.get(i).content);
                for (const part of parts) {
                    if (part.status === "approval" && part.command) {
                        root.rejectCommand(part.command, i);
                        return true;
                    }
                }
            }
            return false;
        }

        function testApproval(command: string): void {
            root.pushMessage("assistant", root.approvalCard(command, "Approval required: test approval card."));
        }

        function approve(command: string): void {
            root.approveCommand(command, -1);
        }

        function testApproveInline(command: string): void {
            root.pushMessage("assistant", root.approvalCard(command, "Approval required: test approval card."));
            root.approveCommand(command, messages.count - 1);
        }

        function testImageCard(): void {
            root.pushMessage("user", "image card scroll test");
            root.pushMessage("assistant", "<|CAELESTIA|tool_result title=\"Image search results\" status=\"ok\"><|CAELESTIA|command>dolphin</|CAELESTIA|command><|CAELESTIA|output>- Dolphin photo result\n  https://pixnio.com/free-images/2025/01/08/2025-01-08-19-54-46-1536x1536.jpeg</|CAELESTIA|output><|CAELESTIA|image src=\"https://pixnio.com/free-images/2025/01/08/2025-01-08-19-54-46-1536x1536.jpeg\" title=\"Dolphin photo result\"></|CAELESTIA|image></|CAELESTIA|tool_result>");
        }

        function testLongChat(): void {
            for (let i = 1; i <= 10; i++)
                root.pushMessage(i % 2 === 0 ? "assistant" : "user", "Scroll test message " + i + "\\nThis verifies the chat follows new responses.");
        }

        function openPanel(): void {
            root.showPanel();
        }

        function clear(): void {
            while (messages.count > 1)
                messages.remove(1);
            root.busy = false;
            root.status = qsTr("OpenRouter connected");
            root.scheduleScrollToEnd();
        }

        function scrollNow(): void {
            root.scheduleScrollToEnd();
        }

        function scrollBy(delta: real): void {
            const view = root.historyView;
            if (!view)
                return;
            view.contentY = root.clamp(view.contentY + delta, root.historyMinY(), root.historyMaxY());
        }

        function scrollDebug(): string {
            const view = root.historyView;
            return JSON.stringify({
                count: messages.count,
                contentY: view ? view.contentY : -1,
                originY: view ? view.originY : -1,
                contentHeight: view ? view.contentHeight : -1,
                height: view ? view.height : -1,
                minY: root.historyMinY(),
                maxY: root.historyMaxY(),
                pending: root.scrollToEndPending,
                passes: root.scrollToEndPasses
            });
        }

        function reset(): void {
            root.failPendingRequest("Request cancelled. The panel has been unlocked.");
            if (root.approvalBusyCommand)
                root.failApprovedCommand("Approved command cancelled. The panel has been unlocked.");
        }

        target: "caelestiaAi"
    }

    Process {
        id: requestProc

        stdinEnabled: true
        stdout: StdioCollector {
            id: stdout
        }
        stderr: StdioCollector {
            id: stderr
        }
        onStarted: {
            write(JSON.stringify({
                model: root.activeModel,
                messages: root.requestMessages()
            }) + "\n");
        }
        onExited: exitCode => root.completeRequest(exitCode)
    }

    Process {
        id: approvedProc

        stdout: StdioCollector {
            id: approvedStdout
        }
        stderr: StdioCollector {
            id: approvedStderr
        }
        onExited: exitCode => root.completeApprovedCommand(exitCode)
    }

    Timer {
        id: approvedTimeoutTimer

        interval: 120000
        repeat: false
        onTriggered: root.failApprovedCommand(qsTr("Approved command timed out. The panel has been unlocked so you can try again."))
    }

    Process {
        id: settingsProc

        property string action: "load"

        stdinEnabled: true
        stdout: StdioCollector {
            id: settingsStdout
        }
        stderr: StdioCollector {
            id: settingsStderr
        }
        onStarted: {
            const payload = action === "save" ? {
                action,
                settings: {
                    model: root.settingsModelText.trim(),
                    temperature: root.settingsTemperatureText.trim(),
                    maxContextMessages: root.settingsContextText.trim(),
                    customInstructions: root.settingsInstructionsText.trim(),
                    apiKey: root.settingsApiKeyText.trim(),
                    clearApiKey: root.settingsClearApiKey
                }
            } : {
                action
            };
            write(JSON.stringify(payload) + "\n");
        }
        onExited: exitCode => {
            let response = {};
            try {
                response = JSON.parse(settingsStdout.text || "{}");
            } catch (error) {
                response = {
                    ok: false,
                    error: "Settings response was not valid JSON."
                };
            }

            if (exitCode === 0 && response.ok) {
                root.applySettings(response.settings || {});
                root.settingsStatus = action === "save" ? qsTr("Saved") : qsTr("Settings loaded");
                if (action === "save")
                    root.closeSettings();
            } else {
                root.settingsStatus = response.error || settingsStderr.text || qsTr("Settings failed");
            }
        }
    }

    Timer {
        id: hideTimer

        interval: 140
        onTriggered: root.open = false
    }

    Timer {
        id: scrollEndTimer

        interval: 60
        repeat: false
        onTriggered: root.scrollHistoryToEnd()
    }

    Timer {
        id: requestTimeoutTimer

        interval: 120000
        repeat: false
        onTriggered: root.failPendingRequest(qsTr("Request timed out. The panel has been unlocked so you can try again."))
    }

    Component.onCompleted: {
        settingsProc.action = "load";
        settingsProc.exec([root.aiSettings]);
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            contentItem.Config.screen: screen.name
            contentItem.Tokens.screen: screen.name
            visible: true
            color: "transparent"
            implicitWidth: screen.width
            implicitHeight: screen.height
            readonly property real panelWidth: Math.min(460, Math.max(360, screen.width * 0.28))
            readonly property real panelHeight: Math.min(640, Math.max(420, screen.height * 0.62))
            readonly property real borderThickness: contentItem.Config.border.thickness
            readonly property real borderRounding: contentItem.Config.border.rounding
            readonly property real borderSmoothing: contentItem.Config.border.smoothing
            readonly property real triggerDepth: 6
            readonly property real triggerLength: Math.min(panelWidth, Math.max(180, panelWidth * 0.58))
            property real offsetScale: root.open ? 0 : 1

            function showPanel(): void {
                root.showPanel();
            }

            function requestHide(): void {
                if (!hasPointer())
                    root.closePanel();
            }

            function hasPointer(): bool {
                return topHotEdge.containsMouse || rightHotEdge.containsMouse || panelHover.hovered || root.settingsOpen;
            }

            WlrLayershell.namespace: "caelestia-ai"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            mask: Region {
                Region {
                    x: win.width - win.triggerLength
                    y: 0
                    width: win.triggerLength
                    height: win.triggerDepth
                }

                Region {
                    x: win.width - win.triggerDepth
                    y: 0
                    width: win.triggerDepth
                    height: win.triggerLength
                }

                Region {
                    x: panel.x - win.borderRounding
                    y: 0
                    width: root.open ? panel.width + win.borderRounding : 0
                    height: root.open ? panel.height + win.borderRounding : 0
                }
            }

            Behavior on offsetScale {
                Anim {}
            }

            Item {
                anchors.fill: parent
                opacity: root.open ? Colours.tPalette.m3surface.a : 0
                layer.enabled: opacity > 0
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    blurMax: 15
                    shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                BlobGroup {
                    id: blobGroup

                    color: Colours.tPalette.m3surface
                    smoothing: win.borderSmoothing
                }

                BlobInvertedRect {
                    anchors.fill: parent
                    anchors.margins: -50
                    group: blobGroup
                    radius: win.borderRounding
                    borderLeft: -anchors.margins
                    borderRight: win.borderThickness - anchors.margins
                    borderTop: win.borderThickness - anchors.margins
                    borderBottom: win.borderThickness - anchors.margins
                }

                BlobRect {
                    x: panel.x
                    y: panel.y
                    implicitWidth: panel.width
                    implicitHeight: panel.height
                    group: blobGroup
                    radius: Tokens.rounding.extraLarge
                    deformScale: (0.12 * Config.appearance.deformScale) / 10000
                }
            }

            MouseArea {
                id: topHotEdge

                anchors.top: parent.top
                anchors.right: parent.right
                width: win.triggerLength
                height: win.triggerDepth
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: win.showPanel()
            }

            MouseArea {
                id: rightHotEdge

                anchors.top: parent.top
                anchors.right: parent.right
                width: win.triggerDepth
                height: win.triggerLength
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: win.showPanel()
            }

            StyledRect {
                id: panel

                width: win.panelWidth
                height: win.panelHeight
                x: win.width - width + (width + 5) * win.offsetScale
                y: 0
                color: "transparent"
                radius: Tokens.rounding.extraLarge
                opacity: 1 - win.offsetScale

                HoverHandler {
                    id: panelHover

                    onHoveredChanged: {
                        if (hovered)
                            win.showPanel();
                        else
                            win.requestHide();
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        MaterialIcon {
                            text: "auto_awesome"
                            fill: 1
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.medium
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                text: qsTr("Assistant")
                                font: Tokens.font.title.medium
                                color: Colours.palette.m3onSurface
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: `${root.status} - ${root.activeModel}`
                                font: Tokens.font.body.small
                                color: Colours.palette.m3outline
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        LoadingIndicator {
                            visible: root.busy
                            animated: root.busy
                            implicitSize: 28
                            color: Colours.palette.m3primary
                        }

                        IconButton {
                            icon: "settings"
                            type: IconButton.Text
                            onClicked: root.openSettings()
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            onClicked: root.closePanel()
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
                    }

                    ListView {
                        id: history

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Tokens.spacing.small
                        clip: true
                        model: messages
                        bottomMargin: Tokens.spacing.medium
                        boundsBehavior: Flickable.StopAtBounds
                        boundsMovement: Flickable.StopAtBounds
                        flickDeceleration: 3200
                        maximumFlickVelocity: 18000
                        Component.onCompleted: {
                            root.historyView = history;
                            root.scheduleScrollToEnd();
                        }
                        Component.onDestruction: {
                            if (root.historyView === history)
                                root.historyView = null;
                        }
                        onMovementEnded: root.clampHistoryScroll()
                        onFlickEnded: root.clampHistoryScroll()
                        onContentHeightChanged: {
                            if (root.scrollToEndPending)
                                root.scheduleScrollToEnd();
                            else
                                root.scheduleClampHistoryScroll();
                        }
                        onHeightChanged: {
                            if (root.scrollToEndPending)
                                root.scheduleScrollToEnd();
                            else
                                root.scheduleClampHistoryScroll();
                        }

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const minY = root.historyMinY();
                                const maxY = root.historyMaxY();
                                const rawDelta = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 1.8 : event.angleDelta.y;
                                history.contentY = root.clamp(history.contentY - rawDelta, minY, maxY);
                                event.accepted = true;
                            }
                        }

                        ScrollBar.vertical: StyledScrollBar {
                            flickable: history
                        }

                        delegate: Item {
                            id: row

                            required property string role
                            required property string content
                            required property bool pending
                            required property int index

                            width: ListView.view.width
                            implicitHeight: bubble.implicitHeight

                            StyledRect {
                                id: bubble

                                readonly property bool fromUser: row.role === "user"
                                readonly property bool isError: row.role === "error"
                                readonly property var parts: root.messageParts(row.content)

                                anchors.right: fromUser ? parent.right : undefined
                                anchors.left: fromUser ? undefined : parent.left
                                width: parent.width * 0.88
                                implicitHeight: messageContent.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.large
                                color: isError ? Colours.palette.m3errorContainer : fromUser ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHigh, 3)
                                border.width: 1
                                border.color: Qt.alpha(isError ? Colours.palette.m3error : fromUser ? Colours.palette.m3primary : Colours.palette.m3outline, 0.28)

                                ColumnLayout {
                                    id: messageContent

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.padding.medium
                                    spacing: Tokens.spacing.small

                                    Repeater {
                                        model: bubble.parts

                                        Loader {
                                            required property var modelData
                                            property var part: modelData

                                            Layout.fillWidth: true
                                            sourceComponent: part.type === "tool" || part.type === "result" ? toolPart : textPart

                                            Component {
                                                id: textPart

                                                StyledText {
                                                    text: part.text
                                                    textFormat: /[`*_#\[\]\n]/.test(part.text) ? Text.MarkdownText : Text.PlainText
                                                    wrapMode: Text.Wrap
                                                    color: bubble.isError ? Colours.palette.m3onErrorContainer : bubble.fromUser ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                                                    font: Tokens.font.body.medium
                                                }
                                            }

                                            Component {
                                                id: toolPart

                                                StyledRect {
                                                    Layout.fillWidth: true
                                                    implicitHeight: toolLayout.implicitHeight + Tokens.padding.medium * 2
                                                    radius: Tokens.rounding.medium
                                                    color: Colours.layer(Colours.palette.m3surfaceContainerLowest, 3)
                                                    border.width: 1
                                                    border.color: Qt.alpha(Colours.palette.m3primary, 0.38)

                                                    ColumnLayout {
                                                        id: toolLayout

                                                        anchors.fill: parent
                                                        anchors.margins: Tokens.padding.medium
                                                        spacing: Tokens.spacing.small

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Tokens.spacing.small

                                                            MaterialIcon {
                                                                text: "terminal"
                                                                fill: 1
                                                                color: Colours.palette.m3primary
                                                                fontStyle: Tokens.font.icon.small
                                                            }

                                                            StyledText {
                                                                Layout.fillWidth: true
                                                                text: part.description || qsTr("Suggested terminal command")
                                                                color: Colours.palette.m3onSurface
                                                                font: Tokens.font.body.small
                                                                elide: Text.ElideRight
                                                                maximumLineCount: 1
                                                            }
                                                        }

                                                        StyledRect {
                                                            visible: (part.command || "").length > 0
                                                            Layout.fillWidth: true
                                                            implicitHeight: commandText.paintedHeight + Tokens.padding.small * 2
                                                            radius: Tokens.rounding.small
                                                            color: Qt.alpha(Colours.palette.m3shadow, 0.28)

                                                            Text {
                                                                id: commandText

                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.top: parent.top
                                                                anchors.margins: Tokens.padding.small
                                                                text: part.command || ""
                                                                color: Colours.palette.m3onSurface
                                                                font.family: "monospace"
                                                                font.pointSize: Tokens.font.body.small.pointSize
                                                                wrapMode: Text.Wrap
                                                                textFormat: Text.PlainText
                                                                renderType: Text.NativeRendering
                                                            }
                                                        }

                                                        RowLayout {
                                                            visible: part && part.status === "approval"
                                                            Layout.fillWidth: true
                                                            spacing: Tokens.spacing.small

                                                            TextButton {
                                                                Layout.fillWidth: true
                                                                enabled: root.approvalBusyCommand.length === 0
                                                                text: part && root.approvalBusyCommand === part.command ? qsTr("Running") : qsTr("Approve")
                                                                type: TextButton.Filled
                                                                onClicked: {
                                                                    if (part)
                                                                        root.approveCommand(part.command, row.index);
                                                                }
                                                            }

                                                            TextButton {
                                                                Layout.fillWidth: true
                                                                enabled: root.approvalBusyCommand.length === 0
                                                                text: qsTr("Decline")
                                                                type: TextButton.Text
                                                                onClicked: {
                                                                    if (part)
                                                                        root.rejectCommand(part.command, row.index);
                                                                }
                                                            }
                                                        }

                                                        StyledRect {
                                                            visible: part.type === "result" && (part.output || "").length > 0
                                                            Layout.fillWidth: true
                                                            implicitHeight: outputText.paintedHeight + Tokens.padding.small * 2
                                                            radius: Tokens.rounding.small
                                                            color: Qt.alpha(Colours.palette.m3shadow, 0.2)
                                                            border.width: part.status === "ok" ? 0 : 1
                                                            border.color: part.status === "blocked" || part.status === "approval" || part.status === "declined" ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3outline, 0.4)

                                                            Text {
                                                                id: outputText

                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.top: parent.top
                                                                anchors.margins: Tokens.padding.small
                                                                text: part.output || ""
                                                                color: part.status === "blocked" || part.status === "approval" || part.status === "declined" ? Colours.palette.m3error : Colours.palette.m3onSurface
                                                                font.family: "monospace"
                                                                font.pointSize: Tokens.font.body.small.pointSize
                                                                wrapMode: Text.Wrap
                                                                textFormat: Text.PlainText
                                                                renderType: Text.NativeRendering
                                                            }
                                                        }

                                                        Repeater {
                                                            model: part.images || []

                                                            ColumnLayout {
                                                                required property var modelData

                                                                Layout.fillWidth: true
                                                                spacing: Tokens.spacing.small

                                                                StyledRect {
                                                                    Layout.fillWidth: true
                                                                    Layout.preferredHeight: 150
                                                                    radius: Tokens.rounding.small
                                                                    color: Qt.alpha(Colours.palette.m3shadow, 0.2)
                                                                    clip: true

                                                                    Image {
                                                                        id: previewImage

                                                                        anchors.fill: parent
                                                                        anchors.margins: Tokens.padding.small
                                                                        source: root.imageSource(modelData.src)
                                                                        asynchronous: true
                                                                        cache: true
                                                                        fillMode: Image.PreserveAspectFit
                                                                        onStatusChanged: root.scheduleScrollToEndIfNearBottom()
                                                                    }

                                                                    StyledText {
                                                                        anchors.centerIn: parent
                                                                        width: parent.width - Tokens.padding.large * 2
                                                                        visible: previewImage.status === Image.Loading || previewImage.status === Image.Error
                                                                        text: previewImage.status === Image.Error ? qsTr("Image preview unavailable") : qsTr("Loading image")
                                                                        color: Colours.palette.m3outline
                                                                        font: Tokens.font.body.small
                                                                        horizontalAlignment: Text.AlignHCenter
                                                                        wrapMode: Text.Wrap
                                                                    }
                                                                }

                                                                StyledText {
                                                                    visible: (modelData.title || "").length > 0
                                                                    Layout.fillWidth: true
                                                                    text: modelData.title || ""
                                                                    color: Colours.palette.m3outline
                                                                    font: Tokens.font.body.small
                                                                    wrapMode: Text.Wrap
                                                                    maximumLineCount: 2
                                                                    elide: Text.ElideRight
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: inputRow.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.large
                        color: Colours.layer(Colours.palette.m3surfaceContainer, 3)
                        border.width: 1
                        border.color: input.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.32)

                        RowLayout {
                            id: inputRow

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            TextField {
                                id: input

                                Layout.fillWidth: true
                                enabled: !root.busy
                                placeholderText: root.busy ? qsTr("Waiting for OpenRouter") : qsTr("Ask something")
                                color: Colours.palette.m3onSurface
                                placeholderTextColor: Colours.palette.m3outline
                                selectedTextColor: Colours.palette.m3onPrimary
                                selectionColor: Colours.palette.m3primary
                                font: Tokens.font.body.medium
                                background: Item {}
                                renderType: Text.NativeRendering
                                onAccepted: {
                                    if (root.send(text))
                                        text = "";
                                }
                                Keys.onEnterPressed: {
                                    if (root.send(text))
                                        text = "";
                                }
                                Component.onCompleted: root.inputField = input
                                Component.onDestruction: {
                                    if (root.inputField === input)
                                        root.inputField = null;
                                }
                            }

                            IconButton {
                                enabled: input.text.trim().length > 0 && !root.busy
                                icon: "arrow_upward"
                                type: IconButton.Filled
                                onClicked: {
                                    if (root.send(input.text))
                                        input.text = "";
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    id: settingsSheet

                    anchors.fill: parent
                    visible: root.settingsOpen
                    z: 20
                    radius: Tokens.rounding.extraLarge
                    color: Colours.layer(Colours.palette.m3surfaceContainerLow, 2)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3outline, 0.32)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "settings"
                                fill: 1
                                color: Colours.palette.m3primary
                                fontStyle: Tokens.font.icon.medium
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    text: qsTr("AI Settings")
                                    font: Tokens.font.title.medium
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.settingsStatus || (root.settingsApiKeySet ? qsTr("OpenRouter key saved") : qsTr("OpenRouter key missing"))
                                    font: Tokens.font.body.small
                                    color: root.settingsApiKeySet ? Colours.palette.m3outline : Colours.palette.m3error
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            IconButton {
                                icon: "close"
                                type: IconButton.Text
                                onClicked: root.closeSettings()
                            }
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Qt.alpha(Colours.palette.m3outlineVariant, 0.8)
                        }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ColumnLayout {
                                width: settingsSheet.width - Tokens.padding.large * 2
                                spacing: Tokens.spacing.medium

                                StyledText {
                                    text: qsTr("Provider")
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3outline
                                }

                                SettingsField {
                                    id: settingsModel

                                    Layout.fillWidth: true
                                    label: qsTr("Model")
                                    placeholder: "qwen/qwen-2.5-coder-32b-instruct"
                                    text: root.settingsModelText
                                    onTextChanged: root.settingsModelText = text
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.medium

                                    SettingsField {
                                        id: settingsTemperature

                                        Layout.fillWidth: true
                                        label: qsTr("Temperature")
                                        placeholder: "0.4"
                                        text: root.settingsTemperatureText
                                        onTextChanged: root.settingsTemperatureText = text
                                    }

                                    SettingsField {
                                        id: settingsContext

                                        Layout.fillWidth: true
                                        label: qsTr("Context turns")
                                        placeholder: "18"
                                        text: root.settingsContextText
                                        onTextChanged: root.settingsContextText = text
                                    }
                                }

                                StyledText {
                                    text: qsTr("Credentials")
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3outline
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacing.extraSmall

                                    StyledText {
                                        text: root.settingsApiKeySet ? qsTr("OpenRouter API key saved") : qsTr("OpenRouter API key")
                                        font: Tokens.font.body.small
                                        color: root.settingsApiKeySet ? Colours.palette.m3primary : Colours.palette.m3outline
                                    }

                                    StyledRect {
                                        Layout.fillWidth: true
                                        implicitHeight: settingsApiKey.implicitHeight + Tokens.padding.medium
                                        radius: Tokens.rounding.medium
                                        color: Colours.layer(Colours.palette.m3surfaceContainer, 3)
                                        border.width: 1
                                        border.color: settingsApiKey.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.32)

                                        TextField {
                                            id: settingsApiKey

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.margins: Tokens.padding.medium
                                            echoMode: TextInput.Password
                                            text: root.settingsApiKeyText
                                            placeholderText: root.settingsApiKeySet ? qsTr("Leave blank to keep saved key") : qsTr("sk-or-v1-...")
                                            color: Colours.palette.m3onSurface
                                            placeholderTextColor: Colours.palette.m3outline
                                            selectedTextColor: Colours.palette.m3onPrimary
                                            selectionColor: Colours.palette.m3primary
                                            font: Tokens.font.body.medium
                                            background: Item {}
                                            renderType: Text.NativeRendering
                                            onTextEdited: {
                                                root.settingsApiKeyText = text;
                                                root.settingsClearApiKey = false;
                                            }
                                        }
                                    }

                                    TextButton {
                                        text: qsTr("Clear saved key")
                                        enabled: root.settingsApiKeySet
                                        type: TextButton.Text
                                        onClicked: {
                                            root.settingsClearApiKey = true;
                                            root.settingsApiKeyText = "";
                                            root.settingsStatus = qsTr("Key will be cleared on save");
                                        }
                                    }
                                }

                                StyledText {
                                    text: qsTr("Instructions")
                                    font: Tokens.font.label.medium
                                    color: Colours.palette.m3outline
                                }

                                StyledRect {
                                    Layout.fillWidth: true
                                    implicitHeight: 170
                                    radius: Tokens.rounding.medium
                                    color: Colours.layer(Colours.palette.m3surfaceContainer, 3)
                                    border.width: 1
                                    border.color: settingsInstructions.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.32)

                                    TextArea {
                                        id: settingsInstructions

                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.medium
                                        wrapMode: TextEdit.Wrap
                                        text: root.settingsInstructionsText
                                        placeholderText: qsTr("How should the assistant behave?")
                                        color: Colours.palette.m3onSurface
                                        placeholderTextColor: Colours.palette.m3outline
                                        selectedTextColor: Colours.palette.m3onPrimary
                                        selectionColor: Colours.palette.m3primary
                                        font: Tokens.font.body.medium
                                        background: Item {}
                                        renderType: Text.NativeRendering
                                        onTextChanged: root.settingsInstructionsText = text
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("Risky shell commands require explicit approval in chat. Screenshots and image search results render inline.")
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3outline
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            TextButton {
                                Layout.fillWidth: true
                                text: qsTr("Cancel")
                                type: TextButton.Text
                                onClicked: root.closeSettings()
                            }

                            TextButton {
                                Layout.fillWidth: true
                                text: qsTr("Save")
                                type: TextButton.Filled
                                onClicked: root.saveSettings()
                            }
                        }
                    }
                }
            }
        }
    }

    component SettingsField: ColumnLayout {
        property alias text: field.text
        property string label
        property string placeholder

        spacing: Tokens.spacing.extraSmall

        StyledText {
            text: parent.label
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: field.implicitHeight + Tokens.padding.medium
            radius: Tokens.rounding.medium
            color: Colours.layer(Colours.palette.m3surfaceContainer, 3)
            border.width: 1
            border.color: field.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outline, 0.32)

            TextField {
                id: field

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                placeholderText: placeholder
                color: Colours.palette.m3onSurface
                placeholderTextColor: Colours.palette.m3outline
                selectedTextColor: Colours.palette.m3onPrimary
                selectionColor: Colours.palette.m3primary
                font: Tokens.font.body.medium
                background: Item {}
                renderType: Text.NativeRendering
            }
        }
    }
}
