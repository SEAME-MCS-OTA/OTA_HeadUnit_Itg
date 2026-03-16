import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: climateScreen

    signal backClicked()

    property var weatherProvider: weatherService
    property real temperature: 22
    property int fanSpeed: 3
    property bool autoMode: true
    property bool acEnabled: true
    property bool recirculation: false
    property bool defrost: false
    property string lastWeatherError: ""

    function clampTemperature(value) {
        return Math.max(16, Math.min(30, value));
    }

    function isNumber(value) {
        return typeof value === "number" && !isNaN(value);
    }

    function formatNumber(value, decimals, suffix) {
        return isNumber(value) ? value.toFixed(decimals) + suffix : "--";
    }

    Component.onCompleted: {
        if (weatherProvider) {
            weatherProvider.fetchWeather();
        }
    }

    onWeatherProviderChanged: {
        lastWeatherError = "";
        if (weatherProvider) {
            weatherProvider.fetchWeather();
        }
    }

    Connections {
        target: weatherProvider

        function onErrorOccurred(message) {
            lastWeatherError = message;
        }
    }

    onVisibleChanged: {
        if (visible && weatherProvider) {
            lastWeatherError = "";
            weatherProvider.fetchWeather();
        }
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
                        onGoBack: climateScreen.backClicked()
                    }

                    Text {
                        Layout.leftMargin: 16
                        text: qsTr("Climate Control")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "🌡"
                        font.pixelSize: 24
                        color: "#60a5fa"
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 24

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 20

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 240
                            radius: 20
                            color: "#0f0f0f"
                            border.color: "#333333"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: qsTr("Interior")
                                        color: "#999999"
                                        font.pixelSize: 14
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        width: 60
                                        height: 28
                                        radius: 14
                                        color: autoMode ? "#10b981" : "#333333"

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "AUTO"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: autoMode = !autoMode
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: temperature.toFixed(1) + "°C"
                                    color: "#ffffff"
                                    font.pixelSize: 54
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: qsTr("Outside %1").arg(formatNumber(weatherProvider ? weatherProvider.temperature : NaN, 1, "°C"))
                                    color: "#666666"
                                    font.pixelSize: 14
                                }

                                Item { Layout.fillHeight: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52

                                        background: Rectangle {
                                            radius: 12
                                            color: parent.hovered ? "#1e3a8a" : "#1e40af"
                                            opacity: 0.35
                                        }

                                    contentItem: Text {
                                            text: "−"
                                            color: "#ffffff"
                                            font.pixelSize: 28
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: temperature = clampTemperature(temperature - 0.5)
                                    }

                                    Button {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52

                                        background: Rectangle {
                                            radius: 12
                                            color: parent.hovered ? "#991b1b" : "#b91c1c"
                                            opacity: 0.35
                                        }

                                        contentItem: Text {
                                            text: "+"
                                            color: "#ffffff"
                                            font.pixelSize: 28
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onClicked: temperature = clampTemperature(temperature + 0.5)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            radius: 20
                            color: "#0f0f0f"
                            border.color: "#333333"
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 24
                                spacing: 16

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        text: qsTr("Fan Speed")
                                        color: "#ffffff"
                                        font.pixelSize: 16
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: fanSpeed
                                        color: "#999999"
                                        font.pixelSize: 14
                                    }
                                }

                                Slider {
                                    id: fanSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 5
                                    stepSize: 1
                                    value: fanSpeed

                                    onValueChanged: {
                                        const rounded = Math.round(value);
                                        if (fanSpeed !== rounded) {
                                            fanSpeed = rounded;
                                        }
                                        if (fanSlider.value !== rounded) {
                                            fanSlider.value = rounded;
                                        }
                                    }

                                    background: Rectangle {
                                        x: fanSlider.leftPadding
                                        y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                                        width: fanSlider.availableWidth
                                        height: 6
                                        radius: 3
                                        color: "#333333"

                                        Rectangle {
                                            width: fanSlider.visualPosition * parent.width
                                            height: parent.height
                                            radius: 3
                                            color: "#60a5fa"
                                        }
                                    }

                                    handle: Rectangle {
                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: 11
                                        color: "#ffffff"
                                        border.width: 3
                                        border.color: "#60a5fa"
                                        x: fanSlider.leftPadding + fanSlider.visualPosition * (fanSlider.availableWidth - width)
                                        y: fanSlider.topPadding + fanSlider.availableHeight / 2 - height / 2
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: 5

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 18
                                            radius: 9
                                            color: index < fanSpeed ? "#60a5fa" : "#1f2937"
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Repeater {
                                model: [
                                    { label: qsTr("A/C"), property: "acEnabled" },
                                    { label: qsTr("Recirculation"), property: "recirculation" },
                                    { label: qsTr("Defrost"), property: "defrost" }
                                ]

                                Button {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 52

                                    background: Rectangle {
                                        radius: 12
                                        color: climateScreen[modelData.property] ? "#8b5cf6" : "#1a1a1a"
                                        border.color: "#333333"
                                        border.width: 1
                                    }

                                    contentItem: Text {
                                        text: modelData.label
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    onClicked: climateScreen[modelData.property] = !climateScreen[modelData.property]
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 360
                        Layout.fillHeight: true
                        spacing: 20

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 120
                            radius: 20
                            color: "#0f0f0f"
                            border.color: "#333333"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 16

                                Text {
                                    text: weatherProvider && weatherProvider.icon.length ? weatherProvider.icon : "🌡"
                                    font.pixelSize: 42
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: qsTr("Outside Weather")
                                        color: "#999999"
                                        font.pixelSize: 13
                                    }

                                    Text {
                                        text: lastWeatherError.length
                                              ? lastWeatherError
                                              : (weatherProvider && weatherProvider.condition.length
                                                 ? weatherProvider.condition
                                                 : qsTr("Updating..."))
                                        color: lastWeatherError.length ? "#f87171" : "#ffffff"
                                        font.pixelSize: 20
                                    }

                                    Text {
                                        text: formatNumber(weatherProvider ? weatherProvider.windSpeed : NaN, 1, " km/h")
                                              + " • "
                                              + formatNumber(weatherProvider ? weatherProvider.precipitation : NaN, 1, " mm")
                                        color: "#666666"
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: 12
                            columnSpacing: 12

                            Repeater {
                                model: [
                                    { icon: "💧", label: qsTr("Humidity"), value: formatNumber(weatherProvider ? weatherProvider.humidity : NaN, 0, "%") },
                                    { icon: "💨", label: qsTr("Wind"), value: formatNumber(weatherProvider ? weatherProvider.windSpeed : NaN, 1, " km/h") },
                                    { icon: "🌧", label: qsTr("Precipitation"), value: formatNumber(weatherProvider ? weatherProvider.precipitation : NaN, 1, " mm") },
                                    { icon: "🌡", label: qsTr("Outside Temp"), value: formatNumber(weatherProvider ? weatherProvider.temperature : NaN, 1, "°C") }
                                ]

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 90
                                    radius: 14
                                    color: "#0f0f0f"
                                    border.color: "#333333"
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: modelData.icon
                                            font.pixelSize: 24
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: modelData.value
                                            color: "#ffffff"
                                            font.pixelSize: 16
                                            Layout.alignment: Qt.AlignHCenter
                                        }

                                        Text {
                                            text: modelData.label
                                            color: "#666666"
                                            font.pixelSize: 11
                                            Layout.alignment: Qt.AlignHCenter
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
