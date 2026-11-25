import { Injectable } from '@nestjs/common';

@Injectable()
export class OperationalMetricsService {
  private readonly counters = new Map<string, number>();

  increment(name: 'location_updates_total'|'location_rejections_total'|'voice_calls_started_total'|'voice_signals_total', amount = 1) {
    this.counters.set(name, (this.counters.get(name) ?? 0) + amount);
  }

  render(): string {
    const lines = ['# Tamreedy operational counters (process-local; aggregate by Prometheus)'];
    for (const [name, value] of [...this.counters.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      lines.push(`# TYPE tamreedy_${name} counter`, `tamreedy_${name} ${value}`);
    }
    lines.push(`# TYPE tamreedy_process_uptime_seconds gauge`, `tamreedy_process_uptime_seconds ${Math.floor(process.uptime())}`);
    const memory = process.memoryUsage();
    lines.push(`# TYPE tamreedy_process_resident_memory_bytes gauge`, `tamreedy_process_resident_memory_bytes ${memory.rss}`);
    return `${lines.join('\n')}\n`;
  }
}
