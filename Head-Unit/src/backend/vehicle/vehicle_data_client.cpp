#include "backend/vehicle/vehicle_data_client.h"

#include <QDBusConnection>
#include <QDBusReply>
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

VehicleDataClient::VehicleDataClient(QObject* parent)
    : QObject(parent)
    , iface_(QString::fromLatin1(ServiceName),
             QString::fromLatin1(ObjectPath),
             QString::fromLatin1(InterfaceName),
             vehicleDataBus())
    , speed_(0)
    , battery_(0)
    , signalsConnected_(false) {

    if (!iface_.isValid()) {
        qWarning() << "[VehicleDataClient] D-Bus interface invalid on"
                   << vehicleDataBusLabel() << "bus:"
                   << vehicleDataBus().lastError().message();
    }

    subscribeToSignals();
    fetchInitialData();
}

int VehicleDataClient::speed() const {
    return speed_;
}

int VehicleDataClient::battery() const {
    return battery_;
}

void VehicleDataClient::refresh() {
    fetchInitialData();
}

void VehicleDataClient::onVehicleDataChanged(int speed, int battery) {
    qDebug() << "[VehicleDataClient] Received D-Bus signal - Speed:" << speed
             << "Battery:" << battery;

    updateData(speed, battery);
}

void VehicleDataClient::subscribeToSignals() {
    if (signalsConnected_) {
        return;
    }

    if (!iface_.isValid()) {
        qWarning() << "[VehicleDataClient] Cannot subscribe; interface invalid";
        return;
    }

    QDBusConnection bus = vehicleDataBus();

    bool connected = bus.connect(
        QString::fromLatin1(ServiceName),
        QString::fromLatin1(ObjectPath),
        QString::fromLatin1(InterfaceName),
        QStringLiteral("VehicleDataChanged"),
        this,
        SLOT(onVehicleDataChanged(int, int)));

    if (!connected) {
        qWarning() << "[VehicleDataClient] Failed to connect to VehicleDataChanged signal on"
                   << vehicleDataBusLabel() << "bus:"
                   << bus.lastError().message();
        return;
    }

    signalsConnected_ = true;
    qDebug() << "[VehicleDataClient] Subscribed to VehicleDataChanged signal on"
             << vehicleDataBusLabel() << "bus";
}

void VehicleDataClient::fetchInitialData() {
    if (!iface_.isValid()) {
        qWarning() << "[VehicleDataClient] Cannot fetch data; interface invalid";
        return;
    }

    QDBusReply<QVariantMap> reply = iface_.call(QStringLiteral("GetVehicleData"));

    if (!reply.isValid()) {
        qWarning() << "[VehicleDataClient] GetVehicleData call failed:"
                   << reply.error().message();
        return;
    }

    QVariantMap data = reply.value();
    int speed = data.value("speed", 0).toInt();
    int battery = data.value("battery", 0).toInt();

    qDebug() << "[VehicleDataClient] Fetched initial data - Speed:" << speed
             << "Battery:" << battery;

    updateData(speed, battery);
}

void VehicleDataClient::updateData(int speed, int battery) {
    bool changed = false;

    if (speed_ != speed) {
        speed_ = speed;
        emit speedChanged();
        changed = true;
    }

    if (battery_ != battery) {
        battery_ = battery;
        emit batteryChanged();
        changed = true;
    }

    if (changed) {
        emit dataChanged(speed_, battery_);
        qDebug() << "[VehicleDataClient] Updated - Speed:" << speed_
                 << "Battery:" << battery_;
    }
}
