#include "VehicleDataManager.h"
#include "../ViewModel.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QVariantMap>
#include <QDebug>

namespace {
// D-Bus constants
constexpr auto ServiceName = "com.des.vehicle";
constexpr auto ObjectPath = "/com/des/vehicle/VehicleData";
constexpr auto InterfaceName = "com.des.vehicle.VehicleData";

constexpr const char* UseSessionEnv = "DES_VEHICLE_USE_SESSION_BUS";

QDBusConnection vehicleDataBus() {
    if (qEnvironmentVariableIsSet(UseSessionEnv)) {
        return QDBusConnection::sessionBus();
    }
    return QDBusConnection::systemBus();
}

QString vehicleDataBusLabel() {
    return qEnvironmentVariableIsSet(UseSessionEnv)
               ? QStringLiteral("session")
               : QStringLiteral("system");
}
} // namespace

VehicleDataManager::VehicleDataManager(QObject* parent)
    : QObject(parent)
    , viewModel_(nullptr)
    , registered_(false)
    , lastSpeed_(0)
    , lastBattery_(0) {

    registerOnBus();
}

VehicleDataManager::~VehicleDataManager() {
    unregisterFromBus();
}

void VehicleDataManager::setViewModel(ViewModel* viewModel) {
    if (viewModel_) {
        disconnect(viewModel_, nullptr, this, nullptr);
    }

    viewModel_ = viewModel;

    if (viewModel_) {
        connect(viewModel_, &ViewModel::updateSpeed,
                this, &VehicleDataManager::onViewModelDataChanged);
        connect(viewModel_, &ViewModel::updateCapacity,
                this, &VehicleDataManager::onViewModelDataChanged);

        // Initialize with current values
        lastSpeed_ = viewModel_->speed();
        lastBattery_ = viewModel_->capacity();
    }
}

QVariantMap VehicleDataManager::GetVehicleData() const {
    QVariantMap data;
    if (viewModel_) {
        data["speed"] = viewModel_->speed();
        data["battery"] = viewModel_->capacity();
    } else {
        data["speed"] = 0;
        data["battery"] = 0;
    }

    qDebug() << "[VehicleDataManager] GetVehicleData called - Speed:"
             << data["speed"] << "Battery:" << data["battery"];

    return data;
}

void VehicleDataManager::onViewModelDataChanged() {
    if (!viewModel_) {
        return;
    }

    int currentSpeed = viewModel_->speed();
    int currentBattery = viewModel_->capacity();

    // Only emit signal if values changed
    if (currentSpeed != lastSpeed_ || currentBattery != lastBattery_) {
        lastSpeed_ = currentSpeed;
        lastBattery_ = currentBattery;

        qDebug() << "[VehicleDataManager] Emitting VehicleDataChanged - Speed:"
                 << currentSpeed << "Battery:" << currentBattery;

        emit VehicleDataChanged(currentSpeed, currentBattery);
    }
}

bool VehicleDataManager::registerOnBus() {
    if (registered_) {
        qWarning() << "[VehicleDataManager] Already registered on D-Bus";
        return true;
    }

    QDBusConnection bus = vehicleDataBus();

    // Register object
    if (!bus.registerObject(QString::fromLatin1(ObjectPath), this,
                            QDBusConnection::ExportAllSlots |
                            QDBusConnection::ExportAllSignals)) {
        qWarning() << "[VehicleDataManager] Failed to register object on"
                   << vehicleDataBusLabel() << "bus:"
                   << bus.lastError().message();
        return false;
    }

    // Register service
    if (!bus.registerService(QString::fromLatin1(ServiceName))) {
        qWarning() << "[VehicleDataManager] Failed to register service on"
                   << vehicleDataBusLabel() << "bus:"
                   << bus.lastError().message();
        bus.unregisterObject(QString::fromLatin1(ObjectPath));
        return false;
    }

    registered_ = true;
    qDebug() << "[VehicleDataManager] Successfully registered on"
             << vehicleDataBusLabel() << "bus";

    return true;
}

void VehicleDataManager::unregisterFromBus() {
    if (!registered_) {
        return;
    }

    QDBusConnection bus = vehicleDataBus();
    bus.unregisterObject(QString::fromLatin1(ObjectPath));
    bus.unregisterService(QString::fromLatin1(ServiceName));

    registered_ = false;
    qDebug() << "[VehicleDataManager] Unregistered from D-Bus";
}
