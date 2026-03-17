import QtQuick 2.15
import QtQuick.Window 2.15

Window {
    id: win
    width: 960
    height: 1080
    x: 0
    y: 0
    visible: true
    visibility: Window.Windowed
    flags: Qt.FramelessWindowHint
    title: qsTr("Instrument Cluster")

    InstrumentCluster {
        id: instrumentCluster
        anchors.fill: parent
        anchors.margins: 0  // Add some padding if needed
    }
}
