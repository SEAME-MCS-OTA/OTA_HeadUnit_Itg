import QtQuick
import QtQuick.Controls

Button {
    id: backButton
    width: 44
    height: 44

    signal goBack()

    background: Rectangle {
        radius: width / 2
        color: parent.hovered ? "#2a2a2a" : "#1a1a1a"
        border.color: "#333333"
        border.width: 1

        Behavior on color {
            ColorAnimation { duration: 150 }
        }
    }

    contentItem: Text {
        text: "‹"
        color: "#ffffff"
        font.pixelSize: 28
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    onClicked: goBack()
}
