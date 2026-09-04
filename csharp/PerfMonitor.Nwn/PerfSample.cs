using System.Text.Json;
using System.Text.Json.Serialization;

namespace PerfMonitor.Nwn;

/// <summary>
/// One report window, exactly as it is written to
/// <c>&lt;PluginData&gt;/perfmon-status.json</c> and to a recording session.
///
/// <para>This record IS the host contract — <c>bin/perfmon</c> and
/// <c>bin/perf-report</c> read these names. Renaming a property is a breaking
/// change to those tools, so treat it like a schema, not an internal type.</para>
/// </summary>
internal readonly record struct PerfSample(
    DateTimeOffset At,
    int Frames,
    double MeanMs,
    double MedianMs,
    double P95Ms,
    double MaxMs,
    double TicksPerSecond,
    int Players,
    int AreasWithPlayers,
    double CpuCores,
    double ManagedHeapMb,
    double WorkingSetMb,
    bool Degraded,
    string? Recording)
{
    public static readonly PerfSample Empty = new(
        DateTimeOffset.MinValue, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, null);

    /// <summary>True once at least one window has been published.</summary>
    [JsonIgnore]
    public bool HasData => Frames > 0;
}

internal static class PerfJson
{
    /// <summary>
    /// Compact, single-line output: the status file is rewritten every window
    /// and each recording line must be one JSON object for the JSONL readers.
    /// </summary>
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };
}
