// resolve_qml_path() walks four candidate locations in priority order; the
// tests below pin each branch by manipulating AURUM_QML_DIR and a temp dir
// laid out like a build tree. We deliberately do NOT seed the system paths
// (/usr/share, /usr/local/share) — those tests would only ever work where the
// host already had AurumOS installed.
#include <QtTest>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QFileInfo>

#include "core_services.h"

class TestResolvePath : public QObject {
    Q_OBJECT
private slots:
    void init();              // per-test cleanup
    void honors_aurum_qml_dir_when_set();
    void returns_empty_when_nothing_exists();
    void falls_back_to_argv0_qml_subdir();
    void argv0_takes_precedence_over_nonexistent_aurum_qml_dir();

private:
    // Each test gets its own temp dir to keep fixtures isolated. We can't
    // member-init it because QTemporaryDir creates a real dir on disk on
    // construction, and we want a fresh one per test.
    void writeFile(const QString& path, const QByteArray& data = "// stub\n");
};

void TestResolvePath::init() {
    // Wipe across tests so AURUM_QML_DIR leakage can't confuse the next case.
    qunsetenv("AURUM_QML_DIR");
}

void TestResolvePath::writeFile(const QString& path, const QByteArray& data) {
    QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QCOMPARE(f.write(data), qint64(data.size()));
}

void TestResolvePath::honors_aurum_qml_dir_when_set() {
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString qmlPath = tmp.path() + "/Foo.qml";
    writeFile(qmlPath);

    qputenv("AURUM_QML_DIR", tmp.path().toUtf8());

    // argv0 is a path under /tmp that has *no* qml/ subdir, so the only
    // candidate that resolves is AURUM_QML_DIR/Foo.qml.
    const QString got = resolve_qml_path(
        QStringLiteral("Foo.qml"),
        "/tmp/no-such-build-tree/bin/myapp");
    QCOMPARE(got, QFileInfo(qmlPath).absoluteFilePath());
}

void TestResolvePath::returns_empty_when_nothing_exists() {
    // AURUM_QML_DIR points at a real dir but the requested file is absent.
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("AURUM_QML_DIR", tmp.path().toUtf8());

    const QString got = resolve_qml_path(
        QStringLiteral("NoSuch.qml"),
        "/tmp/no-such-build-tree/bin/myapp");
    QVERIFY2(got.isEmpty(), qPrintable(QStringLiteral("expected empty, got: ") + got));
}

void TestResolvePath::falls_back_to_argv0_qml_subdir() {
    // Simulate "running straight out of the build tree": argv0 is
    // <tmp>/bin/myapp, and the qml lives in <tmp>/bin/qml/Foo.qml.
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString argv0  = tmp.path() + "/bin/myapp";
    const QString qmlFile = tmp.path() + "/bin/qml/Foo.qml";
    writeFile(argv0, "#!/bin/sh\n");
    writeFile(qmlFile);

    const QString got = resolve_qml_path(
        QStringLiteral("Foo.qml"), argv0.toUtf8().constData());
    QCOMPARE(got, QFileInfo(qmlFile).absoluteFilePath());
}

void TestResolvePath::argv0_takes_precedence_over_nonexistent_aurum_qml_dir() {
    // AURUM_QML_DIR points to a directory that does NOT contain the file;
    // resolution should skip it and walk down to the argv0 branch.
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    qputenv("AURUM_QML_DIR", (tmp.path() + "/empty").toUtf8());
    QVERIFY(QDir().mkpath(tmp.path() + "/empty"));

    const QString argv0   = tmp.path() + "/bin/myapp";
    const QString qmlFile = tmp.path() + "/bin/qml/Foo.qml";
    writeFile(argv0, "#!/bin/sh\n");
    writeFile(qmlFile);

    const QString got = resolve_qml_path(
        QStringLiteral("Foo.qml"), argv0.toUtf8().constData());
    QCOMPARE(got, QFileInfo(qmlFile).absoluteFilePath());
}

QTEST_GUILESS_MAIN(TestResolvePath)
#include "test_resolve_path.moc"
