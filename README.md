# roboparty_base

Base package for RoboParty robot platform. Initializes the `/opt/roboparty` directory structure and configures system-level dependencies.

## What's included

- `/opt/roboparty/{lib,include,bin,share}` directory skeleton
- `ldconfig` configuration for `/opt/roboparty/lib`
- `CMAKE_PREFIX_PATH` and `PKG_CONFIG_PATH` environment setup via `/etc/profile.d/roboparty.sh`
- udev rules for CAN adapters (F81601A, Hipnuc, RDK, Roboparty)
- udev rules for EtherCAT devices (DM, IF1100)
- udev rules for serial devices (Hipnuc, TWS)

## Build deb package

```bash
./build_deb.sh
```

The `.deb` file will be generated in the current directory.

## Install

```bash
sudo dpkg -i roboparty-base_*.deb
```

## Uninstall

```bash
sudo dpkg -r roboparty-base     # remove
sudo dpkg -P roboparty-base     # purge (removes /opt/roboparty)
```
