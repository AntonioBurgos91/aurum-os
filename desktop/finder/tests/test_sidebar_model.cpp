// QtTest coverage for SidebarModel. The sidebar is built from QStandardPaths
// and $HOME, so we point HOME at a QTemporaryDir, populate the directories we
// want to see, and assert the model picks them up.
//
// SidebarModel only includes entries whose paths actually exist on disk —
// that's the bit worth pinning down here.
#include <QtTest>
#include <QTemporaryDir>
#include <QDir>
#include <QStandardPaths>

#include "sidebar_model.h"

using namespace aurum::finder;

class TestSidebarModel : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void cleanupTestCase();

    void has_at_least_home_entry();
    void names_are_non_empty_strings();
    void favorites_section_present();
    void ml_section_appears_when_dirs_exist();
    void missing_dirs_are_excluded();

private:
    QTemporaryDir m_tmp;
    QByteArray    m_prev_home;
    QByteArray    m_prev_xdg_data_home;
    QByteArray    m_prev_xdg_config_home;

    int rowsInSection(SidebarModel& m, const QString& section) const;
};

void TestSidebarModel::initTestCase() {
    QVERIFY(m_tmp.isValid());

    // Capture so cleanupTestCase can restore.
    m_prev_home            = qgetenv("HOME");
    m_prev_xdg_data_home   = qgetenv("XDG_DATA_HOME");
    m_prev_xdg_config_home = qgetenv("XDG_CONFIG_HOME");

    qputenv("HOME", m_tmp.path().toUtf8());
    qputenv("XDG_DATA_HOME",   (m_tmp.path() + "/.local/share").toUtf8());
    qputenv("XDG_CONFIG_HOME", (m_tmp.path() + "/.config").toUtf8());

    // QStandardPaths caches results; force a reload now that HOME has changed.
    QStandardPaths::setTestModeEnabled(true);
}

void TestSidebarModel::cleanupTestCase() {
    QStandardPaths::setTestModeEnabled(false);
    if (!m_prev_home.isEmpty())            qputenv("HOME", m_prev_home);
    if (!m_prev_xdg_data_home.isEmpty())   qputenv("XDG_DATA_HOME", m_prev_xdg_data_home);
    if (!m_prev_xdg_config_home.isEmpty()) qputenv("XDG_CONFIG_HOME", m_prev_xdg_config_home);
}

int TestSidebarModel::rowsInSection(SidebarModel& m, const QString& section) const {
    int n = 0;
    for (int i = 0; i < m.rowCount(); ++i) {
        if (m.data(m.index(i, 0), SidebarModel::SectionRole).toString() == section)
            ++n;
    }
    return n;
}

void TestSidebarModel::has_at_least_home_entry() {
    SidebarModel m;
    // HOME directory always exists (it's our QTemporaryDir), so the Home
    // favorite must be present.
    QVERIFY(m.rowCount() >= 1);
}

void TestSidebarModel::names_are_non_empty_strings() {
    SidebarModel m;
    for (int i = 0; i < m.rowCount(); ++i) {
        const QString name = m.data(m.index(i, 0), SidebarModel::NameRole).toString();
        QVERIFY2(!name.isEmpty(),
                 qPrintable(QString("empty name at row %1").arg(i)));
        const QString path = m.data(m.index(i, 0), SidebarModel::PathRole).toString();
        QVERIFY2(!path.isEmpty(),
                 qPrintable(QString("empty path at row %1").arg(i)));
    }
}

void TestSidebarModel::favorites_section_present() {
    SidebarModel m;
    QVERIFY(rowsInSection(m, "Favorites") >= 1);  // Home at minimum
}

void TestSidebarModel::ml_section_appears_when_dirs_exist() {
    // Create the ML workspace dirs the sidebar looks for.
    QVERIFY(QDir().mkpath(m_tmp.path() + "/datasets"));
    QVERIFY(QDir().mkpath(m_tmp.path() + "/models"));
    QVERIFY(QDir().mkpath(m_tmp.path() + "/notebooks"));

    SidebarModel m;
    QCOMPARE(rowsInSection(m, "ML"), 3);
}

void TestSidebarModel::missing_dirs_are_excluded() {
    // Fresh tempdir for this test — no datasets/models/notebooks.
    QTemporaryDir empty;
    QVERIFY(empty.isValid());
    qputenv("HOME", empty.path().toUtf8());

    SidebarModel m;
    QCOMPARE(rowsInSection(m, "ML"), 0);

    // Restore for any subsequent tests.
    qputenv("HOME", m_tmp.path().toUtf8());
}

QTEST_GUILESS_MAIN(TestSidebarModel)
#include "test_sidebar_model.moc"
