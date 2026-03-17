#ifndef CANGATEWAY_H
# define CANGATEWAY_H

# include <QObject>

# include <unistd.h>
# include <sys/socket.h>
# include <sys/ioctl.h>
# include <net/if.h>
# include <cstring>

# ifdef __linux__
#  include <linux/can.h>
# elif defined(__APPLE__) || defined(__MACH__)
#  include "can.h"
#  include "sockios.h"

#  define AF_CAN 29
#  define PF_CAN AF_CAN
# endif

# define INTERVAL 10 // ms

enum status_e {
	INIT,
	FAULT,
	READY,
	ACTIVE,
	STOP
};

class CanGateway: public QObject {
	/* QT FRAMEWORK */
    Q_OBJECT

	public slots:
		void start();
		void stop();
		// void transmit(int canId, const QByteArray& data);

	signals:
		void connected();
		void disconnected();
		void finished();
		void error(const QString &);

		void newData(int, const QByteArray&);

	/* CLASS */
	public:
		struct can_pipe {
			int socket;
			ifreq ifr;
			sockaddr_can addr;
			
			can_pipe() : socket(-1) {
				std::memset(&addr, 0, sizeof(addr));
			}
		};

		const std::string ifname;
		int status; 

		CanGateway() = delete;
		CanGateway(const std::string& ifname);
		~CanGateway();
		
	private:
		struct can_pipe _pipe;
		
		void _init();
		void _initDomainSocket();
		void _initCanInterface();
		void _initBind();

		void _startHandleData(const can_frame&);
};

#endif
