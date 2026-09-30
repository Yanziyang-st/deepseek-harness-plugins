# DSH 鲸鱼娘桌宠 🐋

把 **DeepSeek Harness 最小化**，桌面上就会浮出鲸鱼娘陪你；Harness 恢复显示，她自动躲回去。

**她跟着 Harness 一起启动、一起退出**：已注册为当前 profile 的 DSH 插件（`dsh-whale-pet`），
Harness 启动时自动拉起，Harness 退出时自动关闭。

- 零安装：Windows PowerShell 5.1 + WPF，不需要 Node / Electron / npm / 任何第三方模块
- 透明置顶无边框浮窗，空白处鼠标穿透（不挡你点桌面），可拖动、位置自动记忆
- 角色美术用**现成的开源素材**（MIT，见 [THIRD-PARTY.md](THIRD-PARTY.md)），没有素材时用内置矢量画兜底
- 会**感知 Harness 状态**：干活中 / 等你回答 / 空闲 / 打瞌睡，换不同表情
- 单击摸摸头、双击把 Harness 叫回来、右键菜单、托盘图标、滚轮缩放、气泡台词

## 首次安装（从仓库克隆后）

```powershell
git clone https://github.com/Yanziyang-st/deepseek-harness-plugins.git
cd deepseek-harness-plugins\whale-pet

# 1) 下载现成素材（可选，约 10MB）。不下载也能用：自动回退到内置矢量画
powershell -NoProfile -ExecutionPolicy Bypass -File .\fetch-assets.ps1

# 2) 注册成 DSH 插件（Harness 启动时拉起桌宠、退出时关闭）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugin.ps1

# 3) profile 会热加载，几秒内桌宠就起来了；没反应就重启一次 Harness
```

> 仓库里**不含**角色素材（第三方 MIT 素材，体积大且可再生成），所以第 1 步建议跑一下。
> 只想手动启动、不装插件：双击 `start-whale-pet.vbs`。

## 跟 Harness 一起启动 / 退出

| 方向 | 机制 |
| --- | --- |
| Harness 启动 → 桌宠起来 | 插件 `apply()` 里 `spawn` 桌宠进程 |
| Harness 退出 → 桌宠关掉 | 插件 dispose 里 `taskkill /PID <pid> /T /F` 收掉进程树 |
| 兜底（Harness 被强杀、插件没机会清理） | 桌宠自带看门狗：进程名和窗口标题都匹配不到 Harness 超过 20 秒就自行退出 |

插件是普通的工作区文件，装在 profile 里：

```
dsh-plugin/           插件包（package.json + cordis.patch.yml + index.js，Host-only，无依赖）
install-plugin.ps1    安装/卸载脚本（改 profile 的 cordis.patch.yml 前会先备份）
```

```powershell
# 已装好；需要重装或卸载时：
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugin.ps1 -DryRun      # 只看会改什么
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugin.ps1              # 安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugin.ps1 -Uninstall   # 卸载
```

profile 改动会被 Harness 热加载（实测：写 patch 后约 2 秒桌宠就被自动拉起），一般不用重启。
`install-plugin.ps1` 做的事就是把 `dsh-plugin/` 复制到 `<profile>\node_modules\dsh-whale-pet\`，
再往 `<profile>\cordis.patch.yml` 追加一段带标记的 `insert` 行（标记块便于一键撤销）。
如果当前会话有 `plugin_manager` 工具，也可以直接对它说「安装 `<工作区>\whale-pet\dsh-plugin`」走官方 `install_bundle`。

## 快速开始

插件装好后**什么都不用做**：Harness 起来她就在了。想手动单独启动（比如没装插件）：

双击 **`start-whale-pet.vbs`**（静默启动，不闪黑框）。
启动时她会先露个脸打个招呼，然后藏起来；**把 Harness 最小化**，她就浮出来了。

> 手动启动的实例没被插件托管，退出 Harness 后由看门狗（20 秒宽限）负责关掉它。
> 想看到调试输出 / 排障，用 `start-whale-pet-debug.cmd`。

## 交互

| 操作 | 效果 |
| --- | --- |
| 左键拖动 | 移动位置（自动记忆，下次还在原地） |
| 左键单击 | 摸摸头（开心表情 + 台词） |
| 左键双击 | 恢复并置顶 Harness 窗口 |
| 右键 | 菜单：恢复窗口 / 气泡 / 置顶 / 素材风格 / 回到右下角 / 打开素材文件夹 / 开机自启 / 退出 |
| 滚轮 | 缩放（0.6x ~ 1.8x） |
| 托盘图标 | 双击恢复 Harness；右键「立即现身 / 退出」 |

## 状态与素材对应

状态由「Harness 怎么被收起来的」+「DSH 会话是否正在干活」共同决定：

| 状态 | 触发条件 | 用的素材（高清静图模式） |
| --- | --- | --- |
| `greet` | 启动报到（先露个脸） | `bigfish-greet`（挥手） |
| `idle` | **点了最小化按钮**（干活结束后也回到这个基准） | `bigfish-idle` |
| `sleep` | **点了关闭按钮、Harness 收进托盘** | `bigfish-sleep`（趴枕头上） |
| `busy` | 会话里 agent 正在跑（`sessionStats.openStep` 有值） | `bigfish-running`（抱着笔记本） |
| `waiting` | 有待处理的提问/审批（`userQuestions.active`、`plan.wanted`） | `bigfish-thinking` |
| `pat` | 你点了她 | `bigfish-wink`（眨眼） |

Harness 窗口状态 → 桌宠行为（每 0.3 秒看一次，持续 0.45 秒才动作，防抖）：

| 窗口状态 | 桌宠 | 基准素材 |
| --- | --- | --- |
| 正常显示、且是当前活动窗口 | 躲起来 | — |
| 点了最小化（`IsIconic`） | 浮出来 | `idle` |
| **被别的窗口压住 / 切到别的软件了（不是当前活动窗口）** | **浮出来** | `idle`（按最小化逻辑） |
| 点了关闭、收进托盘（窗口被隐藏 `IsWindowVisible=false`） | 浮出来 | `sleep` |
| 窗口被销毁但进程还在（有些托盘实现会这么干） | 浮出来 | `sleep` |
| 进程和窗口都没了（真的退出了） | 躲起来，20 秒后自行退出 | — |

`busy` / `waiting` 优先级最高、行为不变：会话在干活时，无论最小化还是收进托盘都显示对应素材，
干完再回到上表里那种"不在眼前"的方式对应的基准素材。
（`-SleepAfterSec` 默认 0 = 最小化后不会自己转成 sleep，这样几种状态能一眼区分。）

"不在最前台"这条判定规则：拿 `GetForegroundWindow()` 和 Harness 主窗口比，另外
**前台窗口在它的属主链上、或与它同进程**（例如 Harness 自己的对话框）都算还在前台，避免误弹。
不想要这条触发就加 `-NoFocusTrigger`。

浮窗用 `ShowActivated = false` 显示，**不会抢焦点**——所以它在你在别的软件里打字时弹出来，
也不会打断输入。

素材风格可以在右键菜单里随时切换，**立即生效不用重启**：

- **高清静图（512px）** —— 最清晰，动作由 WPF 做（呼吸、摇摆、摸头蹦一下）
- **GIF 动图** —— `norm-*.gif`，真·逐帧动画
- **内置矢量画（不用素材）** —— `WhaleArt.xaml`，我用 XAML 矢量画的兜底角色

### 素材为什么要"归一化"

上游素材每个状态的画布尺寸和角色占比都不一样（例如 GIF 版 `idle` 是 176x169、`pat` 是 300x169），
而桌宠是把贴图 Uniform 塞进固定框渲染的 —— 于是**点一下换个状态图，角色在屏幕上的大小就会跳变**
（实测 `idle` 角色高 230px，点击后 `pat` 只有 147px，缩到 64%）。

`prepare-assets.py` 会为每个状态产出归一化素材 `norm-<state>.png` / `norm-<state>.gif`：

- 先用**行列覆盖率**框出角色本体（忽略源图边缘的杂点、细线、闪光）
- 动图取**逐帧框的中位数**当尺寸基准（比并集稳，不会被个别帧的杂点带偏），
  裁剪范围则用「剔除离群帧后的并集」，保住脚下阴影和正常动作幅度
- 按统一高度贴到固定画布（静图 512x512 角色高 450，动图 300x300 角色高 264），
  底部基线对齐 —— 两类素材渲染出来都是**约 246px 高**

桌宠优先加载 `norm-*`，没有才回退到原始素材。改了素材后重新生成：

```powershell
python prepare-assets.py .\assets        # 需要 Python + Pillow（脚本会退化到用 numpy/PIL）
```

### 鼠标点击区域

贴图元素的整个矩形（含透明留白）默认都会"吃掉"点击，会挡住底下的窗口。
所以现在只有**角色本体附近的一块矩形**接收鼠标事件，四周留白直接穿透给桌面/底下的窗口 ——
拖拽、单击摸头、右键菜单、滚轮缩放都在角色身上照常可用。

## 命令行参数

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File WhalePet.ps1 [参数]
```

| 参数 | 说明 |
| --- | --- |
| `-TargetProcess <名>` | 要监视的进程名，默认 `DeepSeek Harness` |
| `-TargetTitleLike <串>` | 要监视的窗口标题关键字，默认 `Harness`（进程名匹配不到时靠它） |
| `-ShowDelayMs <毫秒>` | 目标窗口收起后延迟多久浮出（防抖），默认 450 |
| `-SleepAfterSec <秒>` | 最小化后多久转成打瞌睡（0=不转，默认 0；收进托盘一律用 sleep） |
| `-HarnessGoneGraceSec <秒>` | Harness 彻底消失多久后自行退出，默认 20 |
| `-KeepAlive` | 关掉「Harness 消失就退出」的看门狗 |
| `-NoFocusTrigger` | 关掉「Harness 失去焦点/被压住也浮出」这条触发（默认开启） |
| `-Scale <倍数>` | 初始缩放，默认 1.0 |
| `-ForceShow` | 忽略 Harness 状态，一直显示（调试用） |
| `-Snapshot <路径>` | 把窗口内容渲染成 PNG 后退出（验证素材/排版用） |
| `-ForceState <状态>` | 调试：锁在某个状态（idle/busy/waiting/sleep/pat/greet），用于逐状态比对素材 |
| `-ListWindows` | 打印候选窗口并告诉你它会监视哪一个，然后退出 |
| `-NoTray` | 不创建托盘图标 |
| `-Log` | 日志同时打到控制台（日志文件始终会写） |

## 排障

1. **最小化了但没浮出来** → 先看它到底在监视哪个窗口：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\WhalePet.ps1 -ListWindows
   ```
   带 `[√]` 的就是被选中的窗口。如果选错了，用 `-TargetTitleLike` 指定更精确的标题关键字，
   或 `-TargetProcess` 指定进程名。
2. **日志** → `whale-pet.log`（每次运行都会追加）。里面有几行特别好用：
   - `started: target='…' assets=N mode=gifs` —— 这一轮在监视谁、用哪套素材
   - `show mode -> minimized/tray (base=idle/sleep)` —— 判定成了哪种"收起来"
   - `dsh: ok busy=True/False waiting=… ctx=…%` —— 会话状态探测结果（只在变化时打印）
   - `pet shown (tray 859ms, base=sleep)` / `pet hidden (harness front)`
3. **像是有两个桌宠 / 换新版后没生效** → 单实例锁按被监视的进程名区分。
   新实例启动时如果发现已有桌宠在跑，**会把旧实例关掉再接管**（日志里是 `found running pet (pid …), taking over`），
   所以升级完直接再启动一次就行，不用先去右键菜单点退出。
4. **素材不显示 / 大小不对** → 看 `assets/` 里有没有 `norm-<state>.png|gif`；
   没有就跑 `prepare-assets.py` 重新归一化；素材本身缺失就先跑 `fetch-assets.ps1`（支持 jsDelivr / ghproxy 等镜像）。
   `.webp` 素材 WPF 读不了，`prepare-assets.py` 会转成 `.png`（需要 Python+Pillow，脚本会自动找 DSH 自带的）。
5. **开机自启没生效** → 菜单里点一次「开机自动启动」，它会在启动文件夹放一个 `DSH-WhalePet.lnk`；
   若被安全软件拦截，日志里会有 `autostart failed`。

## 文件清单

| 文件 | 作用 |
| --- | --- |
| `WhalePet.ps1` | 桌宠主程序（窗口检测、浮窗、动画、交互、托盘、设置、看门狗） |
| `dsh-plugin/` | DSH 插件包：Harness 启动时拉起桌宠、退出时关闭 |
| `install-plugin.ps1` | 安装/卸载插件（改 profile 配置前会备份，可一键还原） |
| `test-plugin.mjs` | 插件自测：mock cordis ctx，真拉起桌宠再杀掉它，`node test-plugin.mjs` |
| `test-show-triggers.ps1` | 回归测试：替身窗口验证 7 种触发（最前台/最小化/关闭到托盘/被压住失焦 → 躲起来或浮出，以及各自用什么素材） |
| `test-takeover.ps1` | 回归测试：已有桌宠在跑时，新实例应当把旧实例关掉再接管 |
| `WhaleArt.xaml` | 内置矢量鲸鱼娘（无素材时的兜底，也可右菜单切换使用） |
| `assets/` | 现成开源素材：`norm-*`（归一化产物，首选）+ `bigfish-*`/`rlw-*`（原始素材）+ 许可文件 |
| `start-whale-pet.vbs` | 手动静默启动器（没装插件时用） |
| `start-whale-pet-debug.cmd` | 带控制台输出的启动器 |
| `fetch-assets.ps1` | 下载素材 + 调用后处理（可重复执行，已存在会跳过） |
| `prepare-assets.py` | 素材后处理：webp→png、按角色本体归一化各状态尺寸（`norm-*`） |
| `render-preview.ps1` | 开发用：把 `WhaleArt.xaml` 各状态渲染成对照图 |
| `settings.json` | 运行时生成：位置、缩放、气泡、素材风格、自启等 |
| `whale-pet.log` | 运行时生成：日志 |
| `THIRD-PARTY.md` | 素材来源与授权 |

## 说明

素材来自 MIT 授权的开源桌宠项目（见 [THIRD-PARTY.md](THIRD-PARTY.md)），已保留其许可文件。
本桌宠与 DeepSeek 官方无关，纯属个人桌面玩具。

插件侧有一处 API 语义容易踩坑，写插件时注意：cordis 的 `ctx.effect(body)` **body 会立即执行**，
它**返回**的函数才是卸载时的清理逻辑——`ctx.effect(() => { stopPet() })` 会在插件加载瞬间就把桌宠杀掉。
正确写法见 [dsh-plugin/README.md](dsh-plugin/README.md)。
