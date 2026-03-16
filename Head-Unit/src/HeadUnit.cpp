#include "HeadUnit.h"

#include <QQmlContext>
#include <QUrl>
#include <QCoreApplication>
#include <QMetaObject>
#include <QProcess>
#include <QTimer>
#include <cstdlib>

HeadUnit::HeadUnit()
    : _engine(std::make_unique<QQmlApplicationEngine>())
    , _musicPlayer(std::make_shared<MusicPlayer>())
    , _gearClient(std::make_shared<GearClient>())
    , _weatherService(std::make_shared<WeatherService>())
    , _bluetoothManager(std::make_shared<BluetoothManager>())
    , _bluetoothAudioPlayer(std::make_shared<BluetoothAudioPlayer>())
    , _vehicleDataClient(std::make_shared<VehicleDataClient>()) {

    // Integrate BluetoothManager with BluetoothAudioPlayer
    _bluetoothManager->setAudioPlayer(_bluetoothAudioPlayer.get());
}

HeadUnit::~HeadUnit() = default;

void HeadUnit::setTimer(const std::string& name) {
    if (_timers.find(name) != _timers.end()) {
        return;
    }

    auto timer = std::make_unique<QTimer>();
    timer->setTimerType(Qt::CoarseTimer);
    _timers.emplace(name, std::move(timer));
}

void HeadUnit::removeTimer(const std::string& name) {
    auto it = _timers.find(name);
    if (it == _timers.end()) {
        return;
    }

    if (it->second) {
        it->second->stop();
    }
    _timers.erase(it);
}

void HeadUnit::connectTimerModel(const std::string& name, int interval, ViewModel& model,
                                 void (ViewModel::*slot)(const std::string&)) {
    if (interval <= 0) {
        return;
    }

    if (_timers.find(name) == _timers.end()) {
        setTimer(name);
    }

    auto& timerPtr = _timers[name];
    if (!timerPtr) {
        return;
    }

    timerPtr->setInterval(interval);
    timerPtr->setSingleShot(false);

    QObject::connect(timerPtr.get(), &QTimer::timeout, &model, [slot, &model, name]() {
        (model.*slot)(name);
    });

    timerPtr->start();
}

void HeadUnit::registerModel(const std::string& name, ViewModel& model) {
    if (!_engine) {
        _engine = std::make_unique<QQmlApplicationEngine>();
    }

    const QString identifier = QString::fromStdString(name);
    _engine->rootContext()->setContextProperty(identifier, &model);
}

void HeadUnit::loadQml(const std::string& path, QGuiApplication& app) {
    if (!_engine) {
        _engine = std::make_unique<QQmlApplicationEngine>();
    }

    _engine->rootContext()->setContextProperty(QStringLiteral("musicPlayer"), _musicPlayer.get());
    _engine->rootContext()->setContextProperty(QStringLiteral("gearClient"), _gearClient.get());
    _engine->rootContext()->setContextProperty(QStringLiteral("weatherService"), _weatherService.get());
    _engine->rootContext()->setContextProperty(QStringLiteral("bluetoothManager"), _bluetoothManager.get());
    _engine->rootContext()->setContextProperty(QStringLiteral("bluetoothAudioPlayer"), _bluetoothAudioPlayer.get());
    _engine->rootContext()->setContextProperty(QStringLiteral("vehicleDataClient"), _vehicleDataClient.get());

    if (_weatherService) {
        QMetaObject::invokeMethod(_weatherService.get(), &WeatherService::fetchWeather, Qt::QueuedConnection);
    }

    const QString sourceString = QString::fromStdString(path);
    const QUrl sourceUrl = sourceString.startsWith(QStringLiteral("qrc:/"))
                               ? QUrl(sourceString)
                               : QUrl::fromLocalFile(sourceString);

    QObject::connect(
        _engine.get(), &QQmlApplicationEngine::objectCreated, &app,
        [sourceUrl, this](QObject* obj, const QUrl& objUrl) {
            if (!obj && sourceUrl == objUrl) {
                QCoreApplication::exit(EXIT_FAILURE);
            } else if (obj && sourceUrl == objUrl) {
                // QML loaded successfully - quit Plymouth after first frame is rendered
                qDebug() << "[HeadUnit] QML loaded, scheduling Plymouth quit";
                QTimer::singleShot(500, this, &HeadUnit::quitPlymouth);
            }
        },
        Qt::QueuedConnection);

    _engine->load(sourceUrl);
}

void HeadUnit::quitPlymouth() {
    // Check if we should quit Plymouth
    QByteArray quitOnReady = qgetenv("PLYMOUTH_QUIT_ON_READY");
    if (quitOnReady.isEmpty() || quitOnReady == "0") {
        qDebug() << "[HeadUnit] Plymouth quit disabled (PLYMOUTH_QUIT_ON_READY not set)";
        return;
    }

    qDebug() << "[HeadUnit] Quitting Plymouth with smooth transition...";

    // Use plymouth quit with --retain-splash for smooth transition
    QProcess plymouthQuit;
    plymouthQuit.start("/usr/bin/plymouth", QStringList() << "quit" << "--retain-splash");

    if (!plymouthQuit.waitForStarted(1000)) {
        qWarning() << "[HeadUnit] Failed to start plymouth quit command";
        return;
    }

    if (!plymouthQuit.waitForFinished(3000)) {
        qWarning() << "[HeadUnit] Plymouth quit command timed out";
        plymouthQuit.kill();
        return;
    }

    qDebug() << "[HeadUnit] Plymouth quit successfully";
}
