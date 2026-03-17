import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs
import "pages"

ApplicationWindow {
    id: rootWindow
    width: 1024
    height: 600
    x: 0
    y: 0
    visible: true
    visibility: Window.Windowed
    flags: Qt.FramelessWindowHint
    color: "#000000"
    title: qsTr("Head Unit Console")

    property var playerRef: musicPlayer
    property var gearClientRef: gearClient
    property color ambientColor: "#8b5cf6"
    property real ambientBrightness: 0.6   // 0.0 ~ 1.0
    property string currentGear: "P"

    Component.onCompleted: {
        if (playerRef && playerRef.tracks.length === 0) {
            playerRef.loadLibrary();
        }
        if (viewModel) {
            ambientBrightness = Math.max(0, Math.min(1, viewModel.ambientLightLevel / 100.0));
            if (!gearClientRef)
                currentGear = mapDriveMode(viewModel.driveMode);
        }
        if (gearClientRef)
            currentGear = gearClientRef.currentGear;

        // Bluetooth pairing signal connections (GLOBAL - works from any screen)
        if (bluetoothManager && bluetoothManager.agent) {
            bluetoothManager.agent.passkeyConfirmationRequested.connect(function(devicePath, deviceName, passkey) {
                console.log("[main.qml] Pairing request received:", deviceName, passkey);
                passkeyConfirmDialog.deviceName = deviceName;
                passkeyConfirmDialog.passkey = passkey.toString();
                passkeyConfirmDialog.open();
            });

            bluetoothManager.agent.pinCodeRequested.connect(function(devicePath, deviceName) {
                console.log("[main.qml] PIN code request received:", deviceName);
                pinCodeDialog.deviceName = deviceName;
                pinCodeDialog.open();
            });

            bluetoothManager.agent.passkeyDisplayRequested.connect(function(devicePath, deviceName, passkey, entered) {
                console.log("[main.qml] Passkey display request:", deviceName, passkey);
                passkeyDisplayDialog.deviceName = deviceName;
                passkeyDisplayDialog.passkey = passkey.toString();
                passkeyDisplayDialog.open();
            });

            bluetoothManager.agent.pairingCancelled.connect(function() {
                console.log("[main.qml] Pairing cancelled");
                passkeyConfirmDialog.close();
                pinCodeDialog.close();
                passkeyDisplayDialog.close();
            });
        }

        // Auto-navigate to music screen ONLY after pairing is complete
        if (bluetoothManager) {
            bluetoothManager.connectedDeviceChanged.connect(() => {
                if (bluetoothManager.connected && !passkeyConfirmDialog.opened) {
                    // Only auto-navigate if not in pairing dialog
                    stackView.push(musicScreen);
                }
            });
        }
    }

    function mapDriveMode(mode) {
        if (!mode)
            return "P";
        const upper = mode.toUpperCase();
        if (upper.startsWith("D"))
            return "D";
        if (upper.startsWith("R"))
            return "R";
        if (upper.startsWith("N"))
            return "N";
        return "P";
    }

    Connections {
        target: viewModel

        function onAmbientLightLevelChanged() {
            ambientBrightness = Math.max(0, Math.min(1, viewModel.ambientLightLevel / 100.0));
        }

        function onDriveModeChanged() {
            if (!gearClientRef)
                currentGear = mapDriveMode(viewModel.driveMode);
        }
    }

    Connections {
        target: gearClientRef

        function onCurrentGearChanged() {
            if (gearClientRef)
                currentGear = gearClientRef.currentGear;
        }

        function onGearRequestRejected(reason) {
            console.warn("Gear request rejected:", reason);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Rectangle {
        id: glowPrimary
        width: 360
        height: 360
        radius: 180
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: parent.width * 0.25

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(ambientColor.r, ambientColor.g, ambientColor.b, ambientBrightness * 0.4)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(ambientColor.r, ambientColor.g, ambientColor.b, 0)
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 80
        }

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 28000
            loops: Animation.Infinite
            running: ambientBrightness > 0
        }
    }

    Rectangle {
        id: glowSecondary
        width: 340
        height: 340
        radius: 170
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: parent.width * 0.22

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(ambientColor.r * 0.9, ambientColor.g, ambientColor.b * 1.15, ambientBrightness * 0.32)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(ambientColor.r, ambientColor.g, ambientColor.b, 0)
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 80
        }

        RotationAnimation on rotation {
            from: 360
            to: 0
            duration: 24000
            loops: Animation.Infinite
            running: ambientBrightness > 0
        }
    }

    Rectangle {
        id: glowAccent
        width: 240
        height: 240
        radius: 120
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(ambientColor.r * 1.05, ambientColor.g * 0.95, ambientColor.b, ambientBrightness * 0.25)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(ambientColor.r, ambientColor.g, ambientColor.b, 0)
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 70
        }

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 32000
            loops: Animation.Infinite
            running: ambientBrightness > 0
        }
    }

    // ========================================
    // GLOBAL Pairing Dialogs (visible from ANY screen)
    // ========================================

    // Passkey Confirmation Dialog (YES/NO for 6-digit number)
    Dialog {
        id: passkeyConfirmDialog
        anchors.centerIn: parent
        title: qsTr("Bluetooth Pairing Request")
        modal: true
        width: 500
        height: 300
        z: 10000  // Top-most layer

        property string deviceName: ""
        property string passkey: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 16
            border.color: "#8b5cf6"
            border.width: 3
        }

        onOpened: {
            console.log("[main.qml] Pairing dialog OPENED");
        }

        onClosed: {
            console.log("[main.qml] Pairing dialog CLOSED");
        }

        contentItem: Rectangle {
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 20

                Text {
                    Layout.fillWidth: true
                    text: qsTr("📱 Pairing Request")
                    color: "#8b5cf6"
                    font.pixelSize: 24
                    font.bold: true
                }

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
                    font.pixelSize: 22
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    color: "#2a2a2a"
                    radius: 12
                    border.color: "#8b5cf6"
                    border.width: 3

                    Text {
                        anchors.centerIn: parent
                        text: passkeyConfirmDialog.passkey
                        color: "#ffffff"
                        font.pixelSize: 40
                        font.bold: true
                        font.family: "monospace"
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Does this code match the one on your phone?")
                    color: "#cccccc"
                    font.pixelSize: 16
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 16

                    Button {
                        text: qsTr("NO")
                        implicitWidth: 120
                        implicitHeight: 50

                        onClicked: {
                            console.log("[main.qml] User clicked NO");
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.confirmPairing(false);
                            }
                            passkeyConfirmDialog.close();
                        }

                        background: Rectangle {
                            radius: 10
                            color: parent.pressed ? "#7f1d1d" : (parent.hovered ? "#991b1b" : "#b91c1c")
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 18
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        text: qsTr("YES")
                        implicitWidth: 120
                        implicitHeight: 50

                        onClicked: {
                            console.log("[main.qml] User clicked YES");
                            if (bluetoothManager && bluetoothManager.agent) {
                                bluetoothManager.agent.confirmPairing(true);
                            }
                            passkeyConfirmDialog.close();
                        }

                        background: Rectangle {
                            radius: 10
                            color: parent.pressed ? "#047857" : (parent.hovered ? "#059669" : "#10b981")
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.pixelSize: 18
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
        width: 450
        height: 280
        z: 10000

        property string deviceName: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 16
            border.color: "#8b5cf6"
            border.width: 3
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
                    font.pixelSize: 20
                    font.bold: true
                }

                TextField {
                    id: pinCodeInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 55
                    placeholderText: qsTr("Enter PIN (e.g., 0000 or 1234)")
                    font.pixelSize: 20
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
        width: 450
        height: 250
        z: 10000

        property string deviceName: ""
        property string passkey: ""

        background: Rectangle {
            color: "#1a1a1a"
            radius: 16
            border.color: "#8b5cf6"
            border.width: 3
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
                    font.pixelSize: 20
                    font.bold: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 70
                    color: "#2a2a2a"
                    radius: 12
                    border.color: "#8b5cf6"
                    border.width: 3

                    Text {
                        anchors.centerIn: parent
                        text: passkeyDisplayDialog.passkey
                        color: "#ffffff"
                        font.pixelSize: 40
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

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: homeScreen

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 280; easing.type: Easing.OutCubic }
            }
        }

        pushExit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 220; easing.type: Easing.InCubic }
        }

        popEnter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
        }

        popExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 220; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1.0; to: 0.96; duration: 220; easing.type: Easing.InCubic }
            }
        }
    }

    Component {
        id: homeScreen
        HomeScreen {
            musicPlayer: rootWindow.playerRef
            gearClient: rootWindow.gearClientRef
            driveMode: viewModel ? viewModel.driveMode : "PARK"
            ambientColor: rootWindow.ambientColor
            ambientBrightness: rootWindow.ambientBrightness

            onOpenMusic: stackView.push(musicScreen)
            onOpenAmbient: stackView.push(ambientScreen)
            onOpenClimate: stackView.push(climateScreen)
            onOpenBluetooth: stackView.push(bluetoothScreen)
            onOpenNavigation: stackView.push(navigationScreen)

            onGearChanged: function(gear) {
                if (!rootWindow.gearClientRef)
                    rootWindow.currentGear = gear;
            }
        }
    }

    Component {
        id: musicScreen
        MusicScreen {
            onBackClicked: stackView.pop()
        }
    }

    Component {
        id: ambientScreen
        AmbientScreen {
            currentColor: rootWindow.ambientColor
            currentBrightness: rootWindow.ambientBrightness * 100

            onColorChanged: function(color) {
                rootWindow.ambientColor = color;
            }

            onBrightnessChanged: function(level) {
                rootWindow.ambientBrightness = Math.max(0, Math.min(1, level / 100));
            }

            onBackClicked: stackView.pop()
        }
    }

    Component {
        id: climateScreen
        ClimateScreen {
            onBackClicked: stackView.pop()
        }
    }

    Component {
        id: bluetoothScreen
        BluetoothScreen {
            onBackClicked: stackView.pop()
        }
    }

    Component {
        id: navigationScreen
        NavigationScreen {
            onBackClicked: stackView.pop()
        }
    }
}
