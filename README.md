# 爷爷不泡茶「瓜分百万奖池」抽奖 Skill

> **这不是通用 Android / iPhone / 微信自动化工具。**
>
> 这是一个**只服务一次活动**的 skill：爷爷不泡茶 **2026-10-29 10:00 — 2026-11-04 23:59:59**
> 的「瓜分百万奖池」微信小程序抽奖。
>
> ADB / Mika / iPhone Mirroring 只是传输层；活动入口、6 档奖池、任务、闸门和文案
> 都是为这一次活动写死的。跑别的品牌/活动，必须重写 `references/activity-facts.md`
> 和流程，**不要直接套用**。

## 为什么专门做

- 活动官方名不是「新品抽奖」，是 **「瓜分百万奖池／抽 10 克足金 999 金条」**。
- 入口不是首页横幅，是小程序底部导航 **「百万奖池」**。
- 图片汇总只列 3 档奖品；官方页面有 **6 档**（另有 9.9 元券 80 万、冰箱贴 120、7 折券不限量）。
- 11 次是**总上限含首次**；额外次数靠邀请好友/下单满 5 元，不是免费 11 次。
- 券必须回「我的券包」核对；中奖弹窗可能不写全。

## 两个通道

| 目录 | 平台 | 主通道 | 兜底 |
|---|---|---|---|
| `yeye-bupaocha-lottery/` | Android | ADB + Mika（MCP over USB） | `android-device-operator`（best-effort） |
| `yeye-bupaocha-lottery-ios/` | iPhone | iPhone Mirroring + phone-harness | 本 skill 的 `iphone.py` / `bgphone.py` |

## 状态（2026-11-03 实测）

- **Android**：Mika 到达活动页 + 手机号一键登录；用户手动抽中
  **全品类饮品单杯 7 折券**（上限 30 元，2026-11-09 23:59 到期），Mika 读券包核对。
- **iPhone**：镜像到达活动页；短点「马上抽奖」进入活动页，显示 **「剩余 0 次」**；
  券包 7 折券与安卓同一账号同步。
- **未覆盖**：iPhone 抽奖结果（账号无剩余次数）；Android 抽奖点击是用户手动，
  Mika 只到抽奖前的闸门。
- **Android 兜底**：`android-device-operator` 已按
  <https://github.com/marswaveai/cola-skills/tree/main/android-device-operator>
  接入并 pin 到 `c975a22`；但微信小程序页面在 `device` 通道读不到，
  只能坐标/OCR，**不保证跑通**。

## 安装

```bash
cp -R yeye-bupaocha-lottery ~/.agents/skills/
cp -R yeye-bupaocha-lottery-ios ~/.agents/skills/
```

每个目录都是一个独立 skill，`SKILL.md` 在目录根部。

## 这个仓库不做什么

- **不是**通用微信自动化框架；
- **不是**通用 ADB/Mika/iPhone 操作库；
- **不是**多品牌活动模板；
- **不做**自动邀请、自动下单、自动支付、自动填地址；
- **不做**多账号、代抽、绕过验证码/风控。

它的价值是：把**这一次**活动的入口、奖池、任务、登录态和抽奖闸门写清楚，
并在 Android/iPhone 两条通道上验证到「活动页」和「券包」。

## 安全与合规

- 登录、短信、密码、系统授权永远交还用户。
- 抽奖/领券前必须回报页面证据，等用户确认。
- 单账号、单活动；不并发、不批量。
- 与爷爷不泡茶品牌无隶属关系；活动解释权归品牌方。

## 目录

```
yeye-bupaocha-lottery/          Android（ADB + Mika，兜底 android-device-operator）
  SKILL.md
  scripts/android-bootstrap.sh
  scripts/ensure-fallback.sh
  flows/yeye-bupaocha-million-pool.json
  references/activity-facts.md
  references/android-connect.md
  references/fallback-android-device-operator.md

yeye-bupaocha-lottery-ios/      iPhone（iPhone Mirroring + phone-harness）
  SKILL.md
  scripts/iphone-bootstrap.sh
  scripts/iphone.py
  scripts/bgphone.py
  scripts/repatch.sh
  references/activity-facts.md
  references/iphone-mirroring.md
  references/runbook.md
```

## License

未指定 License。这是一个**单活动案例 skill**，不是通用工具；
如需复用代码/流程，请先联系作者确认。
