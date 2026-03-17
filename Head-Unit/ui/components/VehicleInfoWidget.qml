import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: vehicleInfoWidget
    radius: 16
    color: "#1a1a1a"
    border.color: "#333333"
    border.width: 1

    property int speedKmh: vehicleDataClient ? vehicleDataClient.speed : 0
    property int batteryPercent: vehicleDataClient ? vehicleDataClient.battery : 0
    property int rangeKm: 420

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "🏎"
                        font.pixelSize: 26
                        color: "#60a5fa"
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: vehicleInfoWidget.speedKmh
                        color: "#ffffff"
                        font.pixelSize: 30
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("km/h")
                        color: "#666666"
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#333333"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "🔋"
                        font.pixelSize: 26
                        color: "#10b981"
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: batteryPercent + "%"
                        color: "#ffffff"
                        font.pixelSize: 30
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Battery")
                        color: "#666666"
                        font.pixelSize: 11
                    }
                }
            }

            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#333333"
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "⚡"
                        font.pixelSize: 26
                        color: "#fbbf24"
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: rangeKm
                        color: "#ffffff"
                        font.pixelSize: 30
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("km range")
                        color: "#666666"
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
