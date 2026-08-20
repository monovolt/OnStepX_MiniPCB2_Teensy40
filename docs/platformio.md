# Building OnStepX with PlatformIO

This project keeps the original Arduino sketch layout and uses `platformio.ini`
to tell PlatformIO which files to build.

## Environments

Default environment:

```text
onstepx_teensy40_minipcb2
```

- Teensy 4.0
- `MiniPCB2` pinmap from `Config.h`
- `TMCStepper` library (AXIS1/AXIS2 = TMC5160, SPI via dedicated M0..M3 pins)
- WiFi via a WEMOS D1 Mini (ESP8266) companion on `SERIAL_B` (`SERIAL_B_ESP_FLASHING`),
  not a built-in radio
- serial monitor at `115200`

Also present, kept for reference / the original FYSETC E4 target:

```text
onstepx_esp32_mf_oozoo_e4
```

- ESP32 Dev Module compatible board
- `MF_OOZOO_E4` pinmap from `Config.h`
- `huge_app.csv` partition layout
- `TMCStepper` library
- serial monitor at `460800`
- PlatformIO `platformio/espressif32@6.7.0` with Arduino-ESP32 `2.0.16`

Switch environments with PlatformIO's environment picker (bottom status bar in
VS Code) or `pio run -e <env name>`.

`platformio_deps.cpp` exists only to help PlatformIO's Library Dependency Finder
see the ESP32 built-in libraries used through OnStepX headers; it's a no-op
outside of an ESP32 build.

## VS Code

Install the PlatformIO IDE extension, then open this folder. PlatformIO should
detect `platformio.ini` automatically.

Useful commands:

```text
PlatformIO: Build
PlatformIO: Upload
PlatformIO: Monitor
PlatformIO: Clean
```

The workspace also has VS Code tasks that call `tools/pio.ps1`, so
`Ctrl+Shift+B` runs a PlatformIO build even if `pio.exe` is not on `PATH`.

## Upload Port

PlatformIO usually auto-detects the Teensy/ESP32 serial port. If it does not,
add this to the environment in `platformio.ini`:

```ini
upload_port = COM5
monitor_port = COM5
```

Replace `COM5` with the port shown by PlatformIO or Windows Device Manager.
Teensy uploads go through the Teensy Loader (installed with the PlatformIO
Teensy platform); no bootloader button press is normally required over USB.

## Debug

Software serial monitoring works over USB. True breakpoints on the ESP32
target require a JTAG debugger such as ESP-Prog; after wiring it, uncomment
the `debug_tool` lines under `[env:onstepx_esp32_mf_oozoo_e4]` in
`platformio.ini`.
