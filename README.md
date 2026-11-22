# ThingsMpSlBridge

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

```text
F:\SteamLibrary\steamapps\common\Slay the Spire 2\mods\ThingsMpSlBridge\
├─ ThingsMpSlBridge.dll
└─ ThingsMpSlBridge.json
```

清单里 `affects_gameplay: false`，装与不装都不会阻止别人进房；但**前置没装齐的话本 Mod 直接不加载**。这个补丁只需要**客户端**装；房主装了也不会改变行为（房主分支直接跳过）。

## 构建

```powershell
pwsh ./tools/build.ps1
```

`dotnet build` 通过后用 `tools/build.ps1` 复制到游戏 mods 目录。需要游戏 DLL 在 `F:\SteamLibrary\steamapps\common\Slay the Spire 2\data_sts2_windows_x86_64\`（见 `ThingsMpSlBridge.csproj` 的 `HintPath`）。

## 日志

```text
[ThingsMpSlBridge] bound to STS2_Things!STS2_Things.Config.MultiplayerConfig.
[ThingsMpSlBridge] captured locked host config snapshot (revision 3) before session clean-up.
[ThingsMpSlBridge] restored host config snapshot (revision 3) after session rebuild.
```

如果 `STS2_Things` 改了 `MultiplayerConfig` 的字段名，本 Mod 会打一条 `layout changed ... bridge stays idle` 然后完全不干预，行为回到没有本补丁的状态。
