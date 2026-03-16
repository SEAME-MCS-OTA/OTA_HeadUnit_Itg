#include "bluetooth_manager.h"
#include "bluetooth_audio_player.h"
#include "bluetooth_agent.h"
#include <QDebug>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusMessage>
#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusVariant>

BluetoothManager::BluetoothManager(QObject* parent)
    : QObject(parent)
    , localDevice_(std::make_unique<QBluetoothLocalDevice>(this))
    , agent_(nullptr)
    , connectionCheckTimer_(new QTimer(this))
    , autoReconnectTimer_(new QTimer(this)) {

    qDBusRegisterMetaType<QVariantMap>();

    initializeLocalDevice();
    initializeAgent();
    loadSavedDevices();

    // Auto-reconnect timer
    autoReconnectTimer_->setInterval(5000); // Try every 5 seconds
    connect(autoReconnectTimer_, &QTimer::timeout, this, &BluetoothManager::attemptAutoReconnect);

    if (localDevice_->isValid()) {
        connect(localDevice_.get(), &QBluetoothLocalDevice::pairingFinished,
                this, &BluetoothManager::handlePairingFinished);
        connect(localDevice_.get(), &QBluetoothLocalDevice::errorOccurred,
                this, &BluetoothManager::handlePairingError);
        connect(localDevice_.get(), &QBluetoothLocalDevice::hostModeStateChanged,
                this, &BluetoothManager::handleHostModeChanged);
    }

    // Check for connections every 2 seconds
    connectionCheckTimer_->setInterval(2000);
    connect(connectionCheckTimer_, &QTimer::timeout, this, &BluetoothManager::checkConnectionStatus);
    connectionCheckTimer_->start();
}

BluetoothManager::~BluetoothManager() {}

bool BluetoothManager::isBluetoothAvailable() const {
    return bluetoothAvailable_;
}

bool BluetoothManager::isBluetoothPowered() const {
    return bluetoothPowered_;
}

void BluetoothManager::setBluetoothPowered(bool powered) {
    if (!bluetoothAvailable_) {
        qWarning() << "[BluetoothManager] Cannot set power - Bluetooth not available";
        emit errorOccurred(tr("Bluetooth adapter not available"));
        return;
    }

    if (bluetoothPowered_ == powered) {
        qDebug() << "[BluetoothManager] Bluetooth already in requested state:" << powered;
        return;
    }

    qDebug() << "[BluetoothManager] Setting Bluetooth power:" << powered;

    if (powered) {
        qDebug() << "[BluetoothManager] Powering on and setting connectable mode";
        localDevice_->powerOn();
        localDevice_->setHostMode(QBluetoothLocalDevice::HostConnectable);

        bluetoothPowered_ = true;
        emit bluetoothPoweredChanged();
    } else {
        qDebug() << "[BluetoothManager] Powering off";
        stopBroadcasting();
        disconnectDevice();
        localDevice_->setHostMode(QBluetoothLocalDevice::HostPoweredOff);

        bluetoothPowered_ = false;
        emit bluetoothPoweredChanged();
    }
}

bool BluetoothManager::isBroadcasting() const {
    return broadcasting_;
}

QVariantList BluetoothManager::savedDevices() const {
    return savedDevicesVariant_;
}

QString BluetoothManager::connectedDeviceName() const {
    return connectedDeviceName_;
}

QString BluetoothManager::connectedDeviceAddress() const {
    return connectedDeviceAddress_;
}

bool BluetoothManager::isConnected() const {
    return !connectedDeviceAddress_.isEmpty();
}

QObject* BluetoothManager::agent() const {
    return agent_;
}

bool BluetoothManager::autoReconnect() const {
    return autoReconnect_;
}

void BluetoothManager::setAutoReconnect(bool enabled) {
    if (autoReconnect_ == enabled) {
        return;
    }

    autoReconnect_ = enabled;

    QSettings settings("DesGear", "HeadUnit");
    settings.setValue("bluetooth/autoReconnect", enabled);

    if (enabled && !connectedDeviceAddress_.isEmpty() == false && !preferredDeviceAddress_.isEmpty()) {
        // Start trying to reconnect if disconnected
        autoReconnectTimer_->start();
    } else {
        autoReconnectTimer_->stop();
        reconnectAttempts_ = 0;
    }

    emit autoReconnectChanged();
    qDebug() << "[BluetoothManager] Auto-reconnect" << (enabled ? "enabled" : "disabled");
}

QString BluetoothManager::preferredDeviceAddress() const {
    return preferredDeviceAddress_;
}

void BluetoothManager::setPreferredDeviceAddress(const QString& address) {
    if (preferredDeviceAddress_ == address) {
        return;
    }

    preferredDeviceAddress_ = address;

    QSettings settings("DesGear", "HeadUnit");
    settings.setValue("bluetooth/preferredDevice", address);

    emit preferredDeviceChanged();
    qDebug() << "[BluetoothManager] Preferred device set to:" << address;
}

void BluetoothManager::setAudioPlayer(BluetoothAudioPlayer* player) {
    audioPlayer_ = player;
    qDebug() << "[BluetoothManager] Audio player integrated";
}

void BluetoothManager::startBroadcasting() {
    if (!bluetoothAvailable_ || !bluetoothPowered_) {
        emit errorOccurred(tr("Bluetooth must be powered on"));
        return;
    }

    if (broadcasting_) {
        qDebug() << "[BluetoothManager] Already broadcasting";
        return;
    }

    qDebug() << "[BluetoothManager] Starting broadcast mode - discoverable and pairable";

    // Use BlueZ D-Bus to set discoverable (same as bluetoothctl discoverable on)
    QDBusInterface adapter("org.bluez", "/org/bluez/hci0", "org.freedesktop.DBus.Properties",
                           QDBusConnection::systemBus());

    if (!adapter.isValid()) {
        qWarning() << "[BluetoothManager] Cannot access Bluetooth adapter:" << adapter.lastError().message();
        emit errorOccurred(tr("Cannot access Bluetooth adapter"));
        return;
    }

    // Set Discoverable property to true
    QDBusReply<void> discoverableReply = adapter.call("Set", "org.bluez.Adapter1", "Discoverable", QVariant::fromValue(QDBusVariant(true)));
    if (!discoverableReply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to set Discoverable:" << discoverableReply.error().message();
        emit errorOccurred(tr("Failed to enable discoverable mode"));
        return;
    }

    // Set Pairable property to true
    QDBusReply<void> pairableReply = adapter.call("Set", "org.bluez.Adapter1", "Pairable", QVariant::fromValue(QDBusVariant(true)));
    if (!pairableReply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to set Pairable:" << pairableReply.error().message();
        // Continue anyway - discoverable is more important
    }

    // Set DiscoverableTimeout to 0 (infinite) so it doesn't auto-disable
    QDBusReply<void> timeoutReply = adapter.call("Set", "org.bluez.Adapter1", "DiscoverableTimeout", QVariant::fromValue(QDBusVariant(static_cast<quint32>(0))));
    if (!timeoutReply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to set DiscoverableTimeout:" << timeoutReply.error().message();
        // Continue anyway
    }

    broadcasting_ = true;
    emit broadcastingChanged();

    qDebug() << "[BluetoothManager] ✅ Device is now discoverable and pairable";
    qDebug() << "[BluetoothManager] Visible as:" << localDevice_->name();
    qDebug() << "[BluetoothManager] Pair from your phone to connect";
}

void BluetoothManager::stopBroadcasting() {
    if (!broadcasting_) {
        return;
    }

    qDebug() << "[BluetoothManager] Stopping broadcast mode";

    if (bluetoothPowered_) {
        // Use BlueZ D-Bus to disable discoverable (same as bluetoothctl discoverable off)
        QDBusInterface adapter("org.bluez", "/org/bluez/hci0", "org.freedesktop.DBus.Properties",
                               QDBusConnection::systemBus());

        if (adapter.isValid()) {
            // Set Discoverable property to false
            QDBusReply<void> reply = adapter.call("Set", "org.bluez.Adapter1", "Discoverable", QVariant::fromValue(QDBusVariant(false)));
            if (!reply.isValid()) {
                qWarning() << "[BluetoothManager] Failed to disable Discoverable:" << reply.error().message();
            } else {
                qDebug() << "[BluetoothManager] ✅ Device is no longer discoverable";
            }
        } else {
            qWarning() << "[BluetoothManager] Cannot access Bluetooth adapter:" << adapter.lastError().message();
        }
    }

    broadcasting_ = false;
    emit broadcastingChanged();
}

void BluetoothManager::disconnectDevice() {
    if (connectedDeviceAddress_.isEmpty()) {
        return;
    }

    qDebug() << "[BluetoothManager] Disconnecting device" << connectedDeviceName_;

    // Disconnect via D-Bus
    if (!connectedDevicePath_.isEmpty()) {
        QDBusInterface device("org.bluez", connectedDevicePath_, "org.bluez.Device1",
                             QDBusConnection::systemBus());

        if (device.isValid()) {
            QDBusReply<void> reply = device.call("Disconnect");
            if (!reply.isValid()) {
                qWarning() << "[BluetoothManager] Disconnect failed:"
                           << reply.error().message();
            }
        }
    }

    // Notify audio player
    if (audioPlayer_) {
        audioPlayer_->disconnectDevice();
    }

    QString disconnectedAddress = connectedDeviceAddress_;
    connectedDeviceAddress_.clear();
    connectedDeviceName_.clear();
    connectedDevicePath_.clear();

    emit connectedDeviceChanged();
    emit deviceDisconnected(disconnectedAddress);
}

void BluetoothManager::saveDevice(const QString& address, const QString& name) {
    // Check if already saved
    for (const QVariant& var : savedDevicesVariant_) {
        QVariantMap device = var.toMap();
        if (device["address"].toString() == address) {
            qDebug() << "[BluetoothManager] Device already saved:" << name;
            return;
        }
    }

    QVariantMap deviceMap;
    deviceMap["address"] = address;
    deviceMap["name"] = name;
    deviceMap["favorite"] = false;

    savedDevicesVariant_.append(deviceMap);
    saveSavedDevices();

    qDebug() << "[BluetoothManager] Device saved:" << name << "(" << address << ")";
    emit savedDevicesChanged();
}

void BluetoothManager::setDeviceFavorite(const QString& address, bool favorite) {
    for (int i = 0; i < savedDevicesVariant_.size(); ++i) {
        QVariantMap device = savedDevicesVariant_[i].toMap();
        if (device["address"].toString() == address) {
            device["favorite"] = favorite;
            savedDevicesVariant_[i] = device;
            saveSavedDevices();

            qDebug() << "[BluetoothManager] Device" << device["name"].toString()
                     << (favorite ? "marked as favorite" : "unfavorited");

            // Set as preferred device if favorited
            if (favorite) {
                setPreferredDeviceAddress(address);
            }

            emit savedDevicesChanged();
            return;
        }
    }
}

void BluetoothManager::removeSavedDevice(const QString& address) {
    for (int i = 0; i < savedDevicesVariant_.size(); ++i) {
        QVariantMap device = savedDevicesVariant_[i].toMap();
        if (device["address"].toString() == address) {
            savedDevicesVariant_.removeAt(i);
            saveSavedDevices();
            qDebug() << "[BluetoothManager] Device removed:" << device["name"].toString();
            emit savedDevicesChanged();
            break;
        }
    }
}

void BluetoothManager::handlePairingFinished(const QBluetoothAddress& address, QBluetoothLocalDevice::Pairing pairing) {
    QString addressStr = address.toString();

    if (pairing == QBluetoothLocalDevice::Paired || pairing == QBluetoothLocalDevice::AuthorizedPaired) {
        qDebug() << "[BluetoothManager] Device paired successfully:" << addressStr;

        // Set device as trusted to avoid repeated authorization prompts
        qDebug() << "[BluetoothManager] Setting device as trusted";
        QString devicePath = "/org/bluez/hci0/dev_" + QString(addressStr).replace(":", "_");
        QDBusInterface deviceProps("org.bluez", devicePath, "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());
        if (deviceProps.isValid()) {
            QDBusReply<void> reply = deviceProps.call("Set", "org.bluez.Device1", "Trusted", QVariant::fromValue(QDBusVariant(true)));
            if (!reply.isValid()) {
                qWarning() << "[BluetoothManager] Failed to set Trusted property:" << reply.error().message();
            } else {
                qDebug() << "[BluetoothManager] ✅ Device set as trusted";
            }
        } else {
            qWarning() << "[BluetoothManager] Could not get D-Bus interface for device:" << deviceProps.lastError().message();
        }

        // Auto-stop broadcasting after successful pairing
        stopBroadcasting();
    } else if (pairing == QBluetoothLocalDevice::Unpaired) {
        qDebug() << "[BluetoothManager] Device unpaired:" << addressStr;
    }
}

void BluetoothManager::handlePairingError(QBluetoothLocalDevice::Error error) {
    QString errorMsg;
    switch (error) {
    case QBluetoothLocalDevice::PairingError:
        errorMsg = tr("Pairing failed");
        break;
    case QBluetoothLocalDevice::UnknownError:
        errorMsg = tr("Unknown pairing error");
        break;
    default:
        errorMsg = tr("Pairing error occurred");
        break;
    }

    qWarning() << "[BluetoothManager] Pairing error:" << errorMsg;
    emit errorOccurred(errorMsg);
}

void BluetoothManager::handleHostModeChanged(QBluetoothLocalDevice::HostMode mode) {
    bool wasPowered = bluetoothPowered_;

    // bluetoothAvailable_ doesn't change - adapter is always available if it exists
    // Only power state changes
    bluetoothPowered_ = (mode != QBluetoothLocalDevice::HostPoweredOff);

    if (wasPowered != bluetoothPowered_) {
        emit bluetoothPoweredChanged();
        qDebug() << "[BluetoothManager] Bluetooth powered changed:" << bluetoothPowered_;
    }

    // Update broadcasting state based on mode
    bool nowBroadcasting = (mode == QBluetoothLocalDevice::HostDiscoverable);
    if (broadcasting_ != nowBroadcasting) {
        broadcasting_ = nowBroadcasting;
        emit broadcastingChanged();
    }
}

void BluetoothManager::checkConnectionStatus() {
    if (!bluetoothAvailable_) {
        return;
    }

    checkForNewConnections();
}

void BluetoothManager::initializeLocalDevice() {
    if (!localDevice_->isValid()) {
        qWarning() << "[BluetoothManager] No valid Bluetooth adapter found";
        bluetoothAvailable_ = false;
        bluetoothPowered_ = false;
        emit bluetoothAvailableChanged();
        emit bluetoothPoweredChanged();
        return;
    }

    // Adapter exists and is valid
    bluetoothAvailable_ = true;

    // Check current power state
    QBluetoothLocalDevice::HostMode mode = localDevice_->hostMode();
    bluetoothPowered_ = (mode != QBluetoothLocalDevice::HostPoweredOff);

    qDebug() << "[BluetoothManager] Bluetooth adapter available";
    qDebug() << "[BluetoothManager] PC name:" << localDevice_->name();
    qDebug() << "[BluetoothManager] Current power state:" << (bluetoothPowered_ ? "ON" : "OFF");

    if (bluetoothPowered_) {
        localDevice_->setHostMode(QBluetoothLocalDevice::HostConnectable);
        qDebug() << "[BluetoothManager] Bluetooth initialized successfully";
    } else {
        qDebug() << "[BluetoothManager] Bluetooth adapter is powered off - user can power on via UI";
    }

    emit bluetoothAvailableChanged();
    emit bluetoothPoweredChanged();
}

void BluetoothManager::initializeAgent() {
    qDebug() << "========================================";
    qDebug() << "[BluetoothManager] Initializing Bluetooth Agent...";

    // Create agent object
    agent_ = new BluetoothAgent(this);
    qDebug() << "[BluetoothManager] Agent object created";

    // Register agent object on D-Bus
    QDBusConnection bus = QDBusConnection::systemBus();
    QString agentPath = "/com/des/headunit/bluetooth/agent";

    qDebug() << "[BluetoothManager] Registering agent at D-Bus path:" << agentPath;
    // IMPORTANT: For QDBusAbstractAdaptor, register the PARENT object, not the adaptor itself!
    if (!bus.registerObject(agentPath, this)) {
        qCritical() << "[BluetoothManager] *** FAILED to register agent object ***";
        qCritical() << "[BluetoothManager] Error:" << bus.lastError().message();
        qCritical() << "[BluetoothManager] Make sure you run with sudo!";
        qDebug() << "========================================";
        return;
    }

    qDebug() << "[BluetoothManager] ✅ Agent object registered at" << agentPath;

    // Register agent with BlueZ AgentManager
    QDBusInterface agentManager("org.bluez", "/org/bluez", "org.bluez.AgentManager1", bus);

    if (!agentManager.isValid()) {
        qWarning() << "[BluetoothManager] AgentManager interface invalid:"
                   << agentManager.lastError().message();
        bus.unregisterObject(agentPath);
        return;
    }

    // Register agent with "KeyboardDisplay" capability
    // This allows BlueZ to call our agent methods (AuthorizeService, RequestConfirmation, etc.)
    // We will auto-accept in the methods themselves
    qDebug() << "[BluetoothManager] Calling BlueZ AgentManager.RegisterAgent...";
    QDBusReply<void> reply = agentManager.call("RegisterAgent",
                                                 QVariant::fromValue(QDBusObjectPath(agentPath)),
                                                 "KeyboardDisplay");

    if (!reply.isValid()) {
        qCritical() << "[BluetoothManager] *** FAILED to register agent with BlueZ ***";
        qCritical() << "[BluetoothManager] Error:" << reply.error().message();
        qCritical() << "[BluetoothManager] Error name:" << reply.error().name();
        qCritical() << "[BluetoothManager] This means BlueZ won't call our agent for pairing!";
        bus.unregisterObject(agentPath);
        qDebug() << "========================================";
        return;
    }

    qDebug() << "[BluetoothManager] ✅ Agent registered with BlueZ AgentManager";

    // Set as default agent
    qDebug() << "[BluetoothManager] Calling BlueZ AgentManager.RequestDefaultAgent...";
    QDBusReply<void> defaultReply = agentManager.call("RequestDefaultAgent",
                                                        QVariant::fromValue(QDBusObjectPath(agentPath)));

    if (!defaultReply.isValid()) {
        qWarning() << "[BluetoothManager] Failed to set default agent:"
                   << defaultReply.error().message();
        qWarning() << "[BluetoothManager] Another agent might be active (e.g., bluetoothctl)";
        // Not critical - continue anyway
    } else {
        qDebug() << "[BluetoothManager] ✅ Agent set as default";
    }

    qDebug() << "[BluetoothManager] ✅ Bluetooth Agent fully initialized!";
    qDebug() << "========================================";
}

void BluetoothManager::loadSavedDevices() {
    QSettings settings("DesGear", "HeadUnit");
    int size = settings.beginReadArray("savedDevices");

    for (int i = 0; i < size; ++i) {
        settings.setArrayIndex(i);
        QVariantMap device;
        device["address"] = settings.value("address").toString();
        device["name"] = settings.value("name").toString();
        device["favorite"] = settings.value("favorite", false).toBool();
        savedDevicesVariant_.append(device);
    }

    settings.endArray();
    qDebug() << "[BluetoothManager] Loaded" << size << "saved devices";

    if (size > 0) {
        emit savedDevicesChanged();
    }

    // Load auto-reconnect settings
    autoReconnect_ = settings.value("bluetooth/autoReconnect", true).toBool();
    preferredDeviceAddress_ = settings.value("bluetooth/preferredDevice", QString()).toString();

    qDebug() << "[BluetoothManager] Auto-reconnect:" << autoReconnect_;
    qDebug() << "[BluetoothManager] Preferred device:" << preferredDeviceAddress_;

    // Start auto-reconnect if enabled and we have a preferred device
    if (autoReconnect_ && !preferredDeviceAddress_.isEmpty() && bluetoothPowered_) {
        QTimer::singleShot(2000, this, &BluetoothManager::attemptAutoReconnect);
    }
}

void BluetoothManager::saveSavedDevices() {
    QSettings settings("DesGear", "HeadUnit");
    settings.beginWriteArray("savedDevices");

    for (int i = 0; i < savedDevicesVariant_.size(); ++i) {
        settings.setArrayIndex(i);
        QVariantMap device = savedDevicesVariant_[i].toMap();
        settings.setValue("address", device["address"].toString());
        settings.setValue("name", device["name"].toString());
        settings.setValue("favorite", device["favorite"].toBool());
    }

    settings.endArray();
    settings.sync();
}

void BluetoothManager::checkForNewConnections() {
    // Use bluetoothctl's paired devices approach - query specific device paths
    QStringList knownDevices;

    // First, get list of paired devices from QtBluetooth
    QList<QBluetoothAddress> pairedAddresses = localDevice_->connectedDevices();

    // Also check all devices under /org/bluez/hci0/dev_*
    QDBusInterface manager("org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
                          QDBusConnection::systemBus());

    QDBusMessage reply = manager.call("GetManagedObjects");

    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[BluetoothManager] Failed to query D-Bus:" << reply.errorMessage();
        return;
    }

    bool foundConnection = false;
    QString newConnectedAddress;
    QString newConnectedName;
    QString newConnectedPath;

    int pairedCount = 0;
    int connectedCount = 0;

    // Parse D-Bus reply manually for each object path
    const QDBusArgument arg = reply.arguments().at(0).value<QDBusArgument>();

    arg.beginMap();
    while (!arg.atEnd()) {
        QString objectPath;

        arg.beginMapEntry();
        arg >> objectPath;

        // Skip the interfaces map (we'll query each device directly)
        QVariant interfaces;
        arg >> interfaces;

        arg.endMapEntry();

        // Only process device paths
        if (!objectPath.contains("/dev_") || objectPath.contains("/service") || objectPath.contains("/char") || objectPath.contains("/desc")) {
            continue;
        }

        // Query this specific device path for properties
        QDBusInterface device("org.bluez", objectPath, "org.freedesktop.DBus.Properties",
                             QDBusConnection::systemBus());

        QDBusMessage propsReply = device.call("GetAll", "org.bluez.Device1");
        if (propsReply.type() == QDBusMessage::ReplyMessage && !propsReply.arguments().isEmpty()) {
            const QDBusArgument propsArg = propsReply.arguments().at(0).value<QDBusArgument>();
            QVariantMap deviceProps;
            propsArg >> deviceProps;

            bool paired = deviceProps.value("Paired", false).toBool();
            bool connected = deviceProps.value("Connected", false).toBool();
            QString address = objectPathToAddress(objectPath);
            QString name = deviceProps.value("Name", address).toString();

            if (paired) {
                pairedCount++;
                qDebug() << "[BluetoothManager] Found paired device:" << name << "(" << address << ") - Connected:" << connected;
            }

            if (paired && connected) {
                connectedCount++;
                newConnectedAddress = address;
                newConnectedName = name;
                newConnectedPath = objectPath;
                foundConnection = true;
                qDebug() << "[BluetoothManager] Active connection found:" << name;
                break;
            }
        }
    }
    arg.endMap();

    qDebug() << "[BluetoothManager] Connection check - Paired:" << pairedCount << "Connected:" << connectedCount;

    // Handle connection state changes
    if (foundConnection && newConnectedAddress != connectedDeviceAddress_) {
        // New device connected
        connectedDeviceAddress_ = newConnectedAddress;
        connectedDeviceName_ = newConnectedName;
        connectedDevicePath_ = newConnectedPath;

        qDebug() << "[BluetoothManager] Device connected:" << connectedDeviceName_;

        // Notify audio player
        if (audioPlayer_) {
            audioPlayer_->setConnectedDevice(newConnectedPath);
        }

        emit connectedDeviceChanged();
        emit deviceConnected(connectedDeviceAddress_, connectedDeviceName_);

        // Check if device is saved
        bool isSaved = false;
        for (const QVariant& var : savedDevicesVariant_) {
            QVariantMap device = var.toMap();
            if (device["address"].toString() == connectedDeviceAddress_) {
                isSaved = true;
                break;
            }
        }

        // Ask to save if not saved
        if (!isSaved) {
            emit askToSaveDevice(connectedDeviceAddress_, connectedDeviceName_);
        }

    } else if (!foundConnection && !connectedDeviceAddress_.isEmpty()) {
        // Device disconnected
        QString disconnectedAddress = connectedDeviceAddress_;

        connectedDeviceAddress_.clear();
        connectedDeviceName_.clear();
        connectedDevicePath_.clear();

        qDebug() << "[BluetoothManager] Device disconnected";

        // Notify audio player
        if (audioPlayer_) {
            audioPlayer_->disconnectDevice();
        }

        emit connectedDeviceChanged();
        emit deviceDisconnected(disconnectedAddress);

        // Start auto-reconnect if enabled
        if (autoReconnect_ && disconnectedAddress == preferredDeviceAddress_) {
            qDebug() << "[BluetoothManager] Starting auto-reconnect attempts";
            reconnectAttempts_ = 0;
            autoReconnectTimer_->start();
        }
    }
}

void BluetoothManager::attemptAutoReconnect() {
    if (!autoReconnect_ || preferredDeviceAddress_.isEmpty()) {
        autoReconnectTimer_->stop();
        return;
    }

    // Stop if already connected
    if (!connectedDeviceAddress_.isEmpty()) {
        autoReconnectTimer_->stop();
        reconnectAttempts_ = 0;
        return;
    }

    // Stop after max attempts
    if (reconnectAttempts_ >= MAX_RECONNECT_ATTEMPTS) {
        qDebug() << "[BluetoothManager] Max reconnect attempts reached, stopping";
        autoReconnectTimer_->stop();
        reconnectAttempts_ = 0;
        return;
    }

    reconnectAttempts_++;
    qDebug() << "[BluetoothManager] Auto-reconnect attempt" << reconnectAttempts_
             << "of" << MAX_RECONNECT_ATTEMPTS;

    // Convert address format (XX:XX:XX:XX:XX:XX -> XX_XX_XX_XX_XX_XX)
    QString devicePath = "/org/bluez/hci0/dev_" + preferredDeviceAddress_;
    devicePath.replace(':', '_');

    // Try to connect via D-Bus
    QDBusInterface device("org.bluez", devicePath, "org.bluez.Device1",
                         QDBusConnection::systemBus());

    if (!device.isValid()) {
        qWarning() << "[BluetoothManager] Cannot access preferred device:"
                   << preferredDeviceAddress_;
        return;
    }

    QDBusReply<void> reply = device.call("Connect");
    if (!reply.isValid()) {
        qWarning() << "[BluetoothManager] Auto-reconnect failed:"
                   << reply.error().message();
    } else {
        qDebug() << "[BluetoothManager] Auto-reconnect initiated successfully";
    }
}

QString BluetoothManager::objectPathToAddress(const QString& path) {
    // Convert /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX to XX:XX:XX:XX:XX:XX
    QString address = path;
    int devIndex = address.lastIndexOf("/dev_");
    if (devIndex != -1) {
        address = address.mid(devIndex + 5); // Skip "/dev_"
        address.replace('_', ':');
    }
    return address;
}
