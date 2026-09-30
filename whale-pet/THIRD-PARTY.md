# 素材来源与授权 / Third-party assets

本桌宠（`WhalePet.ps1` 等）自身的代码由本次开发编写。**角色美术素材全部来自开源项目**，
不包含任何手绘替代品（内置矢量画 `WhaleArt.xaml` 为兜底，仅在没有素材时使用）。

| 文件 | 来源 | 授权 |
| --- | --- | --- |
| `assets/bigfish-*.png`（由 `bigfish-*.webp` 转换） | [crossoverthere/dsh-whale-desktop](https://github.com/crossoverthere/dsh-whale-desktop) → `vendor/whale/generated/` | MIT（见 `assets/LICENSE.dsh-whale-desktop.txt`） |
| `assets/rlw-*.gif`、`assets/rlw-tray.png`、`assets/rlw-avatar.png` | [touche-s/rice-loving-whale](https://github.com/touche-s/rice-loving-whale) → `electron/assets/` | MIT（见 `assets/LICENSE.rice-loving-whale.txt`） |
| `assets/pet-*.gif` | 由上面的 `rlw-*.gif` 用 `prepare-assets.py` 裁剪角色边界生成 | 同上（MIT） |

两个上游项目均为 MIT 授权，允许使用、修改与再分发，条件是保留版权与许可声明——
因此 `assets/` 目录内保留了各自的 `LICENSE.*.txt` 原文。若你要对外分发本桌宠，
请连同这些许可文件一起保留。

## 参考过的同类项目

- [crossoverthere/dsh-whale-desktop](https://github.com/crossoverthere/dsh-whale-desktop)：DSH 桌面挂件（Electron，透明置顶、可点击穿透）
- [touche-s/rice-loving-whale](https://github.com/touche-s/rice-loving-whale)：能感知 DSH 状态的傲娇鲸鱼娘桌宠
- [Andersen216/dsh-whale-girl-live2d](https://github.com/Andersen216/dsh-whale-girl-live2d)：DSH Web 界面里的 Live2D 桌宠（模型素材 CC BY-NC-SA 4.0，本桌宠未使用其素材）

## 重新获取素材

素材可从上游重新下载并自动后处理（webp→png、GIF 裁剪）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\fetch-assets.ps1
```

脚本会依次尝试 jsDelivr / raw.githubusercontent / ghproxy 等镜像下载，可重复执行（已存在的文件会跳过）。
