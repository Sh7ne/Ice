<div align="center">
    <img src="docs/assets/app-icon.png" alt="Ice 应用图标" width="200" height="200">
    <h1>Ice - macOS 菜单栏管理工具</h1>
</div>

<p align="center"><a href="README.md">English</a> | 简体中文</p>

Ice 是一款开源 macOS 菜单栏管理工具，用于隐藏、显示和整理菜单栏图标。本分支提供 Apple silicon（arm64）DMG 安装包，以及实验性的 macOS 27 兼容版本；macOS 14-26 继续使用原有的菜单栏管理方式。

![功能预览](https://github.com/user-attachments/assets/4423085c-4e4b-4f3d-ad0f-90a217c03470)

[![下载](https://img.shields.io/badge/download-latest-brightgreen?style=flat-square)](https://github.com/Sh7ne/Ice/releases/latest)
![平台](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![系统要求](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![许可证](https://img.shields.io/github/license/Sh7ne/Ice?style=flat-square)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy_me_a_coffee-sh7ne-FFDD00?style=flat-square&logo=buymeacoffee&logoColor=000000)](https://www.buymeacoffee.com/sh7ne)

> [!IMPORTANT]
> 本仓库是 [jordanbaird/Ice](https://github.com/jordanbaird/Ice) 的修改分支，由 [Sh7ne](https://github.com/Sh7ne) 维护。分支专属修改始于 2026 年 8 月，继续遵循 GPL-3.0 许可证。上游版权和许可证声明予以保留。

> [!NOTE]
> Ice 仍在持续开发中，部分计划功能尚未实现。macOS 14-26 用户可下载[最新正式版](https://github.com/Sh7ne/Ice/releases/latest)；macOS 27 用户请使用下方的兼容性预览版，不要将正式版下载入口当作预览版入口。

## 安装

### macOS 27 预览版

[下载 macOS 27 兼容性预览版](https://github.com/Sh7ne/Ice/releases/tag/v0.11.13-sh7ne.3-preview.2)。对应源码位于 `macos-27-compatibility` 分支。

在设置的菜单栏布局页面启用 **Experimental app hiding** 后，可以按应用隐藏或展开图标，并为支持的系统菜单栏项目设置可见性。Time Machine 与 Siri 等由同一系统进程托管的项目共用一项设置，不能分别隐藏。

> [!WARNING]
> 这是实验功能，不等同于 macOS 26 版本的完整功能。隐藏期间，部分额外的系统图标也可能消失，点击时钟打开通知中心会受到影响。展开全部分区、关闭实验性隐藏或退出 Ice 后可恢复。Ice Bar、拖拽分区及部分旧版展开方式暂不可用。

启用前请阅读[完整兼容性说明（英文）](https://github.com/Sh7ne/Ice/blob/macos-27-compatibility/docs/MACOS-27.md)。下方功能清单与截图描述的是 macOS 14-26 的旧版实现。

### 手动安装

从[最新正式版](https://github.com/Sh7ne/Ice/releases/latest)或上方预览版页面下载 DMG，打开后将 `Ice.app` 拖入 `Applications`（应用程序）文件夹。

自动生成的 DMG 使用 ad-hoc 签名，未经 Apple 公证。安装或更新后，macOS 可能要求在“系统设置 > 隐私与安全性”中明确允许打开；更新后也可能需要重新授予隐私权限。

### 本地开发者签名构建

要为当前 Mac 构建 Apple silicon 版本，请先安装有效的 Apple Development 或 Developer ID Application 证书，然后运行：

```sh
./Scripts/build-local-release.sh
```

脚本默认选择 Apple Development 签名身份，使用同一开发者团队为 Ice 及所有内嵌服务签名，并保留强化运行时。脚本还会移除 Sparkle 更新组件中的 Intel 架构切片，使生成的应用不依赖 Rosetta。

使用 `ICE_CODE_SIGN_IDENTITY` 可选择另一张已安装的签名证书；若证书属于其他团队，还需通过 `ICE_DEVELOPMENT_TEAM` 指定对应的 Team ID。

在 macOS 26 或更新系统上，可运行独立的 Release 应用与 XPC 往返通信测试，无需申请辅助功能或屏幕录制权限：

```sh
./Scripts/smoke-test-xpc.sh
```

推送版本标签后，GitHub Actions 会自动构建并发布 Apple silicon DMG，无需提供 Apple 凭据。标签格式与签名说明见[发布文档（英文）](docs/RELEASING.md)。

## 功能与路线图

以下已完成功能适用于 macOS 14-26 的旧版实现；macOS 27 的可用功能与限制以上方兼容性说明为准。

### 菜单栏图标管理

- [x] 隐藏菜单栏图标
- [x] “始终隐藏”分区
- [x] 鼠标悬停菜单栏时显示隐藏图标
- [x] 点击菜单栏空白处显示隐藏图标
- [x] 在菜单栏滚动或轻扫以显示隐藏图标
- [x] 自动重新隐藏菜单栏图标
- [x] 应用菜单与已展开图标重叠时隐藏应用菜单
- [x] 通过拖放调整单个菜单栏图标的位置
- [x] 在独立的 Ice Bar 中显示隐藏图标，适用于带刘海屏的 MacBook 等场景
- [x] 搜索菜单栏图标
- [x] 调整菜单栏图标间距（测试功能）
- [ ] 菜单栏布局配置方案
- [ ] 独立分隔项
- [ ] 菜单栏图标分组
- [ ] 满足指定条件时显示菜单栏图标

### 菜单栏外观

- [x] 菜单栏着色（纯色与渐变）
- [x] 菜单栏阴影
- [x] 菜单栏边框
- [x] 自定义菜单栏形状（圆角或分段）
- [ ] 移除菜单栏背景
- [ ] 屏幕圆角
- [ ] 为浅色与深色模式设置不同外观

### 快捷键

- [x] 切换各菜单栏分区
- [x] 显示搜索面板
- [x] 启用或停用 Ice Bar
- [x] 显示或隐藏分区分隔图标
- [x] 切换应用菜单的显示状态
- [ ] 启用或停用自动隐藏
- [ ] 临时显示指定菜单栏图标

### 其他

- [x] 登录时启动
- [ ] 自动更新
- [ ] 菜单栏小组件

## 为什么只支持 macOS 14 及更新版本？

Ice 使用了多项从 macOS 14 开始提供的系统 API，因此目前没有支持更早系统版本的计划。本仓库发布的 DMG 面向 Apple silicon Mac。

## 界面预览

以下截图展示 macOS 14-26 的旧版功能，不代表 macOS 27 预览版已支持全部功能。

### 在菜单栏下方显示隐藏图标

![Ice Bar](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b)

### 拖放整理菜单栏图标

![菜单栏布局](https://github.com/user-attachments/assets/095442ba-f2d0-4bb4-9632-91e26ef8d45b)

### 自定义菜单栏外观

![菜单栏外观](https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3)

### 搜索菜单栏图标

![菜单栏图标搜索](https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8)

### 自定义图标间距

![菜单栏图标间距](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6)

## 许可证

Ice 及本修改分支均采用 [GPL-3.0 许可证](LICENSE)。上游版权与许可证声明保持完整，修改历史及日期记录在 Git 中。
