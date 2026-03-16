#ifndef MODULE_VEHICLEDATAMANAGER_H
#define MODULE_VEHICLEDATAMANAGER_H

#include <QObject>
#include <QString>
#include <QtDBus/QDBusConnection>
#include <QtGlobal>
#include <memory>

class ViewModel;

class VehicleDataManager : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "com.des.vehicle.VehicleData")

public:
    explicit VehicleDataManager(QObject* parent = nullptr);
    ~VehicleDataManager() override;

    void setViewModel(ViewModel* viewModel);
    bool isRegistered() const { return registered_; }

public slots:
    // D-Bus accessible methods
    QVariantMap GetVehicleData() const;

signals:
    // D-Bus signals
    void VehicleDataChanged(int speed, int battery);

private slots:
    void onViewModelDataChanged();

private:
    bool registerOnBus();
    void unregisterFromBus();

    ViewModel* viewModel_ = nullptr;
    bool registered_ = false;
    int lastSpeed_ = 0;
    int lastBattery_ = 0;
};

#endif // MODULE_VEHICLEDATAMANAGER_H
