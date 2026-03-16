import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "../components"

Item {
    id: ambientScreen

    signal backClicked()
    signal colorChanged(color selectedColor)
    signal brightnessChanged(real brightness)

    property color currentColor: "#8b5cf6"
    property real currentBrightness: 60

    property var colorPresets: [
        { name: qsTr("Polar White"), gradient: ["#e0f2fe", "#bae6fd"] },
        { name: qsTr("Silver Wave"), gradient: ["#cbd5e1", "#94a3b8"] },
        { name: qsTr("Cool Blue"), gradient: ["#3b82f6", "#60a5fa"] },
        { name: qsTr("Azure"), gradient: ["#06b6d4", "#22d3ee"] },
        { name: qsTr("Rose Gold"), gradient: ["#f43f5e", "#fb7185"] },
        { name: qsTr("Amber Glow"), gradient: ["#f59e0b", "#fbbf24"] },
        { name: qsTr("Royal Purple"), gradient: ["#8b5cf6", "#a855f7"] },
        { name: qsTr("Mystic Violet"), gradient: ["#a855f7", "#c084fc"] },
        { name: qsTr("Emerald"), gradient: ["#10b981", "#34d399"] },
        { name: qsTr("Mint"), gradient: ["#14b8a6", "#2dd4bf"] },
        { name: qsTr("Lime"), gradient: ["#84cc16", "#a3e635"] },
        { name: qsTr("Sunset"), gradient: ["#f97316", "#fb923c"] },
        { name: qsTr("Crimson"), gradient: ["#dc2626", "#ef4444"] },
        { name: qsTr("Hot Pink"), gradient: ["#ec4899", "#f472b6"] },
        { name: qsTr("Deep Blue"), gradient: ["#1e40af", "#3b82f6"] },
        { name: qsTr("Aurora"), gradient: ["#8b5cf6", "#06b6d4", "#10b981"] }
    ]

    property var zones: [
        { id: "all", name: qsTr("All"), icon: "🌐" },
        { id: "front", name: qsTr("Front"), icon: "⬆️" },
        { id: "rear", name: qsTr("Rear"), icon: "⬇️" },
        { id: "left", name: qsTr("Left"), icon: "⬅️" },
        { id: "right", name: qsTr("Right"), icon: "➡️" },
        { id: "dash", name: qsTr("Dash"), icon: "📊" }
    ]

    property int selectedZone: 0
    property int selectedPresetIndex: 6
    property var activeGradient: colorPresets.length > 0 ? colorPresets[selectedPresetIndex].gradient : [currentColor]

    function presetPrimaryColor(index) {
        if (index < 0 || index >= colorPresets.length)
            return currentColor;
        return colorPresets[index].gradient[0];
    }

    function presetSecondaryColor(index) {
        if (index < 0 || index >= colorPresets.length)
            return currentColor;
        const gradient = colorPresets[index].gradient;
        return gradient[gradient.length - 1];
    }

    function highlightColor(factor) {
        const base = currentBrightness <= 0 ? 0 : Math.max(0.08, currentBrightness / 160.0);
        return Qt.rgba(currentColor.r, currentColor.g, currentColor.b, Math.min(1, base * factor));
    }

    function currentZoneId() {
        return zones[selectedZone] ? zones[selectedZone].id : "all";
    }

    function zoneActive(area) {
        const id = currentZoneId();
        if (id === "all")
            return true;
        if (id === "front")
            return area === "front" || area === "dash";
        if (id === "rear")
            return area === "rear";
        if (id === "left")
            return area === "left";
        if (id === "right")
            return area === "right";
        if (id === "dash")
            return area === "dash";
        return false;
    }

    onSelectedPresetIndexChanged: {
        if (selectedPresetIndex >= 0 && selectedPresetIndex < colorPresets.length) {
            activeGradient = colorPresets[selectedPresetIndex].gradient;
            currentColor = activeGradient[0];
            colorChanged(currentColor);
        }
    }

    Component.onCompleted: {
        if (colorPresets.length > 0) {
            activeGradient = colorPresets[selectedPresetIndex].gradient;
            currentColor = activeGradient[0];
        }
        colorChanged(currentColor);
        brightnessChanged(currentBrightness);
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
                        onGoBack: ambientScreen.backClicked()
                    }

                    Text {
                        Layout.leftMargin: 16
                        text: qsTr("Ambient Light")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "💡"
                        font.pixelSize: 24
                        color: "#fbbf24"
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 20

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 12

                        Text {
                            text: qsTr("Preview")
                            color: "#ffffff"
                            font.pixelSize: 14
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 16
                            color: "#0f0f0f"
                            border.color: "#333333"
                            border.width: 1

                            Item {
                                id: previewCanvas
                                anchors.fill: parent
                                anchors.margins: 24

                                Rectangle {
                                    id: baseGlow
                                    anchors.centerIn: parent
                                    width: parent.width * 0.65
                                    height: parent.height * 0.55
                                    radius: 20
                                    clip: true

                                    gradient: Gradient {
                                        GradientStop {
                                            position: 0.0
                                            color: Qt.rgba(currentColor.r, currentColor.g, currentColor.b,
                                                           currentBrightness <= 0 ? 0
                                                                                  : Math.max(0.12, currentBrightness / 140.0))
                                        }
                                        GradientStop { position: 1.0; color: Qt.rgba(currentColor.r, currentColor.g, currentColor.b, 0.0) }
                                    }

                                    border.width: currentBrightness <= 0 ? 0 : 3
                                    border.color: Qt.rgba(currentColor.r, currentColor.g, currentColor.b,
                                                          currentBrightness <= 0 ? 0 : Math.max(0.2, currentBrightness / 120.0))

                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        blurEnabled: true
                                        blur: 0.8
                                        blurMax: 48
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "🚗"
                                        font.pixelSize: 80
                                        opacity: 0.25
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        height: parent.height * 0.45
                                        radius: parent.radius
                                        color: highlightColor(1.0)
                                        visible: zoneActive("front")
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        height: parent.height * 0.45
                                        radius: parent.radius
                                        color: highlightColor(0.9)
                                        visible: zoneActive("rear")
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * 0.5
                                        radius: parent.radius
                                        color: highlightColor(0.7)
                                        visible: zoneActive("left")
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * 0.5
                                        radius: parent.radius
                                        color: highlightColor(0.7)
                                        visible: zoneActive("right")
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        width: parent.width * 0.7
                                        height: parent.height * 0.2
                                        radius: parent.radius
                                        color: highlightColor(0.85)
                                        visible: zoneActive("dash")
                                    }
                                }

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: 20
                                    text: Math.round(currentBrightness) + "%"
                                    color: "#ffffff"
                                    font.pixelSize: 28
                                }
                            }
                        }

                        Text {
                            text: qsTr("Zones")
                            color: "#ffffff"
                            font.pixelSize: 14
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: zones

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40

                                    background: Rectangle {
                                        radius: 12
                                        color: selectedZone === index ? currentColor : (parent.hovered ? "#2a2a2a" : "#1a1a1a")
                                        border.color: selectedZone === index ? Qt.lighter(currentColor, 1.2) : "#333333"
                                        border.width: 1

                                        Behavior on color {
                                            ColorAnimation { duration: 150 }
                                        }
                                    }

                                    contentItem: RowLayout {
                                        spacing: 4

                                        Text {
                                            text: modelData.icon
                                            font.pixelSize: 14
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: modelData.name
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }

                                    onClicked: selectedZone = index
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 280
                        Layout.fillHeight: true
                        spacing: 20

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: qsTr("Color Presets")
                                color: "#ffffff"
                                font.pixelSize: 14
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 4
                                rowSpacing: 8
                                columnSpacing: 8

                                Repeater {
                                    model: colorPresets

                                    Rectangle {
                                        Layout.preferredWidth: 56
                                        Layout.preferredHeight: 56
                                        radius: 12

                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: modelData.gradient[0] }
                                            GradientStop { position: 1.0; color: modelData.gradient[modelData.gradient.length - 1] }
                                        }

                                        border.color: selectedPresetIndex === index ? "#ffffff" : "transparent"
                                        border.width: 2
                                        scale: selectedPresetIndex === index ? 1.05 : 1.0

                                        Behavior on scale {
                                            NumberAnimation { duration: 200 }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: selectedPresetIndex = index
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: qsTr("Brightness")
                                    color: "#ffffff"
                                    font.pixelSize: 14
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(currentBrightness) + "%"
                                    color: "#999999"
                                    font.pixelSize: 13
                                }
                            }

                            Slider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: currentBrightness

                                onValueChanged: {
                                    ambientScreen.currentBrightness = value
                                    ambientScreen.brightnessChanged(value)
                                }

                                background: Rectangle {
                                    x: brightnessSlider.leftPadding
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                    implicitHeight: 6
                                    width: brightnessSlider.availableWidth
                                    height: implicitHeight
                                    radius: 3
                                    color: "#333333"

                                    Rectangle {
                                        width: brightnessSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 3
                                        gradient: Gradient {
                                        GradientStop { position: 0.0; color: presetPrimaryColor(selectedPresetIndex) }
                                        GradientStop { position: 1.0; color: presetSecondaryColor(selectedPresetIndex) }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    implicitWidth: 24
                                    implicitHeight: 24
                                    radius: 12
                                    border.width: 3
                                    border.color: currentColor
                                    color: "#ffffff"
                                    x: brightnessSlider.leftPadding + brightnessSlider.visualPosition * (brightnessSlider.availableWidth - width)
                                    y: brightnessSlider.topPadding + brightnessSlider.availableHeight / 2 - height / 2
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: qsTr("Quick Actions")
                                color: "#ffffff"
                                font.pixelSize: 14
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: [
                                        { label: qsTr("Off"), value: 0 },
                                        { label: "50%", value: 50 },
                                        { label: qsTr("Max"), value: 100 }
                                    ]

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40

                                        background: Rectangle {
                                            radius: 12
                                            color: parent.hovered ? "#2a2a2a" : "#1a1a1a"
                                            border.color: "#333333"
                                            border.width: 1
                                        }

                                        contentItem: Text {
                                            text: modelData.label
                                            color: "#ffffff"
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: {
                                            ambientScreen.currentBrightness = modelData.value;
                                            brightnessSlider.value = modelData.value;
                                            ambientScreen.brightnessChanged(modelData.value);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
