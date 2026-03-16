#include "GearManager.h"

#include "SharedMemory.h"

#include <QDBusError>
#include <QDBusMessage>
#include <QVariant>
#include <QDebug>
#include <QtCore/qglobal.h>

namespace {
constexpr auto ServiceName = "com.des.vehicle";
constexpr auto ObjectPath = "/com/des/vehicle/Gear";
constexpr auto InterfaceName = "com.des.vehicle.Gear";

constexpr quint8 GearNeutral = 0;
constexpr quint8 GearDrive = 1;
constexpr quint8 GearReverse = 2;
constexpr quint8 GearPark = 3;

constexpr const char* UseSessionEnv = "DES_GEAR_USE_SESSION_BUS";

QDBusConnection gearBus() { //getter?
    if (qEnvironmentVariableIsSet(UseSessionEnv)) {
        return QDBusConnection::sessionBus();
    }
    return QDBusConnection::systemBus();
}

QString gearBusLabel() {
    return qEnvironmentVariableIsSet(UseSessionEnv) // criteria check
               ? QStringLiteral("session") //true - return session
               : QStringLiteral("system"); //false - return system
}
} // namespace

GearManager::GearManager(QObject* parent) //constructor for initialization
    : QObject(parent) {
    registered_ = registerOnBus();
}

GearManager::~GearManager() { //destructor for stop D-Bus service
    unregisterFromBus();
}

void GearManager::setVehicleMemory(const std::shared_ptr<SharedMemory>& vehicle) {
    vehicle_ = vehicle;  //what is shared_ptr type? -> smart pointer that shares an object
}

void GearManager::updateFromCluster(const QString& gear, const QString& source) {
    const quint8 code = gearStringToCode(gear);
    setCurrentGear(code, source);
}

QVariantList GearManager::RequestGear(quint8 gear, const QString& source) {
    const QString origin = sanitizeSource(source);
    if (!isAllowed(gear, source)) { //if gear is invalid
        emit GearRequestRejected(gear, QStringLiteral("invalid_gear"));
        return QVariantList{false, seq_, QStringLiteral("invalid_gear")};
    }

    bool changed = false;
    if (gear_ != gear) {
        gear_ = gear;
        changed = true;
        emit GearChanged(gear_, origin, ++seq_); //increase sequence number by 1 only when changed
    }
    
    writeGearToSharedMemory(gear);
    return QVariantList{true, seq_, QString()}; //this is weird whether gear is changed or not, return same thing
}

QVariantList GearManager::GetGear() const {
    return QVariantList{gear_, seq_};
}

bool GearManager::registerOnBus() {
    QDBusConnection bus = gearBus();
    if (!bus.isConnected()) {
        qWarning() << "[GearManager] Failed to connect to" << gearBusLabel() << "bus:"
                   << bus.lastError().message();
        return false;
    }

    if (!bus.registerService(QString::fromLatin1(ServiceName))) {
        const QDBusError error = bus.lastError();
        const bool serviceExists = (error.name() == QStringLiteral("org.freedesktop.DBus.Error.ServiceExists"));
        if (!serviceExists && error.type() != QDBusError::NoError) {
            qWarning() << "[GearManager] Failed to register service:"
                       << error.message();
            return false;
        }
        if (serviceExists) {
            qInfo() << "[GearManager] Service already registered on" << gearBusLabel()
                    << "bus; continuing";
        }
    }

    const bool objectRegistered = bus.registerObject(
        QString::fromLatin1(ObjectPath),
        this,
        QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);

    if (!objectRegistered) {
        qWarning() << "[GearManager] Failed to register object on" << gearBusLabel()
                   << "bus:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[GearManager] Registered D-Bus interface"
            << QString::fromLatin1(InterfaceName) << "on" << gearBusLabel() << "bus";
    return true;
}

void GearManager::unregisterFromBus() {
    if (!registered_) {
        return;
    }

    QDBusConnection bus = gearBus();
    bus.unregisterObject(QString::fromLatin1(ObjectPath)); //unregisterObject() from module what?
    bus.unregisterService(QString::fromLatin1(ServiceName));
    registered_ = false;
}

//just to check if the requested gear is valid("P,D,R,N") or not
bool GearManager::isAllowed(quint8 gear, const QString& source) const {
    Q_UNUSED(source);
    switch (gear) {
    case GearNeutral:
    case GearDrive:
    case GearReverse:
    case GearPark:
        return true;
    default:
        qWarning() << "[GearManager] Rejecting invalid gear code:" << gear;
        return false;
    }
}
//is there no uint8 instead of quint8 in C++ standard library? why do I have to use Qt type?
bool GearManager::setCurrentGear(quint8 gear, const QString& source) {
    if (gear == gear_) { //if gear is same, end function
        return false;
    }

    gear_ = gear; //if gear is different, change update member variable
    seq_ += 1; //sequence number increase by 1 this is for tracking changes

    emit GearChanged(gear_, source, seq_);
    return true;
}

//write gear code to SHM for Cluster to read
void GearManager::writeGearToSharedMemory(quint8 gear) {
    const auto vehicle = vehicle_.lock();
    if (!vehicle || !vehicle->isValid()) {
        return;
    }

    auto* data = static_cast<int*>(vehicle->getMemoryPtr());
    if (!data) {
        return;
    }

    // Map gear codes to ViewModel::drive_mode_e values (same order)
    *data = static_cast<int>(gear);
    vehicle->sync();
}

//I don't know what this function does exactly what is s sanitizing source? what is source? 
QString GearManager::sanitizeSource(const QString& source) const {
    const QString trimmed = source.trimmed();
    if (trimmed.isEmpty()) {
        return QStringLiteral("Unknown");
    }
    return trimmed.left(32);
}

//return gear(QString) to code(quint8)
quint8 GearManager::gearStringToCode(const QString& gear) const {
    const QString normalized = gear.trimmed().toUpper();
    if (normalized == QStringLiteral("N")) {
        return GearNeutral;
    }
    if (normalized == QStringLiteral("D")) {
        return GearDrive;
    }
    if (normalized == QStringLiteral("R")) {
        return GearReverse;
    }
    if (normalized == QStringLiteral("P")) {
        return GearPark;
    }

    qWarning() << "[GearManager] Unknown gear string:" << gear;
    return GearNeutral;
}
