import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Item {
    id: homeScreen

    signal openMusic()
    signal openAmbient()
    signal openClimate()
    signal openBluetooth()
    signal openNavigation()
    signal gearChanged(string gear)

    property var musicPlayer
    property var gearClient: null
    property string driveMode: "PARK"
    property color ambientColor: "#8b5cf6"
    property real ambientBrightness: 0.6

    property string currentGear: "P"
    onDriveModeChanged: {
        if (!gearClient) {
            currentGear = driveModeToGear(driveMode)
        }
    }

    property string currentTrack: musicPlayer && musicPlayer.currentTrack ? musicPlayer.currentTrack : ""
    property bool isPlaying: musicPlayer && musicPlayer.playing

    readonly property string currentTrackTitle: isPlaying && currentTrack ? formatTrackTitle(currentTrack) : qsTr("Tap to play music")
    readonly property string currentTrackArtist: isPlaying && currentTrack ? formatTrackArtist(currentTrack) : qsTr("No track playing")

    function driveModeToGear(mode) {
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

    function stripExtension(str) {
        if (!str)
            return "";
        const idx = str.lastIndexOf(".");
        return idx > -1 ? str.substring(0, idx) : str;
    }

    function formatTrackTitle(fileName) {
        if (!fileName)
            return qsTr("Select a track");
        const parts = fileName.split("-");
        if (parts.length < 2)
            return stripExtension(fileName).replace(/_/g, " ").trim();
        return stripExtension(parts.slice(1).join("-")).replace(/_/g, " ").trim();
    }

    function formatTrackArtist(fileName) {
        if (!fileName)
            return qsTr("Unknown artist");
        const parts = fileName.split("-");
        if (parts.length < 2)
            return qsTr("Unknown artist");
        return parts[0].replace(/_/g, " ").trim();
    }

    Component.onCompleted: {
        currentGear = gearClient ? gearClient.currentGear : driveModeToGear(driveMode)
    }

    Connections {
        target: gearClient

        function onCurrentGearChanged() {
            if (gearClient)
                homeScreen.currentGear = gearClient.currentGear
        }

        function onGearRequestRejected(reason) {
            console.warn("Gear request rejected:", reason)
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const now = new Date();
            // Add 1 hour for Germany timezone (GMT+1)
            const germanyTime = new Date(now.getTime() + (60 * 60 * 1000));
            timeText.text = Qt.formatTime(germanyTime, "hh:mm");
            dateText.text = Qt.formatDate(germanyTime, "dddd, MMMM d");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 20

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2

                Text {
                    id: timeText
                    color: "#ffffff"
                    font.pixelSize: 42
                    text: {
                        const now = new Date();
                        const germanyTime = new Date(now.getTime() + (60 * 60 * 1000));
                        return Qt.formatTime(germanyTime, "hh:mm");
                    }
                }

                Text {
                    id: dateText
                    color: "#999999"
                    font.pixelSize: 14
                    text: {
                        const now = new Date();
                        const germanyTime = new Date(now.getTime() + (60 * 60 * 1000));
                        return Qt.formatDate(germanyTime, "dddd, MMMM d");
                    }
                }
            }

            Item { Layout.fillWidth: true }

            GearSelector {
                width: 200
                height: 36
                currentGear: homeScreen.currentGear
                onGearChanged: function(gear) {
                    if (gearClient)
                        gearClient.requestGear(gear, "HeadUnit")
                    homeScreen.gearChanged(gear)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                radius: 28
                visible: ambientBrightness > 0
                opacity: Math.min(0.35, ambientBrightness * 0.4)
                z: -1
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(ambientColor.r, ambientColor.g, ambientColor.b, 0.35) }
                    GradientStop { position: 1.0; color: Qt.rgba(ambientColor.r * 0.7, ambientColor.g * 0.7, ambientColor.b * 0.7, 0.05) }
                }
            }

            GridLayout {
                anchors.fill: parent
                columns: 3
                rows: 3
                columnSpacing: 16
                rowSpacing: 16

                VehicleInfoWidget {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: navMouse.containsMouse ? "#252525" : "#1a1a1a"
                    border.color: "#333333"
                    border.width: 1

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }

                    MouseArea {
                        id: navMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: homeScreen.openNavigation()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "🧭"
                                font.pixelSize: 20
                                color: "#38bdf8"
                            }

                            Text {
                                text: qsTr("Navigation")
                                color: "#ffffff"
                                font.pixelSize: 14
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "›"
                                color: "#666666"
                                font.pixelSize: 24
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 78
                            radius: 14
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#0b1220" }
                                GradientStop { position: 1.0; color: "#0f172a" }
                            }
                            border.color: "#1f2937"
                            border.width: 1

                            Item {
                                anchors.fill: parent
                                anchors.margins: 10

                                property var roadSegments: [
                                    { x: 0.04, y: 0.2, length: 0.78, angle: -8, color: "#1f2937" },
                                    { x: 0.12, y: 0.55, length: 0.82, angle: 6, color: "#1f2937" },
                                    { x: 0.18, y: 0.32, length: 0.62, angle: 44, color: "#1f2937" },
                                    { x: 0.42, y: 0.08, length: 0.68, angle: -38, color: "#1f2937" }
                                ]

                                Repeater {
                                    model: parent.roadSegments
                                    delegate: Rectangle {
                                        width: parent.width * modelData.length
                                        height: 5
                                        radius: 3
                                        color: modelData.color
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: parent.width * modelData.x
                                        anchors.topMargin: parent.height * modelData.y
                                        rotation: modelData.angle
                                    }
                                }

                                Rectangle {
                                    width: parent.width * 0.88
                                    height: 4
                                    radius: 2
                                    color: "#38bdf8"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    rotation: -6
                                    opacity: 0.9

                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        blurEnabled: true
                                        blur: 0.35
                                        blurMax: 12
                                    }
                                }

                                Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: "#38bdf8"
                                    border.color: "#e0f2fe"
                                    border.width: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.horizontalCenterOffset: parent.width * 0.2
                                    anchors.verticalCenterOffset: -6
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Route preview · Seoul → Pangyo")
                            color: "#666666"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: musicMouse.containsMouse ? "#252525" : "#1a1a1a"
                border.color: "#333333"
                border.width: 1

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }

                MouseArea {
                    id: musicMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: homeScreen.openMusic()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    Rectangle {
                        width: 100
                        height: 100
                        radius: 12
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#a855f7" }
                            GradientStop { position: 1.0; color: "#ec4899" }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "🎵"
                            font.pixelSize: 44
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: qsTr("Music")
                            color: "#ffffff"
                            font.pixelSize: 18
                        }

                        Text {
                            text: currentTrackTitle
                            color: "#cccccc"
                            font.pixelSize: 15
                            elide: Text.ElideRight
                        }

                        Text {
                            text: currentTrackArtist
                            color: "#666666"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Text {
                        text: "›"
                        color: "#666666"
                        font.pixelSize: 32
                    }
                }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: ambientMouse.containsMouse ? "#252525" : "#1a1a1a"
                    border.color: "#333333"
                border.width: 1

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }

                MouseArea {
                    id: ambientMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: homeScreen.openAmbient()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "💡"
                            font.pixelSize: 20
                            color: "#fbbf24"
                        }

                        Text {
                            text: qsTr("Ambient")
                            color: "#ffffff"
                            font.pixelSize: 14
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "›"
                            color: "#666666"
                            font.pixelSize: 24
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 64
                        height: 64
                        radius: 32
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: ambientColor }
                            GradientStop { position: 1.0; color: Qt.darker(ambientColor, 1.2) }
                        }
                        opacity: ambientBrightness > 0
                                 ? Math.min(1, ambientBrightness * 1.4 + 0.2)
                                 : 0.25

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            blurEnabled: true
                            blur: 0.5
                            blurMax: 20
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Math.round(ambientBrightness * 100) + "%"
                        color: "#666666"
                        font.pixelSize: 12
                    }

                    Item { Layout.fillHeight: true }
                }
                }

                Rectangle {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: bluetoothMouse.containsMouse ? "#252525" : "#1a1a1a"
                    border.color: "#333333"
                    border.width: 1

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }

                    MouseArea {
                        id: bluetoothMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: homeScreen.openBluetooth()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 16

                        Rectangle {
                            width: 100
                            height: 100
                            radius: 12
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#3b82f6" }
                                GradientStop { position: 1.0; color: "#8b5cf6" }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "📱"
                                font.pixelSize: 44
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: qsTr("Bluetooth")
                                color: "#ffffff"
                                font.pixelSize: 18
                            }

                            Text {
                                text: qsTr("Connect your devices")
                                color: "#cccccc"
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }

                            Text {
                                text: qsTr("Manage connections")
                                color: "#666666"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillHeight: true }
                        }

                        Text {
                            text: "›"
                            color: "#666666"
                            font.pixelSize: 32
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    radius: 16
                    color: climateMouse.containsMouse ? "#252525" : "#1a1a1a"
                    border.color: "#333333"
                    border.width: 1

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }

                    MouseArea {
                        id: climateMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: homeScreen.openClimate()
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "🌡"
                                font.pixelSize: 18
                                color: "#60a5fa"
                            }

                            Text {
                                text: qsTr("Climate")
                                color: "#ffffff"
                                font.pixelSize: 14
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "›"
                                color: "#666666"
                                font.pixelSize: 24
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("22°C")
                            color: "#ffffff"
                            font.pixelSize: 36
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
