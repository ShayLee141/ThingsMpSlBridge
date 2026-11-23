# ThingsMpSlBridge

**尖塔琐事 × 快速SL · 兼容补丁**

[Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3844267432) · [前置：尖塔：琐事 STS2_Things](https://steamcommunity.com/sharedfiles/filedetails/?id=3747607944) · [前置：多功能快速SL QuickSlAndRerollStart](https://steamcommunity.com/sharedfiles/filedetails/?id=3747626826)

兼容补丁 Mod：让 `STS2_Things`（尖塔：琐事）和 `QuickSlAndRerollStart`（多功能快速SL）在多人局里能同时用。

## 解决什么

多人局里用快速 SL 回档后，客户端会在开始载入的瞬间被判定 `No final host configuration was received before run start` 并主动断开，接着 MpSL 加载抛 `NullReferenceException`，整队掉线。

原因：快速 SL 重建联机会话时会调用 `RunManager.CleanUp(true)`，`STS2_Things` 的 `ConfigSessionCleanupPatch` 在该方法的 Prefix 里执行 `MultiplayerConfig.Clear()`，把房主锁定的配置快照清掉；重建后客户端只重新注册了消息处理器，拿不回快照，于是 `PrepareRun` 判定不一致。

## 怎么做

- `RunManager.CleanUp` 的 Prefix（`Priority.First`，早于 STS2_Things）：客户端把当前**已锁定**的快照和它的网络连接对象存到本 Mod 里。
- `RunManager.SetUpSavedMultiplayer` / `LoadRunLobby.BeginRunLocally` 的 Prefix（`Priority.First`，早于 STS2_Things 的 `PrepareRun`）：如果还是同一条连接、自己是客户端、且当前没有快照，就把存下的快照写回 `MultiplayerConfig._snapshot` 并触发一次配置生效。

不改动这两个 Mod，也不放宽校验：恢复的是本局之前由房主下发并通过校验的那份快照；房主之后发来的更高 revision 仍会正常覆盖，锁定后改配置依旧会被拒绝。

## 依赖

清单里声明了两个前置（游戏加载时强制检查，缺一个本 Mod 就不会加载，并在 Mod 界面报错）：

```json
"dependencies": [
  { "id": "STS2_Things", "min_version": "2.0.7" },
  { "id": "QuickSlAndRerollStart" }
]
```

`STS2_Things` 锁 2.0.7：本补丁靠反射读写 `MultiplayerConfig` 的私有字段，字段布局是 2.0.7 反编译确认过的。`QuickSlAndRerollStart` 只要求存在 —— 它自己报的版本是 `v0.0.0`，写 `min_version` 没有意义。

## 装到哪

把整个 `ThingsMpSlBridge` 文件夹放到你的游戏装目录下的 `mods\` 里（没有 `mods` 就自己建一个）：

```text
<游戏安装目录>\mods\ThingsMpSlBridge\
├─ ThingsMpSlBridge.dll
└─ ThingsMpSlBridge.json
```

`<游戏安装目录>` 就是含 `SlayTheSpire2.exe` 的那一层，典型位置：

```text
<Steam 库>\steamapps\common\Slay the Spire 2\
```

默认库里就是 `C:\Program Files (x86)\Steam\steamapps\common\Slay the Spire 2`，装在其它盘时换掉前面的库路径就行。

清单里 `affects_gameplay: true`：本 Mod 会进入玩法相关 mod 列表，握手时不装或版本不同都会被直接拒掉（`ModMismatch`），不会再出现“先能进房、回档才崩”。代价是每次更新必须全员同步到同一版本。

前置没装齐的话本 Mod 直接不加载。这个补丁只需要**客户端**装；房主装了也不会改变行为（房主分支直接跳过）。

## 构建

需要 .NET 9 SDK，以及游戏目录（用来引用 `sts2.dll` 和 `0Harmony.dll`）。游戏目录不写死在仓库里，按下面任一方式提供：

```powershell
# 方式 1：本地配置文件（推荐，文件不入库）
Copy-Item local.props.example local.props
#   然后把 local.props 里的 Sts2GameDir 改成本机游戏目录

# 方式 2：命令行参数
dotnet build -p:Sts2GameDir="D:\SteamLibrary\steamapps\common\Slay the Spire 2"

# 方式 3：环境变量
$env:STS2_GAME_DIR = "D:\SteamLibrary\steamapps\common\Slay the Spire 2"
dotnet build
```

产物：`.godot/mono/temp/bin/Debug/ThingsMpSlBridge.dll`，与仓库根目录的 `ThingsMpSlBridge.json` 一起就是发布用的两个文件。

## 发布到创意工坊

```powershell
pwsh ./tools/publish-workshop.ps1 -SteamUser <你的 Steam 账号>
```

脚本会：把构建产物和清单拷到 `dist\` → 用 `workshop\item.vdf.template` 渲染出 `item.vdf` → 调 steamcmd 上传。

- steamcmd 路径默认依次找 `-SteamCmd` → `STEAMCMD` 环境变量 → `PATH` → `C:\steamcmd\steamcmd.exe`；账号也可以用 `STEAM_USER` 环境变量给。
- 首次要先在 steamcmd 里登录过一次（需要 Steam Guard），之后凭据会缓存。
- `-DryRun` 只暂存 `dist\` 并渲染 `item.vdf`，不实际上传；`-Configuration Release` 可换构建配置。
- 物品处于自动内容检查期间时，标题/简介的修改会被 `Access Denied` 拒绝，等检查放行再传。

## 日志

```text
[ThingsMpSlBridge] bound to STS2_Things!STS2_Things.Config.MultiplayerConfig.
[ThingsMpSlBridge] captured locked host config snapshot (revision 3) before session clean-up.
[ThingsMpSlBridge] restored host config snapshot (revision 3) after session rebuild.
```

如果 `STS2_Things` 改了 `MultiplayerConfig` 的字段名，本 Mod 会打一条 `layout changed ... bridge stays idle` 然后完全不干预，行为回到没有本补丁的状态。
