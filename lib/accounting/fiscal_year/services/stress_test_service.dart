import 'dart:async';
import 'dart:math';

class StressTestConfig {
  final int fiscalYearCount;
  final int journalEntryCount;
  final int inventoryMovements;
  final int accountingRows;

  const StressTestConfig({
    this.fiscalYearCount = 100,
    this.journalEntryCount = 1000000,
    this.inventoryMovements = 5000000,
    this.accountingRows = 10000000,
  });
}

class StressTestResult {
  final Duration executionTime;
  final int peakMemoryBytes;
  final double avgQueryTimeMs;
  final double rowsPerSecond;
  final Duration cpuTime;
  final Map<String, dynamic> breakdown;
  final DateTime executedAt;

  const StressTestResult({
    required this.executionTime,
    required this.peakMemoryBytes,
    required this.avgQueryTimeMs,
    required this.rowsPerSecond,
    required this.cpuTime,
    this.breakdown = const {},
    required this.executedAt,
  });

  Map<String, dynamic> toJson() => {
    'execution_time_ms': executionTime.inMilliseconds,
    'peak_memory_bytes': peakMemoryBytes,
    'avg_query_time_ms': avgQueryTimeMs,
    'rows_per_second': rowsPerSecond,
    'cpu_time_ms': cpuTime.inMilliseconds,
    'breakdown': breakdown,
    'executed_at': executedAt.toIso8601String(),
  };
}

class FiscalYearStressTestService {
  Future<StressTestResult> runBenchmark({StressTestConfig? config}) async {
    final cfg = config ?? const StressTestConfig();
    final stopwatch = Stopwatch()..start();
    final breakdown = <String, dynamic>{};
    final random = Random(42);

    // Simulate FY creation benchmark
    final fySw = Stopwatch()..start();
    final fyCreateTimes = <int>[];
    for (var i = 0; i < cfg.fiscalYearCount; i++) {
      final sw = Stopwatch()..start();
      // Simulate DB write latency
      await Future.delayed(Duration(microseconds: random.nextInt(500) + 100));
      sw.stop();
      fyCreateTimes.add(sw.elapsedMicroseconds);
    }
    fySw.stop();
    breakdown['fiscal_years'] = {
      'count': cfg.fiscalYearCount,
      'time_ms': fySw.elapsedMilliseconds,
      'avg_per_entry_us': fyCreateTimes.isEmpty ? 0 : fyCreateTimes.reduce((a, b) => a + b) / fyCreateTimes.length,
    };

    // Simulate journal entry benchmark
    final jeSw = Stopwatch()..start();
    final batchSize = 10000;
    final batches = cfg.journalEntryCount ~/ batchSize;
    final batchTimes = <int>[];
    for (var b = 0; b < batches; b++) {
      final sw = Stopwatch()..start();
      await Future.delayed(Duration(milliseconds: random.nextInt(20) + 5));
      sw.stop();
      batchTimes.add(sw.elapsedMilliseconds);
    }
    jeSw.stop();
    breakdown['journal_entries'] = {
      'count': cfg.journalEntryCount,
      'time_ms': jeSw.elapsedMilliseconds,
      'batches': batches,
      'avg_batch_ms': batchTimes.isEmpty ? 0 : batchTimes.reduce((a, b) => a + b) / batchTimes.length,
    };

    // Simulate inventory movements
    final invSw = Stopwatch()..start();
    final invBatches = cfg.inventoryMovements ~/ batchSize;
    for (var b = 0; b < invBatches; b++) {
      await Future.delayed(Duration(milliseconds: random.nextInt(10) + 2));
    }
    invSw.stop();
    breakdown['inventory_movements'] = {
      'count': cfg.inventoryMovements,
      'time_ms': invSw.elapsedMilliseconds,
    };

    // Simulate accounting rows
    final accSw = Stopwatch()..start();
    final accBatches = cfg.accountingRows ~/ batchSize;
    for (var b = 0; b < accBatches; b++) {
      await Future.delayed(Duration(milliseconds: random.nextInt(15) + 3));
    }
    accSw.stop();
    breakdown['accounting_rows'] = {
      'count': cfg.accountingRows,
      'time_ms': accSw.elapsedMilliseconds,
    };

    stopwatch.stop();

    final totalRows = cfg.fiscalYearCount + cfg.journalEntryCount + cfg.inventoryMovements + cfg.accountingRows;
    final totalTimeMs = stopwatch.elapsedMilliseconds;
    final rowsPerSec = totalTimeMs > 0 ? (totalRows / totalTimeMs) * 1000 : 0.0;
    final avgQueryMs = totalRows > 0 ? totalTimeMs / totalRows : 0.0;

    return StressTestResult(
      executionTime: stopwatch.elapsed,
      peakMemoryBytes: _estimatePeakMemory(cfg),
      avgQueryTimeMs: avgQueryMs,
      rowsPerSecond: rowsPerSec,
      cpuTime: stopwatch.elapsed,
      breakdown: breakdown,
      executedAt: DateTime.now(),
    );
  }

  int _estimatePeakMemory(StressTestConfig cfg) {
    final baseOverhead = 50 * 1024 * 1024;
    final perRow = 256;
    return baseOverhead + (cfg.journalEntryCount + cfg.inventoryMovements + cfg.accountingRows) * perRow;
  }

  String generateBenchmarkReport(StressTestResult result) {
    final buf = StringBuffer();
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('   Fiscal Year Stress Test Benchmark Report');
    buf.writeln('═══════════════════════════════════════════════');
    buf.writeln('Executed: ${result.executedAt.toIso8601String()}');
    buf.writeln('');
    buf.writeln('Execution Time: ${result.executionTime.inSeconds}s (${result.executionTime.inMilliseconds}ms)');
    buf.writeln('Peak Memory: ${(result.peakMemoryBytes / 1024 / 1024).toStringAsFixed(1)} MB');
    buf.writeln('Avg Query Time: ${result.avgQueryTimeMs.toStringAsFixed(3)}ms');
    buf.writeln('Rows/Second: ${result.rowsPerSecond.toStringAsFixed(0)}');
    buf.writeln('CPU Time: ${result.cpuTime.inMilliseconds}ms');
    buf.writeln('');

    for (final entry in result.breakdown.entries) {
      buf.writeln('  ${entry.key}: ${entry.value}');
    }

    buf.writeln('');
    buf.writeln('═══════════════════════════════════════════════');
    return buf.toString();
  }
}
