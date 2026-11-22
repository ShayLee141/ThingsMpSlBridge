using System;
using System.Reflection;
using System.Runtime.Loader;
using MegaCrit.Sts2.Core.Logging;
using MegaCrit.Sts2.Core.Multiplayer.Game;

namespace ThingsMpSlBridge;

/// <summary>
/// 在「快速SL 拆掉联机会话 → 用同一条连接重建 LoadRunLobby」这个窗口里，
/// 保住 STS2_Things 已经锁定的房主配置快照。
///
/// 只读写 STS2_Things 的私有状态，不改动它的校验逻辑：
/// 恢复的是本局之前由房主下发、已通过校验并锁定的那份快照。
/// </summary>
internal static class ThingsConfigBridge
{
    private const string ImplAssemblyName = "STS2_Things";
    private const string ConfigTypeName = "STS2_Things.Config.MultiplayerConfig";

    private static Type? _configType;
    private static FieldInfo? _snapshotField;
    private static FieldInfo? _serviceField;
    private static PropertyInfo? _isActiveProp;
    private static PropertyInfo? _isHostProp;
    private static PropertyInfo? _hasSnapshotProp;
    private static PropertyInfo? _isLockedProp;
    private static MethodInfo? _notifyMethod;
    private static FieldInfo? _revisionField;

    private static object? _savedSnapshot;
    private static INetGameService? _savedService;
    private static uint _savedRevision;

    public static bool IsBound => _snapshotField != null;

    /// <summary>在 RunManager.CleanUp 之前调用：把当前已锁定的客户端快照存下来。</summary>
    public static void CaptureBeforeCleanUp()
    {
        try
        {
            if (!EnsureBound())
            {
                return;
            }

            if (!ReadBool(_isActiveProp) || ReadBool(_isHostProp))
            {
                // 没有联机会话，或者自己是房主（房主会重新捕获并广播，不需要干预）。
                return;
            }

            if (!ReadBool(_hasSnapshotProp) || !ReadBool(_isLockedProp))
            {
                return;
            }

            if (_serviceField?.GetValue(null) is not INetGameService service || !service.IsConnected)
            {
                return;
            }

            object? snapshot = _snapshotField!.GetValue(null);
            if (snapshot == null)
            {
                return;
            }

            _savedSnapshot = snapshot;
            _savedService = service;
            _savedRevision = ReadRevision(snapshot);
            Log.Info($"[ThingsMpSlBridge] captured locked host config snapshot (revision {_savedRevision}) before session clean-up.");
        }
        catch (Exception ex)
        {
            Log.Warn($"[ThingsMpSlBridge] capture failed: {ex.GetType().Name}: {ex.Message}");
        }
    }

    /// <summary>在会话重建后、STS2_Things 校验配置之前调用：把快照还回去。</summary>
    public static void RestoreBeforeRunStart(INetGameService? service)
    {
        try
        {
            if (_savedSnapshot == null || _savedService == null || service == null)
            {
                return;
            }

            // 必须还是同一条网络连接：换了连接说明是新的加入流程，不能套用旧快照。
            if (!ReferenceEquals(service, _savedService))
            {
                return;
            }

            if (!EnsureBound())
            {
                return;
            }

            if (!ReadBool(_isActiveProp) || ReadBool(_isHostProp))
            {
                return;
            }

            if (ReadBool(_hasSnapshotProp))
            {
                // 房主已经重新下发过快照，用它的。
                return;
            }

            _snapshotField!.SetValue(null, _savedSnapshot);
            _notifyMethod?.Invoke(null, null);

            if (_snapshotField.GetValue(null) is object restored)
            {
                Log.Warn($"[ThingsMpSlBridge] restored host config snapshot (revision {ReadRevision(restored)}) after session rebuild.");
            }
            else
            {
                Log.Error("[ThingsMpSlBridge] restore wrote the snapshot but it read back as null.");
            }
        }
        catch (Exception ex)
        {
            Log.Warn($"[ThingsMpSlBridge] restore failed: {ex.GetType().Name}: {ex.Message}");
        }
    }

    private static bool EnsureBound()
    {
        if (_snapshotField != null)
        {
            return true;
        }

        Type? configType = FindImplementationType(ConfigTypeName);
        if (configType == null)
        {
            // STS2_Things 没装或还没加载，本补丁无事可做。
            return false;
        }

        const BindingFlags Static = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        FieldInfo? snapshotField = configType.GetField("_snapshot", Static);
        FieldInfo? serviceField = configType.GetField("_service", Static);
        if (snapshotField == null || serviceField == null)
        {
            Log.Warn("[ThingsMpSlBridge] STS2_Things MultiplayerConfig layout changed (_snapshot/_service not found); bridge stays idle.");
            return false;
        }

        _configType = configType;
        _snapshotField = snapshotField;
        _serviceField = serviceField;
        _isActiveProp = configType.GetProperty("IsActive", Static);
        _isHostProp = configType.GetProperty("IsHost", Static);
        _hasSnapshotProp = configType.GetProperty("HasSnapshot", Static);
        _isLockedProp = configType.GetProperty("IsLocked", Static);

        Type? thingsConfigType = FindImplementationType("STS2_Things.Config.ThingsModConfig");
        _notifyMethod = thingsConfigType?.GetMethod("NotifyEffectiveChanged", Static);

        Log.Info($"[ThingsMpSlBridge] bound to {configType.Assembly.GetName().Name}!{configType.FullName}.");
        return true;
    }

    private static uint ReadRevision(object snapshot)
    {
        _revisionField ??= snapshot.GetType().GetField("Revision", BindingFlags.Instance | BindingFlags.Public);
        return _revisionField?.GetValue(snapshot) is uint revision ? revision : 0u;
    }

    private static bool ReadBool(PropertyInfo? property)
    {
        return property?.GetValue(null) is bool value && value;
    }

    private static Type? FindImplementationType(string fullName)
    {
        // 1) 程序集限定名直接解析（STS2_Things 已加载时最快）。
        Type? type = Type.GetType($"{fullName}, {ImplAssemblyName}", throwOnError: false);
        if (type != null)
        {
            return type;
        }

        // 2) 遍历当前域里已加载的程序集。
        foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            type = SafeGetType(assembly, fullName);
            if (type != null)
            {
                return type;
            }
        }

        // 3) STS2_Things 的实现程序集是运行时 LoadFromStream 进来的，兜底扫一遍所有加载上下文。
        foreach (AssemblyLoadContext context in AssemblyLoadContext.All)
        {
            foreach (Assembly assembly in context.Assemblies)
            {
                type = SafeGetType(assembly, fullName);
                if (type != null)
                {
                    return type;
                }
            }
        }

        return null;
    }

    private static Type? SafeGetType(Assembly assembly, string fullName)
    {
        try
        {
            return assembly.GetType(fullName, throwOnError: false);
        }
        catch
        {
            return null;
        }
    }
}
