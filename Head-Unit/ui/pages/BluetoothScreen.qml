import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: bluetoothScreen

    signal backClicked()

    property string pendingSaveAddress: ""
    property string pendingSaveName: ""
    property string lastErrorMessage: ""

    Component.onCompleted: {
        if (bluetoothManager) {
            bluetoothManager.askToSaveDevice.connect(function(address, name) {
                pendingSaveAddress = address;
                pendingSaveName = name;
                saveDialog.open();
            });

            // Connect to error signal
            bluetoothManager.errorOccurred.connect(function(message) {
                lastErrorMessage = message;
                errorToast.show();
            });

            // Connect to pairing agent signals
            if (bluetoothManager.agent) {
                bluetoothManager.agent.passkeyConfirmationRequested.connect(function(devicePath, deviceName, passkey) {
                    passkeyConfirmDialog.deviceName = deviceName;
                    passkeyConfirmDialog.passkey = passkey.toString();
                    passkeyConfirmDialog.open();
                });

                bluetoothManager.agent.pinCodeRequested.connect(function(devicePath, deviceName) {
                    pinCodeDialog.deviceName = deviceName;
                    pinCodeDialog.open();
                });

                bluetoothManager.agent.passkeyDisplayRequested.connect(function(devicePath, deviceName, passkey, entered) {
                    passkeyDisplayDialog.deviceName = deviceName;
                    passkeyDisplayDialog.passkey = passkey.toString();
                    passkeyDisplayDialog.open();
                });

                bluetoothManager.agent.pairingCancelled.connect(function() {
                    passkeyConfirmDialog.close();
                    pinCodeDialog.close();
                    passkeyDisplayDialog.close();
                });
            }
        }
    }

    // Error Toast Notification
    Rectangle {
        id: errorToast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 100
        width: Math.min(parent.width - 48, 500)
        height: errorToastContent.height + 32
        radius: 12
        color: "#dc2626"
        border.color: "#991b1b"
        border.width: 2
        opacity: 0
        visible: opacity > 0
        z: 1000

        Behavior on opacity {
            NumberAnimation { duration: 300 }
        }

        function show() {
            opacity = 1;
            errorTimer.restart();
        }

        Timer {
            id: errorTimer
            interval: 5000
            onTriggered: errorToast.opacity = 0
        }

        RowLayout {
            id: errorToastContent
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "⚠️"
                font.pixelSize: 28
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: qsTr("Bluetooth Error")
                    color: "#ffffff"
                    font.pixelSize: 16
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: lastErrorMessage
                    color: "#fecaca"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                }
            }

            Button {
                width: 32
                height: 32

                background: Rectangle {
                    radius: 16
                    color: parent.hovered ? "#991b1b" : "transparent"
                }

                contentItem: Text {
                    text: "✕"
                    color: "#ffffff"
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: errorToast.opacity = 0
            }
        }
    }

    // Save device dialog
    Dialog {
        id: saveDialog
        anchors.centerIn: parent
        title: qsTr("Save Device?")
        modal: true
        width: 400
        height: 200

        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
        }

        contentItem: Rectangle {
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Do you want to save this device?")
                    color: "#ffffff"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: pendingSaveName
                    color: "#8b5cf6"
                    font.pixelSize: 18
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 12

                    Button {
                        text: qsTr("No")
                        onClicked: saveDialog.close()

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#404040" : "#2a2a2a"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: qsTr("Yes, Save")
                        onClicked: {
                            if (bluetoothManager) {
                                bluetoothManager.saveDevice(pendingSaveAddress, pendingSaveName);
                            }
                            saveDialog.close();
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#7c3aed" : "#8b5cf6"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // Passkey Confirmation Dialog (YES/NO for 6-digit number)
    Dialog {
        id: passkeyConfirmDialog
        anchors.centerIn: parent
        title: qsTr("Pairing Request")
        modal: true
        width: 450
        height: 250

        property string deviceName: ""
        property string passkey: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
            border.color: "#8b5cf6"
            border.width: 2
        }

        contentItem: Rectangle {
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 20

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Confirm pairing with:")
                    color: "#ffffff"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: passkeyConfirmDialog.deviceName
                    color: "#8b5cf6"
                    font.pixelSize: 20
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: "#2a2a2a"
                    radius: 8
                    border.color: "#8b5cf6"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: passkeyConfirmDialog.passkey
                        color: "#ffffff"
                        font.pixelSize: 32
                        font.bold: true
                        font.family: "monospace"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Does this code match the one on your phone?")
                    color: "#cccccc"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 12

                    Button {
                        text: qsTr("NO")
                        width: 100
                        height: 45

                        onClicked: {
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.confirmPairing(false);
                            }
                            passkeyConfirmDialog.close();
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#991b1b" : "#b91c1c"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: qsTr("YES")
                        width: 100
                        height: 45

                        onClicked: {
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.confirmPairing(true);
                            }
                            passkeyConfirmDialog.close();
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#059669" : "#10b981"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 16
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // PIN Code Input Dialog
    Dialog {
        id: pinCodeDialog
        anchors.centerIn: parent
        title: qsTr("PIN Code Required")
        modal: true
        width: 400
        height: 250

        property string deviceName: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
            border.color: "#8b5cf6"
            border.width: 2
        }

        contentItem: Rectangle {
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Enter PIN code to pair with:")
                    color: "#ffffff"
                    font.pixelSize: 16
                }

                Text {
                    Layout.fillWidth: true
                    text: pinCodeDialog.deviceName
                    color: "#8b5cf6"
                    font.pixelSize: 18
                    font.bold: true
                }

                TextField {
                    id: pinCodeInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    placeholderText: qsTr("Enter PIN (e.g., 0000 or 1234)")
                    font.pixelSize: 18
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter

                    background: Rectangle {
                        color: "#2a2a2a"
                        radius: 8
                        border.color: pinCodeInput.activeFocus ? "#8b5cf6" : "#404040"
                        border.width: 2
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 12

                    Button {
                        text: qsTr("Cancel")
                        onClicked: {
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.providePinCode("");
                            }
                            pinCodeInput.text = "";
                            pinCodeDialog.close();
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.hovered ? "#404040" : "#2a2a2a"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: qsTr("Pair")
                        enabled: pinCodeInput.text.length > 0

                        onClicked: {
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.providePinCode(pinCodeInput.text);
                            }
                            pinCodeInput.text = "";
                            pinCodeDialog.close();
                        }

                        background: Rectangle {
                            radius: 8
                            color: parent.enabled ? (parent.hovered ? "#7c3aed" : "#8b5cf6") : "#404040"
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    // Passkey Display Dialog (show number to user)
    Dialog {
        id: passkeyDisplayDialog
        anchors.centerIn: parent
        title: qsTr("Enter This Code on Your Phone")
        modal: true
        width: 400
        height: 220

        property string deviceName: ""
        property string passkey: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 12
            border.color: "#8b5cf6"
            border.width: 2
        }

        contentItem: Rectangle {
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Pairing with:")
                    color: "#ffffff"
                    font.pixelSize: 16
                }

                Text {
                    Layout.fillWidth: true
                    text: passkeyDisplayDialog.deviceName
                    color: "#8b5cf6"
                    font.pixelSize: 18
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: "#2a2a2a"
                    radius: 8
                    border.color: "#8b5cf6"
                    border.width: 2

                    Text {
                        anchors.centerIn: parent
                        text: passkeyDisplayDialog.passkey
                        color: "#ffffff"
                        font.pixelSize: 32
                        font.bold: true
                        font.family: "monospace"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Enter this code on your phone to complete pairing")
                    color: "#cccccc"
                    font.pixelSize: 14
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#0a0a0a"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    BackButton {
                        onGoBack: bluetoothScreen.backClicked()
                    }

                    Text {
                        Layout.leftMargin: 16
                        text: qsTr("Bluetooth Settings")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.parent.width
                    spacing: 24

                    // Bluetooth Power Section
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 24
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.preferredHeight: 80
                        radius: 12
                        color: "#1a1a1a"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20

                            Text {
                                text: "⚡"
                                font.pixelSize: 32
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Bluetooth Power")
                                    color: "#ffffff"
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    text: bluetoothManager && bluetoothManager.bluetoothPowered ? qsTr("On") : qsTr("Off")
                                    color: bluetoothManager && bluetoothManager.bluetoothPowered ? "#22c55e" : "#666666"
                                    font.pixelSize: 14
                                }
                            }

                            Switch {
                                checked: bluetoothManager ? bluetoothManager.bluetoothPowered : false
                                enabled: bluetoothManager && bluetoothManager.bluetoothAvailable
                                onToggled: {
                                    if (bluetoothManager) {
                                        bluetoothManager.bluetoothPowered = checked;
                                    }
                                }
                            }
                        }
                    }

                    // Broadcasting Section
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.preferredHeight: broadcastColumn.height + 40
                        radius: 12
                        color: "#1a1a1a"
                        visible: bluetoothManager && bluetoothManager.bluetoothPowered

                        ColumnLayout {
                            id: broadcastColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "📡"
                                    font.pixelSize: 32
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("Make PC Discoverable")
                                        color: "#ffffff"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    Text {
                                        text: bluetoothManager && bluetoothManager.broadcasting ?
                                              qsTr("Your phone can now find this PC") :
                                              qsTr("Start broadcasting to pair from phone")
                                        color: bluetoothManager && bluetoothManager.broadcasting ? "#8b5cf6" : "#666666"
                                        font.pixelSize: 14
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            Button {
                                id: broadcastButton
                                Layout.alignment: Qt.AlignHCenter
                                width: 200
                                height: 48
                                property bool isHovered: false

                                background: Rectangle {
                                    radius: 24
                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: broadcastButton.isHovered ?
                                                   (bluetoothManager && bluetoothManager.broadcasting ? "#dc2626" : "#7c3aed") :
                                                   (bluetoothManager && bluetoothManager.broadcasting ? "#ef4444" : "#8b5cf6")
                                        }
                                        GradientStop {
                                            position: 1.0
                                            color: broadcastButton.isHovered ?
                                                   (bluetoothManager && bluetoothManager.broadcasting ? "#b91c1c" : "#6d28d9") :
                                                   (bluetoothManager && bluetoothManager.broadcasting ? "#dc2626" : "#7c3aed")
                                        }
                                    }
                                }

                                HoverHandler {
                                    onHoveredChanged: broadcastButton.isHovered = hovered
                                }

                                contentItem: Text {
                                    text: bluetoothManager && bluetoothManager.broadcasting ? qsTr("Stop Broadcasting") : qsTr("Start Broadcasting")
                                    color: "#ffffff"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (bluetoothManager) {
                                        if (bluetoothManager.broadcasting) {
                                            bluetoothManager.stopBroadcasting();
                                        } else {
                                            bluetoothManager.startBroadcasting();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Connected Device Section
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.preferredHeight: 100
                        radius: 12
                        color: "#1a1a1a"
                        visible: bluetoothManager && bluetoothManager.connected

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 16

                            Text {
                                text: "🔗"
                                font.pixelSize: 40
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: qsTr("Connected Device")
                                    color: "#666666"
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: bluetoothManager ? bluetoothManager.connectedDeviceName : ""
                                    color: "#ffffff"
                                    font.pixelSize: 20
                                    font.bold: true
                                }

                                Text {
                                    text: bluetoothManager ? bluetoothManager.connectedDeviceAddress : ""
                                    color: "#8b5cf6"
                                    font.pixelSize: 13
                                }
                            }

                            Button {
                                width: 100
                                height: 40

                                background: Rectangle {
                                    radius: 8
                                    color: parent.hovered ? "#991b1b" : "#b91c1c"
                                }

                                contentItem: Text {
                                    text: qsTr("Disconnect")
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (bluetoothManager) {
                                        bluetoothManager.disconnectDevice();
                                    }
                                }
                            }
                        }
                    }

                    // Saved Devices Section
                    Text {
                        Layout.leftMargin: 24
                        text: qsTr("Saved Devices")
                        color: "#ffffff"
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Repeater {
                        model: bluetoothManager ? bluetoothManager.savedDevices : []

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.leftMargin: 24
                            Layout.rightMargin: 24
                            Layout.preferredHeight: 80
                            radius: 12
                            color: "#1a1a1a"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 16

                                Text {
                                    text: "📱"
                                    font.pixelSize: 32
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: modelData.name || qsTr("Unknown Device")
                                        color: "#ffffff"
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        text: modelData.address || ""
                                        color: "#666666"
                                        font.pixelSize: 13
                                    }
                                }

                                Button {
                                    width: 80
                                    height: 36

                                    background: Rectangle {
                                        radius: 8
                                        color: parent.hovered ? "#991b1b" : "#b91c1c"
                                    }

                                    contentItem: Text {
                                        text: qsTr("Remove")
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: {
                                        if (bluetoothManager) {
                                            bluetoothManager.removeSavedDevice(modelData.address);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Empty state
                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.preferredHeight: 60
                        text: qsTr("No saved devices")
                        color: "#666666"
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        visible: bluetoothManager && bluetoothManager.savedDevices.length === 0
                    }

                    // Debug Info Section (helpful for troubleshooting)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.preferredHeight: debugColumn.height + 32
                        radius: 12
                        color: "#1a1a1a"
                        border.color: "#404040"
                        border.width: 1

                        ColumnLayout {
                            id: debugColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: "🔧 System Status"
                                color: "#8b5cf6"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Text {
                                text: "Bluetooth Available: " + (bluetoothManager && bluetoothManager.bluetoothAvailable ? "✅ Yes" : "❌ No")
                                color: bluetoothManager && bluetoothManager.bluetoothAvailable ? "#22c55e" : "#ef4444"
                                font.pixelSize: 13
                                font.family: "monospace"
                            }

                            Text {
                                text: "Bluetooth Powered: " + (bluetoothManager && bluetoothManager.bluetoothPowered ? "✅ On" : "⚪ Off")
                                color: bluetoothManager && bluetoothManager.bluetoothPowered ? "#22c55e" : "#666666"
                                font.pixelSize: 13
                                font.family: "monospace"
                            }

                            Text {
                                text: "Broadcasting: " + (bluetoothManager && bluetoothManager.broadcasting ? "📡 Active" : "⚪ Inactive")
                                color: bluetoothManager && bluetoothManager.broadcasting ? "#8b5cf6" : "#666666"
                                font.pixelSize: 13
                                font.family: "monospace"
                            }

                            Text {
                                text: "Agent Registered: " + (bluetoothManager && bluetoothManager.agent ? "✅ Yes" : "❌ No")
                                color: bluetoothManager && bluetoothManager.agent ? "#22c55e" : "#ef4444"
                                font.pixelSize: 13
                                font.family: "monospace"
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: "#404040"
                                Layout.topMargin: 4
                                Layout.bottomMargin: 4
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Pairing Instructions:\n1. Turn on Bluetooth Power\n2. Click 'Start Broadcasting'\n3. Find this PC from your phone\n4. A pairing dialog will appear on THIS screen\n5. Tap 'YES' to confirm the 6-digit code")
                                color: "#999999"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                lineHeight: 1.3
                            }

                            Text {
                                Layout.fillWidth: true
                                text: lastErrorMessage ? ("⚠️ Last Error: " + lastErrorMessage) : ""
                                color: "#ef4444"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                visible: lastErrorMessage.length > 0
                                Layout.topMargin: 4
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                    }
                }
            }
        }
    }
}
