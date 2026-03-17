cmake_minimum_required(VERSION 3.21)

project(HeadUnit
    VERSION 0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

include(GNUInstallDirs)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    QuickControls2
    Core5Compat
    Multimedia
    Network
    DBus
    Bluetooth
    Location
    Positioning
)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

set(HEADUNIT_SOURCES
    src/main.cpp
    src/HeadUnit.cpp
    src/ViewModel.cpp
    src/backend/music/music_player.cpp
    src/backend/gear/gear_client.cpp
    src/backend/weather/weather_service.cpp
    src/backend/bluetooth/bluetooth_manager.cpp
    src/backend/bluetooth/bluetooth_audio_player.cpp
    src/backend/bluetooth/bluetooth_agent.cpp
    src/backend/vehicle/vehicle_data_client.cpp
)

set(HEADUNIT_HEADERS
    src/HeadUnit.h
    src/ViewModel.h
    src/backend/music/music_player.h
    src/backend/gear/gear_client.h
    src/backend/weather/weather_service.h
    src/backend/bluetooth/bluetooth_manager.h
    src/backend/bluetooth/bluetooth_audio_player.h
    src/backend/bluetooth/bluetooth_agent.h
    src/backend/vehicle/vehicle_data_client.h
)

qt_add_executable(HeadUnitApp
    ${HEADUNIT_SOURCES}
    ${HEADUNIT_HEADERS}
)

qt_add_qml_module(HeadUnitApp
    URI HeadUnit
    VERSION 1.0
    QML_FILES
        ui/main.qml
        ui/components/BackButton.qml
        ui/components/GearSelector.qml
        ui/components/VehicleInfoWidget.qml
        ui/pages/HomeScreen.qml
        ui/pages/MusicScreen.qml
        ui/pages/AmbientScreen.qml
        ui/pages/ClimateScreen.qml
        ui/pages/BluetoothScreen.qml
        ui/pages/NavigationScreen.qml
    SOURCES
        ${HEADUNIT_SOURCES}
        ${HEADUNIT_HEADERS}
)

target_include_directories(HeadUnitApp
    PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/src"
)

target_link_libraries(HeadUnitApp
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Widgets
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Core5Compat
        Qt6::Multimedia
        Qt6::Network
        Qt6::DBus
        Qt6::Bluetooth
        Qt6::Location
        Qt6::Positioning
)

install(TARGETS HeadUnitApp
    BUNDLE DESTINATION .
    RUNTIME DESTINATION bin
)

install(DIRECTORY design/assets/
    DESTINATION ${CMAKE_INSTALL_DATADIR}/headunit/music
    FILES_MATCHING PATTERN "*.mp3"
)
