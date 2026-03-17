import QtQuick 6.5
import QtQuick.Controls 6.5
ApplicationWindow {
    visible: true; width: 1024; height: 600; title: "DES Head-Unit"
    Column {
        anchors.centerIn: parent; spacing: 16
        Label { text: "Hello, DES!"; font.pixelSize: 42 }
        Button { text: "Tap"; onClicked: console.log("Tap!") }
        Label { text: Qt.platform.os }
    }
}
