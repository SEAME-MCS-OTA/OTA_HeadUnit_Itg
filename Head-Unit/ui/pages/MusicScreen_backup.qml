import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: musicScreen

    signal backClicked()

    property var musicPlayer
    property int currentIndex: (musicPlayer && musicPlayer.tracks)
                               ? musicPlayer.tracks.indexOf(musicPlayer.currentTrack)
                               : -1
    property bool isPlaying: musicPlayer ? musicPlayer.playing : false

    function stripExtension(str) {
        if (!str)
            return "";
        const idx = str.lastIndexOf(".");
        return idx > -1 ? str.substring(0, idx) : str;
    }

    function trackTitle(fileName) {
        if (!fileName)
            return qsTr("No track selected");
        const parts = fileName.split("-");
        if (parts.length < 2)
            return stripExtension(fileName).replace(/_/g, " ").trim();
        return stripExtension(parts.slice(1).join("-")).replace(/_/g, " ").trim();
    }

    function trackArtist(fileName) {
        if (!fileName)
            return qsTr("Unknown artist");
        const parts = fileName.split("-");
        if (parts.length < 2)
            return qsTr("Unknown artist");
        return parts[0].replace(/_/g, " ").trim();
    }

    function formatTime(ms) {
        if (!ms || ms <= 0)
            return "00:00";
        const totalSeconds = Math.floor(ms / 1000);
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = totalSeconds % 60;
        const minuteStr = minutes < 10 ? "0" + minutes : "" + minutes;
        const secondStr = seconds < 10 ? "0" + seconds : "" + seconds;
        return minuteStr + ":" + secondStr;
    }

    function ensureLibrary() {
        if (musicPlayer && musicPlayer.tracks && musicPlayer.tracks.length === 0) {
            musicPlayer.loadLibrary();
        }
    }

    Component.onCompleted: ensureLibrary();

    Connections {
        target: musicPlayer

        function onTracksChanged() {
            ensureLibrary();
            currentIndex = musicPlayer.tracks.indexOf(musicPlayer.currentTrack);
        }

        function onCurrentTrackChanged() {
            currentIndex = musicPlayer.tracks.indexOf(musicPlayer.currentTrack);
        }

        function onPlayingChanged() {
            isPlaying = musicPlayer.playing;
        }

        function onDurationChanged() {
            progressCanvas.requestPaint();
        }

        function onPositionChanged() {
            progressCanvas.requestPaint();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                color: "#0a0a0a"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    BackButton {
                        onGoBack: musicScreen.backClicked()
                    }

                    Text {
                        Layout.leftMargin: 16
                        text: qsTr("Music Player")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                color: "#0f0f0f"

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 24

                    Rectangle {
                        width: 140
                        height: 140
                        radius: 16
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#a855f7" }
                            GradientStop { position: 1.0; color: "#ec4899" }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "🎵"
                            font.pixelSize: 60
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: trackTitle(musicPlayer ? musicPlayer.currentTrack : "")
                            color: "#ffffff"
                            font.pixelSize: 24
                            elide: Text.ElideRight
                        }

                        Text {
                            text: trackArtist(musicPlayer ? musicPlayer.currentTrack : "")
                            color: "#999999"
                            font.pixelSize: 16
                            elide: Text.ElideRight
                        }

                        Text {
                            text: qsTr("HeadUnit Library")
                            color: "#666666"
                            font.pixelSize: 14
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 12

                            Text {
                                text: formatTime(musicPlayer ? musicPlayer.position : 0)
                                color: "#666666"
                                font.pixelSize: 12
                            }

                            Canvas {
                                id: progressCanvas
                                Layout.fillWidth: true
                                height: 4

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.reset();
                                    ctx.fillStyle = "#333333";
                                    ctx.fillRect(0, 0, width, height);
                                    var progress = musicPlayer && musicPlayer.progress ? musicPlayer.progress : 0;
                                    ctx.fillStyle = "#8b5cf6";
                                    ctx.fillRect(0, 0, width * progress, height);
                                }
                            }

                            Text {
                                text: formatTime(musicPlayer ? musicPlayer.duration : 0)
                                color: "#666666"
                                font.pixelSize: 12
                            }
                        }
                    }

                    RowLayout {
                        spacing: 12

                        Button {
                            width: 52
                            height: 52

                            background: Rectangle {
                                radius: 26
                                color: parent.hovered ? "#2a2a2a" : "#1a1a1a"
                                border.color: "#333333"
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            contentItem: Text {
                                text: "⏮"
                                color: "#ffffff"
                                font.pixelSize: 20
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: musicPlayer && musicPlayer.previous()
                        }

                        Button {
                            width: 60
                            height: 60

                            background: Rectangle {
                                radius: 30
                                color: parent.hovered ? "#e5e5e5" : "#ffffff"

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            contentItem: Text {
                                text: isPlaying ? "⏸" : "▶"
                                color: "#000000"
                                font.pixelSize: 24
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                if (!musicPlayer)
                                    return;
                                musicPlayer.toggle(musicPlayer.currentTrack);
                                isPlaying = musicPlayer.playing;
                            }
                        }

                        Button {
                            width: 52
                            height: 52

                            background: Rectangle {
                                radius: 26
                                color: parent.hovered ? "#2a2a2a" : "#1a1a1a"
                                border.color: "#333333"
                                border.width: 1

                                Behavior on color {
                                    ColorAnimation { duration: 150 }
                                }
                            }

                            contentItem: Text {
                                text: "⏭"
                                color: "#ffffff"
                                font.pixelSize: 20
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: musicPlayer && musicPlayer.next()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: "#000000"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Playlist")
                    color: "#ffffff"
                    font.pixelSize: 18
                }
            }

            ListView {
                id: playlistView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: musicPlayer ? musicPlayer.tracks : []
                currentIndex: musicScreen.currentIndex

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 70
                    color: (index === musicScreen.currentIndex)
                           ? "#111111"
                           : (trackMouse.containsMouse ? "#1a1a1a" : "#000000")

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: trackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!musicPlayer)
                                return;
                            musicPlayer.play(modelData);
                            musicScreen.isPlaying = true;
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        spacing: 16

                        Text {
                            text: (index + 1).toString().padStart(2, "0")
                            color: index === musicScreen.currentIndex ? "#8b5cf6" : "#666666"
                            font.pixelSize: 16
                            Layout.preferredWidth: 30
                        }

                       ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            Text {
                                text: trackTitle(modelData)
                                color: index === musicScreen.currentIndex ? "#ffffff" : "#cccccc"
                                font.pixelSize: 15
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                            }

                            Text {
                                text: trackArtist(modelData)
                                color: "#666666"
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignLeft
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: index === musicScreen.currentIndex
                                  ? formatTime(musicPlayer ? musicPlayer.duration : 0)
                                  : "--:--"
                            color: "#666666"
                            font.pixelSize: 13
                        }

                        Text {
                            text: (index === musicScreen.currentIndex && musicScreen.isPlaying) ? "🔊" : ""
                            font.pixelSize: 16
                            Layout.preferredWidth: 24
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 24
                        anchors.rightMargin: 24
                        height: 1
                        color: "#1a1a1a"
                    }
                }
            }
        }
    }
}
