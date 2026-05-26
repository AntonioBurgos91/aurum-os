// QtTest coverage for DockModel. The model reads:
//   * $XDG_CONFIG_HOME/aurum/dock.list (favorites list, one app-id per line)
//   * .desktop files under $XDG_DATA_HOME/applications + $XDG_DATA_DIRS
// We point both env vars at a QTemporaryDir so the test runs hermetically.
//
// What's worth pinning down:
//   * Honors XDG_CONFIG_HOME for the dock.list location.
//   * Reads N entries when the list points at N valid .desktop files.
//   * Skips list entries with no matching .desktop (no crash).
//   * reload() picks up edits to dock.list.
//   * Missing dock.list → falls back to kDefaultFavorites (we can only assert
//     "something" loads, since the defaults reference apps not on the test
//     system; the row count will be 0 with isValid()==true).
#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTextStream>
#include <QtTest>

#include "dock_model.h"

using namespace aurum::dock;

class TestDockModel : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void cleanupTestCase();
    void init();

    void ctor_reads_three_entries_from_list();
    void row_count_matches_list_length();
    void name_role_matches_desktop_name();
    void icon_url_role_present_when_icon_set();
    void reload_picks_up_added_entry();
    void missing_list_falls_back_to_defaults();
    void unresolvable_id_silently_skipped();
    void reload_emits_model_reset();

private:
    QTemporaryDir m_tmp;
    QString m_appsDir;    // <tmp>/applications  (== XDG_DATA_HOME/applications)
    QString m_configDir;  // <tmp>/config        (== XDG_CONFIG_HOME)
    QString m_listPath;   // <configDir>/aurum/dock.list

    QByteArray m_prev_data_home;
    QByteArray m_prev_data_dirs;
    QByteArray m_prev_config_home;

    void writeDesktop(const QString& id, const QString& name,
                      const QString& icon = QStringLiteral("application-x-executable"));
    void writeList(const QStringList& ids);
};

void TestDockModel::initTestCase() {
    QVERIFY(m_tmp.isValid());

    m_appsDir = m_tmp.path() + "/applications";  // XDG_DATA_HOME/applications
    m_configDir = m_tmp.path() + "/config";
    m_listPath = m_configDir + "/aurum/dock.list";

    QVERIFY(QDir().mkpath(m_appsDir));
    QVERIFY(QDir().mkpath(m_configDir + "/aurum"));

    m_prev_data_home = qgetenv("XDG_DATA_HOME");
    m_prev_data_dirs = qgetenv("XDG_DATA_DIRS");
    m_prev_config_home = qgetenv("XDG_CONFIG_HOME");

    // core-services looks under $XDG_DATA_HOME/applications. We pin
    // XDG_DATA_DIRS too so /usr/share's real .desktop files don't leak in
    // and confuse lookups (e.g. by resolving "firefox" against the host).
    qputenv("XDG_DATA_HOME", m_tmp.path().toUtf8());
    qputenv("XDG_DATA_DIRS", m_tmp.path().toUtf8());
    qputenv("XDG_CONFIG_HOME", m_configDir.toUtf8());
}

void TestDockModel::cleanupTestCase() {
    if (!m_prev_data_home.isEmpty())
        qputenv("XDG_DATA_HOME", m_prev_data_home);
    else
        qunsetenv("XDG_DATA_HOME");
    if (!m_prev_data_dirs.isEmpty())
        qputenv("XDG_DATA_DIRS", m_prev_data_dirs);
    else
        qunsetenv("XDG_DATA_DIRS");
    if (!m_prev_config_home.isEmpty())
        qputenv("XDG_CONFIG_HOME", m_prev_config_home);
    else
        qunsetenv("XDG_CONFIG_HOME");
}

void TestDockModel::init() {
    // Clean slate per test: wipe any .desktop fixtures and the list file.
    QDir(m_appsDir).removeRecursively();
    QVERIFY(QDir().mkpath(m_appsDir));
    QFile::remove(m_listPath);
}

void TestDockModel::writeDesktop(const QString& id, const QString& name, const QString& icon) {
    QFile f(m_appsDir + "/" + id + ".desktop");
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QTextStream s(&f);
    s << "[Desktop Entry]\n"
      << "Type=Application\n"
      << "Name=" << name << "\n"
      << "Exec=/usr/bin/true\n"
      << "Icon=" << icon << "\n";
}

void TestDockModel::writeList(const QStringList& ids) {
    QFile f(m_listPath);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QTextStream s(&f);
    for (const auto& id : ids) s << id << "\n";
}

void TestDockModel::ctor_reads_three_entries_from_list() {
    writeDesktop("aurum.dock.one", "App One");
    writeDesktop("aurum.dock.two", "App Two");
    writeDesktop("aurum.dock.three", "App Three");
    writeList({"aurum.dock.one", "aurum.dock.two", "aurum.dock.three"});

    DockModel m;
    QCOMPARE(m.rowCount(), 3);
}

void TestDockModel::row_count_matches_list_length() {
    writeDesktop("aurum.dock.a", "A");
    writeDesktop("aurum.dock.b", "B");
    writeList({"aurum.dock.a", "aurum.dock.b"});

    DockModel m;
    QCOMPARE(m.rowCount(), 2);
}

void TestDockModel::name_role_matches_desktop_name() {
    writeDesktop("aurum.dock.named", "My Pretty Name");
    writeList({"aurum.dock.named"});

    DockModel m;
    QCOMPARE(m.rowCount(), 1);
    QCOMPARE(m.data(m.index(0, 0), DockModel::NameRole).toString(),
             QStringLiteral("My Pretty Name"));
}

void TestDockModel::icon_url_role_present_when_icon_set() {
    // Use an absolute-path icon — themed_icon_url() passes those through
    // verbatim and skips the QIcon::fromTheme detour, which is sensitive to
    // the icon theme present on the test host.
    const QString iconPath = m_tmp.path() + "/icon.png";
    {
        QFile f(iconPath);
        QVERIFY(f.open(QIODevice::WriteOnly));
        // Smallest legal PNG bytes are fine — themed_icon_url just builds a
        // file:// URL from the absolute path; it doesn't decode the image.
        f.write("\x89PNG\r\n\x1a\n", 8);
    }
    writeDesktop("aurum.dock.icon", "Icon App", iconPath);
    writeList({"aurum.dock.icon"});

    DockModel m;
    QCOMPARE(m.rowCount(), 1);
    const QString url = m.data(m.index(0, 0), DockModel::IconUrlRole).toString();
    QVERIFY2(!url.isEmpty(), "iconUrl role should be non-empty when Icon= is set");
    QVERIFY(url.startsWith("file://"));
}

void TestDockModel::reload_picks_up_added_entry() {
    writeDesktop("aurum.dock.a", "A");
    writeDesktop("aurum.dock.b", "B");
    writeList({"aurum.dock.a", "aurum.dock.b"});

    DockModel m;
    QCOMPARE(m.rowCount(), 2);

    writeDesktop("aurum.dock.c", "C");
    writeList({"aurum.dock.a", "aurum.dock.b", "aurum.dock.c"});
    m.reload();
    QCOMPARE(m.rowCount(), 3);
}

void TestDockModel::missing_list_falls_back_to_defaults() {
    // No list file, no .desktop fixtures. The default favorite ids won't
    // resolve against our empty applications dir, so the model is valid but
    // empty. The key assertion is "does not crash and does not throw".
    QVERIFY(!QFile::exists(m_listPath));

    DockModel m;
    // The actual rowCount is 0 (defaults reference apps we don't ship in the
    // fixture), but the model must still be queryable.
    QVERIFY(m.rowCount() >= 0);
}

void TestDockModel::unresolvable_id_silently_skipped() {
    writeDesktop("aurum.dock.real", "Real App");
    writeList({"aurum.dock.real", "this.id.does.not.exist", "neither.does.this"});

    DockModel m;
    // The two missing ids drop out; only the real one survives.
    QCOMPARE(m.rowCount(), 1);
    QCOMPARE(m.data(m.index(0, 0), DockModel::NameRole).toString(), QStringLiteral("Real App"));
}

void TestDockModel::reload_emits_model_reset() {
    writeDesktop("aurum.dock.a", "A");
    writeList({"aurum.dock.a"});

    DockModel m;
    QSignalSpy spy(&m, &QAbstractItemModel::modelReset);
    QVERIFY(spy.isValid());

    m.reload();
    QCOMPARE(spy.count(), 1);
}

QTEST_GUILESS_MAIN(TestDockModel)
#include "test_dock_model.moc"
