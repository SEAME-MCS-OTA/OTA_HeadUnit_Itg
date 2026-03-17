#ifndef INA219_H
#define INA219_H

#include <cstdint>
#include <string>

/**
 * @brief INA219 High Side DC Current Sensor Driver for Raspberry Pi
 *
 * This class provides an interface to communicate with the INA219 current/power
 * monitor IC via I2C. It supports reading voltage, current, and power measurements.
 */
class INA219 {
public:
    // INA219 Register addresses
    static constexpr uint8_t REG_CONFIG         = 0x00;
    static constexpr uint8_t REG_SHUNT_VOLTAGE  = 0x01;
    static constexpr uint8_t REG_BUS_VOLTAGE    = 0x02;
    static constexpr uint8_t REG_POWER          = 0x03;
    static constexpr uint8_t REG_CURRENT        = 0x04;
    static constexpr uint8_t REG_CALIBRATION    = 0x05;

    // Configuration register bit definitions
    static constexpr uint16_t CONFIG_RESET      = 0x8000;
    static constexpr uint16_t CONFIG_BVOLTAGERANGE_32V = 0x2000;
    static constexpr uint16_t CONFIG_BVOLTAGERANGE_16V = 0x0000;
    static constexpr uint16_t CONFIG_GAIN_1_40MV = 0x0000;
    static constexpr uint16_t CONFIG_GAIN_2_80MV = 0x0800;
    static constexpr uint16_t CONFIG_GAIN_4_160MV = 0x1000;
    static constexpr uint16_t CONFIG_GAIN_8_320MV = 0x1800;
    static constexpr uint16_t CONFIG_BADCRES_9BIT = 0x0000;
    static constexpr uint16_t CONFIG_BADCRES_10BIT = 0x0080;
    static constexpr uint16_t CONFIG_BADCRES_11BIT = 0x0100;
    static constexpr uint16_t CONFIG_BADCRES_12BIT = 0x0180;
    static constexpr uint16_t CONFIG_SADCRES_9BIT_1S = 0x0000;
    static constexpr uint16_t CONFIG_SADCRES_10BIT_1S = 0x0008;
    static constexpr uint16_t CONFIG_SADCRES_11BIT_1S = 0x0010;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_1S = 0x0018;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_2S = 0x0048;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_4S = 0x0050;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_8S = 0x0058;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_16S = 0x0060;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_32S = 0x0068;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_64S = 0x0070;
    static constexpr uint16_t CONFIG_SADCRES_12BIT_128S = 0x0078;
    static constexpr uint16_t CONFIG_MODE_POWERDOWN = 0x0000;
    static constexpr uint16_t CONFIG_MODE_SVOLT_TRIGGERED = 0x0001;
    static constexpr uint16_t CONFIG_MODE_BVOLT_TRIGGERED = 0x0002;
    static constexpr uint16_t CONFIG_MODE_SANDBVOLT_TRIGGERED = 0x0003;
    static constexpr uint16_t CONFIG_MODE_ADCOFF = 0x0004;
    static constexpr uint16_t CONFIG_MODE_SVOLT_CONTINUOUS = 0x0005;
    static constexpr uint16_t CONFIG_MODE_BVOLT_CONTINUOUS = 0x0006;
    static constexpr uint16_t CONFIG_MODE_SANDBVOLT_CONTINUOUS = 0x0007;

    // Default I2C address
    static constexpr uint8_t DEFAULT_ADDRESS = 0x40;

    /**
     * @brief Constructor
     * @param i2c_bus I2C bus number (typically 1 for Raspberry Pi)
     * @param address I2C address of the INA219 (default: 0x40)
     */
    INA219(int i2c_bus = 1, uint8_t address = DEFAULT_ADDRESS);

    /**
     * @brief Destructor
     */
    ~INA219();

    /**
     * @brief Initialize the INA219 sensor
     * @param shunt_resistor_ohms Shunt resistor value in ohms (default: 0.1)
     * @param max_expected_amps Maximum expected current in amperes (default: 3.2)
     * @return true if initialization successful, false otherwise
     */
    bool begin(float shunt_resistor_ohms = 0.1f, float max_expected_amps = 3.2f);

    /**
     * @brief Read the bus voltage
     * @return Bus voltage in volts, or -1.0 on error
     */
    float getBusVoltage();

    /**
     * @brief Read the shunt voltage
     * @return Shunt voltage in millivolts, or -1.0 on error
     */
    float getShuntVoltage();

    /**
     * @brief Read the current
     * @return Current in amperes, or -1.0 on error
     */
    float getCurrent();

    /**
     * @brief Read the power consumption
     * @return Power in watts, or -1.0 on error
     */
    float getPower();

    /**
     * @brief Read the supply voltage (bus voltage + shunt voltage)
     * @return Supply voltage in volts, or -1.0 on error
     */
    float getSupplyVoltage();

    /**
     * @brief Check if the sensor is connected and responding
     * @return true if sensor is accessible, false otherwise
     */
    bool isConnected();

    /**
     * @brief Reset the INA219 to default settings
     * @return true if reset successful, false otherwise
     */
    bool reset();

    /**
     * @brief Get the last error message
     * @return Error message string
     */
    std::string getLastError() const;

private:
    int i2c_fd;              // I2C file descriptor
    uint8_t i2c_address;     // I2C device address
    float current_lsb;       // Current LSB value for calibration
    float power_lsb;         // Power LSB value for calibration
    std::string last_error;  // Last error message

    /**
     * @brief Write a 16-bit value to a register
     * @param reg Register address
     * @param value 16-bit value to write
     * @return true if successful, false otherwise
     */
    bool writeRegister(uint8_t reg, uint16_t value);

    /**
     * @brief Read a 16-bit value from a register
     * @param reg Register address
     * @param value Reference to store the read value
     * @return true if successful, false otherwise
     */
    bool readRegister(uint8_t reg, uint16_t& value);

    /**
     * @brief Set the calibration register
     * @param shunt_resistor_ohms Shunt resistor value in ohms
     * @param max_expected_amps Maximum expected current in amperes
     * @return true if successful, false otherwise
     */
    bool setCalibration(float shunt_resistor_ohms, float max_expected_amps);

    /**
     * @brief Convert signed 16-bit value to signed integer
     * @param value Unsigned 16-bit value
     * @return Signed integer value
     */
    int16_t toSigned16(uint16_t value);
};

#endif // INA219_H
