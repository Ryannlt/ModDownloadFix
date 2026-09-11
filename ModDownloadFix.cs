using System;
using System.Collections.Generic;
using System.Reflection;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using HoldfastGame;

// Kept in step with BepInPlugin below; package.ps1 reads this back off the built DLL.
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace ModDownloadFix
{
    // Stops the soft crash when the Workshop popup auto-joins a server after downloading or updating a mod.
    [BepInPlugin(Guid, "ModDownloadFix", "1.0.0")]
    public class ModDownloadFixMod : BaseUnityPlugin
    {
        public const string Guid = "com.ryannlt.moddownloadfix";

        internal static ManualLogSource Log;

        private void Awake()
        {
            Log = Logger;

            // Harmony patches need no GameObject, so this works whatever HideManagerGameObject is set to.
            Harmony.CreateAndPatchAll(typeof(ModDownloadFixMod).Assembly, Guid);

            Log.LogInfo("Ready.");
        }
    }

    // The handshake frees its packet on return, even when the map load inside it has been handed to the popup.
    internal static class Handshake
    {
        internal static bool Running;
        internal static bool Deferred;
        internal static bool Withheld;
        internal static bool PendingRelease;
    }

    [HarmonyPatch(typeof(ClientGameManager), nameof(ClientGameManager.WelcomeToTheServer))]
    internal static class WelcomeToTheServerPatch
    {
        private static void Prefix()
        {
            Handshake.Running = true;
            Handshake.Deferred = false;
            Handshake.Withheld = false;
            Handshake.PendingRelease = false;
        }

        // Keyed on what was actually withheld, so a game-side fix that moves the release never frees it twice.
        private static void Postfix()
        {
            Handshake.Running = false;
            Handshake.PendingRelease = Handshake.Withheld;
        }
    }

    // The main menu calls this same overload on its healthy reconnect path, so only a call mid-handshake counts.
    [HarmonyPatch(typeof(ClientErrorManager), nameof(ClientErrorManager.SetDisconnectPanelInformation),
        new[] { typeof(IList<ModDisconnectReason>), typeof(string), typeof(Action), typeof(Action) })]
    internal static class DisconnectPanelPatch
    {
        private static void Prefix()
        {
            if (Handshake.Running) Handshake.Deferred = true;
        }
    }

    [HarmonyPatch(typeof(GameServerInitialDetails), nameof(GameServerInitialDetails.ReleaseFields))]
    internal static class ReleaseFieldsPatch
    {
        private static bool Prefix()
        {
            if (!Handshake.Running || !Handshake.Deferred) return true;

            Handshake.Withheld = true;
            ModDownloadFixMod.Log.LogInfo("Kept the handshake packet for the Workshop auto-join.");
            return false;
        }
    }

    // By now the deferred load has copied the rotations into the panel, so the packet is finally safe to free.
    [HarmonyPatch(typeof(ClientGameManager), "HandleMapLoading")]
    internal static class HandleMapLoadingPatch
    {
        private static void Postfix(GameServerInitialDetailsData gameServerInitialDetails)
        {
            if (Handshake.Running || !Handshake.PendingRelease) return;

            Handshake.PendingRelease = false;
            GameServerInitialDetails.ReleaseFields(gameServerInitialDetails);
            ModDownloadFixMod.Log.LogInfo("Released the handshake packet after loading.");
        }
    }

    // The scoreboard dereferences whatever comes back, so an out-of-range lookup gets a stand-in rather than null.
    [HarmonyPatch(typeof(UIAdminMapRotationsPanel), nameof(UIAdminMapRotationsPanel.ResolveMapRotationDetails))]
    internal static class ResolveMapRotationDetailsPatch
    {
        private static bool Prefix(int mapRotationIndex, List<UIAdminMapRotationsPanelRow> ___activeRows,
                                   ref MapRotationDetails __result)
        {
            int rows = ___activeRows == null ? 0 : ___activeRows.Count;
            if (mapRotationIndex >= 0 && mapRotationIndex < rows) return true;

            __result = new MapRotationDetails { MapNameOverride = CustomMapName() };
            ModDownloadFixMod.Log.LogWarning("Rotation " + mapRotationIndex + " was looked up with " + rows +
                                             " rows loaded. Used a stand-in so the round could start.");
            return false;
        }

        // Explicit null checks rather than ?. so Unity's destroyed-object test still applies.
        private static string CustomMapName()
        {
            ClientComponentReferenceManager client = ClientComponentReferenceManager.ClientInstance;
            if (client == null || client.clientModLoaderManager == null) return null;

            CustomMapDefinition definition = client.clientModLoaderManager.lastLoadedCustomMapDefinition;
            return definition != null ? definition.mapName : null;
        }
    }

    // The rotations tab highlights the current row by index on every map load, with no bounds check of its own.
    [HarmonyPatch(typeof(UIAdminMapRotationsPanel), nameof(UIAdminMapRotationsPanel._InitializeOnMap))]
    internal static class RotationsTabInitializePatch
    {
        private static bool Prefix(RoundGameDetails roundGameDetails, List<UIAdminMapRotationsPanelRow> ___activeRows,
                                   ref int ___currentRotationIndex)
        {
            int index = roundGameDetails == null ? -1 : roundGameDetails.RotationIndex;
            int rows = ___activeRows == null ? 0 : ___activeRows.Count;
            if (index >= 0 && index < rows) return true;

            // -1 is the panel's own "nothing highlighted" value, which _ResetObject already checks for.
            ___currentRotationIndex = -1;
            ModDownloadFixMod.Log.LogWarning("Rotations tab asked to highlight row " + index + " of " + rows +
                                             ". Skipped the highlight so the round could start.");
            return false;
        }
    }

    // Last line of defence if the one-line lookup above is ever inlined into this caller and so skips its patch.
    [HarmonyPatch(typeof(UIScoreboardPanel), nameof(UIScoreboardPanel.InitializeOnMap),
        new[] { typeof(RoundGameDetails) })]
    internal static class ScoreboardInitializePatch
    {
        private static Exception Finalizer(Exception __exception)
        {
            if (!(__exception is ArgumentOutOfRangeException)) return __exception;

            ModDownloadFixMod.Log.LogWarning("Scoreboard setup threw \"" + __exception.Message +
                                             "\". Carried on so the round could start.");
            return null;
        }
    }
}
