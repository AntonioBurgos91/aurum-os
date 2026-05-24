// Tests for launch_mutex_for(id) — the per-id mutex that serialises
// concurrent launches of the same desktop entry, preventing the
// hyprctl-window-check race that used to produce duplicate windows on rapid
// dock clicks.
//
// Two invariants we care about:
//   1. Multiple threads contending on the SAME id never deadlock and all
//      eventually make progress.
//   2. Threads contending on DIFFERENT ids run concurrently — the lock is
//      per-id, not global.
#include <QtTest>
#include <QElapsedTimer>

#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>
#include <vector>

#include "core_services.h"

using namespace aurum::core;
using namespace std::chrono_literals;

class TestDedupMutex : public QObject {
    Q_OBJECT
private slots:
    void same_id_returns_same_mutex();
    void different_ids_return_distinct_mutexes();
    void same_id_serialises_without_deadlock();
    void different_ids_run_in_parallel();
};

void TestDedupMutex::same_id_returns_same_mutex() {
    // Memoisation invariant: two lookups for the same id must yield the
    // *same* mutex instance, else the lock has no serialising effect.
    std::mutex& a = launch_mutex_for(QStringLiteral("dedup.test.same"));
    std::mutex& b = launch_mutex_for(QStringLiteral("dedup.test.same"));
    QCOMPARE(&a, &b);
}

void TestDedupMutex::different_ids_return_distinct_mutexes() {
    std::mutex& a = launch_mutex_for(QStringLiteral("dedup.test.alpha"));
    std::mutex& b = launch_mutex_for(QStringLiteral("dedup.test.beta"));
    QVERIFY(&a != &b);
}

void TestDedupMutex::same_id_serialises_without_deadlock() {
    constexpr int kThreads = 10;
    std::atomic<int> completed{0};

    std::vector<std::thread> ts;
    ts.reserve(kThreads);
    for (int i = 0; i < kThreads; ++i) {
        ts.emplace_back([&completed]() {
            std::lock_guard<std::mutex> g(
                launch_mutex_for(QStringLiteral("dedup.test.contended")));
            // Hold the lock briefly — long enough that overlapping threads
            // actually contend rather than racing through serially by accident.
            std::this_thread::sleep_for(5ms);
            completed.fetch_add(1, std::memory_order_relaxed);
        });
    }
    for (auto& t : ts) t.join();

    QCOMPARE(completed.load(), kThreads);
}

void TestDedupMutex::different_ids_run_in_parallel() {
    // Each thread gets its own id → its own mutex → no contention. If the
    // implementation accidentally degraded to a global lock, total wall time
    // would be ~kThreads * kHoldMs; with proper per-id locking it should be
    // ~kHoldMs.
    constexpr int kThreads = 10;
    constexpr auto kHoldMs = 50ms;

    std::vector<std::thread> ts;
    ts.reserve(kThreads);

    QElapsedTimer clock;
    clock.start();
    for (int i = 0; i < kThreads; ++i) {
        // Capture kHoldMs explicitly — older clang/gcc on the dev container
        // refuses to implicitly capture a constexpr of non-literal-class type
        // (std::chrono::duration), so the bare [i] form fails to compile.
        ts.emplace_back([i, kHoldMs]() {
            const QString id = QStringLiteral("dedup.test.parallel.%1").arg(i);
            std::lock_guard<std::mutex> g(launch_mutex_for(id));
            std::this_thread::sleep_for(kHoldMs);
        });
    }
    for (auto& t : ts) t.join();
    const qint64 elapsedMs = clock.elapsed();

    // Generous ceiling: serial execution would be ~500ms (10 * 50ms);
    // parallel should be ~50ms. 250ms leaves plenty of slack for slow CI
    // schedulers without ever passing in the serial-regression case.
    QVERIFY2(elapsedMs < 250,
             qPrintable(QStringLiteral("expected parallel < 250ms, got %1ms")
                            .arg(elapsedMs)));
}

QTEST_GUILESS_MAIN(TestDedupMutex)
#include "test_dedup_mutex.moc"
