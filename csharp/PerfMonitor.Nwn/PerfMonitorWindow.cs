using Anvil.API;
using Anvil.API.Events;
using Anvil.Services;
using NWN.Core;
using NLog;

namespace PerfMonitor.Nwn;

/// <summary>
/// The in-game readout: an admin-only NUI window showing live tick rate, frame
/// time and population, with a record button for a stress event.
///
/// <para><b>Why an item and not a console command.</b> This server has no DM
/// client, and a feature that can only be triggered by <c>dm_runscript</c> is
/// not a delivered feature. The trigger is the Palantír — a non-equippable
/// activated item, gated on the <c>admindb</c> whitelist, that an admin carries.</para>
///
/// <para><b>Why the whole window lives in C#.</b> Driving NUI from NWScript in
/// this module means the 16-character resref cap, no <c>&amp;</c> ref
/// parameters, and label widgets that clip silently. Anvil's NUI API has none
/// of those limits, and doing it here also means the module's
/// <c>Mod_OnActvtItem</c> hook (currently <c>dmfi_activate</c>) is left
/// completely alone rather than chained.</para>
/// </summary>
[ServiceBinding(typeof(PerfMonitorWindow))]
internal sealed class PerfMonitorWindow
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    /// <summary>Tag AND resref of the activating item. Must match the .uti blueprint.</summary>
    private const string PalantirTag = "perfmon_palantir";
    private const string WindowId = "perfmon";

    // Bind names are the contract between the layout below and Refresh().
    private static readonly NuiBind<string> Verdict = new("verdict");
    private static readonly NuiBind<string> TickRate = new("tickrate");
    private static readonly NuiBind<string> FrameTime = new("frametime");
    private static readonly NuiBind<string> Population = new("population");
    private static readonly NuiBind<string> Cpu = new("cpu");
    private static readonly NuiBind<string> Memory = new("memory");
    private static readonly NuiBind<string> RecordLabel = new("recordlabel");
    private static readonly NuiBind<string> RecordState = new("recordstate");

    private readonly PerfMonitorService _perf;
    private readonly Dictionary<uint, NuiWindowToken> _open = new();

    public PerfMonitorWindow(PerfMonitorService perf)
    {
        _perf = perf;
        NwModule.Instance.OnActivateItem += OnActivateItem;
        NwModule.Instance.OnNuiEvent += OnNuiEvent;
        NwModule.Instance.OnClientEnter += OnClientEnter;
        _perf.Sampled += OnSampled;
        Log.Info($"[PerfMon] palantir armed (item tag '{PalantirTag}')");
    }

    /// <summary>
    /// Hand an admin their palantir on login, once.
    ///
    /// <para>The alternative was placing it in the Donations/cheat chest, but
    /// that chest's stock is GENERATED from the counter-gear index — a
    /// hand-added entry there would be erased by the next
    /// bin/gen-cheat-chest.py run. Granting on login also means the tool
    /// follows the admin rather than living in one area, which is what a
    /// stress-event instrument needs.</para>
    ///
    /// <para>Doing it here rather than in welloferuenter.nss keeps the whole
    /// feature inside the plugin: no module script to keep in step, and no
    /// repack needed to change the grant rule.</para>
    /// </summary>
    private void OnClientEnter(ModuleEvents.OnClientEnter eventData)
    {
        NwPlayer? player = eventData.Player;
        if (player == null || !AdminGate.CanAdmin(player)) return;

        NwCreature? creature = player.LoginCreature;
        if (creature == null) return;
        if (creature.FindItemWithTag(PalantirTag) != null) return;

        // NWScript's synchronous create, not NwItem.Create — the Anvil overload
        // returns a Task, and an event handler is no place for a fire-and-forget
        // async call whose failure nobody would ever see. We are already on the
        // main thread here, so the direct call is both correct and simpler.
        uint item = NWScript.CreateItemOnObject(PalantirTag, creature);
        if (item == NWScript.OBJECT_INVALID)
        {
            Log.Error($"[PerfMon] could not create '{PalantirTag}' — is the .uti in the module?");
            return;
        }
        player.SendServerMessage(
            "A seeing-stone has been placed in your pack. Activate it to read the server's load.",
            ColorConstants.Cyan);
    }

    private void OnActivateItem(ModuleEvents.OnActivateItem eventData)
    {
        if (eventData.ActivatedItem?.Tag != PalantirTag) return;
        NwPlayer? player = eventData.ItemActivator?.ControllingPlayer;
        if (player == null) return;

        if (!AdminGate.CanAdmin(player))
        {
            // Say nothing revealing. A non-admin who finds one of these should
            // learn that it does nothing, not that a whitelist exists.
            player.SendServerMessage("The orb is dark and cold.", ColorConstants.Gray);
            return;
        }

        Open(player);
    }

    private void Open(NwPlayer player)
    {
        uint id = player.LoginCreature?.ObjectId ?? 0;
        if (id == 0) return;

        if (_open.TryGetValue(id, out NuiWindowToken existing))
        {
            existing.Close();
            _open.Remove(id);
            return;   // the palantir toggles
        }

        var window = new NuiWindow(BuildLayout(), "Server Load")
        {
            Geometry = new NuiRect(80, 80, 430, 330),
            Closable = true,
            Resizable = true,
        };

        if (!player.TryCreateNuiWindow(window, out NuiWindowToken token, WindowId))
        {
            player.SendServerMessage("The palantir will not focus.", ColorConstants.Red);
            return;
        }

        _open[id] = token;
        Render(token, _perf.Latest);
    }

    private static NuiLayout BuildLayout() => new NuiColumn
    {
        Children =
        {
            // The verdict first and largest: this is the number a crash party is
            // actually measuring, and burying it under a table would be a
            // readout nobody reads under pressure.
            new NuiRow { Children = { new NuiLabel(Verdict) { Height = 28f } } },
            new NuiRow { Children = { new NuiLabel(TickRate) { Height = 22f } } },
            new NuiRow { Children = { new NuiLabel(FrameTime) { Height = 22f } } },
            new NuiSpacer { Height = 6f },
            new NuiRow { Children = { new NuiLabel(Population) { Height = 22f } } },
            new NuiRow { Children = { new NuiLabel(Cpu) { Height = 22f } } },
            new NuiRow { Children = { new NuiLabel(Memory) { Height = 22f } } },
            new NuiSpacer { Height = 8f },
            new NuiRow { Children = { new NuiLabel(RecordState) { Height = 22f } } },
            new NuiRow
            {
                Children =
                {
                    new NuiButton(RecordLabel) { Id = "record", Height = 32f },
                    new NuiButton("Refresh") { Id = "refresh", Height = 32f },
                },
            },
            new NuiSpacer(),
            new NuiRow
            {
                Children =
                {
                    new NuiText("Tick rate is the verdict, not CPU. A busy server "
                                + "with a healthy tick rate is still serving everyone "
                                + "on time; players feel it only when frame time climbs.")
                    { Height = 58f },
                },
            },
        },
    };

    private void OnNuiEvent(ModuleEvents.OnNuiEvent eventData)
    {
        if (eventData.Token.WindowId != WindowId) return;

        uint id = eventData.Player.LoginCreature?.ObjectId ?? 0;

        if (eventData.EventType == NuiEventType.Close)
        {
            if (id != 0) _open.Remove(id);
            return;
        }

        if (eventData.EventType != NuiEventType.Click) return;

        // Re-check the gate on every action. The window could have been opened
        // before a key was removed from the whitelist, and a live window is not
        // a standing grant.
        if (!AdminGate.CanAdmin(eventData.Player))
        {
            eventData.Token.Close();
            if (id != 0) _open.Remove(id);
            return;
        }

        switch (eventData.ElementId)
        {
            case "record":
                if (_perf.IsRecording) _perf.StopRecording();
                else _perf.StartRecording($"session-{DateTime.Now:yyyyMMdd-HHmm}");
                break;
            case "refresh":
                break;
        }

        Render(eventData.Token, _perf.Latest);
    }

    private void OnSampled(PerfSample sample)
    {
        if (_open.Count == 0) return;
        foreach (KeyValuePair<uint, NuiWindowToken> entry in _open) Render(entry.Value, sample);
    }

    private void Render(NuiWindowToken token, PerfSample sample)
    {
        if (!sample.HasData)
        {
            token.SetBindValue(Verdict, "Gathering...");
            token.SetBindValue(TickRate, "");
            token.SetBindValue(FrameTime, "");
            token.SetBindValue(Population, "");
            token.SetBindValue(Cpu, "");
            token.SetBindValue(Memory, "");
        }
        else
        {
            token.SetBindValue(Verdict, sample.Degraded ? "DEGRADED — players will feel this"
                                                        : "Healthy");
            token.SetBindValue(TickRate, $"Tick rate    {sample.TicksPerSecond:0.0} /s");
            token.SetBindValue(FrameTime,
                $"Frame time   mean {sample.MeanMs:0.00} ms   p95 {sample.P95Ms:0.00} ms   max {sample.MaxMs:0.0} ms");
            token.SetBindValue(Population,
                $"Players      {sample.Players} in {sample.AreasWithPlayers} area(s)");
            token.SetBindValue(Cpu, $"CPU          {sample.CpuCores:0.00} core");
            token.SetBindValue(Memory,
                $"Memory       {sample.WorkingSetMb:0} MB resident, {sample.ManagedHeapMb:0} MB managed");
        }

        token.SetBindValue(RecordLabel, _perf.IsRecording ? "Stop recording" : "Start recording");
        token.SetBindValue(RecordState, _perf.IsRecording
            ? $"Recording: {_perf.SessionName}"
            : "Not recording");
    }
}
