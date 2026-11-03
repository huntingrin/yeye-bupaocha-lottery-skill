# 兜底：没装 Mika 时用 android-device-operator

## 何时用

`android-bootstrap.sh --json` 返回 `"mika": false`，或 Mika 桥接失败且用户不同意安装 Mika。
**不要自动装 Mika**；用户要的是「没装 Mika 就用 android-device-operator 控制手机」。

## 加载

兜底技能以 **GitHub 仓库**为准，不要默认拿本地副本冒充：

```bash
bash "$SKILL/scripts/ensure-fallback.sh" --install --json
```

它会稀疏克隆 `https://github.com/marswaveai/cola-skills.git`，pin 到 `c975a22`，
输出 `android-device-operator` 的绝对路径（默认在
`~/.local/share/yeye-bupaocha-lottery/cola-skills/android-device-operator`）。

如果 `ensure-fallback.sh` 失败，才退回本地 `~/.agents/skills/android-device-operator`；
这时在报告里注明「本地副本，非 GitHub 克隆」。不要声称用的是 GitHub 版。

拿到路径后，加载该 skill，按它自己的说明操作；不要在本 skill 里复制它的 CDP/无障碍代码。

## 自检

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" preflight
```

关注：

- `channels` 是否含 `device`；微信小程序通常只能走 `device`。
- `preferred` 可能是 `webview`，但那只对其他 H5 有用；**微信小程序不要用 webview**。
- `next` 里的修复步骤照抄给用户，不要自己发挥。
- 退出码 2 表示需要人（插线、解锁、开调试），不是重试。

## 先把微信带到前台

Mika 跑任务时，物理手机的前台可能是 Mika 的聊天界面（`com.wangzan101.mika`）。
兜底通道读写的是**物理前台**，不是 Mika 的虚拟屏。先切微信：

```bash
adb shell monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1
# 或
adb shell am start -n com.tencent.mm/.ui.LauncherUI
```

再 `snapshot --channel device`，确认 `mCurrentFocus` 是 `com.tencent.mm`。
如果还是 Mika，先按 home/返回，再启动微信；不要在 Mika 的聊天界面上找微信按钮。

## 操作映射

### 1. 打开微信 + 搜索小程序

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" snapshot --channel device
```

先读 `page.text`，确认当前是不是微信。然后：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text~:搜索' --expect-text '搜索'
```

输入「爷爷不泡茶」：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op type --ref 'text~:搜索' --text '爷爷不泡茶' --expect-text '爷爷不泡茶'
```

> `device` 通道的中文输入可能不可用（`NonAsciiInput`）。这时让用户自己输入，
> 或改用 `text~:` 点已有搜索词；不要用剪贴板注入绕过。

搜索结果里按文本点小程序：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text~:爷爷不泡茶' --expect-text '百万奖池'
```

如果同名结果多，先 `snapshot` 把候选列表读给用户，人工确认；**不要选第一个**。

### 2. 进小程序 + 找活动

- 目标页底部有「首页 / 点单 / 百万奖池 / 订单 / 我的」。
- 点「百万奖池」：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text:百万奖池' --expect-text '开始抽奖'
```

- 如果隐私协议弹出，停下，把「拒绝仅浏览 / 同意」读给用户；不要自己点。
- 停在「开始抽奖」前；不要点。

### 3. 登录

- 进「我的」→ 点「登录」→「手机号一键登录」。
- 手机号授权是系统弹窗；**停下交还用户**，不要代选号码。
- 短信/密码更不用说，直接交还。
- 登录后回「百万奖池」，读「剩余次数」。

### 4. 抽奖

只有用户确认后才：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text~:开始抽奖' --expect-text '恭喜'
```

如果 `expect` 超时：先 `snapshot` 读页面，不要连点。
不要点「去使用」「去下单」「去喝一杯」。

### 5. 券包

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text:我的' --expect-text '我的券包'
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --ref 'text~:我的券包' --expect-text '优惠券列表'
```

读券名、折扣/面额、上限、有效期、适用范围、状态、来源；不要点「去使用」。

## 坐标兜底

`device` 通道读不到文本/AX 时，才用坐标：

```bash
node "$ANDROID_SKILL/scripts/cli.mjs" act --channel device \
  --op click --xy 540,1200 --touch --expect-text '百万奖池'
```

规则：

- 坐标必须来自**同一次 snapshot/截图**，不能缓存。
- 一次只点一个，点完必须 `expect` 或重新 `snapshot`。
- 连续两次找不到目标就停，交还用户。
- 不要把坐标固化成「稳定流程」；页面一改就失效。

## 兜底的边界

- 微信小程序不是标准 WebView，CDP 通常不可用；`device` 的无障碍树也可能只给容器节点。
- **2026-11-03 实测**：微信搜索页（`MMFTSSOSHomeWebViewUI`）在 `device` 通道返回
  `text: ""`、`elements: []`；小程序页大概率也读不到。
- 因此兜底不是「一定能跑通」：读不到文本/AX 时，需要截图 + OCR/坐标，或者交还用户。
  不要盲点坐标，也不要把「点了」当成「成功」。
- 如果只能拿到容器节点，优先用页面 OCR/文本 + 坐标；连续两次找不到目标就停。
- 兜底通道的可靠性低于 Mika；**不要承诺「一定能跑通」**。
- 登录、验证码、付款、系统授权永远交还用户。
