### RedHead operates independently and relies entirely on community donations to stay online and continue developing free and open-source projects. We support Bitcoin, Monero, and Stripe -- but we prefer bitcoin/monero donations, as Stripe is unreliable as of the current moment.
### You can find all of our donation methods on our website:
[redheadindustries.xyz](https://redheadindustries.xyz)

# LenovoKeyboardFixer

**Author:** RedHead Industries (Technologies Branch)  
**License:** GNU General Public License v3.0  
**Status:** Stable / Production-Ready  
**Maintainer:** RedHead Industries - Technologies Branch  
**Supported OS:** GNU/Linux (All modern distributions)  
**Supported Power Managers:** `systemd`, `elogind`, `pm-utils`

---

## 🧠 Overview

**LenovoKeyboardFixer** is a free and open-source bugfix utility developed by **RedHead Industries** to solve a long-standing issue affecting **Lenovo laptops on Linux**.

### 🐛 The Problem
On many Lenovo systems, suspending or hibernating the device causes the built-in **PS/2 keyboard** (and occasionally the touchpad) to stop functioning after wake.  
This issue is caused by the kernel’s `i8042` controller stack not reinitializing properly after resume.

### 💡 The Solution
This script installs a **post-resume hook** that automatically:
- Rebinds the `i8042` (PS/2) keyboard and touchpad drivers (`atkbd`, `psmouse`)
- Rebinds any detected `i2c_hid_acpi` input devices
- Retriggers the Linux input subsystem to make sure everything works without rebooting

It supports **systemd**, **elogind**, and **pm-utils** environments, making it a universal fix for nearly all modern Linux distributions.

---

## ⚙️ Installation

Run the following commands in your terminal:

```bash
git clone https://https://github.com/redhead-industries/LenovoKeyboardFixer.git
cd LenovoKeyboardFixer
chmod +x redhead-lenovo-kbd-fix.sh
sudo ./redhead-lenovo-kbd-fix.sh install
````

The tool will automatically detect your system’s sleep management system (systemd, elogind, or pm-utils) and install the appropriate hook.

---

## 🔍 Commands

| Command                | Description                                                |
| ---------------------- | ---------------------------------------------------------- |
| `install`              | Installs the resume hook and activates the fix             |
| `uninstall`            | Removes all installed hooks                                |
| `test`                 | Runs the fix immediately without suspending                |
| `enable-kernel-quirk`  | Adds kernel parameters (`i8042.reset i8042.nomux`) to GRUB |
| `disable-kernel-quirk` | Removes the above kernel parameters from GRUB              |
| `status`               | Displays installation details and system compatibility     |

---

## 🧩 Example Usage

```bash
# Install the hook
sudo ./redhead-lenovo-kbd-fix.sh install

# Test the fix immediately
sudo ./redhead-lenovo-kbd-fix.sh test

# Enable kernel quirks for legacy controllers
sudo ./redhead-lenovo-kbd-fix.sh enable-kernel-quirk

# Check current installation status
sudo ./redhead-lenovo-kbd-fix.sh status
```

After installation, the fix will automatically execute whenever your system resumes from suspend or hibernate.

---

## 🧰 Supported Lenovo Devices

This script targets **Lenovo laptops** that use PS/2 or I²C input devices.
This Bash script has been tested only on a Lenovo IdeaPad Slim 3 (82XM) as of now.

---

## 🧱 Technical Details

### What It Does

* Detects Lenovo hardware via `/sys/class/dmi/id/sys_vendor`
* Executes a post-resume script to rebind `serio` (PS/2) and `i2c_hid` devices
* Retriggers the `udev` input subsystem so that libinput/X11/Wayland pick up the devices

### Files Installed

| Path                                                             | Purpose                    |
| ---------------------------------------------------------------- | -------------------------- |
| `/usr/lib/redhead-lenovo-kbd-fix/redhead-lenovo-kbd-fix-hook.sh` | Core fix script            |
| `/usr/lib/systemd/system-sleep/99-redhead-lenovo-kbd-fix`        | systemd hook               |
| `/usr/lib/elogind/system-sleep/99-redhead-lenovo-kbd-fix`        | elogind hook               |
| `/etc/default/grub.d/50-redhead-lenovo-kbd-fix.cfg`              | Optional kernel quirk file |

---

## 🔓 License

This project is licensed under the **GNU General Public License v3.0**.

You are free to modify, redistribute, and use this software under the conditions of the GPLv3 license.
See the [LICENSE](LICENSE) file for more details.

---

## ❤️ Contributing

Contributions, bug reports, and feature requests are welcome!
Fork the repository, make your improvements, and submit a pull request.

Please ensure your code:

* Follows shell scripting best practices (`set -euo pipefail`)
* Is properly commented and tested
* Maintains GPLv3 compatibility

---

**© 2025 RedHead Industries — Free and Open Forever.**
