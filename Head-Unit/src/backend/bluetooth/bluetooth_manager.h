#ifndef BACKEND_BLUETOOTH_BLUETOOTH_MANAGER_H
#define BACKEND_BLUETOOTH_BLUETOOTH_MANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QBluetoothLocalDevice>
#include <QList>
#include <QVariantMap>
#include <QTimer>
#include <QSettings>
#include <memory>

// Forward declarations
class BluetoothAudioPlayer;
class BluetoothAgent;

/**
 * @brief BluetoothManager handles device discovery, pairing, and connection management
 *        for Bluetooth audio streaming in the Head Unit system.
 *        Uses hybrid approach: QtBluetooth for pairing + BlueZ D-Bus for connections.
 */
class BluetoothManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool bluetoothAvailable READ isBluetoothAvailable NOTIFY bluetoothAvailableChanged)
    Q_PROPERTY(bool bluetoothPowered READ isBluetoothPowered WRITE setBluetoothPowered NOTIFY bluetoothPoweredChanged)
    Q_PROPERTY(bool broadcasting READ isBroadcasting NOTIFY broadcastingChanged)
    Q_PROPERTY(QVariantList savedDevices READ savedDevices NOTIFY savedDevicesChanged)
    Q_PROPERTY(QString connectedDeviceName READ connectedDeviceName NOTIFY connectedDeviceChanged)
    Q_PROPERTY(QString connectedDeviceAddress READ connectedDeviceAddress NOTIFY connectedDeviceChanged)
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedDeviceChanged)
    Q_PROPERTY(QObject* agent READ agent CONSTANT)
    Q_PROPERTY(bool autoReconnect READ autoReconnect WRITE setAutoReconnect NOTIFY autoReconnectChanged)
    Q_PROPERTY(QString preferredDeviceAddress READ preferredDeviceAddress WRITE setPreferredDeviceAddress NOTIFY preferredDeviceChanged)

public:
    explicit BluetoothManager(QObject* parent = nullptr);
    ~BluetoothManager();

    bool isBluetoothAvailable() const;
    bool isBluetoothPowered() const;
    void setBluetoothPowered(bool powered);
    bool isBroadcasting() const;
    QVariantList savedDevices() const;
    QString connectedDeviceName() const;
    QString connectedDeviceAddress() const;
    bool isConnected() const;
    QObject* agent() const;
    bool autoReconnect() const;
    void setAutoReconnect(bool enabled);
    QString preferredDeviceAddress() const;
    void setPreferredDeviceAddress(const QString& address);

    // Set audio player for integration
    void setAudioPlayer(BluetoothAudioPlayer* player);

    Q_INVOKABLE void startBroadcasting();
    Q_INVOKABLE void stopBroadcasting();
    Q_INVOKABLE void disconnectDevice();
    Q_INVOKABLE void saveDevice(const QString& address, const QString& name);
    Q_INVOKABLE void removeSavedDevice(const QString& address);
    Q_INVOKABLE void setDeviceFavorite(const QString& address, bool favorite);

signals:
    void bluetoothAvailableChanged();
    void bluetoothPoweredChanged();
    void broadcastingChanged();
    void savedDevicesChanged();
    void connectedDeviceChanged();
    void deviceConnected(const QString& address, const QString& name);
    void deviceDisconnected(const QString& address);
    void askToSaveDevice(const QString& address, const QString& name);
    void errorOccurred(const QString& message);
    void autoReconnectChanged();
    void preferredDeviceChanged();

private slots:
    void handlePairingFinished(const QBluetoothAddress& address, QBluetoothLocalDevice::Pairing pairing);
    void handlePairingError(QBluetoothLocalDevice::Error error);
    void handleHostModeChanged(QBluetoothLocalDevice::HostMode mode);
    void checkConnectionStatus();
    void attemptAutoReconnect();

private:
    void initializeLocalDevice();
    void initializeAgent();
    void loadSavedDevices();
    void saveSavedDevices();
    void checkForNewConnections();
    QString objectPathToAddress(const QString& path);

    std::unique_ptr<QBluetoothLocalDevice> localDevice_;
    BluetoothAgent* agent_;
    QTimer* connectionCheckTimer_;
    QTimer* autoReconnectTimer_;

    QVariantList savedDevicesVariant_;
    bool bluetoothPowered_ = false;
    bool broadcasting_ = false;
    bool autoReconnect_ = true;
    QString preferredDeviceAddress_;
    int reconnectAttempts_ = 0;
    static constexpr int MAX_RECONNECT_ATTEMPTS = 3;

    QString connectedDeviceAddress_;
    QString connectedDeviceName_;
    QString connectedDevicePath_;  // D-Bus object path
    bool bluetoothAvailable_ = false;

    // Audio player integration
    BluetoothAudioPlayer* audioPlayer_ = nullptr;
};

#endif // BACKEND_BLUETOOTH_BLUETOOTH_MANAGER_H
