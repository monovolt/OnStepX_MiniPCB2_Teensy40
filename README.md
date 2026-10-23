OnStepX for MiniPCB v2 (Teensy 4.0) Dobsonian Alt-Az GOTO
=========================================================

MiniPCB v2 (Teensy 4.0)와 TMC5160 드라이버로 만든 돕소니언 Alt-Az GOTO 마운트용 OnStepX
펌웨어 포크입니다. 이 섹션 아래부터는 원래 OnStepX README입니다.

## 출처

```
hjd1964/OnStepX                (OnStepX 원본, Howard Dutton)
  └─ hjoungjoo/OpenX_pio_E4    (하정주: PlatformIO 빌드, FYSETC E4/ESP32 타깃, 각종 수정)
       └─ monovolt/OnStepX_MiniPCB2_Teensy40   (이 저장소: MiniPCB v2 / Teensy 4.0 포팅, 마운트 튜닝)
```

- **OnStepX**: [hjd1964/OnStepX](https://github.com/hjd1964/OnStepX), Howard Dutton, GPL-3.0
- **OpenX_pio_E4**: [hjoungjoo/OpenX_pio_E4](https://github.com/hjoungjoo/OpenX_pio_E4), 하정주.
  이 저장소는 여기서 fork했습니다.
- **TMCStepper**: [teemuatlut/TMCStepper](https://github.com/teemuatlut/TMCStepper), MIT.
  `lib/TMCStepper`에 수정본을 포함했습니다(아래 참고).

펌웨어 원작자와 저작권은 위 저장소들에 있고, 이 저장소의 변경분도 같은 GPL-3.0을 따릅니다.
원본의 수정 사항은 가능한 한 그대로 따라가고, 이 저장소에서는 하드웨어에 맞춘 설정과 꼭 필요한
수정만 유지합니다.

## 하드웨어 구성

| 항목 | 구성 |
|---|---|
| 컨트롤러 | MiniPCB v2 + Teensy 4.0 (`PINMAP MiniPCB2`) |
| 모터 드라이버 | TMC5160T Pro V1.0 ×2 (SPI) |
| 마운트 | 돕소니언 Alt-Az (`MOUNT_TYPE ALTAZM_UNL`) |
| 전원 | USB-PD 보조배터리 20V |
| 수동 조작 | ST4 핸드 컨트롤러 (SHC, Teleran Industries) |
| WiFi | Wemos D1 Mini (SmartWebServer, `SERIAL_B`) |
| 메인 제어 | PiFinder: Teensy USB 포트에 연결, INDI + LX200 OnStepX 드라이버 |

### 축 구성

| | axis1 (방위각) | axis2 (고도) |
|---|---|---|
| 모터 | 17HS6401S (60mm, 1.5Ω/상) | 17HS8401S (48mm, 1.8Ω/상) |
| 감속 | 벨트 2.5:1 (16T:40T) × 웜 90:1 = **225:1** | 유성기어 5.18:1 × 벨트 2:1 (20T:40T) × 웜 90:1 = **932.4:1** |
| `STEPS_PER_DEGREE` | 16000 | 66304 |
| 마이크로스텝 (추적 / GOTO) | 128 / 128 | 128 / 32 |
| 전류 | 1500mA | 1500mA |

`STEPS_PER_DEGREE` = 200 풀스텝/회전 × 마이크로스텝 × 감속비 / 360

## 원본 대비 주요 변경점

- **Teensy 4.x 소프트웨어 SPI 타이밍 수정** (`lib/TMCStepper/src/source/TMC_platforms.h`):
  TMCStepper의 SW-SPI가 600MHz Teensy 4.x에서 SCK를 너무 빨리 토글해서 TMC5160 레지스터
  쓰기가 조용히 깨졌습니다. 칩은 응답하지만 모터에 전류가 흐르지 않았습니다. SCK 에지마다
  2µs 대기를 넣어 고쳤습니다. TMCStepper 라이브러리 자체의 버그라서, Teensy 4.x에서 이
  라이브러리의 SW-SPI를 쓰는 다른 프로젝트에도 해당합니다.
- **빌드 환경** `onstepx_teensy40_minipcb2` 추가 (`platformio.ini`, 기본 env)
- **마운트 튜닝** (`Config.h`, `Tmc5160.cpp`): 위 표의 스텝/전류 값, 축 방향, 홈 고도 84.9°,
  고도 한계 85°, 슬루 속도/가속, TMC5160 PWM 주파수 ~23.4kHz, SpreadCycle 히스테리시스
- **테스트 스크립트** `scripts/onstep.ps1`: 시리얼로 LX200 명령 하나를 보내고 응답을 출력

자세한 작업 기록과 주의사항은 [CLAUDE.md](./CLAUDE.md)에 있습니다.

## 빌드와 업로드

```bash
pio run -e onstepx_teensy40_minipcb2
```

업로드는 Teensy Loader(USB HID)로 합니다. USB 시리얼은 115200 baud입니다.

```powershell
.\scripts\onstep.ps1 GVP              # 제품명 확인
.\scripts\onstep.ps1 Ms -Port COM5    # 남쪽으로 가이드 속도 이동 (Q로 정지)
```

---

OnStepX Telescope Controller
===========================

# What is OnStepX?
OnStepX is the advanced version of the OnStep computerized telescope controller with support for interfacing with/controlling a variety of motor drivers (and so motors) including Step/Dir, ODrive, and Servo (a combination of encoder and DC motor or Stepper motor) types.

It supports:
* Telescope Mount control (Alt/Azm and Equatorial GEM/Fork.)  Optional support for Eq mounts with Tangent Arm Declination.  Usually the Goto capability is enabled, but that's optional as well for those who just want basic mount control.
* Telescope Rotator control (including Alt/Azm de-rotation.)
* Telescope Focuser control (up to 6 focusers so it can handle collimation as well as focusing.)
* Telescope Accessory control (combination of up to 8 dew-heaters, switches, analog PWM.)

# Features
OnStepX supports a wide variety of connection options.  Several serial
"command channels" can be utilized. One of the these is normally devoted to a USB
connection and for the other(s) choose from the following:

* Bluetooth
* ESP8266 WiFi
* Arduino M0/Ethernet Shield
* Even another USB port or RS232 serial isn't very difficult to add.

In the case of running OnStepX on an ESP32 it can provide its own Bluetooth or WiFi IP command channels without additional hardware by simply activating the feature in OnStepX.

Other software in the OnStep ecosystem include:

* an [ASCOM](http://ascom-standards.org/) driver (with IP and Serial support),
* an Android App useable over WiFi or Bluetooth equipped Phones/Tablets,
* a "built-in" website (on the Ethernet and/or WiFi device),
* a full planetarium program that controls all features ([Sky Planetarium](http://stellarjourney.com/index.php?r=site/software_sky)).

OnStep is compatible with the LX200 protocol. This means it can be controlled
from other planetarium software, like: Sky Safari, CdC (even without ASCOM),
Stellarium, etc.

There are also [INDI](http://www.indilib.org/about.html) drivers so it can be used from Linux, with CdC or KStars.

# Documentation
Detailed documentation, including the full set of features, detailed designs for
PCBs, instructions on how to build a controller, how to configure the firmware
for your particular mount, can all be found the [OnStep Group Wiki](https://groups.io/g/onstep/wiki/home).

# Change Log
All the changes are tracking in git, and a detailed list can be accessed using the
following git command:
 
git log --date=short --pretty=format:"%h %ad %<(20)%an %<(150,trunc)%s"

# Support
Questions and discussion should be on the mailing list (also accessible via the
web) at the [OnStep Group](https://groups.io/g/onstep/).

# License
OnStep is open source free software, licensed under the GPL.

See [LICENSE.txt](./LICENSE.txt) file.

# Author
[Howard Dutton](http://www.stellarjourney.com)

