# ADB 连接逻辑

## 目标

电脑运行本 skill 时，先确保「电脑 → 安卓手机」的 ADB 通道可用：

```
adb 已装？ ── 否 → 安装 adb ──→ 再检查
   │ 是
   ↓
设备在线？ ── 否 → 插线/开 USB 调试/允许调试
   │ 是
   ↓
Mika 已装？ ── 是 → Mika 通道
   │ 否
   ↓
android-device-operator 兜底
```

## 自检命令

```bash
bash "$SKILL/scripts/android-bootstrap.sh" --json
```

脚本只做连接和探测，不操作微信、不安装 Mika。

## 退出码

| 码 | 含义 | 处理 |
|---|---|---|
| 0 | 就绪 | 读 `mika` 字段选通道 |
| 10 | adb 不存在/安装失败 | 告知用户；确认后 `--install-adb` 重跑 |
| 11 | 没有设备 | 插线、开发者选项、USB 调试、允许本机调试 |
| 12 | 多台设备 | `--serial <id>` 指定 |
| 13 | 未授权/离线 | 手机上点「允许 USB 调试」；重新插线 |
| 20 | 缺少 node | 安装 Node.js |

## 安装 adb

脚本的 `--install-adb` 会按系统选择：

| 系统 | 命令 |
|---|---|
| macOS | `brew install --cask android-platform-tools` |
| Debian/Ubuntu | `sudo apt-get update && sudo apt-get install -y android-tools-adb` |
| Fedora | `sudo dnf install -y android-tools` |
| Arch | `sudo pacman -S --noconfirm android-tools` |
| Windows | `winget install --id Google.PlatformTools -e` |

没有 Homebrew / 包管理器 / winget 时，脚本会打印官方下载地址：
<https://developer.android.com/tools/releases/platform-tools>

**安装是系统变更。** 用户已经明确要求「没装就装」时可以直接装；否则先说明要装什么、
为什么装、需要网络/管理员权限，再执行。

## 常见 adb 路径

脚本会依次找：

- `command -v adb`
- `$ANDROID_HOME/platform-tools/adb`
- `$ANDROID_SDK_ROOT/platform-tools/adb`
- `~/Library/Android/sdk/platform-tools/adb`（macOS）
- `~/Android/Sdk/platform-tools/adb`（Linux）
- `/opt/homebrew/bin/adb`、`/usr/local/bin/adb`、`/usr/bin/adb`

找不到时设置 `ADB=/path/to/adb` 也可以（脚本会读环境变量）。

## 无感连接的条件

三个条件同时满足：

1. `adb` 可执行；
2. `adb devices` 里目标设备状态是 `device`；
3. 手机装了 Mika（`com.wangzan101.mika`）。

满足时不需要用户额外操作；缺一个就按退出码处理。
**不要「重试三次」**——`unauthorized` 重试一百次也还是 `unauthorized`。

## 多设备

- 只有一台：自动选。
- 多台：脚本退出 12，打印列表；用 `--serial <id>` 重跑。
- 不要「选第一个」；多台设备时选错会操作到别人的手机。

## 无线 ADB

默认 USB。若用户明确要用无线：

```bash
adb connect <手机IP>:5555
adb devices -l
```

需要手机和电脑同一网络、手机已开无线调试。无线连接更容易掉线；
本 skill 默认不主动开启。

## 安全

- 只给用户自己的手机授权；不要在陌生电脑上点「允许 USB 调试」。
- 不安装来源不明的 APK。
- 不读取/保存微信账号密码、短信验证码、支付信息。
- Mika token 等同「能操作这台手机」的凭据；不要写进仓库、不要发给第三方。
- 本 skill 不需要 root；不要为了跑活动去 root 手机。

## 兜底来源

`android-bootstrap.sh --json` 的 `fallback_source` 有三种：

| 值 | 含义 | 处理 |
|---|---|---|
| `github` | 已用 `ensure-fallback.sh` 从 GitHub 克隆并 pin 到 c975a22 | 直接用 |
| `local` | 本地 `~/.agents/skills/android-device-operator` 或 `~/Project/android-device-operator` | 先注明「本地副本」；严格用 GitHub 版就 `ensure-fallback.sh --install` |
| `none` | 没找到 | 先 `ensure-fallback.sh --install`；失败就交还用户 |

不要用本地副本冒充 GitHub 版；两者内容在 2026-11-03 基本一致，但来源和可复现性不同。
