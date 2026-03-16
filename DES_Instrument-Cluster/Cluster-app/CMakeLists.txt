# Minimum version of CMake required
cmake_minimum_required(VERSION 3.16)

# Project name and language
project(IC_Project VERSION 0.1 LANGUAGES CXX)

# Target and directory path variables
set(TARGET_NAME appIC)
set(DIR_SRC ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(DIR_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(DIR_DESIGN ./design)

# Use the C++17 standard
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)

# Automatically run Qt's MOC, RCC, and UIC tools when needed
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTOUIC ON)

# Find the necessary Qt6 components. #you can row modules that you need
find_package(Qt6 REQUIRED COMPONENTS Core Gui  Quick Qml Network DBus)

qt_standard_project_setup(REQUIRES 6.8)

# Define the executable target.
# We will now add the .qrc files directly here.
qt_add_executable(${TARGET_NAME}
    ${DIR_SRC}/main.cpp
	${DIR_SRC}/InstrumentCluster.cpp
    ${DIR_SRC}/ViewModel.cpp
    ${DIR_SRC}/module/CanGateway.cpp
	${DIR_SRC}/module/BatteryMonitor.cpp
	${DIR_SRC}/module/BatterySoc.cpp
	${DIR_SRC}/module/INA219.cpp
	${DIR_SRC}/module/SharedMemory.cpp
	${DIR_SRC}/module/GearManager.cpp
	${DIR_SRC}/module/VehicleDataManager.cpp

	# ADDED: Directly add resource files to the executable.
	# This is the most reliable way to ensure they are compiled in.
	${DIR_DESIGN}/qml.qrc
)

# Define the QML module for your application.
# Updated QML_FILES paths to reflect new directory structure
qt_add_qml_module(${TARGET_NAME}
    URI IC_Project
    VERSION 1.0
    QML_FILES
        ${DIR_DESIGN}/Main.qml
        ${DIR_DESIGN}/InstrumentCluster.qml
        ${DIR_DESIGN}/Gear.qml
        ${DIR_DESIGN}/LeftCluster.qml
        ${DIR_DESIGN}/RightCluster.qml
	RESOURCES
		${DIR_DESIGN}/asset/dial.png
		${DIR_DESIGN}/asset/Gear.png
		${DIR_DESIGN}/asset/BackGround.png
		${DIR_DESIGN}/asset/LeftCircle.png
		${DIR_DESIGN}/asset/LeftOutCircle.png
		${DIR_DESIGN}/asset/needle-normal.png
		${DIR_DESIGN}/asset/RightCircle.png
		${DIR_DESIGN}/asset/RightOutCircle.png
		${DIR_DESIGN}/asset/Gear.png
    SOURCES
        ${DIR_SRC}/InstrumentCluster.h		${DIR_SRC}/InstrumentCluster.cpp
		${DIR_SRC}/ViewModel.h				${DIR_SRC}/ViewModel.cpp
        ${DIR_SRC}/module/CanGateway.h		${DIR_SRC}/module/CanGateway.cpp
		${DIR_SRC}/module/BatteryMonitor.h	${DIR_SRC}/module/BatteryMonitor.cpp
		${DIR_SRC}/module/BatterySoc.h		${DIR_SRC}/module/BatterySoc.cpp
		${DIR_SRC}/module/INA219.h			${DIR_SRC}/module/INA219.cpp
		${DIR_SRC}/module/SharedMemory.h	${DIR_SRC}/module/SharedMemory.cpp
		${DIR_SRC}/module/GearManager.h		${DIR_SRC}/module/GearManager.cpp
		${DIR_SRC}/module/VehicleDataManager.h	${DIR_SRC}/module/VehicleDataManager.cpp
)

# Tell CMake where to find our own header files and the json.hpp header.
target_include_directories(${TARGET_NAME} PRIVATE
    ${DIR_SRC}
	${DIR_SRC}/module
    ${DIR_INCLUDE}
    ${DIR_DESIGN}  # Added design directory for QML files
)

# Link the required Qt libraries to your application.
target_link_libraries(${TARGET_NAME}
    PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::Qml
        Qt6::Network
        Qt6::DBus
)

# --- This section is for macOS and Windows packaging ---
set_target_properties(${TARGET_NAME} PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# --- This section is for creating an installer ---
include(GNUInstallDirs)
install(TARGETS ${TARGET_NAME}
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
