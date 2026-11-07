#!/bin/bash -ex

BUILD_DIR="$PWD/build"

# openssl ecparam -name secp256k1 -genkey -noout -out keys/picofido_sb.pem
SECURE_BOOT_PKEY="$PWD/keys/picofido_sb.pem"

mkdir -p build
cd build

[ -d pico-sdk  ] || git clone --depth 1 --branch 2.1.1 --recurse-submodules --shallow-submodules https://github.com/raspberrypi/pico-sdk
[ -d picotool  ] || git clone --depth 1 --branch 2.1.1 https://github.com/raspberrypi/picotool
[ -d pico-fido ] || git clone --depth 1 --branch v8.0 --recurse-submodules --shallow-submodules https://github.com/polhenarejos/pico-fido

mkdir -p picotool/build
cd picotool/build
PICO_SDK_PATH="$BUILD_DIR/pico-sdk" cmake .. -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/picotool-install"
make
make install
cd -

mkdir -p pico-fido/build
cd pico-fido/build

# Remove the unused HID keyboard interface
sed -i '/#define PHY_USB_ITF_ALL/s/ | PHY_USB_ITF_KB//' \
  ../pico-keys-sdk/src/fs/phy.h

# Lower the default WS2812 brightness (range: 0-15)
sed -i 's/phy_data.led_brightness : MAX_BTNESS/phy_data.led_brightness : 1/' \
  ../pico-keys-sdk/src/led/led_ws2812.c
# Keep the LED off while idle
sed -i '/MODE_MOUNTED *=/s/LED_COLOR_GREEN/LED_COLOR_OFF/' \
  ../pico-keys-sdk/src/led/led.h

sed -i 's/^set(USB_VID 0x2E8A)/set(USB_VID 0x1050)/; s/^set(USB_PID 0x10FE)/set(USB_PID 0x0402)/' \
  ../CMakeLists.txt

# Stop core1 while button_wait() reads BOOTSEL through the flash CS pin
grep -q picok_button_read_locked ../pico-keys-sdk/src/button.c || \
sed -i -e 's/button_pressed = picok_board_button_read();/button_pressed = picok_button_read_locked();/' \
  -e '/^int button_wait(void) {/i\
static bool picok_button_read_locked(void) {\
#ifdef PICO_PLATFORM\
    if (!multicore_lockout_start_timeout_us(1000)) {\
        return false;\
    }\
#endif\
    bool pressed = picok_board_button_read();\
#ifdef PICO_PLATFORM\
    multicore_lockout_end_timeout_us(1000);\
#endif\
    return pressed;\
}\
' ../pico-keys-sdk/src/button.c



PICO_SDK_PATH="$BUILD_DIR/pico-sdk" CFLAGS="-DPICO_DEFAULT_WS2812_PIN=22" \
  cmake .. -Dpicotool_DIR="$BUILD_DIR/picotool-install/lib/cmake/picotool" \
    -DPICO_BOARD=pico2 \
    -DSECURE_BOOT_PKEY="$SECURE_BOOT_PKEY" \
    -DFORCE_BUTTON_WAIT=ON \
    -DENABLE_OATH_APP=OFF \
    -DENABLE_OTP_APP=OFF
make
