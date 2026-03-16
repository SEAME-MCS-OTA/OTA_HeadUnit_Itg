#ifndef HEADUNIT_H
# define HEADUNIT_H

#include "ViewModel.h"
#include "backend/music/music_player.h"
#include "backend/gear/gear_client.h"
#include "backend/weather/weather_service.h"
#include "backend/bluetooth/bluetooth_manager.h"
#include "backend/bluetooth/bluetooth_audio_player.h"
#include "backend/vehicle/vehicle_data_client.h"
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QThread>
#include <QTimer>

#include <string>
#include <list>
#include <unordered_map>
#include <memory>

class HeadUnit : public QObject {
    Q_OBJECT

    public:
        HeadUnit();
        ~HeadUnit();

        /* Methods for Timer Management */
        void setTimer(const std::string&);
        void removeTimer(const std::string&);
        void connectTimerModel(const std::string& name, int time, ViewModel& model, void (ViewModel::*slot)(const std::string&));

        /* Methods for run the application */
        void registerModel(const std::string&, ViewModel&);
        void loadQml(const std::string&, QGuiApplication&);

    private slots:
        void quitPlymouth();

    private:
        static constexpr int CLOSE_WAIT = 5000;
        static constexpr int FORCE_WAIT = 1000;

        /* Types */
        template <typename T>
        using s_ptr = std::shared_ptr<T>;

        template <typename T>
        using u_ptr = std::unique_ptr<T>;

        using QTimer_ptr = u_ptr<QTimer>;
        using QThread_ptr = u_ptr<QThread>;

        /* Members */
        std::unique_ptr<QQmlApplicationEngine> _engine = nullptr;

        std::unordered_map<std::string, QTimer_ptr> _timers;

        s_ptr<MusicPlayer> _musicPlayer = nullptr;
        s_ptr<GearClient> _gearClient = nullptr;
        s_ptr<WeatherService> _weatherService = nullptr;
        s_ptr<BluetoothManager> _bluetoothManager = nullptr;
        s_ptr<BluetoothAudioPlayer> _bluetoothAudioPlayer = nullptr;
        s_ptr<VehicleDataClient> _vehicleDataClient = nullptr;
};


#endif // HEADUNIT_H
