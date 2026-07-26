# TS18 完整文件选择器

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

这是一个 Magisk 模块，用于修复受支持的 TS18 车载主机上的 Android 文件选择器。

## 为什么需要这个模块

在部分 TS18 主机上，文件选择器只显示 **Download（下载）** 和 USB 存储。应用无法选择内部存储其他文件夹中的文件或文件夹。

本模块恢复 Android 10 的正常文件选择器，并增加一个需要 Root 权限的文件来源。

## 本模块提供什么

- 访问 `/storage/emulated/0` 下的全部普通内部存储。
- 一个额外的 **Internal storage (full)（完整内部存储）** 入口。
- 一个 **Root file system（Root 文件系统）** 入口，用于需要 Magisk Root 权限的文件。
- 连接 U 盘时显示 TS18 USB 存储。
- 支持使用 Android 系统文件选择器的应用选择文件和文件夹。

## 使用条件

- Topway **TS18** 主机，运行 Android 10。
- UIS8581A / SP9863A TS18 硬件。
- Magisk 28 或更高版本已经正常工作。

本模块不适用于 TS10、TS10S 或仅外观相似的其他主机。

本模块不会安装 Magisk，也不会自行取得 Root 权限。

## Root 固件来源

本项目使用的 TS18 Magisk Root 固件来自 [4PDA 的 Topway TS10 和 TS18 社区主题](https://4pda.to/forum/index.php?showtopic=1015856)。

4PDA 是第三方社区。本项目不制作、不托管，也不验证其中的固件。

只能使用与主机的系统版本、主板、屏幕、面板和启动配置完全匹配的固件。错误的固件可能使主机无法启动。更改固件前请先制作完整备份。如果不能确认完全匹配，请停止操作。

如果主机上的 Magisk 已经正常工作，则不需要重新安装固件。

## 安装方法

1. 从[最新版本](https://github.com/cbkii/ts-docsui/releases/latest)下载模块 ZIP 文件。
2. 打开 **Magisk**。
3. 打开 **模块**，选择 **从本地安装**。
4. 选择下载的 ZIP 文件。
5. 重启车载主机。

重启后，从任意应用打开文件选择器。正常情况下会看到普通内部存储、完整内部存储和 Root 文件系统。只有连接 USB 存储时才会显示 USB 入口。

## 如果不能正常工作

1. 确认主机是 TS18、Android 10，并且 Magisk 已正常取得 Root 权限。
2. 安装或更新模块后重启一次。
3. 在 Magisk 中打开本模块，然后按 **Action（操作）**。
4. 在以下位置找到诊断 ZIP 文件：

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

将该 ZIP 文件附加到新的 GitHub Issue。不要为了测试本模块而安装其他固件。

## 安全说明

本模块使用 Magisk 的 systemless 方式工作。它不会刷写 boot、MCU、CAN、LCD、开机标志或固件分区。

**Root file system** 入口具有真实 Root 权限。不要修改或删除不了解的文件。只读系统分区仍然保持只读。

## 技术信息

开发者和高级用户请阅读[技术与开发指南](docs/DEVELOPMENT.md)。

