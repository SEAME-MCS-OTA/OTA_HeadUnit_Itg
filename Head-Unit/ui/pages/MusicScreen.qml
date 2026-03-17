import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import Qt5Compat.GraphicalEffects

Item {
    id: musicScreen

    signal backClicked()

    // Bluetooth 연결 상태에 따라 모드 자동 전환 (global context properties 직접 사용)
    readonly property bool isBluetoothMode: typeof bluetoothManager !== 'undefined' &&
                                            bluetoothManager !== null &&
                                            bluetoothManager.connected &&
                                            typeof bluetoothAudioPlayer !== 'undefined' &&
                                            bluetoothAudioPlayer !== null &&
                                            bluetoothAudioPlayer.connected

    Rectangle {
        anchors.fill: parent
        color: "#000000"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // 헤더
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
                        text: isBluetoothMode ? qsTr("Bluetooth Audio") : qsTr("Music Player")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }

                    // 모드 인디케이터
                    Rectangle {
                        width: 120
                        height: 32
                        radius: 16
                        color: isBluetoothMode ? "#1e40af" : "#7c2d12"

                        Text {
                            anchors.centerIn: parent
                            text: isBluetoothMode ? "📱 Bluetooth" : "💿 Local"
                            color: "#ffffff"
                            font.pixelSize: 13
                        }
                    }
                }
            }

            // Bluetooth 오디오 플레이어
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"
                visible: isBluetoothMode

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 32

                    Item { Layout.fillWidth: true }

                    // 앨범 아트 영역
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 220
                        height: 220
                        radius: 16
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#3b82f6" }
                            GradientStop { position: 1.0; color: "#8b5cf6" }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 0
                            source: bluetoothAudioPlayer && bluetoothAudioPlayer.hasAlbumArt ?
                                   "file://" + bluetoothAudioPlayer.albumArtPath : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: bluetoothAudioPlayer && bluetoothAudioPlayer.hasAlbumArt
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                maskSource: Rectangle {
                                    width: 220
                                    height: 220
                                    radius: 16
                                }
                            }
                        }

                        // Fallback UI when no album art
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: !bluetoothAudioPlayer || !bluetoothAudioPlayer.hasAlbumArt

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "🎵"
                                font.pixelSize: 60
                                opacity: 0.9
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 180
                                text: bluetoothAudioPlayer ? bluetoothAudioPlayer.trackTitle : "No Track"
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                opacity: 0.95
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: bluetoothAudioPlayer ? bluetoothAudioPlayer.trackArtist : "Unknown"
                                color: "#e0e0e0"
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                opacity: 0.85
                            }
                        }
                    }

                    // 컨트롤 영역
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 16

                        Item { Layout.fillHeight: true }

                        // 곡 정보
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: bluetoothAudioPlayer ? bluetoothAudioPlayer.trackTitle : "No Track"
                                color: "#ffffff"
                                font.pixelSize: 22
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: bluetoothAudioPlayer ? bluetoothAudioPlayer.trackArtist : "Unknown Artist"
                                color: "#999999"
                                font.pixelSize: 16
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: bluetoothAudioPlayer ? bluetoothAudioPlayer.trackAlbum : "Unknown Album"
                                color: "#666666"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }

                        // 재생 위치 바
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                        Rectangle {
                            id: progressBar
                            Layout.fillWidth: true
                            height: 6
                            radius: 3
                            color: "#333333"

                            Rectangle {
                                id: progressFill
                                width: parent.width * (bluetoothAudioPlayer && bluetoothAudioPlayer.duration > 0 ?
                                       bluetoothAudioPlayer.position / bluetoothAudioPlayer.duration : 0)
                                height: parent.height
                                radius: parent.radius
                                color: "#8b5cf6"

                                Behavior on width {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: bluetoothAudioPlayer ? formatTime(bluetoothAudioPlayer.position) : "0:00"
                                color: "#999999"
                                font.pixelSize: 13
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: bluetoothAudioPlayer ? formatTime(bluetoothAudioPlayer.duration) : "0:00"
                                color: "#999999"
                                font.pixelSize: 13
                            }
                            }
                        }

                        // 재생 컨트롤 버튼
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 20

                            // Previous
                            Button {
                                width: 48
                                height: 48

                                background: Rectangle {
                                    radius: 24
                                    color: parent.hovered ? "#252525" : "#1a1a1a"
                                    border.color: "#333333"
                                    border.width: 1

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }

                                contentItem: Text {
                                    text: "⏮"
                                    font.pixelSize: 20
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (bluetoothAudioPlayer) {
                                        bluetoothAudioPlayer.previous()
                                    }
                                }
                            }

                            // Play/Pause
                            Button {
                                id: playButton
                                width: 60
                                height: 60

                                background: Rectangle {
                                    radius: 30
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: playButton.hovered ? "#7c3aed" : "#8b5cf6" }
                                        GradientStop { position: 1.0; color: playButton.hovered ? "#6d28d9" : "#7c3aed" }
                                    }

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }

                                contentItem: Text {
                                    text: bluetoothAudioPlayer && bluetoothAudioPlayer.playing ? "⏸" : "▶"
                                    font.pixelSize: 28
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (bluetoothAudioPlayer) {
                                        if (bluetoothAudioPlayer.playing) {
                                            bluetoothAudioPlayer.pause()
                                        } else {
                                            bluetoothAudioPlayer.play()
                                        }
                                    }
                                }
                            }

                            // Next
                            Button {
                                width: 48
                                height: 48

                                background: Rectangle {
                                    radius: 24
                                    color: parent.hovered ? "#252525" : "#1a1a1a"
                                    border.color: "#333333"
                                    border.width: 1

                                    Behavior on color {
                                        ColorAnimation { duration: 150 }
                                    }
                                }

                                contentItem: Text {
                                    text: "⏭"
                                    font.pixelSize: 20
                                    color: "#ffffff"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (bluetoothAudioPlayer) {
                                        bluetoothAudioPlayer.next()
                                    }
                                }
                            }
                        }

                        // 볼륨 컨트롤
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            spacing: 16

                            Text {
                                text: "🔊"
                                font.pixelSize: 24
                            }

                            Slider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                stepSize: 1
                                value: 50  // 기본값 50% (가짜 슬라이더 - 실제 볼륨 제어 안 함)

                                // NOTE: 이 볼륨 슬라이더는 UI 전용 (decorative only)
                                // 실제 블루투스 오디오 볼륨은 스마트폰에서 제어됩니다

                                /* DISABLED: 초기값 설정
                                Component.onCompleted: {
                                    if (bluetoothAudioPlayer) {
                                        value = bluetoothAudioPlayer.volume
                                    }
                                }
                                */

                                /* DISABLED: 폰에서 볼륨 변경 시 슬라이더 업데이트
                                Connections {
                                    target: bluetoothAudioPlayer
                                    function onVolumeChanged() {
                                        if (!volumeSlider.pressed) {
                                            volumeSlider.value = bluetoothAudioPlayer.volume
                                        }
                                    }
                                }
                                */

                                /* DISABLED: 사용자가 슬라이더 드래그 시 볼륨 변경
                                onPressedChanged: {
                                    if (!pressed && bluetoothAudioPlayer) {
                                        console.log("[VolumeSlider] Setting volume to:", Math.round(value))
                                        bluetoothAudioPlayer.setVolume(Math.round(value))
                                    }
                                }
                                */

                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: volumeSlider.availableWidth
                                    height: 6
                                    radius: 3
                                    color: "#333333"

                                    Rectangle {
                                        width: volumeSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: "#8b5cf6"
                                        radius: 3
                                    }
                                }

                                handle: Rectangle {
                                    x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: volumeSlider.pressed ? "#ffffff" : "#f0f0f0"
                                    border.color: "#8b5cf6"
                                    border.width: 2
                                }
                            }

                            Text {
                                text: Math.round(volumeSlider.value) + "%"
                                color: "#999999"
                                font.pixelSize: 14
                                font.bold: true
                                Layout.preferredWidth: 45
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        // 연결 정보
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: qsTr("Connected to: ") + (bluetoothAudioPlayer ? bluetoothAudioPlayer.deviceName : "")
                            color: "#22c55e"
                            font.pixelSize: 12
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            // 로컬 MP3 플레이어 (Bluetooth 연결 안 됨)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"
                visible: !isBluetoothMode

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 24

                    Text {
                        text: "💿"
                        font.pixelSize: 80
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: qsTr("Local Music Player")
                        color: "#ffffff"
                        font.pixelSize: 24
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: qsTr("Connect Bluetooth for phone music")
                        color: "#999999"
                        font.pixelSize: 16
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Button {
                        id: bluetoothSettingsButton
                        Layout.alignment: Qt.AlignHCenter
                        width: 200
                        height: 48

                        background: Rectangle {
                            radius: 24
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: bluetoothSettingsButton.hovered ? "#2563eb" : "#3b82f6" }
                                GradientStop { position: 1.0; color: bluetoothSettingsButton.hovered ? "#1e40af" : "#2563eb" }
                            }
                        }

                        contentItem: Text {
                            text: qsTr("Go to Bluetooth Settings")
                            color: "#ffffff"
                            font.pixelSize: 15
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            musicScreen.backClicked()
                            // HomeScreen에서 Bluetooth 버튼 클릭하도록 신호 전달 필요
                        }
                    }
                }
            }
        }
    }

    function formatTime(ms) {
        var totalSeconds = Math.floor(ms / 1000)
        var minutes = Math.floor(totalSeconds / 60)
        var seconds = totalSeconds % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
    }
}
