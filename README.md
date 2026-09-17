# 叮咚 DingClock

一个会**跳过休息日**的 iOS 闹钟。对标并超越 iOS 27 时钟 App 新增的「工作日（含调休）」闹钟。

- 周末、法定节假日自动静音
- **调休补班日照响** —— 这是最容易睡过头的一天，也是旧版 iOS 闹钟的重灾区
- 系统做不到的：大小周、自定义星期、手动标记某天放假/上班、跟随或不跟随国家调休

## 核心机制

iOS 系统闹钟的重复规则只认「每周固定周几」，认不出节假日。所以不能只排一条周重复就完事。

真正的做法是**先判定日期属性，再决定响不响**：

```
节假日数据（国务院公告 / holiday-cn）
  → 工作日判定引擎（手动标记 > 调休补班 > 法定放假 > 周模式）
  → 排期窗口（把未来 N 天里的每个工作日展开成具体日期）
  → AlarmKit 逐个排期（每个工作日挂一个一次性系统闹钟）
  → 滚动刷新（进前台 / 后台唤醒时把窗口往前推）
```

因为 AlarmKit 的重复规则只有 `.weekly([周几])` 和 `.never` 两种，把工作日**逐个展开成具体日期**是绕不开的一步。

## 响铃靠什么

[AlarmKit](https://developer.apple.com/documentation/alarmkit)（iOS 26 引入）是苹果第一次把**系统级闹钟**开放给第三方：突破静音模式与专注模式、上锁屏与灵动岛，权限规格和系统时钟 App 同级。

本项目**不做本地通知兜底**。本地通知突破不了静音模式、锁屏不可靠，拿它冒充闹钟只会让人睡过头。不支持就明确告诉用户不支持。

## 目录结构

```
DingClock/
├── Core/
│   ├── Holiday/          # 节假日数据：模型、索引、远端更新
│   ├── Engine/           # 判定与排期（核心，纯逻辑，可单测）
│   │   ├── DayKind.swift          # 日期属性：工作日/周末/法定放假/调休补班/手动标记
│   │   ├── WeekPattern.swift      # 周模式：五天制/大小周/自定义
│   │   ├── WorkdayCalendar.swift  # 判定引擎（优先级链路）
│   │   └── SchedulePlanner.swift  # 滑动窗口排期
│   ├── Alarm/            # 响铃层：协议 + AlarmKit 实现 + 调试实现
│   └── Store/            # 编排与持久化
├── Features/             # SwiftUI 界面
└── Resources/Holidays/   # 内置离线数据 2024–2026
DingClockWidget/          # 闹钟的 Live Activity（灵动岛/锁屏倒计时）
Shared/                   # 主 App 与 Widget 共用的类型
DingClockTests/           # 44 个单元测试
```

## 构建与验证

```bash
./scripts/build.sh          # 编译 + 测试 + 装进模拟器并运行
./scripts/build.sh test     # 只跑测试
```

测试全部用**真实的国务院 2026 年调休数据**构造用例，覆盖：法定假日静音、6 个调休补班日必响、大小周轮换、手动标记优先级、中秋+国庆连休逐日核对、排期 ID 幂等性。

## 真实响铃：已接入 ✅

响铃层已经接上 **AlarmKit（iOS 26 系统级闹钟）**，工具链是 Xcode 26.3 + iOS 26.2 SDK。
设置页「后端」会显示「AlarmKit（系统级闹钟）」。

### 怎么构建

```bash
DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/build.sh
```

`DINGCLOCK_XCODE` 也可以不传 —— `scripts/lib-toolchain.sh` 会自动挑「装了 iOS 26+ SDK」的那个 Xcode。
工程最低系统已提到 iOS 26.0（`project.yml` 里 `deploymentTarget`）。

### ⚠️ 模拟器上授权是"已拒绝"

AlarmKit 的授权弹窗**在模拟器上不会真正弹出**，会直接被拒。这是模拟器的限制，不是 bug。
表现是设置页「授权状态：已拒绝」、列表页提示「还没给闹钟权限」。

所以两件事只能在**真机**上验证：
1. 授权弹窗能否正常弹出并同意
2. **响铃是否真的突破静音模式** —— 这个模拟器无论如何都验不出来

### 当初怎么把 Xcode 26.3 装上的（换机器时参考）

- 版本门槛：**macOS Sequoia 15.6+ 最高只能装到 Xcode 26.3**（26.4 起要 macOS Tahoe 26.2）
- 过季版本 App Store 拿不到，得走 <https://developer.apple.com/download/all/?q=Xcode>（免费 Apple ID 即可）
- 下载 `Xcode_26.3_Apple_silicon.xip`（仅 **2.11 GB**，别下 Universal）
- **双击解压会在原目录得到 `Xcode.app`，直接拖进 /Applications 会覆盖现有 Xcode** ——
  必须先改名再移动
- 装完首次启动会弹许可协议与组件安装，等价于：
  `sudo xcodebuild -license accept` 和 `xcodebuild -runFirstLaunch`
- `xip --expand` 在部分受限环境跑不了（报 `Failed to initialize xip sandbox`），用 Finder 双击即可

### 编译时踩过的 AlarmKit API 坑（iOS 26.2 SDK 实测）

以下都与网上资料不符，以 SDK 的 `.swiftinterface` 为准：

- `AlarmButton` **没有** `.stopButton` / `.snoozeButton` / `.pauseButton` / `.resumeButton` 这些静态成员，
  必须用 `init(text:textColor:systemImageName:)` 自己构造
- `AlarmAttributes<Metadata>` 的 `metadata` 是 **Optional**
- 三参的 `AlarmPresentation.Alert.init(title:secondaryButton:secondaryButtonBehavior:)` 要 **iOS 26.1+**，
  要贴着 26.0 就用带 `stopButton:` 的四参版本
- `SecondaryButtonBehavior` 只有 `.countdown` 和 `.custom`，**没有** `.snooze`

## 对老项目（min iOS 14 之类）的影响

装 Xcode 26.3 是**并存安装**，不会动现有的 Xcode 16.2 —— 前提是别改 `xcode-select`。
改了的话命令行、CI、CocoaPods、fastlane 才会跟着切过去。

先跑一遍体检：

```bash
./scripts/check-project-compat.sh /path/to/OldApp.xcodeproj
# 也可以用装好的新 Xcode 去评估迁移后的情况：
DINGCLOCK_XCODE=/Applications/Xcode-26.3.app ./scripts/check-project-compat.sh /path/to/OldApp.xcodeproj
```

四个问题分开看，别混在一起：

**1. 能不能编译 / Archive？能。**

苹果表里 Xcode 26 的「部署目标」下限写的是 iOS 15，但**那个范围在 Xcode 26 里只是黄色警告，不是错误**。
实测（把部署目标临时改成 11.0）：

```
warning: The iOS Simulator deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 11.0,
but the range of supported deployment target versions is 12.0 to 18.2.99.
```

编译继续进行。Apple 的 Xcode 产品经理在开发者论坛上说明过：表里那个范围是针对**模拟器支持与真机调试**的，
低于它的目标仍然能编。有人实测 Xcode 26.5 编译 iOS 9.0 目标也只是警告。

**真正会变红的是 Xcode 27。** 从 Xcode 27 起，低于 iOS 15 的部署目标会直接报错中止编译。
所以 Xcode 26.3 是"还能带着老部署目标走"的最后一个版本 —— 这也和它正好是你系统能装的最高版这一点对上了。

**2. 打包完还能不能装到 iOS 14 设备上？能。**

决定安装门槛的是**部署目标**，不是 Xcode 版本。只要 `IPHONEOS_DEPLOYMENT_TARGET` 还是 14.0，
产出的包就能装进 iOS 14。App Store 那边 2026-04-28 起强制用 Xcode 26 + iOS 26 SDK 构建，
但**没有要求提高部署目标**，所以低版本用户不会掉。

顺带一提：**iOS 14 → 15 不会损失任何设备**。iOS 15 支持的机型和 iOS 14 完全一致，最低都是 iPhone 6s / SE 一代。
真被这条警告烦到，直接抬到 15.0 是零成本的。

**3. 界面会变 —— 这条最容易漏。**

用 iOS 26 SDK 编译后，在 iOS 26 设备上界面会**自动套用 Liquid Glass 外观**。老项目大概率会被改得很难看。
临时顶住的办法是往 Info.plist 加：

```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```

注意它是**全局**生效的（整个 App 回到旧外观，不能只对某个页面生效），而且 Apple 打算在 Xcode 27 移除它。
体检脚本会告诉你当前工程有没有加这个键。

**4. 想完全不受影响？**

老项目继续用 Xcode 16.2 编就行。两个 Xcode 并存互不干扰，
本项目自己的脚本都通过 `DINGCLOCK_XCODE` 指定工具链，**不需要 `xcode-select`**。

## 已知限制

- **2027 年数据还没有**。国务院每年 11 月左右才发布次年安排，在那之前 2027 年的日子只能按周模式判定，
  意味着 2027 年元旦当天会照响。联网时会自动同步，设置页的「覆盖范围」会如实反映到哪一年。
- 无网络且内置数据也用尽时，退回「周一至周五」，不会乱响也不会崩。
- 大小周的锚点存在闹钟里。若手动篡改 `alarms.json`，奇偶会错位。

## 环境注意事项

本机 Xcode 16.2 的 `swift-plugin-server` 无法运行（直接收到 SIGTERM），导致**任何编译期宏都展不开**。
因此工程里刻意不使用宏：

- 状态管理用 `ObservableObject` + `@Published`，而不是 `@Observable`
- 预览用 `PreviewProvider` 协议，而不是 `#Preview`

如果你的 Xcode 宏功能正常，可以换回现代写法，但不换也没有任何功能损失。
