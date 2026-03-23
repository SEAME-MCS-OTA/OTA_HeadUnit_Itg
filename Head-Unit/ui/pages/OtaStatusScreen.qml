import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: otaStatusScreen

    signal backClicked()

    // Set from main.qml in the next step.
    property var otaClient: null

    readonly property string phaseText: otaClient ? String(otaClient.phaseText || "UNKNOWN").toUpperCase() : "UNKNOWN"
    readonly property string eventText: otaClient ? String(otaClient.eventText || "UNKNOWN").toUpperCase() : "UNKNOWN"
    readonly property string currentSlot: otaClient ? String(otaClient.currentSlot || "-").toUpperCase() : "-"
    readonly property string currentVersion: otaClient ? String(otaClient.currentVersion || "-") : "-"
    readonly property string targetVersion: otaClient ? String(otaClient.targetVersion || "-") : "-"
    readonly property string backendError: otaClient ? String(otaClient.backendError || "") : ""
    readonly property string requestError: otaClient ? String(otaClient.requestError || "") : ""
    readonly property bool online: otaClient ? !!otaClient.online : false
    readonly property bool requestInFlight: otaClient ? !!otaClient.requestInFlight : false
    readonly property int retryCount: otaClient ? Number(otaClient.retryCount || 0) : 0
    readonly property string deviceId: otaClient ? String(otaClient.deviceId || "-") : "-"
    readonly property string deviceModel: otaClient ? String(otaClient.deviceModel || otaClient.compatible || "-") : "-"
    readonly property string ipAddress: otaClient ? String(otaClient.ipAddress || "-") : "-"
    readonly property string ipSource: otaClient ? String(otaClient.ipSource || "") : ""
    readonly property var logs: otaClient ? (otaClient.otaLog || []) : []
    readonly property var slotList: otaClient ? (otaClient.slots || []) : []

    function isChipActive(kind) {
        if (kind === "FAILED")
            return eventText === "FAIL";
        return phaseText === kind;
    }

    function chipBackground(kind) {
        if (!isChipActive(kind))
            return "#1a1a1a";
        if (kind === "FAILED")
            return "#3f1722";
        if (kind === "COMMIT")
            return "#11303e";
        return "#1d304d";
    }

    function chipBorder(kind) {
        if (!isChipActive(kind))
            return "#333333";
        if (kind === "FAILED")
            return "#f87171";
        if (kind === "COMMIT")
            return "#67e8f9";
        return "#93c5fd";
    }

    function chipText(kind) {
        if (!isChipActive(kind))
            return "#9ca3af";
        if (kind === "FAILED")
            return "#fecaca";
        if (kind === "COMMIT")
            return "#a5f3fc";
        return "#dbeafe";
    }

    function formatLastUpdated(value) {
        if (!value)
            return "-";

        var parsed = new Date(value);
        if (!isNaN(parsed.getTime()))
            return Qt.formatDateTime(parsed, "yyyy-MM-dd hh:mm:ss");

        try {
            return Qt.formatDateTime(value, "yyyy-MM-dd hh:mm:ss");
        } catch (e) {
            return String(value);
        }
    }

    function slotInfo(bootName) {
        var info = {
            bootname: bootName,
            state: "unknown",
            device: "-",
            name: bootName === "A" ? "rootfs.0" : "rootfs.1"
        };

        for (var i = 0; i < slotList.length; i++) {
            var item = slotList[i];
            var itemBoot = String(item.bootname || "").toUpperCase();
            var itemName = String(item.name || "");
            var matches = (itemBoot === bootName)
                          || (bootName === "A" && itemName === "rootfs.0")
                          || (bootName === "B" && itemName === "rootfs.1");
            if (!matches)
                continue;

            info.state = String(item.state || "unknown");
            info.device = String(item.device || "-");
            info.name = itemName.length > 0 ? itemName : info.name;
            break;
        }

        return info;
    }

    function logBulletColor(message) {
        var text = String(message || "").toUpperCase();
        if (text.indexOf("FAIL") >= 0 || text.indexOf("ERROR") >= 0)
            return "#f87171";
        if (text.indexOf("OK") >= 0)
            return "#4ade80";
        if (text.indexOf("START") >= 0)
            return "#60a5fa";
        return "#94a3b8";
    }

    function ipSummary() {
        if (ipSource.length > 0)
            return ipAddress + " (" + ipSource + ")";
        return ipAddress;
    }

    Component.onCompleted: {
        if (otaClient && otaClient.startPolling)
            otaClient.startPolling();
    }

    onVisibleChanged: {
        if (!otaClient)
            return;

        if (visible) {
            if (otaClient.startPolling)
                otaClient.startPolling();
            if (otaClient.refreshNow)
                otaClient.refreshNow();
        } else if (otaClient.stopPolling) {
            otaClient.stopPolling();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true

                BackButton {
                    onGoBack: otaStatusScreen.backClicked()
                }

                Text {
                    Layout.leftMargin: 16
                    text: qsTr("OTA Status")
                    color: "#ffffff"
                    font.pixelSize: 24
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: qsTr("Last Updated")
                        color: "#94a3b8"
                        font.pixelSize: 11
                    }

                    Text {
                        text: otaClient ? formatLastUpdated(otaClient.lastUpdated) : "-"
                        color: "#e2e8f0"
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    Layout.leftMargin: 12
                    radius: 10
                    color: online ? (requestInFlight ? "#15324f" : "#143728") : "#3f1722"
                    border.color: online ? (requestInFlight ? "#60a5fa" : "#4ade80") : "#f87171"
                    border.width: 1
                    implicitWidth: statusText.implicitWidth + 20
                    implicitHeight: 30

                    Text {
                        id: statusText
                        anchors.centerIn: parent
                        text: online ? (requestInFlight ? qsTr("Syncing") : qsTr("Online")) : qsTr("Offline")
                        color: online ? (requestInFlight ? "#93c5fd" : "#86efac") : "#fecaca"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Button {
                    id: refreshButton
                    text: requestInFlight ? qsTr("Refreshing...") : qsTr("Refresh")
                    enabled: otaClient && otaClient.refreshNow && !requestInFlight
                    implicitWidth: 112
                    implicitHeight: 32

                    onClicked: {
                        if (otaClient && otaClient.refreshNow)
                            otaClient.refreshNow();
                    }

                    background: Rectangle {
                        radius: 16
                        color: refreshButton.enabled
                               ? (refreshButton.pressed ? "#1e3a8a" : (refreshButton.hovered ? "#1d4ed8" : "#1e40af"))
                               : "#1f2937"
                        border.color: refreshButton.enabled ? "#93c5fd" : "#4b5563"
                        border.width: 1
                    }

                    contentItem: Text {
                        text: refreshButton.text
                        color: refreshButton.enabled ? "#eff6ff" : "#9ca3af"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { key: "DOWNLOAD", label: "Downloading" },
                        { key: "APPLY", label: "Applying" },
                        { key: "REBOOT", label: "Reboot" },
                        { key: "COMMIT", label: "Commit" },
                        { key: "FAILED", label: "Failed" }
                    ]

                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 12
                        color: otaStatusScreen.chipBackground(modelData.key)
                        border.color: otaStatusScreen.chipBorder(modelData.key)
                        border.width: otaStatusScreen.isChipActive(modelData.key) ? 2 : 1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: otaStatusScreen.chipText(modelData.key)
                            font.pixelSize: 13
                            font.bold: otaStatusScreen.isChipActive(modelData.key)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: requestError.length > 0 || backendError.length > 0 || retryCount > 0
                radius: 12
                color: "#2a171b"
                border.color: "#7f1d1d"
                border.width: 1
                implicitHeight: errorInfo.implicitHeight + 14

                ColumnLayout {
                    id: errorInfo
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 3

                    Text {
                        visible: requestError.length > 0
                        text: qsTr("Request Error: %1").arg(requestError)
                        color: "#fecaca"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: backendError.length > 0
                        text: qsTr("Backend Error: %1").arg(backendError)
                        color: "#fca5a5"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Text {
                        visible: retryCount > 0
                        text: qsTr("Retry Count: %1").arg(retryCount)
                        color: "#fecaca"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    radius: 14
                    color: "#111111"
                    border.color: "#333333"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 4

                        Text {
                            text: qsTr("Current Version")
                            color: "#94a3b8"
                            font.pixelSize: 11
                        }
                        Text {
                            text: currentVersion
                            color: "#f8fafc"
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    radius: 14
                    color: "#111111"
                    border.color: "#333333"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 4

                        Text {
                            text: qsTr("Target Version")
                            color: "#94a3b8"
                            font.pixelSize: 11
                        }
                        Text {
                            text: targetVersion
                            color: "#f8fafc"
                            font.pixelSize: 20
                            font.bold: true
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    radius: 14
                    color: "#111111"
                    border.color: "#333333"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 2

                        Text {
                            text: qsTr("Device / Network")
                            color: "#94a3b8"
                            font.pixelSize: 11
                        }
                        Text {
                            text: deviceId + qsTr("  |  Slot ") + currentSlot
                            color: "#f8fafc"
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: deviceModel
                            color: "#cbd5e1"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: ipSummary()
                            color: "#93c5fd"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: "#0f0f0f"
                    border.color: "#2e2e2e"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: qsTr("Slots")
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Repeater {
                            model: ["A", "B"]
                            delegate: Rectangle {
                                readonly property var info: otaStatusScreen.slotInfo(modelData)
                                readonly property bool isCurrent: otaStatusScreen.currentSlot === modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 96
                                radius: 12
                                color: isCurrent ? "#162640" : "#151515"
                                border.color: isCurrent ? "#60a5fa" : "#333333"
                                border.width: isCurrent ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 12

                                    Rectangle {
                                        width: 34
                                        height: 34
                                        radius: 17
                                        color: isCurrent ? "#2563eb" : "#334155"
                                        border.color: isCurrent ? "#93c5fd" : "#64748b"
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: "#ffffff"
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: info.name + (isCurrent ? "  (Booted)" : "")
                                            color: "#f8fafc"
                                            font.pixelSize: 14
                                            font.bold: isCurrent
                                        }
                                        Text {
                                            text: info.device
                                            color: "#94a3b8"
                                            font.pixelSize: 12
                                        }
                                    }

                                    Rectangle {
                                        radius: 8
                                        height: 28
                                        width: stateLabel.implicitWidth + 16
                                        color: String(info.state).toLowerCase() === "booted" ? "#153b2f" : "#242424"
                                        border.color: String(info.state).toLowerCase() === "booted" ? "#4ade80" : "#4b5563"
                                        border.width: 1

                                        Text {
                                            id: stateLabel
                                            anchors.centerIn: parent
                                            text: String(info.state).toUpperCase()
                                            color: String(info.state).toLowerCase() === "booted" ? "#86efac" : "#d1d5db"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: "#0f0f0f"
                    border.color: "#2e2e2e"
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Text {
                            text: qsTr("Recent Logs")
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#101010"
                            border.color: "#262626"
                            border.width: 1
                            radius: 12
                            clip: true

                            ListView {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8
                                model: logs

                                delegate: RowLayout {
                                    width: ListView.view.width
                                    spacing: 10

                                    Rectangle {
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: otaStatusScreen.logBulletColor(modelData)
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 6
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData
                                        color: "#e5e7eb"
                                        font.pixelSize: 13
                                        wrapMode: Text.Wrap
                                    }
                                }

                                Text {
                                    visible: logs.length === 0
                                    anchors.centerIn: parent
                                    text: qsTr("No OTA logs yet")
                                    color: "#9ca3af"
                                    font.pixelSize: 13
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
