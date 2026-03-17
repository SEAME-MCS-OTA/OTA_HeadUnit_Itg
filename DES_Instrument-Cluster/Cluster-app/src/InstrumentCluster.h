#ifndef INSTRUMENTCLUSTER_H
# define INSTRUMENTCLUSTER_H

# include "ViewModel.h"
# include "CanGateway.h"
# include "module/GearManager.h"
# include "module/VehicleDataManager.h"

# include <QGuiApplication>
# include <QQmlApplicationEngine>
# include <QThread>
# include <QTimer>

# include <string>
# include <list>
# include <unordered_map>

# define SIZE_INT 4

class InstrumentCluster {
	public:
		InstrumentCluster();
		~InstrumentCluster();

		/* Methods for Timer management */
		void setTimer(const std::string&);
		void removeTimer(const std::string&);
		void connectTimerModel(const std::string& name, int time, ViewModel& model, void (ViewModel::*&& slot)(const std::string&));

		/* Methods for CAN communication management */
		bool openCan(const std::string&);
		void closeCan(const std::string&);
		void connectCanModel(const std::string& interface, ViewModel& model, void (ViewModel::*&& slot)(int, const QByteArray&));
		
		/* Methods for run the application */
		void registerModel(const std::string&, ViewModel&);
		void loadQml(const std::string&, QGuiApplication&);

		const std::shared_ptr<BatteryMonitor>& getBattery() const { return _battery; }
		const std::shared_ptr<SharedMemory>& getVehicle() const { return _vehicle; }
		const std::shared_ptr<GearManager>& getGearManager() const { return _gearManager; }
		const std::shared_ptr<VehicleDataManager>& getVehicleDataManager() const { return _vehicleDataManager; }
		
	private:
		static constexpr int CLOSE_WAIT = 5000; 
		static constexpr int FORCE_WAIT = 1000;

		/**
		 * @brief A custom deleter for std::unique_ptr to safely delete QObjects across threads.
		 *
		 * This deleter replaces the default `delete` call with `QObject::deleteLater()`.
		 * `deleteLater()` is thread-safe and posts a `DeferredDelete` event to
		 * the object's event loop, ensuring safe deletion on the correct thread.
		 */
		struct QObjectDeleter {
			void operator()(QObject* obj) const {
				if (obj) {
					obj->deleteLater();
				}
			}
		};

		/* TYPES */
		template <typename T>
		using s_ptr = std::shared_ptr<T>;

		template <typename T>
		using u_ptr = std::unique_ptr<T>;

		template <typename T, typename Deleter = QObjectDeleter>
		using u_ptr_d = std::unique_ptr<T, Deleter>;

		using QTimer_ptr = u_ptr<QTimer>;
		using QThread_ptr = u_ptr<QThread>;
		using CanGateway_ptr = u_ptr_d<CanGateway, QObjectDeleter>;

		/* MEMBER */
		u_ptr<QQmlApplicationEngine> _engine = nullptr;

		std::unordered_map<std::string, QTimer_ptr> _timers;
		std::unordered_map<std::string, QThread_ptr> _threads;
		std::list<CanGateway_ptr> _can;

		s_ptr<SharedMemory> _vehicle = nullptr;
		s_ptr<BatteryMonitor> _battery = nullptr;
		s_ptr<GearManager> _gearManager = nullptr;
		s_ptr<VehicleDataManager> _vehicleDataManager = nullptr;

		bool _validTimer(std::unordered_map<std::string, QTimer_ptr>::iterator, int);
		void _openCanCreate(const std::string&);
		void _openCanSetSignals(CanGateway_ptr&, QThread_ptr&, const std::string&);
		const CanGateway_ptr& _findCan(const std::string&) const;
};

#endif
