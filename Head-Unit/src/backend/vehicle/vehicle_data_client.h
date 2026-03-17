#ifndef BACKEND_VEHICLE_VEHICLE_DATA_CLIENT_H
#define BACKEND_VEHICLE_VEHICLE_DATA_CLIENT_H

#include <QObject>
#include <QString>
#include <QtDBus/QDBusInterface>
#include <QtGlobal>

class VehicleDataClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(int speed READ speed NOTIFY speedChanged)
    Q_PROPERTY(int battery READ battery NOTIFY batteryChanged)

public:
    explicit VehicleDataClient(QObject* parent = nullptr);

    int speed() const;
    int battery() const;

    Q_INVOKABLE void refresh();

signals:
    void speedChanged();
    void batteryChanged();
    void dataChanged(int speed, int battery);

private slots:
    void onVehicleDataChanged(int speed, int battery);

private:
    void subscribeToSignals();
    void fetchInitialData();
    void updateData(int speed, int battery);

    QDBusInterface iface_;
    int speed_;
    int battery_;
    bool signalsConnected_;
};

#endif // BACKEND_VEHICLE_VEHICLE_DATA_CLIENT_H
