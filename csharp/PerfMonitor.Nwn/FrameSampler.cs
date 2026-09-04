using System.Diagnostics;

namespace PerfMonitor.Nwn;

/// <summary>
/// A fixed-capacity ring of recent frame times, and the statistics worth
/// reading off it.
///
/// <para>Deliberately allocation-free per frame. This is sampled on the game's
/// own main thread on a box whose main loop already saturates a core, so the
/// measurement must not become part of the problem: a growing list, a LINQ
/// chain per frame, or a lock would all show up in the very number being
/// measured.</para>
///
/// <para><b>Percentiles are computed on a copy.</b> Sorting the live buffer
/// would corrupt the ring's ordering; the copy happens once per report window
/// (seconds apart), never per frame.</para>
/// </summary>
internal sealed class FrameSampler
{
    private readonly double[] _samples;
    private int _next;
    private int _count;

    // Scratch buffer for percentile work, reused so a report costs no allocation
    // either. Guarded by the same "only touched from the main thread" rule as
    // the ring itself.
    private readonly double[] _scratch;

    public FrameSampler(int capacity)
    {
        _samples = new double[capacity];
        _scratch = new double[capacity];
    }

    public int Count => _count;

    public void Add(double milliseconds)
    {
        _samples[_next] = milliseconds;
        _next = (_next + 1) % _samples.Length;
        if (_count < _samples.Length) _count++;
    }

    public void Clear()
    {
        _next = 0;
        _count = 0;
    }

    /// <summary>Mean, p50, p95, max and the derived tick rate over the window.</summary>
    public FrameStats Snapshot()
    {
        if (_count == 0) return FrameStats.Empty;

        double total = 0, max = 0;
        for (int i = 0; i < _count; i++)
        {
            double value = _samples[i];
            total += value;
            if (value > max) max = value;
            _scratch[i] = value;
        }

        Array.Sort(_scratch, 0, _count);
        double mean = total / _count;

        return new FrameStats(
            Frames: _count,
            MeanMs: mean,
            MedianMs: Percentile(_scratch, _count, 0.50),
            P95Ms: Percentile(_scratch, _count, 0.95),
            MaxMs: max,
            // Frames per second implied by the average frame. Reported instead of
            // counting wall-clock seconds because a stalled frame should drag this
            // down immediately rather than being averaged away by the next window.
            TicksPerSecond: mean > 0 ? 1000.0 / mean : 0);
    }

    private static double Percentile(double[] sorted, int count, double fraction)
    {
        int index = (int)Math.Round(fraction * (count - 1), MidpointRounding.AwayFromZero);
        if (index < 0) index = 0;
        if (index >= count) index = count - 1;
        return sorted[index];
    }
}

internal readonly record struct FrameStats(
    int Frames, double MeanMs, double MedianMs, double P95Ms, double MaxMs, double TicksPerSecond)
{
    public static readonly FrameStats Empty = new(0, 0, 0, 0, 0, 0);
}
