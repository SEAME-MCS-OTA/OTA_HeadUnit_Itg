#!/bin/sh

# WiFi auto-enable script with retry logic
# Set STRICT_WIFI_ENABLE=1 in environment to fail on WiFi unavailability
MAX_RETRIES=10
RETRY_DELAY=3

echo "Starting WiFi auto-enable service..."

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i/$MAX_RETRIES to enable WiFi..."

    # Check if connman is actually running and responsive
    if ! connmanctl state >/dev/null 2>&1; then
        echo "ConnMan not ready yet, waiting ${RETRY_DELAY}s..."
        sleep $RETRY_DELAY
        continue
    fi

    if connmanctl enable wifi 2>&1 | grep -q "Enabled\|Already"; then
        echo "WiFi enabled successfully on attempt $i"
        exit 0
    fi

    echo "Failed to enable WiFi, waiting ${RETRY_DELAY}s before retry..."
    sleep $RETRY_DELAY
done

# Tag failure in journal for monitoring (searchable via journalctl -t wifi-auto-enable)
echo "WARNING: WiFi enable failed after $MAX_RETRIES attempts" | logger -t wifi-auto-enable -p user.warning

# In strict mode, return failure for monitoring/alerting
if [ "${STRICT_WIFI_ENABLE}" = "1" ]; then
    echo "ERROR: STRICT_WIFI_ENABLE=1 — marking service as failed"
    exit 1
fi

# Default: non-critical — don't block boot
exit 0
