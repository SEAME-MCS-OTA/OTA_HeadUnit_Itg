#ifndef ERROR_H
# define ERROR_H

# include <stdexcept>
# include <string>

# define ERR_COUNT 4

enum error_e {
	ERR_INIT_FAIL_DOMAIN_SOCKET,
	ERR_INIT_FAIL_CAN_INTERFACE,
	ERR_INIT_FAIL_BIND,
	ERR_INIT_FAIL_QTFRAME
};

const std::string error_message[ERR_COUNT] = {
	"Failed to create domain socket",
	"Failed to find CAN interface",
	"Failed to bind CAN socket",
	"Failed to initialize Qt framework"
};

class Error : public std::runtime_error {
public:
	explicit Error(error_e code)
		: std::runtime_error(error_message[static_cast<size_t>(code)]), _code(code) {}	

	int code() const noexcept {
		return static_cast<int>(_code);
	}

private:
	error_e _code;
};


#endif