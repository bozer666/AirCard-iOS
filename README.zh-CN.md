# AirCard-iOS

<p align="center">
  <img src="ios-app/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="AirCard-iOS 图标" style="border-radius: 28px; box-shadow: 0 8px 24px rgba(0,0,0,0.18);" />
</p>

<p align="center">
  在 iOS 上直接换 Apple 钱包卡面、锁屏密码键盘主题和 PosterBoard 壁纸（iOS 18.0 – 27.2 beta 2）。
</p>

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2018.0%E2%80%9327.2%20b2-blue?style=flat-square&logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/Rust-FFI%20Core-red?style=flat-square&logo=rust" alt="Rust" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License" />
  <a href="https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="通过 PayPal 捐赠" /></a>
</p>

## 概述

AirCard-iOS 无需越狱，即可在设备上自定义 Apple 钱包的卡面图、锁屏密码拨号键盘和锁屏壁纸。

应用通过 LocalDevVPN 提供的本地回环隧道（`10.7.0.1` 或 `127.0.0.1`）与系统内部服务通信；文件操作由 `AirliftFFI`（一个对接 AirTraffic 服务的 Rust 库）完成。

界面语言可在配对页顶栏切换：中文 / English / 跟随系统。

## 兼容性

| iOS 版本 | 状态 | 配对方式 | 支持的功能 |
| :--- | :--- | :--- | :--- |
| **iOS 27.0 – 27.0.1** | ✅ 支持 | 设备上设置内配对，或导入配对文件 | 钱包卡面、密码主题、Tendies 壁纸 |
| **iOS 27.2 beta 1 – beta 2** | ✅ 支持 | 设备上设置内配对，或导入配对文件 | 已测试可用 |
| **iOS 18.0 – 26.x** | ✅ 支持 | 仅导入配对文件 | 钱包卡面与密码主题（经 SideStore / LiveContainer / AltStore 配对文件） |
| **iOS 27.2 beta 3+** | ❌ 已修复 | 无 | 苹果已修复底层的 `airlift` 漏洞，无法使用。 |

> [!IMPORTANT]
> **不要升级到 iOS 27.2 beta 2 之后：** 苹果在 iOS 27.2 beta 3 中修复了 AirTraffic 同步漏洞，升级后文件注入将不再工作。

## 功能

### Apple 钱包卡面
- 把自定义卡面图写入 Passbook 缓存（`cardBackgroundCombined@3x.png`、`@2x.png`，交通卡如 Suica 还包括 `cardBackgroundCombined.pdf`）。
- 刷新正面图和缩略图缓存，打开钱包即可立即看到新卡面。
- 唤起 Apple Pay 时实时检测卡片标识。
- 可单张应用卡面，也可批量刷写所有检测到的卡片。

### 当前卡面读取与原始备份（feature/card-face-preview 分支）
- 点卡片上的下载按钮，即可读取设备上这张卡**当前的卡面**并显示在卡片下方（已设自制皮肤时优先显示皮肤，否则显示当前卡面并带「当前卡面」徽标）。
- 读取到的原始文件会存入 App 本地，作为这张卡的**原始备份**（首次读取生成，之后不会被覆盖）；刷写新皮肤前，若某张卡还没有备份，会先自动备份再刷写。
- 每张有备份的卡片下方有「恢复默认」按钮，点击即可把原始卡面写回设备还原。
- 读取采用「导出 + 立即原样写回」的方式完成，读取结束后设备上的 `.pkpass` 文件保持原样。

### 锁屏密码键盘主题
- 实时拨号盘预览，支持触摸平移和缩放取景。
- 十个按键的整幅海报布局，或单个圆形按键抠图。
- 写入系统拨号盘缓存（`TelephonyUI-10`）。
- 本地化的数字下标选项，包括乌克兰语和俄语西里尔布局。
- 以 `.passthm` 文件导入/导出主题。

### PosterBoard 壁纸（.tendies）
- 直接从「文件」App 导入并解包 `.tendies` 壁纸包。
- 自动检测 PosterBoard 壁纸容器和当前生效的描述符 UUID。
- 把壁纸配置和资源注入 PosterBoard 存储。
- 刷写后自动触发 NeoSpring 注销（respring）应用壁纸，无需重启 iPhone。

### 配对方式
- **导入配对文件**：支持来自 **SideStore**、**LiveContainer**、**iLoader**、**AltStore**、**Jitterbug** 的配对文件（`.mobiledevicepairing`、`.plist`、`.mobilepair`），或从 Mac/PC 导出的配对记录。
- **设备上配对（iOS 27+）**：通过 Bonjour 在本地广播，手机可在「设置 › 隐私与安全性 › 开发者模式 › 与 AirCard-iOS 配对」中与自己配对。
- **安全取消配对**：随时删除当前配对文件，以便重新配对或切换配对凭证。

## 前置条件

1. **iOS 18.0 – 27.2 beta 2**（设备上设置配对需 iOS 27.0+；iOS 18–26 用导入的配对文件）。注意：iOS 27.2 beta 3+ 已被修复。
2. **LocalDevVPN / WireGuard**：以回环模式运行（`10.7.0.1` 或 `127.0.0.1`），使本地连接能到达设备内部服务。
3. **配对记录**：设备上配对或导入的配对文件，二选一。

## 配对设置指南

AirCard-iOS 需要配对记录才能与设备的 lockdown 服务通信。按你的使用方式选择：

### 方案 A：SideStore（推荐）
如果你已经在设备上使用 SideStore，它已经生成了有效的配对文件：
1. 打开 **AirCard-iOS**，进入**配对**页。
2. 点**导入配对文件…**。
3. 在文件选择器中导航到：
   ```text
   我的 iPhone › SideStore › ALTPairingFile.mobiledevicepairing
   ```
4. 选择 `ALTPairingFile.mobiledevicepairing`，应用会立即加载（显示 `Pairing file loaded ✅`）。

### 方案 B：LiveContainer（内含 SideStore）
如果你在 LiveContainer 里运行 SideStore：
1. 打开 **AirCard-iOS** › **配对**页 › 点**导入配对文件…**。
2. 在文件选择器中导航到：
   ```text
   我的 iPhone › LiveContainer › SideStore › Documents › ALTPairingFile.mobiledevicepairing
   ```
   *（视 LiveContainer 版本不同，也可能是 `我的 iPhone › LiveContainer › Data › App › ... › SideStore › Documents`）*
3. 选择 `ALTPairingFile.mobiledevicepairing`。

### 方案 C：iLoader / Jitterbug / AltStore / 电脑
- **iLoader / Jitterbug**：在对应应用里把配对文件（`<UDID>.mobiledevicepairing`）导出到「文件」App，再在 AirCard-iOS 中导入。
- **Mac / PC**：用 `jitterbugpair`、`pymobiledevice3` 生成配对记录，或从电脑上复制（macOS 为 `/var/db/lockdown/<UDID>.plist`，Windows 为 `%ProgramData%\Apple\Lockdown\<UDID>.plist`），通过隔空投送/传输到设备后在 AirCard-iOS 中导入。
- **手动放置**：也可以把 `.mobiledevicepairing` 或 `.plist` 直接放进「文件」App 的 `我的 iPhone › AirCard-iOS`，它会出现在*在文稿中发现*列表里待用。

### 方案 D：设备上配对（仅 iOS 27+）
在运行 iOS 27 或更新系统的设备上：
1. 在**配对**页点**配对这台 iPhone**。
2. 记下屏幕上显示的 6 位 PIN 码。
3. 打开**设置 › 隐私与安全性 › 开发者模式 › 与 AirCard-iOS 配对**。
4. 输入 PIN 码批准配对。AirCard-iOS 会完成握手并保存凭证。

## 安装

使用你习惯的侧载方式安装 `AirCard-iOS.ipa`：

- SideStore 或 AltStore
- TrollStore
- LiveContainer
- Xcode 或 iOS App Signer

## 从源码构建

### 环境要求
- macOS 14.0 或更新版本，Xcode 16 或更新版本
- XcodeGen（`brew install xcodegen`）
- Rust 工具链（仅在重新构建 `rust-core` 时需要）

### 构建 IPA
```bash
git clone https://github.com/mak5er/AirCard-iOS.git
cd AirCard-iOS
./build-ipa.sh
```

构建完成的包位于 `build/AirCard-iOS.ipa`。

### 重新构建 Rust 框架
如需编译 `rust-core` 的改动：
```bash
./build-ios.sh
```

## 仓库结构

```
AirCard-iOS/
├── ios-app/                   # SwiftUI 应用
│   ├── AirCardApp.swift       # 应用入口与生命周期
│   ├── AppViewModel.swift     # 状态管理与漏洞利用编排
│   ├── ContentView.swift      # 主要 UI 视图
│   ├── TendiesView.swift      # PosterBoard 壁纸视图
│   ├── TendiesEngine.swift    # Tendies 解包与注入逻辑
│   ├── RespringHelper.swift   # NeoSpring WebKit 注销实现
│   ├── Models.swift           # 图像切片、主题布局、打包
│   ├── PairingController.swift# Bonjour 主机与配对同步
│   ├── NetworkStatus.swift    # VPN 回环检测
│   ├── Utilities.swift        # 后台保活与工具函数
│   ├── GrappaHelper.[h,m]     # ATC 协议辅助
│   ├── Info.plist             # Bundle 配置
│   └── Assets.xcassets/       # 应用图标与图像资源
├── AirliftFFI.xcframework/    # 已编译的 arm64 Rust 静态库与头文件
├── rust-core/                 # Rust 核心源码
├── project.yml                # XcodeGen 项目定义
├── build-ipa.sh               # IPA 构建脚本
├── build-ios.sh               # Rust 框架构建脚本
├── LICENSE                    # MIT 许可证
├── README.md                  # 项目文档（英文）
└── README.zh-CN.md            # 项目文档（简体中文）
```

## 致谢

- **[@mak5er](https://github.com/mak5er)**：主开发者，负责 UI、密码主题、Tendies 引擎、设备上配对。
- **[@merybist](https://github.com/merybist)**：最初的基础移植。
- **[@0xjohnnydev](https://github.com/0xjohnnydev)** 的 **[AirLift](https://github.com/0xjohnnydev/airlift)**：`AirliftFFI` 底层的 AirTraffic 与 ATAirlock 沙箱逃逸研究。
- **[NeoSpring](https://github.com/rooootdev/neospring)**：Swift 实现由 **[@skadz108](https://github.com/skadz108)** 与 **[@rooootdev](https://github.com/rooootdev)** 完成，**[@neonmodder123](https://github.com/neonmodder123)** 提供 WebKit GPU 进程注销技术。
- 基于 **AirCard** 项目的理念构建。

## 支持与捐赠

如果你想支持 **[@mak5er](https://github.com/mak5er)** 的 AirCard-iOS 开发：

- **Twitter / X**：[@mak5er](https://x.com/mak5er)
- **GitHub**：[@mak5er](https://github.com/mak5er)
- **PayPal**：[通过 PayPal 捐赠（Maksym Reva）](https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y)
- **TON**：`UQBm9KPhtMw-XVVjirUoa09wzrlyWsbeZhKfefl1Uw-qNZ-r`
- **USDT (TRC20)**：`TDkDMCyjYxgvkWUnQiF5Erk2RyPQMT6G1n`
- **USDT / BNB (BEP20)**：`0x0954dc491c502849d04956ef74634aa5931a08e8`

## 许可证

MIT 许可证。详见 [LICENSE](LICENSE)。
