using System;
using HarmonyLib;
using MegaCrit.Sts2.Core.Logging;
using MegaCrit.Sts2.Core.Modding;

namespace ThingsMpSlBridge;

[ModInitializer("Initialize")]
public static class ModEntry
{
    public const string ModId = "ThingsMpSlBridge";
    public const string ThisVersion = "0.1.1";

    public static Harmony? HarmonyInstance { get; private set; }

    public static void Initialize()
    {
        try
        {
            HarmonyInstance = new Harmony("mod.thingsmpslbridge.sts2");
            PatchClass(typeof(RunManagerCleanUpPatch));
            PatchClass(typeof(SetUpSavedMultiplayerPatch));
            PatchClass(typeof(BeginRunLocallyPatch));
            Log.Info($"ThingsMpSlBridge v{ThisVersion} loaded.");
        }
        catch (Exception ex)
        {
            Log.Error($"ThingsMpSlBridge init failed: {ex}");
        }
    }

    private static void PatchClass(Type type)
    {
        try
        {
            HarmonyInstance!.CreateClassProcessor(type).Patch();
        }
        catch (Exception ex)
        {
            // 单个目标缺失不应影响其它补丁，游戏版本变化时这里会留下痕迹。
            Log.Warn($"ThingsMpSlBridge: failed to patch {type.Name}: {ex.GetType().Name}: {ex.Message}");
        }
    }
}
