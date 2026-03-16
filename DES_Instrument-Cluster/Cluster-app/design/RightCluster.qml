import QtQuick 2.15

Item {
    id: rightcluster

    property int capacity: 0

    // Outer shadow circle
    Image {
        id: rightOutCircle
        anchors.fill: parent
        source: "qrc:/asset/RightOutCircle.png"
        fillMode: Image.PreserveAspectFit
    }

    // Central blue circle
    Image {
        id: rightCircle
        width: parent.width * 0.61   // 490/800 ≈ 0.61
        height: parent.height * 0.65 // 485/750 ≈ 0.65
        anchors.centerIn: parent
        source: "qrc:/asset/RightCircle.png"
        fillMode: Image.PreserveAspectFit
    }

    // Capacity value text
    Text {
        anchors.centerIn: parent
        color: "#ffffff"
        text: Math.round(capacity)
        font.pixelSize: parent.height * 0.08  // Relative font size
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Unit text (mAh)
    Text {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.verticalCenter
            topMargin: parent.height * 0.1  // Relative positioning
        }
        color: "#d8d8d8"
        text: qsTr("%")
        font.pixelSize: parent.height * 0.047  // Relative font size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
