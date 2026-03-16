import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent
    // Remove fixed dimensions, let it scale with parent

    property int actualSpeed: ViewModel.speed
    property int actualCapacity: ViewModel.capacity
    property string actualGear: ViewModel.driveMode

    Image {
        id: backGround
        source: "qrc:/asset/BackGround.png"
        sourceSize.height: 650
        sourceSize.width: 1024
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: 0
        anchors.bottomMargin: 0
        fillMode: Image.PreserveAspectFit
    }

    LeftCluster {
        id: leftCluster
        anchors.left: parent.left
        anchors.leftMargin: parent.width * 0.024    // roughly 46px at 1920
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        height: parent.height * 0.69

        speed: actualSpeed
    }

    RightCluster {
        id: rightCluster
        anchors.right: parent.right
        anchors.rightMargin: parent.width * 0.046   // (1920-1027-800)/1920 ≈ 0.046
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.42
        height: parent.height * 0.69

        capacity: actualCapacity
    }

    Item {
        id: middleSlot
        anchors {
            left: leftCluster.right
            right: rightCluster.left
            verticalCenter: parent.verticalCenter
        }

        Gear {
            id: gear

            anchors.centerIn: middleSlot
            width: middleSlot.width * 2
            height: width * (380/450)

            gear: actualGear
        }
        height: parent.height * 0.12
        anchors.leftMargin: 3
        anchors.rightMargin: -3
        anchors.verticalCenterOffset: parent.height * 0.33
    }

}
