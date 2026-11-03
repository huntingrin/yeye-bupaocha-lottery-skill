---
name: yeye-bupaocha-lottery
description: >
  专为「爷爷不泡茶」2026-10-29—11-04「瓜分百万奖池」活动写的安卓抽奖 skill，
  **不是通用 Android / 微信自动化工具**。电脑经 ADB 连接手机：adb 已装且设备在线就无感连接；
  adb 没装先装；连上后优先用 Mika（MCP over USB）操作微信；没装 Mika 时改用
  android-device-operator 技能兜底。含登录、抽奖、任务闸门、券包核对和失败处置。
  Use when the user asks to 抽爷爷不泡茶 / 百万奖池 / 新品免单 / 用手机跑这个活动。
  Do not use as a general WeChat/Android automation framework.
metadata:
  version: "1.0.0"
  status: verified
  verified_at: "2026-11-03"
  platforms: darwin, linux, win32
---

# 爷爷不泡茶「瓜分百万奖池」安卓抽奖

> **Scope：一次性活动 skill，不是通用工具。**
> 只服务爷爷不泡茶 2026-10-29—11-04 的「瓜分百万奖池」活动。
> ADB/Mika 只是传输层；活动事实、入口、奖池、任务和闸门都是为这一次活动写死的。
> 跑别的品牌/活动，必须重写 `references/activity-facts.md` 和流程；不要直接套用。

**本文件所在目录就是 `$SKILL`。** 命令里的 `$SKILL` 换成绝对路径。

这个 skill 把「在安卓手机上抽一次爷爷不泡茶」拆成：
**ADB 连接 → 选择 Mika / 兜底通道 → 到达活动页 → 登录 → 抽奖闸门 → 券包核对**。

> iPhone 镜像版见同级 skill `yeye-bupaocha-lottery-ios`。

## 铁律

1. **先跑 ADB 自检，不猜设备。** 连接状态、Mika 是否存在，都以脚本输出为准。
2. **Mika 说「完成了」不算完成。** 必须有页面原文：标题、按钮文案、剩余次数、券包条目。
3. **不可逆动作前必须停。** 隐私协议、会员登录/手机号授权、抽奖、领券、下单、填地址——
   先回报证据，等用户点头。短信/密码永远交还用户。
4. **不自动做任务。** 邀请好友、下单满 5 元都是用户行为；skill 只报告任务，不代做。
5. **单账号、单活动。** 不做多账号、不并发、不代抽、不保存账号凭证。
6. **活动窗口**：2026-10-29 10:00:00 — 2026-11-04 23:59:59。先看当前日期，过期就停。
7. **券以券包为准。** 中奖弹窗可能不写全；必须进「我的 → 我的券包」读券名、折扣/面额、
   上限、有效期、适用范围、状态、来源。

## 第 0 步：Android 连接（每次先跑）

```bash
bash "$SKILL/scripts/android-bootstrap.sh" --json
```

脚本做四件事：

1. 找 `adb`；没有就按 `--install-adb` 安装（macOS 用 Homebrew cask，Linux 用 apt/dnf/pacman）。
2. `adb start-server`，列出设备，选唯一在线设备（多台用 `--serial`）。
3. 检查设备状态：`device` 才算就绪；`unauthorized` / `offline` 需要人。
4. 检查手机上是否装了 Mika（`com.wangzan101.mika`），并报告兜底 skill 路径。

退出码：

| 码 | 含义 | 处置 |
|---|---|---|
| 0 | 就绪 | 看 `mika` 字段选通道 |
| 10 | adb 不存在/安装失败 | 用户已说「没装就装」时直接加 `--install-adb`；否则先说明要装什么 |
| 11 | 没有设备 | 插线、开 USB 调试、在手机上允许本机调试 |
| 12 | 多台设备 | 用 `--serial <id>` 指定 |
| 13 | 设备未授权/离线 | 手机上点「允许 USB 调试」；不行就重新插线 |
| 20 | 缺少 node | 先装 Node.js（Mika 和兜底 CLI 都需要） |

输出示例：

```json
{
  "ok": true,
  "os": "Darwin",
  "adb": "/Users/me/Library/Android/sdk/platform-tools/adb",
  "serial": "<device-serial>",
  "state": "device",
  "mika": true,
  "fallback_skill": "/Users/me/.agents/skills/android-device-operator",
  "fallback_url": "https://github.com/marswaveai/cola-skills/tree/main/android-device-operator",
  "next": []
}
```

### 通道选择

```
mika=true  → A. Mika 通道
mika=false → B. android-device-operator 兜底
```

**无感连接**的条件：adb 已装 + 设备 `device` + Mika 已装。三者都满足时不需要用户额外操作；
缺一个就按上表处理，不要「重试三次」。

## A. Mika 通道（优先）

先加载 `mika-wechat-mini-program` skill（默认 `~/.agents/skills/mika-wechat-mini-program`），
用它自己的桥接脚本，不要在本 skill 里复制 Mika 代码。

```bash
MIKA_SKILL="${MIKA_SKILL:-$HOME/.agents/skills/mika-wechat-mini-program}"
node "$MIKA_SKILL/scripts/mika.mjs" sync
node "$MIKA_SKILL/scripts/mika.mjs" state
```

- `ready=true` 且 `helper_available=true` 才继续。
- `helper_available=false`：`adb shell sh /sdcard/Android/data/com.wangzan101.mika/files/usb-start.sh`，
  再 `sync`。
- `waiting_on_phone`：登录/验证码/系统授权，交给用户；不要 cancel 重下。
- 同一活动所有步骤共用同一个 `conversation`，避免 Mika 丢页面。

跑本 skill 的流程：

```bash
node "$MIKA_SKILL/scripts/mika.mjs" flow "$SKILL/flows/yeye-bupaocha-million-pool.json"
```

流程里的 `gate: true` 步骤会以退出码 3 停下。确认后从下一步继续：

```bash
node "$MIKA_SKILL/scripts/mika.mjs" flow "$SKILL/flows/yeye-bupaocha-million-pool.json" \
  --from draw --conversation <上一步返回的 conversation>
```

## B. android-device-operator 兜底（没装 Mika）

兜底技能**以 GitHub 仓库为准**，不要默认拿本地副本冒充：

```bash
bash "$SKILL/scripts/ensure-fallback.sh" --install --json
```

- 默认稀疏克隆 `https://github.com/marswaveai/cola-skills.git`，pin 到 `c975a22`，
  输出 `android-device-operator` 的绝对路径。
- 之后用这个路径，不要用 `~/.agents/skills/android-device-operator` 除非 ensure 失败。
- 如果 `android-bootstrap.sh` 输出 `fallback_source=local`，报告里要注明「本地副本，
  非 GitHub 克隆」；不要声称用的是 GitHub 版。
- 如果 `fallback_source=none`，先跑 `ensure-fallback.sh --install`；装不上就交还用户。

**不要为了省事自动装 Mika**；用户要的是「没装 Mika 时用这个技能」。

```bash
ANDROID_SKILL="$(bash "$SKILL/scripts/ensure-fallback.sh" --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).path))')"
node "$ANDROID_SKILL/scripts/cli.mjs" preflight
```

- 微信小程序不走 CDP，**优先 `--channel device`**；`preflight` 的 `webview` 只对其他 H5 有用。
- 先把微信带到前台：`adb shell monkey -p com.tencent.mm -c android.intent.category.LAUNCHER 1`；
  Mika 的聊天界面不是微信，兜底通道读写的是物理前台。
- `snapshot --channel device` 读页面文本；用 `text~:` / `ax:` 找元素，必要时 `--xy x,y`。
- 每个动作都要带 `--expect-text`；没有后置条件就不算成功。
- 读不到文本/AX 时，才用坐标；坐标只做一次性，不要固化成稳定流程。
- **2026-11-03 实测**：微信搜索页在 `device` 通道返回空 `text/elements`；小程序页大概率也读不到。
  这时需要截图 + OCR/坐标，或直接交还用户；不要盲点。
- 兜底通道的可靠性低于 Mika；连续两次找不到目标就停，交还用户。

详细映射见 [`references/fallback-android-device-operator.md`](references/fallback-android-device-operator.md)。

## 活动流程（两条通道共用）

### 1. 到达（可逆）

1. 打开微信。
2. 搜索「爷爷不泡茶」，在结果里选**小程序**：
   - 主体：**湖北异想天开生物科技有限公司**
   - 带「交易保障」标识
   - 与官方服务号「爷爷不泡茶NOYEYENOTITE」同一主体
   - 不要选「爷爷茶管家」（爷爷不泡茶（湖北）科技服务有限公司）或
     「爷爷不泡茶信阳商城店」（个人贴图号）。
3. 进小程序。若弹隐私协议「温馨提示」：
   **停下**，把「拒绝仅浏览 / 同意」和协议要点告诉用户，不要自己点。
   Mika 会进入 `waiting_for_answer`；用户确认后用 `mika answer` 回答，再继续到
   「百万奖池」。不要 cancel 重下。
4. 底部导航点 **「百万奖池」**（不是首页横幅，也没有叫「新品抽奖」的入口）。
5. 停在 **「开始抽奖」** 按钮前。不要点抽奖、不要做任务、不要分享、不要下单、不要填地址。

### 2. 登录（闸门）

- 判断未登录：底部「我的」有「登录」/「登录会员尊享多重好礼」，或券包显示「去登录」。
- 点「登录」→「手机号一键登录」→ 微信手机号授权。
- **停下**，把弹窗原文、授权号码、按钮告诉用户；用户确认后再选号码。
- 出现短信验证码、密码、或需要用户手动输入的页面 → 立刻交还用户。
- 登录成功后回「百万奖池」，读「剩余次数」。首次登录会员通常从 0 变 1。

### 3. 抽奖（闸门）

只有同时满足才允许点「开始抽奖」：

- 页面标题是 **「瓜分百万奖池」/「抽 10 克足金 999 金条」**；
- 活动时间在 **2026-10-29 10:00:00 — 2026-11-04 23:59:59** 内；
- 已登录会员是本人；
- 剩余次数 **> 0**；
- 用户明确说「点」。

点完读结果弹窗原文；不要点「去使用」「去下单」「去喝一杯」，不要付款/填地址。

### 4. 券包核对（只读）

「我的」→「我的券包」，读：

- 券名（例：全品类饮品单杯 7 折券（八周年抽奖））
- 折扣/面额、优惠上限（例：7 折，上限 30 元）
- 有效期（例：2026-11-09 23:59）
- 适用范围（门店、饮品、渠道、场景、时段）
- 状态、来源（例：盲盒抽奖）

停在券列表/券详情，不要点「去使用」。

## 已验证事实（2026-11-03）

| 项 | 页面原文 |
|---|---|
| 官方活动名 | 瓜分百万奖池／抽 10 克足金 999 金条 |
| 活动时间 | 2026-10-29 10:00:00 — 2026-11-04 23:59:59 |
| 入口 | 小程序底部导航「百万奖池」 |
| 抽奖按钮 | 「开始抽奖」；登录前「剩余 0 次」，登录后「剩余 1 次」 |
| 会员 | 微信用户 / 初遇 VIP1；手机号一键授权，无短信 |
| 奖池 | 6 档：金条×1、免单券×30,000、买一送一×800,000、9.9 元券×800,000、冰箱贴×120、7 折券不限量 |
| 任务 | 邀请好友（最多 5 次）；下单满 5 元（每日最多 5 次，6 个渠道） |
| 实测抽中 | 全品类饮品单杯 7 折券（八周年抽奖），上限 30 元，2026-11-09 23:59 到期 |

完整原文见 [`references/activity-facts.md`](references/activity-facts.md)。

## 失败处置

| 现象 | 处置 |
|---|---|
| 搜不到小程序 | 让通道回报候选列表；人工确认主体，不要选第一个 |
| 隐私协议弹窗 | 停下，让用户选「拒绝仅浏览 / 同意」 |
| 登录弹窗/手机号授权 | 停下，用户确认号码；短信/密码交还用户 |
| 剩余 0 次 | 不要抽；报告任务：邀请/下单，等用户决定 |
| 抽奖按钮灰/「活动已参与」 | 记录原文，不重试 |
| 券包为空 | 先看登录态；未登录时为空不代表没中奖 |
| 活动已结束 | 停；活动窗口 11-04 23:59:59 |
| Mika `waiting_on_phone` | 用户处理；不要 cancel 重下 |
| 兜底通道读不到页面 | 连续两次失败就停，交还用户；不要盲点坐标 |

## 交付格式

给用户三样东西：

1. **结果原文**：券名、折扣/面额、上限、有效期、适用范围、来源。
2. **当前状态**：剩余次数、是否还能再抽、券是否到账。
3. **下一步建议**：别点「去使用」除非用户要下单；任务是否值得做由用户判断。

## 参考

| 文件 | 内容 |
|---|---|
| `references/activity-facts.md` | 官方页面原文、6 档奖池、任务、券规则、待核 |
| `references/android-connect.md` | ADB 安装/连接/多设备/授权/退出码 |
| `references/fallback-android-device-operator.md` | 没装 Mika 时的兜底操作映射 |
| `flows/yeye-bupaocha-million-pool.json` | Mika 可执行流程（reach/login/draw/coupon） |
| `scripts/android-bootstrap.sh` | ADB 自检、设备选择、Mika 检测 |
