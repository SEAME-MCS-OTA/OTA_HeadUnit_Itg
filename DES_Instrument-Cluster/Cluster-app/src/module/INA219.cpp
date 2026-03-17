#include "INA219.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/i2c-dev.h>
#include <cstring>
#include <cmath>
#include <thread>
#include <chrono>

INA219::INA219(int i2c_bus, uint8_t address)
    : i2c_fd(-1), i2c_address(address), current_lsb(0.0f), power_lsb(0.0f) {

    // Open I2C device
    std::string device_path = "/dev/i2c-" + std::to_string(i2c_bus);
    i2c_fd = open(device_path.c_str(), O_RDWR);

    if (i2c_fd < 0) {
        last_error = "Failed to open I2C device: " + device_path + " - " + strerror(errno);
        return;
    }

    // Set I2C slave address
    if (ioctl(i2c_fd, I2C_SLAVE, i2c_address) < 0) {
        last_error = "Failed to set I2C slave address: " + std::string(strerror(errno));
        close(i2c_fd);
        i2c_fd = -1;
        return;
    }
}

INA219::~INA219() {
    if (i2c_fd >= 0) {
        close(i2c_fd);
    }
}

bool INA219::begin(float shunt_resistor_ohms, float max_expected_amps) {
    if (i2c_fd < 0) {
        last_error = "I2C device not properly initialized";
        return false;
    }

    // Reset the device
    if (!reset()) {
        return false;
    }

    // Wait for reset to complete
    std::this_thread::sleep_for(std::chrono::milliseconds(5));

    // Set configuration
    uint16_t config = CONFIG_BVOLTAGERANGE_32V |
                      CONFIG_GAIN_8_320MV |
                      CONFIG_BADCRES_12BIT |
                      CONFIG_SADCRES_12BIT_1S |
                      CONFIG_MODE_SANDBVOLT_CONTINUOUS;

    if (!writeRegister(REG_CONFIG, config)) {
        last_error = "Failed to write configuration register";
        return false;
    }

    // Set calibration
    if (!setCalibration(shunt_resistor_ohms, max_expected_amps)) {
        return false;
    }

    return true;
}

bool INA219::reset() {
    return writeRegister(REG_CONFIG, CONFIG_RESET);
}

bool INA219::isConnected() {
    uint16_t config;
    return readRegister(REG_CONFIG, config);
}

float INA219::getBusVoltage() {
    uint16_t raw_value;
    if (!readRegister(REG_BUS_VOLTAGE, raw_value)) {
        return -1.0f;
    }

    // Check overflow flag (bit 0)
    if (raw_value & 0x01) {
        last_error = "Bus voltage overflow detected";
        return -1.0f;
    }

    // Bus voltage is in bits 15-3, LSB = 4mV
    int16_t voltage_raw = (raw_value >> 3) & 0x1FFF;
    return voltage_raw * 0.004f; // Convert to volts
}

float INA219::getShuntVoltage() {
    uint16_t raw_value;
    if (!readRegister(REG_SHUNT_VOLTAGE, raw_value)) {
        return -1.0f;
    }

    // Shunt voltage is signed, LSB = 10µV
    int16_t shunt_raw = toSigned16(raw_value);
    return shunt_raw * 0.01f; // Convert to millivolts
}

float INA219::getCurrent() {
    if (current_lsb == 0.0f) {
        last_error = "Device not calibrated - call begin() first";
        return -1.0f;
    }

    uint16_t raw_value;
    if (!readRegister(REG_CURRENT, raw_value)) {
        return -1.0f;
    }

    // Current is signed
    int16_t current_raw = toSigned16(raw_value);
    return current_raw * current_lsb; // Convert to amperes
}

float INA219::getPower() {
    if (power_lsb == 0.0f) {
        last_error = "Device not calibrated - call begin() first";
        return -1.0f;
    }

    uint16_t raw_value;
    if (!readRegister(REG_POWER, raw_value)) {
        return -1.0f;
    }

    return raw_value * power_lsb; // Convert to watts
}

float INA219::getSupplyVoltage() {
    float bus_voltage = getBusVoltage();
    float shunt_voltage = getShuntVoltage();

    if (bus_voltage < 0 || shunt_voltage < 0) {
        return -1.0f;
    }

    return bus_voltage + (shunt_voltage / 1000.0f); // Convert shunt from mV to V
}

std::string INA219::getLastError() const {
    return last_error;
}

bool INA219::writeRegister(uint8_t reg, uint16_t value) {
    uint8_t buffer[3];
    buffer[0] = reg;
    buffer[1] = (value >> 8) & 0xFF;  // MSB
    buffer[2] = value & 0xFF;         // LSB

    if (write(i2c_fd, buffer, 3) != 3) {
        last_error = "Failed to write register 0x" + std::to_string(reg) +
                     ": " + strerror(errno);
        return false;
    }

    return true;
}

bool INA219::readRegister(uint8_t reg, uint16_t& value) {
    // Write register address
    if (write(i2c_fd, &reg, 1) != 1) {
        last_error = "Failed to write register address: " + std::string(strerror(errno));
        return false;
    }

    // Read 2 bytes
    uint8_t buffer[2];
    if (read(i2c_fd, buffer, 2) != 2) {
        last_error = "Failed to read register data: " + std::string(strerror(errno));
        return false;
    }

    // Combine MSB and LSB
    value = (buffer[0] << 8) | buffer[1];
    return true;
}

bool INA219::setCalibration(float shunt_resistor_ohms, float max_expected_amps) {
    // Calculate current LSB
    current_lsb = max_expected_amps / 32768.0f;

    // Round current LSB to nearest step
    float current_lsb_steps[] = {
        0.0001f, 0.0002f, 0.0005f,
        0.001f, 0.002f, 0.005f,
        0.01f, 0.02f, 0.05f,
        0.1f, 0.2f, 0.5f
    };

    for (float step : current_lsb_steps) {
        if (current_lsb <= step) {
            current_lsb = step;
            break;
        }
    }

    // Calculate calibration register value
    float calibration_value = 0.04096f / (current_lsb * shunt_resistor_ohms);
    uint16_t cal_reg = static_cast<uint16_t>(calibration_value);

    // Ensure calibration value is within valid range
    if (cal_reg == 0 || cal_reg > 0xFFFE) {
        last_error = "Calibration value out of range. Check shunt resistor and max current values.";
        return false;
    }

    // Calculate power LSB (20 * current LSB)
    power_lsb = 20.0f * current_lsb;

    // Write calibration register
    if (!writeRegister(REG_CALIBRATION, cal_reg)) {
        last_error = "Failed to write calibration register";
        return false;
    }

    return true;
}

int16_t INA219::toSigned16(uint16_t value) {
    if (value & 0x8000) {
        // Negative value - convert from two's complement
        return -static_cast<int16_t>((~value) + 1);
    }
    return static_cast<int16_t>(value);
}
