// Locks in the menubar telemetry readout formatting — the strings/values the
// user sees on the top strip. These were inline in aurum-menubar's
// SystemClient (untestable without a D-Bus daemon); extracted to
// aurum::core so they can be verified directly.
#include <QtTest>

#include "core_services.h"

using namespace aurum::core;

class TestTelemetryFormat : public QObject {
    Q_OBJECT
private slots:
    void net_zero_is_kb();
    void net_below_threshold_is_kb();
    void net_at_threshold_is_mb();
    void net_high_is_mb();
    void labels_switch_on_cpu_backend();
    void labels_are_gpu_on_real_gpu_backends();
    void bytes_to_gib_converts();
};

void TestTelemetryFormat::net_zero_is_kb() {
    QCOMPARE(format_net_throughput(0), QStringLiteral("0.0 KB/s"));
}

void TestTelemetryFormat::net_below_threshold_is_kb() {
    // 512 KiB/s = 0.5 MB/s? No: 524288 B = 0.5 MiB → that's >= 0.1, so MB/s.
    // Pick a value clearly under 0.1 MB/s: 51200 B = 0.0488 MB/s → KB/s.
    QCOMPARE(format_net_throughput(51200), QStringLiteral("50.0 KB/s"));
}

void TestTelemetryFormat::net_at_threshold_is_mb() {
    // 0.1 MB/s exactly = 104857.6 B; use 104858 → 0.1 MB/s (not < 0.1) → MB/s.
    QCOMPARE(format_net_throughput(104858), QStringLiteral("0.1 MB/s"));
}

void TestTelemetryFormat::net_high_is_mb() {
    // 5 MiB/s = 5242880 B → "5.0 MB/s".
    QCOMPARE(format_net_throughput(5242880), QStringLiteral("5.0 MB/s"));
}

void TestTelemetryFormat::labels_switch_on_cpu_backend() {
    QCOMPARE(util_label_for(QStringLiteral("cpu")), QStringLiteral("CPU"));
    QCOMPARE(mem_label_for(QStringLiteral("cpu")), QStringLiteral("RAM"));
}

void TestTelemetryFormat::labels_are_gpu_on_real_gpu_backends() {
    for (const auto& k : {"nvml", "amd-sysfs", "none", ""}) {
        QCOMPARE(util_label_for(QString::fromLatin1(k)), QStringLiteral("GPU"));
        QCOMPARE(mem_label_for(QString::fromLatin1(k)), QStringLiteral("VRAM"));
    }
}

void TestTelemetryFormat::bytes_to_gib_converts() {
    QCOMPARE(bytes_to_gib(0), 0.0);
    QCOMPARE(bytes_to_gib(1073741824ULL), 1.0);  // 1 GiB
    QCOMPARE(bytes_to_gib(536870912ULL), 0.5);   // 0.5 GiB
}

QTEST_MAIN(TestTelemetryFormat)
#include "test_telemetry_format.moc"
