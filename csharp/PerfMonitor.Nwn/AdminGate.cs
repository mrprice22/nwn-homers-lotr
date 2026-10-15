using Anvil.API;
using NLog;
using NWN.Core;

namespace PerfMonitor.Nwn;

/// <summary>
/// The <c>can_admin</c> half of the module's existing admindb whitelist.
///
/// <para><b>No CD keys are hard-coded here, and none may ever be.</b> nasher
/// compiles every .nss on disk into the .mod regardless of .gitignore, so a
/// gitignored key file is still shipped inside a module anyone can unpack —
/// which has already leaked the admin keys once. Authorisation therefore lives
/// in the <c>admindb</c> campaign database, which is never part of the .mod.
/// This class is the C# mirror of <c>unpacked/admin_db.nss</c>'s
/// <c>Admin_CanAdmin()</c>: same table, same column, SELECT only.</para>
///
/// <para>It deliberately does NOT create or migrate the table. <c>onmoduleload</c>
/// already calls <c>Admin_InitDb()</c>, and a second writer racing that one at
/// startup is a way to corrupt a table for no gain. If the table is missing the
/// query simply fails and everyone is treated as unauthorised, which is the
/// correct direction to fail.</para>
/// </summary>
internal static class AdminGate
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    private const string Database = "admindb";
    private const string Query =
        "SELECT can_admin FROM admins WHERE cdkey = @cdkey LIMIT 1;";

    // A player's CD key cannot change mid-session, so the answer is stable for
    // as long as they are connected. Caching it keeps a UI that refreshes every
    // few seconds from issuing a synchronous SQLite read each time — the same
    // reasoning that moved *_InitDb() off the login frame.
    private static readonly Dictionary<string, bool> Cache = new();

    public static bool CanAdmin(NwPlayer? player)
    {
        if (player == null || !player.IsValid) return false;

        NwCreature? creature = player.LoginCreature;
        if (creature == null) return false;

        string cdKey = NWScript.GetPCPublicCDKey(creature, NWScript.FALSE);
        if (string.IsNullOrWhiteSpace(cdKey)) return false;

        if (Cache.TryGetValue(cdKey, out bool cached)) return cached;

        bool allowed = false;
        try
        {
            // The statement MUST be finalized before this returns. The raw
            // NWScript.SqlPrepareQueryCampaign handle this used to be leaked
            // mid-step (LIMIT 1 returns a row, so it is never stepped to DONE),
            // and an unfinalized SQLite statement keeps its read transaction
            // open: this process then held a SHARED lock on the shared admindb
            // until it restarted. Every other realm's write to admindb -- dev's
            // Admin_InitDb() at module load -- got SQLITE_BUSY, which nwserver
            // reports as "database unavailable" and aborts on. That was the
            // dev crash loop that only ever healed at the 03:00 reboot.
            using SQLQuery query = NwModule.Instance.PrepareCampaignSQLQuery(Database, Query);
            query.BindParam("@cdkey", cdKey);
            query.Execute();
            // Drain rather than break: stepping to DONE ends the read
            // transaction even before the statement is disposed.
            foreach (SQLResult row in query.Results)
            {
                allowed = row.GetInt(0) != 0;
            }
        }
        catch (Exception ex)
        {
            // Fail closed, and say so once rather than per call.
            Log.Error(ex, "[PerfMon] admindb lookup failed; treating as not authorised");
            allowed = false;
        }

        Cache[cdKey] = allowed;
        return allowed;
    }

    /// <summary>Drop a cached answer, so a whitelist edit takes effect without a restart.</summary>
    public static void Forget(string cdKey) => Cache.Remove(cdKey);
}
