import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: root
    anchors.fill: parent
    implicitWidth: 820
    implicitHeight: 520

    property var eqHeights: [28, 42, 35, 48]
    property var onNavigateHome: null
    property url albumArtSource: ""

    function trackTitle(fileName) {
        if (!fileName || fileName.length === 0)
            return qsTr("Ready to play");

        var parts = fileName.split("-");
        if (parts.length < 2)
            return stripExtension(fileName);
        return stripExtension(parts.slice(1).join("-")).replace(/_/g, " ");
    }

    function trackArtist(fileName) {
        if (!fileName || fileName.length === 0)
            return qsTr("Playlist idle");
        var parts = fileName.split("-");
        return parts[0];
    }

    function stripExtension(str) {
        var idx = str.lastIndexOf(".");
        return idx > -1 ? str.substring(0, idx) : str;
    }

    function formatTime(ms) {
        if (!ms || ms <= 0)
            return "00:00";
        var totalSeconds = Math.floor(ms / 1000);
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds % 60;
        var minuteStr = minutes < 10 ? "0" + minutes : "" + minutes;
        var secondStr = seconds < 10 ? "0" + seconds : "" + seconds;
        return minuteStr + ":" + secondStr;
    }

    Component.onCompleted: {
        musicPlayer.loadLibrary();
    }

    Timer {
        interval: 420
        running: true
        repeat: true
        onTriggered: {
            for (var i = 0; i < eqHeights.length; ++i) {
                eqHeights[i] = 24 + Math.random() * 48;
            }
        }
    }

    Component {
        id: emptyHint
        Text {
            anchors.centerIn: parent
            text: qsTr("음악 파일이 없습니다. design/assets/music 폴더에 추가하세요.")
            color: "#8ea1c3"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            width: parent ? parent.width * 0.8 : implicitWidth
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 28
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#4534c9" }
            GradientStop { position: 1.0; color: "#3426a5" }
        }
        border.color: "#5145cd"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 36
            spacing: 24

            RowLayout {
                Layout.fillWidth: true

                ToolButton {
                    id: homeButton
                    Layout.preferredWidth: 52
                    Layout.preferredHeight: 52
                    hoverEnabled: true
                    onClicked: {
                        if (root.onNavigateHome) {
                            root.onNavigateHome()
                        }
                    }
                    contentItem: Text {
                        text: "\u2302"
                        color: homeButton.hovered ? "#0f172a" : "#e0e7ff"
                        font.pixelSize: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.weight: Font.DemiBold
                    }
                    background: Rectangle {
                        implicitWidth: 52
                        implicitHeight: 52
                        radius: 18
                        color: homeButton.hovered ? "#e0e7ff" : "#4338ca"
                        border.color: "#4f46e5"
                        border.width: 1
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Column {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Text {
                    text: qsTr("Retro Mix Console")
                    color: "#e0e7ff"
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: qsTr("Tap a track to play on the head unit")
                    color: "#c7d2fe"
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                Rectangle {
                    id: playerBody
                    Layout.preferredWidth: 360
                    Layout.minimumWidth: 320
                    Layout.fillHeight: true
                    radius: 26
                    color: "#f4f5f7"
                    border.color: "#d1d5db"
                    border.width: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 28
                        spacing: 20

                        Rectangle {
                            id: albumArt
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 220
                            Layout.preferredHeight: 220
                            radius: 18
                            border.color: "#d6dbe6"
                            color: "#1f2937"

                            Image {
                                id: albumArtImage
                                anchors.fill: parent
                                anchors.margins: 8
                                source: root.albumArtSource
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                visible: status === Image.Ready
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: albumArtImage.status !== Image.Ready

                                Text {
                                    text: qsTr("Album Art")
                                    color: "#e5e7eb"
                                    font.pixelSize: 16
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    text: qsTr("Coming soon")
                                    color: "#cbd5f5"
                                    font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }

                        Rectangle {
                            id: trackInfo
                            Layout.fillWidth: true
                            Layout.preferredHeight: 88
                            radius: 16
                            color: "#111c2b"
                            border.color: "#1c2a40"

                            Row {
                                anchors.fill: parent
                                anchors.margins: 18
                                spacing: 18

                                Column {
                                    spacing: 4
                                    Text {
                                        text: trackTitle(musicPlayer.currentTrack)
                                        color: "#e2e8f0"
                                        font.pixelSize: 18
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: trackArtist(musicPlayer.currentTrack)
                                        color: "#94a3b8"
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }

                                Item {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 80
                                    height: parent.height - 12

                                    Repeater {
                                        model: eqHeights.length
                                        delegate: Rectangle {
                                            width: 10
                                            radius: 5
                                            height: eqHeights[index]
                                            anchors.bottom: parent.bottom
                                            anchors.left: parent.left
                                            anchors.leftMargin: index * 18
                                            color: index % 2 === 0 ? "#2563eb" : "#3b82f6"
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true; Layout.fillHeight: true }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            RowLayout {
                                id: controlsRow
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 16

                                Rectangle {
                                    width: 72
                                    height: 52
                                    radius: 14
                                    color: "#111827"
                                    border.color: "#1f2937"

                                    Text {
                                        text: "<<"
                                        anchors.centerIn: parent
                                        color: "#e2e8f0"
                                        font.pixelSize: 20
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: musicPlayer.previous()
                                    }
                                }

                                Rectangle {
                                    width: 100
                                    height: 52
                                    radius: 14
                                    color: "#15803d"
                                    border.color: "#16a34a"

                                    Text {
                                        text: musicPlayer.playing ? qsTr("Pause") : qsTr("Play")
                                        anchors.centerIn: parent
                                        color: "#fafff5"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (musicPlayer.playing) {
                                                musicPlayer.pause()
                                            } else {
                                                musicPlayer.play()
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    width: 72
                                    height: 52
                                    radius: 14
                                    color: "#111827"
                                    border.color: "#1f2937"

                                    Text {
                                        text: "■"
                                        anchors.centerIn: parent
                                        color: "#e2e8f0"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: musicPlayer.pause()
                                    }
                                }

                                Rectangle {
                                    width: 72
                                    height: 52
                                    radius: 14
                                    color: "#111827"
                                    border.color: "#1f2937"

                                    Text {
                                        text: ">>"
                                        anchors.centerIn: parent
                                        color: "#e2e8f0"
                                        font.pixelSize: 20
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: musicPlayer.next()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10
                                radius: 5
                                color: "#d1d5db"
                                border.color: "#e5e7eb"

                                Rectangle {
                                    width: parent.width * (musicPlayer ? musicPlayer.progress : 0)
                                    height: parent.height
                                    radius: parent.radius
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: "#2563eb" }
                                        GradientStop { position: 1.0; color: "#4f46e5" }
                                    }
                                    Behavior on width {
                                        NumberAnimation { duration: 180; easing.type: Easing.InOutQuad }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: formatTime(musicPlayer ? musicPlayer.position : 0)
                                    color: "#4b5563"
                                    font.pixelSize: 12
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: formatTime(musicPlayer ? musicPlayer.duration : 0)
                                    color: "#4b5563"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 22
                    color: "#0b1225"
                    border.color: "#1e293b"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 16

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: qsTr("Playlist")
                                color: "#c7d2fe"
                                font.pixelSize: 18
                                font.weight: Font.Medium
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: qsTr("%1 tracks").arg(musicPlayer.tracks.length)
                                color: "#94a3b8"
                                font.pixelSize: 12
                            }
                        }

                        ListView {
                            id: playlistView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: musicPlayer.tracks
                            delegate: Rectangle {
                                width: playlistView.width
                                height: 52
                                radius: 12
                                color: modelData === musicPlayer.currentTrack ? "#1d4ed8" : "#121b33"
                                border.color: modelData === musicPlayer.currentTrack ? "#2563eb" : "#1e293b"
                                border.width: modelData === musicPlayer.currentTrack ? 2 : 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    spacing: 14

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: trackTitle(modelData)
                                            color: "#f8fafc"
                                            font.pixelSize: 16
                                            font.weight: modelData === musicPlayer.currentTrack ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: trackArtist(modelData)
                                            color: "#cbd5f5"
                                            font.pixelSize: 12
                                            opacity: 0.85
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: musicPlayer.toggle(modelData)
                                }
                            }
                        }

                        Loader {
                            Layout.alignment: Qt.AlignHCenter
                            active: playlistView.count === 0
                            sourceComponent: emptyHint
                        }
                    }
                }
            }
        }
    }
}
