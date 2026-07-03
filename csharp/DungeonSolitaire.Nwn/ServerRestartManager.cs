using Anvil.API;
using Anvil.API.Events;
using Anvil.Services;
using NWN.Core;
using NLog;

namespace DungeonSolitaire.Nwn;

/// <summary>
/// Drives the daily scheduled restart: broadcasts countdown warnings to every
/// online player, then at T-0 exports all characters and shuts the server down
/// cleanly. The host (a root systemd timer) reboots the machine a few minutes
/// later and the server auto-starts on boot.
///
/// Schedule comes from the <c>ANVIL_RESTART_DAILY</c> environment variable
/// (HH:mm, server-local time; forwarded from server.env). Set it empty to
/// disable. A control file <c>&lt;PluginData&gt;/restart-now</c> triggers the
/// shutdown sequence immediately, for testing without waiting for the clock.
///
/// <para><b>Adhoc "reboot on empty".</b> A control file
/// <c>&lt;PluginData&gt;/reboot-on-empty</c> (presence = armed; its text = a
/// custom player message) lets an admin stage a module update and have the
/// server reboot itself the moment it next sits empty — without kicking anyone.
/// While armed, online players are warned (broadcast + shout) and new joiners
/// get an on-login notice. Once the server has been empty for
/// <see cref="EmptyGraceSeconds"/>, it deletes the arm file (so it can't
/// boot-loop), writes <c>&lt;PluginData&gt;/restart-server</c> (a host systemd
/// <c>.path</c> unit watches this and restarts <i>just</i> the server service,
/// optionally rebuilding the NWSync manifest first), then runs the same clean
/// export+shutdown as the daily restart. The arm/disarm CLI is
/// <c>bin/reboot-on-empty</c>.</para>
/// </summary>
[ServiceBinding(typeof(ServerRestartManager))]
internal sealed class ServerRestartManager
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    // Minutes-remaining marks at which a warning is broadcast (plus a final at 0).
    private static readonly int[] WarnMarks = { 60, 30, 15, 10, 5, 1 };
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(15);
    private const string DownDuration = "about 8 minutes";

    // How long the server must sit continuously empty (while armed) before an
    // adhoc reboot-on-empty fires. A short grace lets a mid-login player connect
    // instead of being cut off the instant the last player logs out.
    private const double EmptyGraceSeconds = 45;
    // How often the "reboot pending, please log off" reminder is re-broadcast to
    // players who are still online while armed.
    private static readonly TimeSpan RemindEvery = TimeSpan.FromMinutes(15);

    private readonly TimeSpan? _target;     // local time-of-day, or null when disabled
    private readonly string _controlFile;
    private DateTime? _nextRestart;          // updated by RunLoop; read by OnClientEnter

    // Adhoc reboot-on-empty state (all driven from RunLoop on the main thread).
    private readonly string _armFile;            // presence = armed; text = custom message
    private readonly string _restartRequestFile; // host .path unit watches this
    private bool _emptyArmed;
    private string _emptyMsg = "";
    private double _emptyIdleSeconds;            // how long we've been empty while armed
    private DateTime _lastReminder = DateTime.MinValue;

    public ServerRestartManager()
    {
        _controlFile = Path.Combine(HomeStorage.PluginData, "restart-now");
        _armFile = Path.Combine(HomeStorage.PluginData, "reboot-on-empty");
        _restartRequestFile = Path.Combine(HomeStorage.PluginData, "restart-server");
        _target = ParseTarget(Environment.GetEnvironmentVariable("ANVIL_RESTART_DAILY"));
        if (_target == null)
        {
            Log.Info("[ServerRestart] ANVIL_RESTART_DAILY unset/invalid — scheduled restart disabled "
                     + "(control file still honoured: " + _controlFile + ")");
        }
        else
        {
            Log.Info($"[ServerRestart] daily restart armed for {_target:hh\\:mm} server-local time.");
        }
        NwModule.Instance.OnClientEnter += OnPlayerEnter;
        _ = RunLoop();
    }

    private static TimeSpan? ParseTarget(string? hhmm)
    {
        if (string.IsNullOrWhiteSpace(hhmm)) return null;
        return TimeSpan.TryParseExact(hhmm.Trim(), new[] { "hh\\:mm", "h\\:mm" }, null, out TimeSpan t)
            ? t : (TimeSpan?)null;
    }

    private async Task RunLoop()
    {
        await NwTask.SwitchToMainThread();

        _nextRestart = _target == null ? null : NextOccurrence(_target.Value);
        var announced = new HashSet<int>();
        double prevRemaining = double.MaxValue;   // for once-only "crossing" detection

        while (true)
        {
            await NwTask.Delay(Tick);

            // Manual override for testing: a control file fires an immediate restart.
            if (File.Exists(_controlFile))
            {
                Log.Info("[ServerRestart] control file detected — triggering immediate restart.");
                TryDelete(_controlFile);
                await ShutdownSequence();
                announced.Clear();
                prevRemaining = double.MaxValue;
                _nextRestart = _target == null ? null : NextOccurrence(_target.Value);
                continue;
            }

            // Adhoc "reboot on empty": arm/disarm from the control file, warn
            // online players, and fire once the server has sat empty long enough.
            // Runs independently of the daily schedule; if it fires it exits the
            // loop via ShutdownSequence, so process it before the daily block.
            ProcessRebootOnEmpty();
            if (await MaybeRebootOnEmpty()) continue;

            if (_nextRestart == null) continue;

            double remaining = (_nextRestart.Value - DateTime.Now).TotalMinutes;

            if (remaining <= 0)
            {
                await ShutdownSequence();
                announced.Clear();
                prevRemaining = double.MaxValue;
                _nextRestart = NextOccurrence(_target!.Value);
                continue;
            }

            // Fire each warning once, as the countdown crosses below its mark. Using a
            // crossing test (prev above, now at/below) means a mid-window (re)start
            // won't retro-spam every earlier mark.
            foreach (int mark in WarnMarks)
            {
                if (!announced.Contains(mark) && remaining <= mark && prevRemaining > mark)
                {
                    string msg = WarnMessage(mark);
                    Broadcast(msg, mark <= 5 ? ColorConstants.Red : ColorConstants.Orange);
                    Shout(msg);
                    announced.Add(mark);
                }
            }
            prevRemaining = remaining;
        }
    }

    private static DateTime NextOccurrence(TimeSpan timeOfDay)
    {
        DateTime now = DateTime.Now;
        DateTime today = now.Date + timeOfDay;
        return today > now ? today : today.AddDays(1);
    }

    private static string WarnMessage(int minutes)
    {
        // Only the final 1-minute alert carries the downtime/safe-spot verbiage; the
        // earlier marks stay terse so the chat isn't spammed with the long sentence.
        if (minutes == 1)
            return $"[Server] Scheduled restart in 1 minute. The server will reboot for {DownDuration}; "
                 + "find a safe spot and expect a brief disconnect.";
        return $"[Server] Scheduled restart in {minutes} minutes.";
    }

    // ── Adhoc reboot-on-empty ────────────────────────────────────────────────────

    // Reconcile armed state against the control file each tick: arm on first
    // sight (or re-announce if the admin changed the message), disarm if the file
    // was removed (an admin can cancel a pending reboot with `bin/reboot-on-empty off`).
    private void ProcessRebootOnEmpty()
    {
        bool present = File.Exists(_armFile);
        if (present)
        {
            string msg = ReadAllTextSafe(_armFile).Trim();
            if (!_emptyArmed)
            {
                _emptyArmed = true;
                _emptyMsg = msg;
                _emptyIdleSeconds = 0;
                _lastReminder = DateTime.Now;
                AnnounceArm();
            }
            else if (msg != _emptyMsg)
            {
                _emptyMsg = msg;      // admin updated the message — re-announce
                _lastReminder = DateTime.Now;
                AnnounceArm();
            }
        }
        else if (_emptyArmed)
        {
            _emptyArmed = false;
            _emptyIdleSeconds = 0;
            Broadcast("[Server] The pending reboot has been cancelled by the admin.", ColorConstants.Green);
        }
    }

    // Fire the reboot once the server has been continuously empty for the grace
    // window. Returns true if a shutdown was triggered (caller should `continue`).
    private async Task<bool> MaybeRebootOnEmpty()
    {
        if (!_emptyArmed) return false;

        int online = NwModule.Instance.Players.Count(p => p.IsValid);
        if (online == 0)
        {
            _emptyIdleSeconds += Tick.TotalSeconds;
            if (_emptyIdleSeconds >= EmptyGraceSeconds)
            {
                await FireEmptyReboot();
                return true;
            }
            return false;
        }

        // Players present: reset the idle timer and re-nudge them periodically.
        _emptyIdleSeconds = 0;
        if (DateTime.Now - _lastReminder >= RemindEvery)
        {
            _lastReminder = DateTime.Now;
            Broadcast(ArmHeadline(), ColorConstants.Orange);
        }
        return false;
    }

    private async Task FireEmptyReboot()
    {
        Log.Info("[ServerRestart] reboot-on-empty: server empty — rebooting to load the staged update.");

        // Order matters. Delete the arm file FIRST so the restarted (still-empty)
        // server doesn't immediately reboot again — a boot loop. Then drop the
        // host restart-request flag; the systemd .path unit picks it up and
        // relaunches just the server service (optionally rebuilding nwsync first).
        TryDelete(_armFile);
        try { File.WriteAllText(_restartRequestFile, DateTime.Now.ToString("o")); }
        catch (Exception ex) { Log.Error(ex, "[ServerRestart] failed to write restart-request flag"); }

        _emptyArmed = false;
        await ShutdownSequence();   // clean export + ShutdownServer, same as the daily path
    }

    private void AnnounceArm()
    {
        string head = ArmHeadline();
        Broadcast(head, ColorConstants.Orange);
        Shout(head);
        if (!string.IsNullOrWhiteSpace(_emptyMsg))
        {
            string reason = "Reason: " + _emptyMsg;
            Broadcast(reason, ColorConstants.Cyan);
            Shout(reason);
        }
    }

    private string ArmHeadline() =>
        "[Server] A module update is staged. The server will reboot automatically the moment "
        + "it is next empty — please wrap up and log out when convenient.";

    private static string ReadAllTextSafe(string path)
    {
        try { return File.ReadAllText(path); } catch { return ""; }
    }

    private async Task ShutdownSequence()
    {
        await NwTask.SwitchToMainThread();
        string shutdownMsg = "[Server] Restarting NOW — saving characters.";
        Broadcast(shutdownMsg, ColorConstants.Red);
        Shout(shutdownMsg);

        // Persist every online character to the vault before the server exits.
        try { NWScript.ExportAllCharacters(); }
        catch (Exception ex) { Log.Error(ex, "[ServerRestart] ExportAllCharacters failed"); }

        // Give the export a moment to flush to disk, then shut the server down.
        await NwTask.Delay(TimeSpan.FromSeconds(3));
        Log.Info("[ServerRestart] export complete; shutting server down.");
        try { NwServer.Instance.ShutdownServer(); }
        catch (Exception ex) { Log.Error(ex, "[ServerRestart] ShutdownServer failed"); }
    }

    private static void Broadcast(string message, Color color)
    {
        foreach (NwPlayer p in NwModule.Instance.Players)
            if (p.IsValid)
                p.SendServerMessage(message, color);
        Log.Info($"[ServerRestart] broadcast: {message}");
    }

    // Spawns a temporary [SERVER] herald at an active player's location and has it
    // shout. SpeakString/SHOUT is server-wide, but action queues only run in areas
    // that have at least one player present — so we can't use the static NPC in
    // House of Homer if that area is empty. Spawning next to any online player
    // guarantees the area is active and the shout fires immediately.
    private static async void Shout(string message)
    {
        NwCreature? anchor = NwModule.Instance.Players
            .Where(p => p.IsValid && p.ControlledCreature?.Area != null)
            .Select(p => p.ControlledCreature)
            .FirstOrDefault();

        if (anchor == null)
        {
            Log.Info("[ServerRestart] No players online — shout skipped.");
            return;
        }

        NwCreature? herald = NwCreature.Create("server_npc", anchor.Location);
        if (herald == null)
        {
            Log.Warn("[ServerRestart] Failed to spawn shout herald — server_npc resref missing?");
            return;
        }

        // The shout is dropped if it fires the same instant the herald is created (the
        // object isn't fully registered module-wide yet). Let it settle for a beat, then
        // shout; keep the herald alive past the speak so it isn't destroyed mid-shout.
        NWScript.DestroyObject(herald, 6.0f);
        await NwTask.Delay(TimeSpan.FromSeconds(1));
        if (herald.IsValid)
            await herald.SpeakString(message, TalkVolume.Shout);
        Log.Info($"[ServerRestart] Shout herald spawned in area {anchor.Area!.Name}.");
    }

    private async void OnPlayerEnter(ModuleEvents.OnClientEnter evt)
    {
        if (evt.Player is not { IsValid: true } player) return;
        string? notice = RestartNotice();
        if (notice == null) return;

        // Messages sent the instant a client connects are dropped before the chat UI
        // is ready — wait a few seconds so the player actually sees the red notice.
        await NwTask.Delay(TimeSpan.FromSeconds(5));
        if (player.IsValid)
            player.SendServerMessage(notice, ColorConstants.Red);
    }

    private string? RestartNotice()
    {
        // A pending adhoc reboot-on-empty takes precedence in the on-login notice
        // — it's the more actionable "please log off so we can update" message.
        if (_emptyArmed)
        {
            string notice = "[Server] A module update is pending — the server will reboot as soon "
                          + "as it is next empty. Please log out when you're at a good stopping point.";
            if (!string.IsNullOrWhiteSpace(_emptyMsg))
                notice += " " + _emptyMsg;
            return notice;
        }

        if (_nextRestart == null) return null;
        double remaining = (_nextRestart.Value - DateTime.Now).TotalMinutes;
        if (remaining <= 0) return null;

        int hours = (int)remaining / 60;
        int minutes = (int)remaining % 60;
        string when = hours > 0
            ? $"{hours} hour{(hours == 1 ? "" : "s")} {minutes} minute{(minutes == 1 ? "" : "s")}"
            : $"{minutes} minute{(minutes == 1 ? "" : "s")}";
        return $"[Server] Next scheduled restart in {when}.";
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch { /* best-effort */ }
    }
}
