using HarmonyLib;
using MegaCrit.Sts2.Core.Multiplayer.Game.Lobby;
using MegaCrit.Sts2.Core.Runs;

namespace ThingsMpSlBridge;

/// <summary>
/// 快速SL 回档时 RunManager.CleanUp(true) 会触发 STS2_Things 的 Clear()。
/// Priority.First 保证我们先于它把已锁定快照存下来。
/// </summary>
[HarmonyPatch(typeof(RunManager), nameof(RunManager.CleanUp), new[] { typeof(bool) })]
internal static class RunManagerCleanUpPatch
{
    [HarmonyPriority(Priority.First)]
    private static void Prefix()
    {
        ThingsConfigBridge.CaptureBeforeCleanUp();
    }
}

/// <summary>
/// 会话重建后 RunManager.SetUpSavedMultiplayer 会先跑，载入过程中就会用到配置。
/// </summary>
[HarmonyPatch(typeof(RunManager), nameof(RunManager.SetUpSavedMultiplayer), new[] { typeof(RunState), typeof(LoadRunLobby) })]
internal static class SetUpSavedMultiplayerPatch
{
    [HarmonyPriority(Priority.First)]
    private static void Prefix(LoadRunLobby lobby)
    {
        ThingsConfigBridge.RestoreBeforeRunStart(lobby?.NetService);
    }
}

/// <summary>
/// 兜底：即使 SetUpSavedMultiplayer 被跳过（或顺序变化），
/// 也要在 STS2_Things 的 BeginRunLocally Prefix 执行 PrepareRun 之前把快照还回去。
/// </summary>
[HarmonyPatch(typeof(LoadRunLobby), "BeginRunLocally")]
internal static class BeginRunLocallyPatch
{
    [HarmonyPriority(Priority.First)]
    private static void Prefix(LoadRunLobby __instance)
    {
        ThingsConfigBridge.RestoreBeforeRunStart(__instance?.NetService);
    }
}
