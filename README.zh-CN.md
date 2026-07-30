# TS18 文件选择器

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

`ts-docsui` 是一个 Magisk 模块，用于修复受支持的 Topway TS18 Android 10 车载主机上的系统文件选择器。它保留 Android 原生存储提供程序，并增加一个独立的 Magisk Root 文件来源。

## 功能

- 通过 Android 原生提供程序访问 `/storage/emulated/0`。
- 增加 **Internal storage (full)**（完整内部存储）入口。
- 增加 **Root file system**（Root 文件系统）入口。
- 连接兼容的 USB 存储后显示 TS18 USB 入口。
- 支持使用 Android SAF 的应用选择文件和文件夹。

> [!TIP]
> TS18 首次打开目录时可能错误地显示为空。请先刷新当前目录，再判断存储提供程序是否失败。

## 使用条件

- Topway TS18 / UIS8581A / SP9863A 硬件；
- Android 10 / API 29；
- Magisk 28 或更高版本已经正常工作。

不要把 TS10、TS10S 或外观相似的主机视为可互换设备。本模块不会安装 Magisk，也不会自行取得 Root 权限。

## 两个发行版本

每个 Release 都包含两个可安装 ZIP，运行时实现相同：

- `ts-docsui-v<versionCode>.zip`：精简正式版，只包含必要的运行组件。
- `ts-docsui-debug-v<versionCode>.zip`：调试版，额外包含有界诊断工具和 Magisk **Action** 按钮。

日常使用请选择正式版。只有在收集诊断证据时才安装调试版。两个 ZIP 的模块 ID 都是 `ts-docsui`，安装其中一个会替换另一个，请勿同时安装。

## 安装

1. 从[最新版本](https://github.com/cbkii/ts-docsui/releases/latest)下载其中一个 ZIP。
2. 在 Magisk 中打开 **模块**，选择 **从本地安装**。
3. 选择 ZIP。
4. 重启车载主机。

重启后，从应用打开文件选择器。普通内部存储应继续使用 Android 原生来源；完整内部存储和 Root 文件系统由独立 Root 提供程序提供。USB 入口只在 USB 存储已挂载时显示。

## 诊断

诊断工具只包含在调试版中。可在 Magisk 中按 **Action**，或运行：

```sh
su -c '/data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh full'
```

所有诊断工作文件、日志和已校验归档都保存在：

```text
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

普通服务和安装日志保存在：

```text
/storage/emulated/0/Download/ts-docsui/logs/
```

`/data/adb/ts-docsui` 只用于保存运行所需的小型状态、Root helper 和协调标记。

## 安全说明

本模块使用 Magisk systemless 方式工作，不会刷写 boot、MCU、CAN、LCD、开机标志或固件分区。

Root 文件来源具有真实 Root 权限，但 Root 不会使只读 device-mapper 分区变为可写。不要修改受保护的 system、vendor、metadata、Magisk 或 Android 状态路径。

本项目使用的 Root 固件来自 [4PDA 的 Topway TS10 和 TS18 社区主题](https://4pda.to/forum/index.php?showtopic=1015856)。该固件不属于本仓库，也不能证明其他主机兼容。

## 技术信息

开发者和高级用户请阅读[技术指南](docs/DEVELOPMENT.md)和[实体 TS18 验收流程](docs/DEVICE_ACCEPTANCE.md)。
