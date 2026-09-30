# dsh-whale-pet

让 [鲸鱼娘桌宠](../README.md) 跟着 DeepSeek Harness 一起启动 / 退出：

- Harness 启动 → 插件 `apply` 拉起 `WhalePet.ps1`
- Harness 退出 / 插件被停用 → 插件 dispose 用 `taskkill /T /F` 收掉桌宠进程

## 它是什么

一个 Host-only 的 cordis bundle：`package.json` 里声明 `dsh.bundle.patch`，
`cordis.patch.yml` 往当前 profile 插一行 `whale-pet`，`index.js` 导出一个
`apply(ctx, config)`。

```yaml
- insert:
    - id: whale-pet
      name: 'dsh-whale-pet'
      config:
        petScript: 'C:\...\whale-pet\WhalePet.ps1'
        startDelayMs: 1200
```

## 配置项

| 字段 | 说明 |
| --- | --- |
| `petScript` | `WhalePet.ps1` 的绝对路径；不写则按 bundle 相对位置找，也可用环境变量 `DSH_WHALE_PET_SCRIPT` |
| `powershell` | 指定 `powershell.exe`，默认用系统自带的 Windows PowerShell |
| `extraArgs` | 追加给 `WhalePet.ps1` 的参数数组，如 `["-Scale","1.2"]` |
| `startDelayMs` | 启动延迟毫秒（默认 1200） |

## 一处容易写错的 API 语义

cordis 的 `ctx.effect(body)`：**body 会立即执行**，它**返回**的函数才是卸载时的清理逻辑。
所以正确写法是——

```js
ctx.effect(() => () => stopPet(), 'whale-pet: stop desktop pet')
//            ^^^^^^^^^^^^^^^ 返回的才是 disposer
```

写成 `ctx.effect(() => { stopPet() })` 会在插件加载的瞬间就把桌宠杀掉（刚拉起就收掉）。

## 安装 / 卸载

用工作区里的 `install-plugin.ps1`：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\install-plugin.ps1            # 装
powershell -NoProfile -ExecutionPolicy Bypass -File ..\install-plugin.ps1 -Uninstall # 卸
```

或者用 Harness 自带的 Plugin Manager（如果当前会话有 `plugin_manager` 工具）：
`install_bundle`，`target` 指向本目录。
