import QtQuick 2.15

Item {
    id: leftcluster
    visible: true

    property real speed: 0

    //화면에 부드럽게 표시될 값
    property real displayedSpeed: 0

    //튜닝 파라미터
    property int shortDuration: 100
    property int longDuration: 500
    property real decelThreshold: 150.0 //큰 감속으로 볼 변화량
    property int chosenDuration: longDuration

    // 숫자 변화를 부드럽게 만들어주는 애니메이션 객체
    Behavior on displayedSpeed {
        NumberAnimation {
            id: smoothAnimation
            duration: leftcluster.chosenDuration
            easing.type: Easing.InOutQuad // 시작과 끝을 부드럽게 처리
            alwaysRunToEnd: false //새 값 오면 애니메이션 즉시 중단
        }
    }

    // speed 속성(실제 값)이 변경될 때마다 자동으로 호출됨
    onSpeedChanged: {
        const d = Math.abs(speed - displayedSpeed)
        const decel = speed < displayedSpeed
        // 큰 감속이면 짧은 애니메이션, 그 외엔 긴 애니메이션
        chosenDuration = (decel && d >= decelThreshold) ? shortDuration : longDuration

        // Behavior가 알아서 현재→목표로 애니메이션하므로 start()/from/to 필요 없음
        displayedSpeed = speed             // 애니메이션 시작!
    }

    // Outer shadow circle
    Image {
        id: leftOutCircle
        anchors.fill: parent
        source: "qrc:/asset/LeftOutCircle.png"
        fillMode: Image.PreserveAspectFit
    }

    // Central blue circle
    Image {
        id: leftCircle
        // Make it proportional to the outer circle
        width: parent.width * 0.61   // 490/800 ≈ 0.61
        height: parent.height * 0.65 // 485/750 ≈ 0.65
        anchors.centerIn: parent
        source: "qrc:/asset/LeftCircle.png"
        fillMode: Image.PreserveAspectFit
    }

    // Speed value text
    Text {
        anchors.centerIn: parent
        color: "#ffffff"
        font.pixelSize: parent.height * 0.1  // Relative font size
        text: Math.floor(displayedSpeed)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.bold: true
    }
    
    // Unit text (cm/s)
    Text {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.verticalCenter
            topMargin: parent.height * 0.11  // Relative positioning below center
        }
        color: "#d7d8d9"
        text: qsTr("cm/s")
        font.pixelSize: parent.height * 0.053  // Relative font size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
