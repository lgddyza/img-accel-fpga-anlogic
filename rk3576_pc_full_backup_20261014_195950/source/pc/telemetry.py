"""Derive utilization and payload rates from timestamped board counters."""
import math


class TelemetryRates:
    def __init__(self):
        self.reset()

    def reset(self):
        self.previous_cpu = None
        self.previous_tiles = {}

    def update(self, status):
        cpu = status.get('cpu', {})
        previous = self.previous_cpu
        cpu_percent, cores = None, {}
        if previous and previous.get('boot_id') == cpu.get('boot_id'):
            elapsed = cpu.get('sample_s', 0)-previous.get('sample_s', 0)
            if .1 <= elapsed <= 10:
                for name, current in cpu.get('ticks', {}).items():
                    old = previous.get('ticks', {}).get(name)
                    if old:
                        total = current['total']-old['total']
                        idle = current['idle']-old['idle']
                        if total > 0 and 0 <= idle <= total:
                            percent = 100*(total-idle)/total
                            if name == 'cpu':
                                cpu_percent = percent
                            else:
                                cores[name] = percent
        self.previous_cpu = cpu if cpu else None
        rates, tile_fps = [None]*3, [None]*3
        current_tiles = {}
        now = status.get('monotonic_s', 0)
        viewer = status.get('viewer_pid')
        if viewer and status.get('runtime') != 'stopped':
            for sample in status.get('pcie_capture', []):
                tile = sample.get('tile')
                if tile not in (0, 1, 2) or sample.get('pid') != viewer:
                    continue
                if not 0 <= now-sample.get('sample_s', 0) < 3:
                    continue
                old = self.previous_tiles.get(tile)
                if old and old['pid'] == viewer:
                    elapsed = sample['sample_s']-old['sample_s']
                    count = sample['payload_bytes']-old['payload_bytes']
                    frames = sample['frames']-old['frames']
                    if .1 <= elapsed <= 10 and count >= 0 and frames >= 0:
                        rates[tile] = count*8/elapsed/1e6
                        tile_fps[tile] = frames/elapsed
                    elif elapsed == 0:
                        # Polling may read the same one-second board snapshot twice.
                        rates[tile] = old.get('rate_mbps')
                        tile_fps[tile] = old.get('fps')
                current_tiles[tile] = dict(sample, rate_mbps=rates[tile], fps=tile_fps[tile])
        self.previous_tiles = current_tiles
        total_rate = sum(rates) if all(value is not None for value in rates) else None
        return {'cpu_percent': cpu_percent, 'cpu_cores': cores,
                'pcie_mbps': rates, 'pcie_total_mbps': total_rate, 'tile_fps': tile_fps}


def finite_percent(value):
    if isinstance(value, (int, float)) and math.isfinite(value):
        return max(0, min(100, value))
    return None
