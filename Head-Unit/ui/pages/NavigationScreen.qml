import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtLocation
import QtPositioning
import "../components"

Item {
    id: navigationScreen

    signal backClicked()

    property string destinationName: qsTr("Ansan-si Danwon-gu Gwangdeokseoro 19")
    property string eta: qsTr("12:24")
    property string distance: qsTr("23 km")
    property var defaultCenter: QtPositioning.coordinate(37.306234942517, 126.82656780115)

    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter { name: "osm.mapping.host"; value: "https://tile.openstreetmap.org/" }
        PluginParameter { name: "osm.mapping.highdpi_tiles"; value: true }
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
                        onGoBack: navigationScreen.backClicked()
                    }

                    Text {
                        Layout.leftMargin: 16
                        text: qsTr("Navigation")
                        color: "#ffffff"
                        font.pixelSize: 22
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 20
                    radius: 24
                    color: "#05070d"
                    border.color: "#111827"
                    border.width: 1
                    clip: true

                    Map {
                        id: mapView
                        anchors.fill: parent
                        anchors.margins: 0
                        plugin: osmPlugin
                        center: defaultCenter
                        zoomLevel: 13
                        copyrightsVisible: true
                        // gesture.enabled: true  // Removed: Qt 6 deprecated gesture property
                        minimumZoomLevel: 3
                        maximumZoomLevel: 19
                        activeMapType: supportedMapTypes.length > 0 ? supportedMapTypes[0] : null
                    }

                    MapQuickItem {
                        coordinate: mapView.center
                        anchorPoint: Qt.point(10, 10)
                        sourceItem: Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: "#22d3ee"
                            border.color: "#e0f2fe"
                            border.width: 2
                            opacity: 0.95

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                running: true
                                NumberAnimation { from: 1.0; to: 1.15; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 1.15; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 80
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(0.0, 0.0, 0.0, 0.28) }
                            GradientStop { position: 1.0; color: Qt.rgba(0.0, 0.0, 0.0, 0.0) }
                        }
                        visible: true
                    }

                    Rectangle {
                        id: infoBar
                        width: parent.width
                        height: 72
                        radius: 18
                        color: "#0b1220"
                        border.color: "#1f2937"
                        border.width: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 12
                        anchors.margins: 12
                        opacity: 0.95

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: qsTr("Drag to explore • Starting at Ansan-si Danwon-gu Gwangdeokseoro 19")
                                    color: "#e5e7eb"
                                    font.pixelSize: 16
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: destinationName
                                    color: "#9ca3af"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            ColumnLayout {
                                spacing: 2

                                Text {
                                    text: distance
                                    color: "#38bdf8"
                                    font.pixelSize: 18
                                    font.bold: true
                                }

                                Text {
                                    text: qsTr("ETA ") + eta
                                    color: "#9ca3af"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: mapView.error !== Map.NoError
                              ? qsTr("Unable to load the map. Check your network connection.")
                              : ""
                        color: "#ffffff"
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        width: parent.width * 0.7
                        visible: mapView.error !== Map.NoError
                        z: 2
                    }
                }
            }
        }
    }
}
