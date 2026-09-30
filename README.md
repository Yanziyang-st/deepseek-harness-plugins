# DeepSeek Harness Plugins

给 [DeepSeek Harness](https://github.com/Yanziyang-st/deepseek-harness-plugins) 桌面版用的插件集合。
*Plugins for DeepSeek Harness (Windows).*

## 插件列表

| 插件 | 说明 | 目录 |
| --- | --- | --- |
| 🐋 **鲸鱼娘桌宠** | Harness 一"收起"（点最小化 / 点关闭收进托盘 / 切到别的软件失焦），桌面上就浮出鲸鱼娘；Harness 启动时自动拉起、退出时自动关闭。零依赖（PowerShell 5.1 + WPF），会读 DSH 会话状态换表情 | [`whale-pet/`](whale-pet/) |

## 安装：鲸鱼娘桌宠

**前置条件**：Windows 10/11 + 系统自带的 Windows PowerShell 5.1 + DSH 桌面版。
**不需要** Node / npm / Electron / Python（只有重新下载素材时才用到 Python+Pillow，脚本会自动找 DSH 自带的）。

```powershell
git clone https://github.com/Yanziyang-st/deepseek-harness-plugins.git
cd deepseek-harness-plugins\whale-pet

# 1) 下载现成素材（可选，约 10MB，MIT 授权的开源素材）
#    不下载也能用：会自动回退到内置矢量画 WhaleArt.xaml
powershell -NoProfile -ExecutionPolicy Bypass -File .\fetch-assets.ps1

# 2) 注册成 DSH 插件：Harness 启动时自动拉起桌宠，退出时自动关闭
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-plugin.ps1

# 3) profile 会被热加载，几秒内桌宠就起来了；没反应就重启一次 Harness
```

装完就是这样：

| 你对 Harness 做什么 | 桌宠的表现 |
| --- | --- |
| 点**最小化** | 浮出来，用 `idle` 素材 |
| 切到别的软件（Harness 失焦 / 被压住） | 浮出来，同样按最小化处理 |
| 点**关闭**（收进托盘） | 浮出来，用 `sleep` 素材（趴枕头上） |
| 把它叫回前台 | 躲回去 |
| 会话在跑 agent / 有提问等你回答 | 换成 `busy`（抱笔记本）/ `waiting` 素材 |
| 真的退出 Harness | 桌宠也跟着退出（插件 dispose + 自带看门狗双保险） |

不想装插件、只想手动开一次：双击 `whale-pet\start-whale-pet.vbs`。
卸载：`powershell -File .\install-plugin.ps1 -Uninstall`（改 profile 前都会自动备份，可一键还原）。

> `install-plugin.ps1` 做的事就两件：把 `whale-pet\dsh-plugin\` 复制到
> `<profile>\node_modules\dsh-whale-pet\`，再往 `<profile>\cordis.patch.yml` 追加一段**带标记**的 `insert` 行。
> 如果你的 DSH 会话里有 `plugin_manager` 工具，也可以直接让它 `install_bundle` 安装 `whale-pet\dsh-plugin`。

## 素材说明

- 仓库**不包含**角色美术素材（第三方 MIT 素材，约 10MB）：用 `fetch-assets.ps1` 下载、`prepare-assets.py` 归一化各状态尺寸。
- 没有素材时桌宠使用内置矢量画 `WhaleArt.xaml`，功能完全一样，只是形象是简笔的。
- 素材来源与许可：见 [`whale-pet/THIRD-PARTY.md`](whale-pet/THIRD-PARTY.md)。

## 仓库结构

```
whale-pet/                 🐋 鲸鱼娘桌宠
  WhalePet.ps1             桌宠主程序（窗口检测、浮窗、动画、交互、托盘、看门狗）
  WhaleArt.xaml            内置矢量画兜底
  dsh-plugin/              DSH 插件包（Harness 启动拉起 / 退出关闭）
  install-plugin.ps1       插件安装/卸载
  fetch-assets.ps1         素材下载 + 后处理
  prepare-assets.py        素材归一化（webp→png、各状态角色尺寸统一）
  test-*.ps1 / test-*.mjs  回归测试（触发判定、单实例接管、插件自测）
  README.md                完整文档（交互、状态映射、命令行参数、排障）
```

## 许可

本仓库代码以 MIT 许可发布，见 [LICENSE](LICENSE)。
第三方素材使用其各自许可（见 `whale-pet/assets/LICENSE.*.txt` 与 `whale-pet/THIRD-PARTY.md`）。
