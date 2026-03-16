import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: gearSelector
    radius: height / 2
    color: "#0a0a0a"
    border.color: "#333333"
    border.width: 1

    property var gears: ["P", "R", "N", "D"]
    property string currentGear: "P"
    signal gearChanged(string gear)

    readonly property var gearColors: ({
        "P": "#ef4444",
        "R": "#f59e0b",
        "N": "#3b82f6",
        "D": "#10b981"
    })

    RowLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 4

        Repeater {
            model: gears

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: height / 2
                color: gearSelector.currentGear === modelData ? gearSelector.gearColors[modelData] : "transparent"

                Behavior on color {
                    ColorAnimation { duration: 200 }
                }

                Text {
                    anchors.centerIn: parent
                    text: modelData
                    color: gearSelector.currentGear === modelData ? "#ffffff" : "#666666"
                    font.pixelSize: 14
                    font.bold: gearSelector.currentGear === modelData

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (gearSelector.currentGear !== modelData) {
                            gearSelector.gearChanged(modelData)
                        }
                    }
                }
            }
        }
    }
}
