// QtTest coverage for FinderModel. The model is a QAbstractListModel that
// reads a directory off disk on cd()/refresh(), classifies entries via
// ml-integrations, and exposes them through Qt roles. We exercise it against
// a synthetic workspace built fresh in a QTemporaryDir for each test, so
// nothing depends on the host filesystem.
//
// Notes:
//   * The model's ctor calls reload() against $HOME, which may take a moment
//     on some hosts. init() immediately cd()'s into the fixture so the
//     home-dir state never leaks into a test assertion.
//   * QTEST_GUILESS_MAIN — no QGuiApplication needed; the model has no GUI
//     dependencies.
#include <QtTest>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QDir>
#include <QFile>
#include <QTextStream>

#include "finder_model.h"

using namespace aurum::finder;

class TestFinderModel : public QObject {
    Q_OBJECT
private slots:
    void init();
    void cleanup();

    void cd_into_workspace_lists_top_level_dirs();
    void cd_into_projects_lists_files();
    void cd_up_returns_to_workspace();
    void cd_to_nonexistent_path_is_noop();
    void filter_narrows_results();
    void filter_empty_clears();
    void data_roles_round_trip();
    void kind_classification_correct();
    void current_path_property_matches_cd();
    void breadcrumbs_property_chain();
    void refresh_picks_up_new_file();
    void cd_emits_current_path_changed();

private:
    QTemporaryDir m_tmp;
    QString m_workspace;

    void writeFile(const QString& relpath, const QString& body = QString());
    void mkdir(const QString& relpath);
    int findRow(FinderModel& m, const QString& name) const;
};

void TestFinderModel::init() {
    QVERIFY(m_tmp.isValid());
    m_workspace = m_tmp.path() + "/workspace";
    QVERIFY(QDir().mkpath(m_workspace));

    // Layout:
    //   workspace/Projects/{train.py, config.yaml}
    //   workspace/Models/checkpoint.safetensors
    //   workspace/Notebooks/analysis.ipynb
    mkdir("Projects");
    mkdir("Models");
    mkdir("Notebooks");
    writeFile("Projects/train.py",                  "print('hi')\n");
    writeFile("Projects/config.yaml",               "lr: 0.001\n");
    writeFile("Models/checkpoint.safetensors",      "binary-bytes");
    writeFile("Notebooks/analysis.ipynb",
              R"({"cells":[],"metadata":{},"nbformat":4,"nbformat_minor":5})");
}

void TestFinderModel::cleanup() {
    // QTemporaryDir auto-removes on destruction; we re-create it per test by
    // shadowing the member. Reassigning forces removal of the prior fixture.
    m_tmp.remove();
    m_tmp = QTemporaryDir();
}

void TestFinderModel::writeFile(const QString& relpath, const QString& body) {
    QFile f(m_workspace + "/" + relpath);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QTextStream s(&f);
    s << body;
}

void TestFinderModel::mkdir(const QString& relpath) {
    QVERIFY(QDir().mkpath(m_workspace + "/" + relpath));
}

int TestFinderModel::findRow(FinderModel& m, const QString& name) const {
    for (int i = 0; i < m.rowCount(); ++i) {
        if (m.data(m.index(i, 0), FinderModel::NameRole).toString() == name)
            return i;
    }
    return -1;
}

void TestFinderModel::cd_into_workspace_lists_top_level_dirs() {
    FinderModel m;
    m.cd(m_workspace);
    QCOMPARE(m.rowCount(), 3);  // Projects, Models, Notebooks — no files at top
}

void TestFinderModel::cd_into_projects_lists_files() {
    FinderModel m;
    m.cd(m_workspace);
    m.cd(m_workspace + "/Projects");
    QCOMPARE(m.rowCount(), 2);  // train.py, config.yaml
    QVERIFY(findRow(m, "train.py")    >= 0);
    QVERIFY(findRow(m, "config.yaml") >= 0);
}

void TestFinderModel::cd_up_returns_to_workspace() {
    FinderModel m;
    m.cd(m_workspace);
    m.cd(m_workspace + "/Projects");
    m.cdUp();
    QCOMPARE(m.currentPath(), m_workspace);
    QCOMPARE(m.rowCount(), 3);
}

void TestFinderModel::cd_to_nonexistent_path_is_noop() {
    FinderModel m;
    m.cd(m_workspace);
    const QString before = m.currentPath();
    const int rows_before = m.rowCount();

    m.cd(m_workspace + "/Does/Not/Exist/zzz");
    QCOMPARE(m.currentPath(), before);
    QCOMPARE(m.rowCount(), rows_before);
}

void TestFinderModel::filter_narrows_results() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    const int count = m.setFilter("train");
    QCOMPARE(count, 1);
    QCOMPARE(m.rowCount(), 1);
    QCOMPARE(m.data(m.index(0, 0), FinderModel::NameRole).toString(),
             QStringLiteral("train.py"));
}

void TestFinderModel::filter_empty_clears() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    m.setFilter("train");
    QCOMPARE(m.rowCount(), 1);

    m.setFilter(QString());
    QCOMPARE(m.rowCount(), 2);
}

void TestFinderModel::data_roles_round_trip() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    const int row = findRow(m, "train.py");
    QVERIFY(row >= 0);
    const auto idx = m.index(row, 0);

    QCOMPARE(m.data(idx, FinderModel::NameRole).toString(),
             QStringLiteral("train.py"));
    QVERIFY(m.data(idx, FinderModel::PathRole).toString()
                .endsWith("/Projects/train.py"));
    QCOMPARE(m.data(idx, FinderModel::IsDirRole).toBool(), false);
    QVERIFY(!m.data(idx, FinderModel::MtimeRole).toString().isEmpty());
}

void TestFinderModel::kind_classification_correct() {
    // Notebook
    {
        FinderModel m;
        m.cd(m_workspace + "/Notebooks");
        const int row = findRow(m, "analysis.ipynb");
        QVERIFY(row >= 0);
        QCOMPARE(m.data(m.index(row, 0), FinderModel::KindRole).toString(),
                 QStringLiteral("notebook"));
    }
    // Model (.safetensors)
    {
        FinderModel m;
        m.cd(m_workspace + "/Models");
        const int row = findRow(m, "checkpoint.safetensors");
        QVERIFY(row >= 0);
        QCOMPARE(m.data(m.index(row, 0), FinderModel::KindRole).toString(),
                 QStringLiteral("model"));
    }
    // Plain file (.py is not classified by ml-integrations -> "file")
    // and directories -> "dir".
    {
        FinderModel m;
        m.cd(m_workspace + "/Projects");
        const int row = findRow(m, "train.py");
        QVERIFY(row >= 0);
        QCOMPARE(m.data(m.index(row, 0), FinderModel::KindRole).toString(),
                 QStringLiteral("file"));
    }
    {
        FinderModel m;
        m.cd(m_workspace);
        const int row = findRow(m, "Projects");
        QVERIFY(row >= 0);
        QCOMPARE(m.data(m.index(row, 0), FinderModel::IsDirRole).toBool(), true);
        QCOMPARE(m.data(m.index(row, 0), FinderModel::KindRole).toString(),
                 QStringLiteral("dir"));
    }
}

void TestFinderModel::current_path_property_matches_cd() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    QCOMPARE(m.currentPath(), m_workspace + "/Projects");
}

void TestFinderModel::breadcrumbs_property_chain() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    const QStringList crumbs = m.breadcrumbs();
    // Every crumb must be a prefix of the next and the last must equal cwd.
    QVERIFY(!crumbs.isEmpty());
    QCOMPARE(crumbs.last(), m.currentPath());
    for (int i = 1; i < crumbs.size(); ++i)
        QVERIFY(crumbs[i].startsWith(crumbs[i - 1]));
}

void TestFinderModel::refresh_picks_up_new_file() {
    FinderModel m;
    m.cd(m_workspace + "/Projects");
    const int before = m.rowCount();

    writeFile("Projects/notes.md", "# notes\n");
    m.refresh();
    QCOMPARE(m.rowCount(), before + 1);
    QVERIFY(findRow(m, "notes.md") >= 0);
}

void TestFinderModel::cd_emits_current_path_changed() {
    FinderModel m;
    m.cd(m_workspace);
    QSignalSpy spy(&m, &FinderModel::currentPathChanged);
    QVERIFY(spy.isValid());

    m.cd(m_workspace + "/Projects");
    QCOMPARE(spy.count(), 1);

    // No-op cd (same path? still emits because guard only checks exists/dir).
    // Pull up to assert cdUp emits as well.
    spy.clear();
    m.cdUp();
    QCOMPARE(spy.count(), 1);

    // Invalid path → no signal.
    spy.clear();
    m.cd("/does/not/exist/aurum-finder-test");
    QCOMPARE(spy.count(), 0);
}

QTEST_GUILESS_MAIN(TestFinderModel)
#include "test_finder_model.moc"
