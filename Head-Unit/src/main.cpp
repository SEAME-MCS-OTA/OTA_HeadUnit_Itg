#include "HeadUnit.h"

#include <QDebug>
#include <QDir>
#include <QApplication>
#include <cstdlib>

int main(int argc, char *argv[]) {
    int appExit = EXIT_FAILURE;

    try {
        // Platform backend (xcb/wayland/eglfs) is controlled by systemd Environment= settings

        QApplication app(argc, argv);

        HeadUnit headUnit;
        ViewModel model;

        headUnit.registerModel("viewModel", model);

        const QString mainPage = QStringLiteral("qrc:/qt/qml/HeadUnit/ui/main.qml");
        qDebug() << "Loading QML file:" << mainPage;
        headUnit.loadQml(mainPage.toStdString(), app);

        appExit = app.exec();
    } catch (const std::exception& e) {
        qCritical() << "Application error:" << e.what();
    }

    return appExit;
}
