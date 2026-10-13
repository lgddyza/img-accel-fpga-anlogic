#!/bin/sh
set -eu

device="2a210000.pcie"
platform_device="/sys/bus/platform/devices/$device"
driver="/sys/bus/platform/drivers/rk-pcie"
reset_gpio="/sys/class/gpio/gpio48"

if lspci -Dn 2>/dev/null | grep -qi "1edb:abcd"; then
    echo "PCIe1 FPGA endpoint is already online"
    exit 0
fi

# The built-in driver's first probe precedes userspace and may still be timing
# out. Wait for that attempt to detach before applying the proven reset order.
attempt=0
while [ -L "$platform_device/driver" ] && [ "$attempt" -lt 40 ]; do
    sleep 0.5
    attempt=$((attempt + 1))
done

if [ -L "$platform_device/driver" ]; then
    echo "$device" > "$driver/unbind"
    sleep 0.2
fi

if [ ! -d "$reset_gpio" ]; then
    echo 48 > /sys/class/gpio/export
fi
echo low > "$reset_gpio/direction"

# Binding enables vcc3v3_pcie0. Release active-low PERST# only after the
# endpoint has had time to power up; bind blocks until link training finishes.
(
    sleep 0.5
    echo 1 > "$reset_gpio/value"
) &
release_pid=$!

echo "$device" > "$driver/bind"
wait "$release_pid"

attempt=0
while ! lspci -Dn 2>/dev/null | grep -qi "1edb:abcd" && [ "$attempt" -lt 30 ]; do
    sleep 0.1
    attempt=$((attempt + 1))
done

if ! lspci -Dn 2>/dev/null | grep -qi "1edb:abcd"; then
    echo "PCIe1 recovery completed without the FPGA endpoint" >&2
    exit 1
fi

echo "PCIe1 FPGA endpoint 1edb:abcd is online"
