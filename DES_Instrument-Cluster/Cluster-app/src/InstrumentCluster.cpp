#include "InstrumentCluster.h"

#include <QQmlContext>
#include <QFile>
#include <QDebug>

#include <algorithm>

/* CON & DESTRUCTOR */
InstrumentCluster::InstrumentCluster()
	: _engine(std::make_unique<QQmlApplicationEngine>())
	, _gearManager(std::make_shared<GearManager>())
	, _vehicleDataManager(std::make_shared<VehicleDataManager>()) {

	try {
		_battery = std::make_shared<BatteryMonitor>();
		_vehicle = std::make_shared<SharedMemory>("piracer_drive_mode", SIZE_INT);
	} catch (std::exception& e) {
		qWarning() << "Fail to load module " << QString::fromStdString(e.what());
	}

	if (_gearManager && _vehicle && _vehicle->isValid()) {
		_gearManager->setVehicleMemory(_vehicle);
	}
}

InstrumentCluster::~InstrumentCluster() {
	for (const auto& pair : _threads) {
		closeCan(pair.first);
	}
}

/* METHODS - Timer */
void InstrumentCluster::setTimer(const std::string& name) {
	auto it = _timers.find(name);
	if (_validTimer(it, 0)) {
		qDebug() << "[IC] Setting timer for" << QString::fromStdString(name);
		_timers[name] = std::make_unique<QTimer>();
	}
}

void InstrumentCluster::removeTimer(const std::string& name) {
	auto it = _timers.find(name);
	if (_validTimer(it, 1)) {
		_timers.erase(it);
	}
}

void InstrumentCluster::connectTimerModel(const std::string& name, int time, ViewModel& model,
	void (ViewModel::*&& slot)(const std::string&)) {

	auto it = _timers.find(name);
	if (_validTimer(it, 1)) {
		QObject::connect(it->second.get(), &QTimer::timeout, &model, [&model, slot, name]() {
			(model.*slot)(name);
		});

		// Let the timer begin :)
		it->second->start(time);
	}
}

bool InstrumentCluster::_validTimer(std::unordered_map<std::string, std::unique_ptr<QTimer>>::iterator it, int flag) {
	if (flag == 0 && it != _timers.end()) {
		qDebug() << "[IC] Timer already exist";
		return false;
	} else if (flag == 1 && it == _timers.end()) {
		qDebug() << "[IC] Timer not found";
		return false;
	}
	return true;
}

/* METHODS - CAN Communication */
bool InstrumentCluster::openCan(const std::string& ifname) {
	try {
		if (_findCan(ifname)) {
			qWarning() << "[IC] Gateway for" << QString::fromStdString(ifname) << "already exists";
			return true;
		}
		
		_openCanCreate(ifname);
		_openCanSetSignals(_can.back(), _threads[ifname], ifname);

		// Let the worker begin :)
		_threads[ifname]->start();
		
		qInfo() << "[IC] CAN Gateway opened for interface:" << QString::fromStdString(ifname);
		return true;
		
	} catch (const std::exception& e) {
		qCritical() << "[IC] Failed to open gateway for" << QString::fromStdString(ifname) << ":" << e.what();
		
		auto it = _threads.find(ifname);
		if (it != _threads.end()) {
			_threads.erase(it);
		}
		return false;
	}
}

void InstrumentCluster::_openCanCreate(const std::string& ifname) {
	// Instanciate gatewad worker
	_can.emplace_back(new CanGateway(ifname));

	// Instanciate thread and move the gateway worker to thread
	_threads[ifname] = QThread_ptr(std::make_unique<QThread>());
	_can.back()->moveToThread(_threads[ifname].get());
}

void InstrumentCluster::_openCanSetSignals(InstrumentCluster::CanGateway_ptr& gateway,
	InstrumentCluster::QThread_ptr& thread, const std::string& ifname) {
		
	// Connect thread management signals
	QObject::connect(thread.get(), &QThread::started, gateway.get(), &CanGateway::start);
	QObject::connect(gateway.get(), &CanGateway::finished, thread.get(), &QThread::quit);

	// Connect status signals
	QObject::connect(gateway.get(), &CanGateway::connected, [ifname]() {
		qInfo() << "[IC] CAN Gateway activated:" << QString::fromStdString(ifname);
	});
	QObject::connect(gateway.get(), &CanGateway::disconnected, [ifname]() {
		qInfo() << "[IC] CAN Gateway deactivated:" << QString::fromStdString(ifname);
	});
	
	// Connect error handling
	QObject::connect(gateway.get(), &CanGateway::error, [ifname](const QString& error) {
		qCritical() << "[IC] CAN Gateway error on" << QString::fromStdString(ifname) << ":" << error;
	});
}

void InstrumentCluster::closeCan(const std::string& ifname) {
	const auto& gateway = _findCan(ifname);
	if (!gateway) {
		qWarning() << "[IC] No gateway found for CAN interface:" << QString::fromStdString(ifname);
		return;
	}

	// Stop the gateway
	gateway->stop();

	// Handle thread cleanup
	auto it = _threads.find(ifname);
	if (it != _threads.end()) {
		const auto& thread = it->second;

		if (thread->isRunning()) {
			thread->quit();
			thread->wait(CLOSE_WAIT);
			
			if (thread->isRunning()) {
				qWarning() << "[IC] Thread for" << QString::fromStdString(ifname) 
						<< "did not stop gracefully, terminating...";
				thread->terminate();
				thread->wait(FORCE_WAIT);
			}
		}
		_threads.erase(it);
	}

	_can.remove_if([&ifname](const CanGateway_ptr& ptr) {
		return ptr && ptr->ifname == ifname;
	});

	qInfo() << "[IC] CAN Gateway closed for interface:" << QString::fromStdString(ifname);
}

void InstrumentCluster::connectCanModel(const std::string& interface, ViewModel& model,
	void (ViewModel::*&& slot)(int, const QByteArray&)) {

	const auto& gateway = _findCan(interface);
	if (!gateway) {
		qWarning() << "No gateway found for CAN interface:" << QString::fromStdString(interface);
		return;
	}
	
	QObject::connect(gateway.get(), &CanGateway::newData, &model, slot, Qt::QueuedConnection);
}

const InstrumentCluster::CanGateway_ptr&
	InstrumentCluster::_findCan(const std::string& interface) const {

	for (const auto& gateway : _can) {
		if (gateway && gateway->ifname == interface) {
			return gateway;
		}
	}
	// Return a null reference - this will be checked by the caller
	static CanGateway_ptr nullPtr;
	return nullPtr;
}

/* METHODS - Running */
void InstrumentCluster::registerModel(const std::string& name, ViewModel& model) {
	_engine->rootContext()->setContextProperty(QString::fromStdString(name), &model);
	qInfo() << "[IC] ViewModel registered as:" << QString::fromStdString(name);
}

void InstrumentCluster::loadQml(const std::string& qmlEntry, QGuiApplication& app) {
	const QUrl url(QString::fromStdString(qmlEntry));
	if (!url.isValid() || url.isEmpty()) {
		qCritical() << "[IC] QML entry path is invalid:" << QString::fromStdString(qmlEntry);
		return;
	}
	if (url.isLocalFile()) { 
		if (!QFile::exists(url.toLocalFile())) {
			qCritical() << "[IC] QML file does not exist at path:" << url.toLocalFile();
			return;
		}
	}

	QObject::connect(_engine.get(), &QQmlApplicationEngine::objectCreated, &app,
		[url](QObject *obj, const QUrl &objUrl) {
			if (!obj && url == objUrl) 
				QCoreApplication::exit(EXIT_FAILURE);
		},
		Qt::QueuedConnection);
	
	_engine->load(url);
	qInfo() << "[IC] QML file loaded:" << QString::fromStdString(qmlEntry);
}
