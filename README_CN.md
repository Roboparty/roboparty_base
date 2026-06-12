# roboto_base

RoboParty 机器人平台基础包。初始化 `/opt/roboparty` 目录结构并配置系统级依赖。

## 包含内容

- `/opt/roboparty/{lib,include,bin,share}` 目录骨架
- `/opt/roboparty/lib` 的 ldconfig 配置
- 通过 `/etc/profile.d/roboparty.sh` 设置 `CMAKE_PREFIX_PATH` 和 `PKG_CONFIG_PATH` 环境变量
- CAN 适配器 udev 规则（F81601A、Hinpuc、RDK、Roboto）
- EtherCAT 设备 udev 规则（DM、IF1100）
- 串口设备 udev 规则（Hinpuc、TWS）

## 构建 deb 包

```bash
./build_deb.sh
```

`.deb` 文件将生成在当前目录下。

## 安装

```bash
sudo dpkg -i roboto-base_*.deb
```

## 卸载

```bash
sudo dpkg -r roboto-base     # 移除
sudo dpkg -P roboto-base     # 清除（会删除 /opt/roboparty）
```
