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

    function showPanel(): void {
        hideTimer.stop();
        open = true;
    }

    function closePanel(): void {
        open = false;
    }

    function requestHide(): void {
        if (settingsOpen)
            return;
        hideTimer.restart();
    }

    function openSettings(): void {
        settingsOpen = true;
        settingsStatus = qsTr("Loading settings");
        settingsProc.action = "load";
        settingsProc.exec(["/home/kensa/.local/bin/caelestia-ai-settings"]);
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
        settingsProc.exec(["/home/kensa/.local/bin/caelestia-ai-settings"]);
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
        Qt.callLater(() => history.positionViewAtEnd());
    }

    function requestMessages(): var {
        const out = [{
            role: "system",
            content: "You are a local AI helper panel running inside the user's Hyprland/Caelestia desktop. The local user is kensa, HOME is /home/kensa, and the default working directory is /home/kensa. You have access to a small local tool bridge for non-destructive shell commands, text file reads, directory listings, screenshots, web search, and read-only hyprctl queries. Use tools when they directly help answer the user, and prefer one focused tool call over many broad ones. Destructive commands, package installation/removal, sudo, service changes, and filesystem writes are blocked unless an approval flow is added later. If a tool is blocked, explain that plainly and suggest the next safe step. Summarize tool output clearly after it runs. Do not emit XML, DSML, raw function-call markup, or hidden control syntax; the panel will render tool results for you.\n\nUser instructions:\n" + customInstructions
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
            parts.push({
                type: "result",
                name: "tool",
                description: attr(attrs, "title", "Tool result"),
                status: attr(attrs, "status", "ok"),
                command: commandMatch ? root.decodeEntities(commandMatch[1].trim()) : "",
                output: outputMatch ? root.decodeEntities(outputMatch[1].trim()) : ""
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

        const fenceRe = /```([A-Za-z0-9_-]*)\n?([\s\S]*?)```/g;
        let last = 0;
        let match;
        let foundFence = false;

        while ((match = fenceRe.exec(source)) !== null) {
            foundFence = true;
            appendTextAndCommandParts(parts, source.slice(last, match.index));
            const lang = (match[1] || "").toLowerCase();
            const body = match[2].trim();
            if (["sh", "shell", "bash", "zsh", "fish", "console", "terminal"].includes(lang) || looksLikeCommand(body.split("\n")[0] || body)) {
                parts.push({
                    type: "tool",
                    name: "terminal",
                    description: "Suggested terminal command",
                    command: body
                });
            } else {
                parts.push({
                    type: "text",
                    text: match[0]
                });
            }
            last = fenceRe.lastIndex;
        }

        if (foundFence) {
            appendTextAndCommandParts(parts, source.slice(last));
            return;
        }

        const lines = source.split("\n");
        let textBuffer = [];
        let commandBuffer = [];

        function flushText(): void {
            const joined = textBuffer.join("\n").trim();
            if (joined)
                parts.push({
                    type: "text",
                    text: joined
                });
            textBuffer = [];
        }

        function flushCommand(): void {
            const joined = commandBuffer.join("\n").trim().replace(/^\$\s*/, "");
            if (joined)
                parts.push({
                    type: "tool",
                    name: "terminal",
                    description: "Suggested terminal command",
                    command: joined
                });
            commandBuffer = [];
        }

        for (const line of lines) {
            if (looksLikeCommand(line)) {
                flushText();
                commandBuffer.push(line);
            } else {
                flushCommand();
                textBuffer.push(line);
            }
        }

        flushCommand();
        flushText();
    }

    function messageParts(text: string): var {
        const parts = [];
        const source = normaliseToolMarkup(parseCaelestiaToolResults(parts, text));
        const invokeRe = /<\|DSML\|invoke\s+name="([^"]+)"[\s\S]*?<\/\|DSML\|invoke>/g;
        let last = 0;
        let match;

        while ((match = invokeRe.exec(source)) !== null) {
            const before = source.slice(last, match.index)
                .replace(/<\/?\|DSML\|tool_calls>/g, "")
                .trim();
            appendTextAndCommandParts(parts, before);

            const block = match[0];
            const descriptionMatch = /<\|DSML\|parameter\s+name="description"[^>]*>([\s\S]*?)<\/\|DSML\|parameter>/.exec(block);
            const commandMatch = /<\|DSML\|parameter\s+name="command"[^>]*>([\s\S]*?)<\/\|DSML\|parameter>/.exec(block);
            parts.push({
                type: "tool",
                name: match[1],
                description: descriptionMatch ? decodeEntities(descriptionMatch[1].trim()) : "Suggested command",
                command: commandMatch ? decodeEntities(commandMatch[1].trim()) : block
            });
            last = invokeRe.lastIndex;
        }

        const tail = source.slice(last)
            .replace(/<\/?\|DSML\|tool_calls>/g, "")
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

        busy = true;
        status = qsTr("Thinking");
        requestProc.exec(["/home/kensa/.local/bin/caelestia-ai-agent"]);
        return true;
    }

    function completeRequest(exitCode: int): void {
        busy = false;

        let pendingIndex = -1;
        for (let i = messages.count - 1; i >= 0; i--) {
            if (messages.get(i).pending) {
                pendingIndex = i;
                break;
            }
        }

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
        Qt.callLater(() => history.positionViewAtEnd());
    }

    ListModel {
        id: messages

        ListElement {
            role: "assistant"
            content: "Hey. I am wired for chat through OpenRouter. Use the gear to set your key, model, and instructions."
            pending: false
        }
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

    Component.onCompleted: {
        settingsProc.action = "load";
        settingsProc.exec(["/home/kensa/.local/bin/caelestia-ai-settings"]);
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
            WlrLayershell.layer: WlrLayer.Top
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
                        boundsBehavior: Flickable.StopAtBounds
                        flickDeceleration: 2500
                        maximumFlickVelocity: 9000

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                const maxY = Math.max(0, history.contentHeight - history.height);
                                const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 2.5 : event.angleDelta.y * 2.4;
                                history.contentY = root.clamp(history.contentY - delta, 0, maxY);
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

                                                        StyledRect {
                                                            visible: part.type === "result" && (part.output || "").length > 0
                                                            Layout.fillWidth: true
                                                            implicitHeight: outputText.paintedHeight + Tokens.padding.small * 2
                                                            radius: Tokens.rounding.small
                                                            color: Qt.alpha(Colours.palette.m3shadow, 0.2)
                                                            border.width: part.status === "ok" ? 0 : 1
                                                            border.color: part.status === "blocked" ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3outline, 0.4)

                                                            Text {
                                                                id: outputText

                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.top: parent.top
                                                                anchors.margins: Tokens.padding.small
                                                                text: part.output || ""
                                                                color: part.status === "blocked" ? Colours.palette.m3error : Colours.palette.m3onSurface
                                                                font.family: "monospace"
                                                                font.pointSize: Tokens.font.body.small.pointSize
                                                                wrapMode: Text.Wrap
                                                                textFormat: Text.PlainText
                                                                renderType: Text.NativeRendering
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
                                    text: qsTr("Agent tools are still disabled. Future file edits, shell commands, package installs, Hyprland commands, web search, and sudo should require explicit approval.")
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
