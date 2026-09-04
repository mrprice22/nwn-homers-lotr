using System.Diagnostics;
using System.Text.Json;
using Anvil.API;
using Anvil.Services;
using NLog;

namespace PerfMonitor.Nwn;

/// <summary>
/// Measures how much headroom the server has left, and publishes it three ways:
/// a JSON status file for the host (<c>bin/perfmon</c>), a tagged log line, and
/// the live NUI window in <see cref="PerfMonitorWindow"/>.
///
/// <para><b>Why this exists alongside NWNX_Profiler.</b> The profiler answers
/// "where did the frame go" — it is the diagnostic. This answers "are we about
/// to fall over", continuously and cheaply, and can be read from inside the game
/// while a stress event is running. The profiler's per-script mode is far too
/// expensive to leave on during one; this is not.</para>
///
/// <para><b>Tick rate is the verdict, CPU% is not.</b> A server at 98% of a core
/// with a healthy tick rate is saturated but still serving every player on time.
/// The moment mean frame time climbs is the moment players feel it. That is the
/// number a crash party is actually measuring, so it is the one on the window.</para>
///
/// <para>Configuration, all forwarded from server.env (bin/serve passes only
/// <c>NWN_*</c>, <c>NWNX_*</c> and <c>ANVIL_*</c>, so the prefix is load-bearing):
/// <list type="bullet">
/// <item><c>ANVIL_PERFMON_INTERVAL</c> — report window in seconds (default 10).</item>
/// <item><c>ANVIL_PERFMON_LOG</c> — <c>always</c>, <c>never</c>, or the default
/// <c>degraded</c>, which logs only when a window looks bad. A per-window log
/// line on a healthy server is pure noise in a file people actually read.</item>
/// <item><c>ANVIL_PERFMON_DEGRADED_MS</c> — mean frame time (ms) that counts as
/// degraded (default 50, i.e. below ~20 ticks/second).</item>
/// </list></para>
/// </summary>
[ServiceBinding(typeof(PerfMonitorService))]
internal sealed class PerfMonitorService
{
    private static readonly Logger Log = LogManager.GetCurrentClassLogger();

    // One minute of frames at a pessimistic 100/s. Sized so the window is always
    // full of recent data without the ring itself becoming a memory concern.
    private const int RingCapacity = 6000;

    private readonly FrameSampler _frames = new(RingCapacity);
    private readonly string _statusFile;
    private readonly string _sessionDir;
    private readonly TimeSpan _interval;
    private readonly LogMode _logMode;
    private readonly double _degradedMs;

    private readonly Process _process = Process.GetCurrentProcess();
    private TimeSpan _lastCpu;
    private DateTime _lastCpuAt;

    // Recording state for a crash party: when set, every report window is also
    // appended to a session file that bin/perf-report can read.
    private string? _sessionName;
    private string? _sessionPath;

    /// <summary>The most recent published sample, for the NUI window to render.</summary>
    public PerfSample Latest { get; private set; } = PerfSample.Empty;

    /// <summary>Fires on the main thread after each report window is published.</summary>
    public event Action<PerfSample>? Sampled;

    public bool IsRecording => _sessionName != null;
    public string? SessionName => _sessionName;

    public PerfMonitorService()
    {
        _statusFile = Path.Combine(HomeStorage.PluginData, "perfmon-status.json");
        _sessionDir = Path.Combine(HomeStorage.PluginData, "perfmon-sessions");
        _interval = TimeSpan.FromSeconds(ReadDouble("ANVIL_PERFMON_INTERVAL", 10, 1, 3600));
        _degradedMs = ReadDouble("ANVIL_PERFMON_DEGRADED_MS", 50, 1, 10000);
        _logMode = (Environment.GetEnvironmentVariable("ANVIL_PERFMON_LOG") ?? "degraded")
            .Trim().ToLowerInvariant() switch
        {
            "always" => LogMode.Always,
            "never" => LogMode.Never,
            _ => LogMode.Degraded,
        };

        _lastCpu = _process.TotalProcessorTime;
        _lastCpuAt = DateTime.UtcNow;

        Log.Info($"[PerfMon] sampling every {_interval.TotalSeconds:0}s; "
                 + $"degraded above {_degradedMs:0}ms mean frame; log={_logMode}; "
                 + $"status={_statusFile}");

        _ = SampleLoop();
        _ = ReportLoop();
    }

    /// <summary>Start writing every window to a named session file. Idempotent.</summary>
    public void StartRecording(string name)
    {
        string safe = Sanitize(name);
        if (safe.Length == 0) return;
        Directory.CreateDirectory(_sessionDir);
        _sessionName = safe;
        _sessionPath = Path.Combine(_sessionDir, $"{safe}.jsonl");
        Log.Info($"[PerfMon] recording started -> {_sessionPath}");
    }

    public void StopRecording()
    {
        if (_sessionName == null) return;
        Log.Info($"[PerfMon] recording stopped ({_sessionName})");
        _sessionName = null;
        _sessionPath = null;
    }

    /// <summary>
    /// Times individual frames on the main thread.
    ///
    /// <para><c>NwTask.NextFrame()</c> resumes once per Anvil scheduler frame, so
    /// the wall time between two resumptions covers everything the engine did in
    /// between. That makes it a real measure of the server's loop rather than of
    /// this plugin.</para>
    ///
    /// <para><b>Calibration caveat, measured 2026-09-04.</b> This is Anvil's
    /// frame cadence, which TRACKS the engine's tick rate but does not equal it:
    /// on an idle dev realm this reported ~48/s while NWNX_Profiler's
    /// GameTickRate reported ~96/s over the same window. Treat the absolute
    /// number as a scale of its own and watch it RELATIVELY — a healthy baseline
    /// for this realm, and the drop away from it under load. When an absolute
    /// engine tick count is what matters, NWNX_Profiler's GameTickRate is the
    /// authority; bin/perf-report --tickrate prints it.</para>
    /// </summary>
    private async Task SampleLoop()
    {
        await NwTask.SwitchToMainThread();

        // A single long-lived Stopwatch, read as a delta. Restarting one per
        // frame would add a syscall-ish cost to the very loop being measured.
        var clock = Stopwatch.StartNew();
        double previous = clock.Elapsed.TotalMilliseconds;

        while (true)
        {
            await NwTask.NextFrame();
            double now = clock.Elapsed.TotalMilliseconds;
            double delta = now - previous;
            previous = now;

            // Guard against the module-load frame and any resume that crossed a
            // pause: a multi-second "frame" is not a frame, and letting one into
            // the ring poisons max and p95 for the next full minute.
            if (delta > 0 && delta < 5000) _frames.Add(delta);
        }
    }

    private async Task ReportLoop()
    {
        await NwTask.SwitchToMainThread();
        while (true)
        {
            await NwTask.Delay(_interval);
            try
            {
                Publish(Collect());
            }
            catch (Exception ex)
            {
                // A monitor that can take the server down is worse than no
                // monitor. Nothing in here is allowed to escape.
                Log.Error(ex, "[PerfMon] report window failed");
            }
        }
    }

    private PerfSample Collect()
    {
        FrameStats stats = _frames.Snapshot();
        _frames.Clear();

        int players = 0;
        foreach (NwPlayer _ in NwModule.Instance.Players) players++;

        // PlayerCount is an engine-side field, so this is 293 cheap reads rather
        // than 293 object enumerations. Deliberately NOT counting creatures or
        // objects here: walking every area's contents once per window is exactly
        // the kind of work this plugin exists to detect, and the profiler already
        // reports the AI update list size (AIUpdateListObjects) for free.
        int areasWithPlayers = 0;
        foreach (NwArea area in NwModule.Instance.Areas)
        {
            if (area.PlayerCount > 0) areasWithPlayers++;
        }

        // CPU share since the previous window: process CPU time divided by wall
        // time, so 1.0 means one core fully consumed. This is the whole nwserver
        // process, because Anvil runs inside it.
        TimeSpan cpuNow = _process.TotalProcessorTime;
        DateTime wallNow = DateTime.UtcNow;
        double elapsed = (wallNow - _lastCpuAt).TotalSeconds;
        double cores = elapsed > 0 ? (cpuNow - _lastCpu).TotalSeconds / elapsed : 0;
        _lastCpu = cpuNow;
        _lastCpuAt = wallNow;

        return new PerfSample(
            At: DateTimeOffset.UtcNow,
            Frames: stats.Frames,
            MeanMs: stats.MeanMs,
            MedianMs: stats.MedianMs,
            P95Ms: stats.P95Ms,
            MaxMs: stats.MaxMs,
            TicksPerSecond: stats.TicksPerSecond,
            Players: players,
            AreasWithPlayers: areasWithPlayers,
            CpuCores: cores,
            ManagedHeapMb: GC.GetTotalMemory(false) / 1048576.0,
            WorkingSetMb: _process.WorkingSet64 / 1048576.0,
            Degraded: stats.Frames > 0 && stats.MeanMs > _degradedMs,
            Recording: _sessionName);
    }

    private void Publish(PerfSample sample)
    {
        Latest = sample;

        string json = JsonSerializer.Serialize(sample, PerfJson.Options);

        // Write-then-rename, so bin/perfmon never reads a half-written file.
        string temp = _statusFile + ".tmp";
        File.WriteAllText(temp, json);
        File.Move(temp, _statusFile, overwrite: true);

        if (_sessionPath != null) File.AppendAllText(_sessionPath, json + "\n");

        bool shouldLog = _logMode switch
        {
            LogMode.Always => true,
            LogMode.Never => false,
            _ => sample.Degraded,
        };
        if (shouldLog && sample.Frames > 0)
        {
            Log.Info($"[PerfMon] {sample.TicksPerSecond:0.0} ticks/s "
                     + $"(mean {sample.MeanMs:0.00}ms, p95 {sample.P95Ms:0.00}ms, max {sample.MaxMs:0.0}ms) "
                     + $"| {sample.Players} player(s) in {sample.AreasWithPlayers} area(s) "
                     + $"| cpu {sample.CpuCores:0.00} core "
                     + (sample.Degraded ? "| DEGRADED" : ""));
        }

        Sampled?.Invoke(sample);
    }

    private static double ReadDouble(string name, double fallback, double min, double max)
    {
        string? raw = Environment.GetEnvironmentVariable(name);
        if (double.TryParse(raw, out double value) && value >= min && value <= max) return value;
        return fallback;
    }

    private static string Sanitize(string name)
    {
        Span<char> buffer = stackalloc char[Math.Min(name.Length, 64)];
        int length = 0;
        foreach (char c in name)
        {
            if (length == buffer.Length) break;
            if (char.IsLetterOrDigit(c) || c is '-' or '_' or '.') buffer[length++] = c;
            else if (c == ' ') buffer[length++] = '-';
        }
        return new string(buffer[..length]);
    }

    private enum LogMode { Always, Degraded, Never }
}
