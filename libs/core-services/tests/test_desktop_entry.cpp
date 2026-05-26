// QtTest coverage for the .desktop file parser and lookup logic in
// core_services. Fixtures are written into a QTemporaryDir whose path is
// pinned via XDG_DATA_HOME so we exercise the real XDG search code without
// touching the host system's /usr/share.
//
// We intentionally avoid GUI bring-up (QTEST_GUILESS_MAIN) — the parser
// touches nothing graphical and CI may not have a display.
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTextStream>
#include <QtTest>

#include "core_services.h"

using namespace aurum::core;

class TestDesktopEntry : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void parses_minimal_entry();
    void rejects_non_application_type();
    void rejects_missing_required_fields();
    void splits_categories();
    void honors_no_display();
    void lookup_returns_invalid_for_missing();
    void lookup_finds_by_id();

private:
    QTemporaryDir m_tmp;
    QString m_appsDir;  // <tmp>/applications

    // Write `body` to <appsDir>/<id>.desktop. The XDG search code looks in
    // $XDG_DATA_HOME/applications, so fixtures must land in the right subdir.
    void writeEntry(const QString& id, const QString& body);
};

void TestDesktopEntry::initTestCase() {
    QVERIFY(m_tmp.isValid());
    m_appsDir = m_tmp.path() + "/applications";
    QVERIFY(QDir().mkpath(m_appsDir));

    // Pin XDG so desktop_search_paths() resolves to our fixture dir. We pin
    // XDG_DATA_DIRS too — the production default is /usr/local/share:/usr/share
    // which on the dev container is full of real .desktop files that would
    // pollute lookup results.
    qputenv("XDG_DATA_HOME", m_tmp.path().toUtf8());
    qputenv("XDG_DATA_DIRS", m_tmp.path().toUtf8());
}

void TestDesktopEntry::writeEntry(const QString& id, const QString& body) {
    const QString path = m_appsDir + "/" + id + ".desktop";
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    QTextStream s(&f);
    s << body;
}

void TestDesktopEntry::parses_minimal_entry() {
    writeEntry("aurum.test.minimal", QStringLiteral(R"([Desktop Entry]
Type=Application
Name=Minimal
Exec=/usr/bin/true
Icon=minimal-icon
)"));

    DesktopEntry e = lookup_desktop_entry("aurum.test.minimal");
    QVERIFY(e.isValid());
    QCOMPARE(e.id, QStringLiteral("aurum.test.minimal"));
    QCOMPARE(e.name, QStringLiteral("Minimal"));
    QCOMPARE(e.exec, QStringLiteral("/usr/bin/true"));
    QCOMPARE(e.icon, QStringLiteral("minimal-icon"));
    QVERIFY(!e.noDisplay);
    QVERIFY(!e.hidden);
    QVERIFY(!e.terminal);
}

void TestDesktopEntry::rejects_non_application_type() {
    writeEntry("aurum.test.link", QStringLiteral(R"([Desktop Entry]
Type=Link
Name=A Link
URL=https://example.com/
)"));

    // parse_one() clears the id when Type != Application, so the entry round-
    // trips as "invalid" from the caller's perspective.
    DesktopEntry e = lookup_desktop_entry("aurum.test.link");
    QVERIFY(!e.isValid());
}

void TestDesktopEntry::rejects_missing_required_fields() {
    // No Type= line at all → parse_one's `Type != "Application"` branch fires
    // and clears id, mirroring the Link case.
    writeEntry("aurum.test.untyped", QStringLiteral(R"([Desktop Entry]
Name=No Type
Exec=/usr/bin/true
)"));

    DesktopEntry e = lookup_desktop_entry("aurum.test.untyped");
    QVERIFY(!e.isValid());
}

void TestDesktopEntry::splits_categories() {
    // Quirk worth pinning: QSettings(IniFormat) treats ';' outside of quotes
    // as a comment delimiter, so the XDG-spec form
    // "Categories=Development;IDE;TextEditor;" arrives at parse_one as just
    // "Development" — split() then produces one element. To force the split
    // path we wrap the whole value in double quotes; QSettings strips the
    // quotes and hands parse_one the literal "Development;IDE;TextEditor;",
    // which then splits cleanly on ';'.
    //
    // (This is a known limitation of using QSettings as the .desktop parser
    // and matches the observable behaviour of the dock today — locking it in
    // here so a future swap to a real XDG parser is loudly visible.)
    writeEntry("aurum.test.categories", QStringLiteral(R"([Desktop Entry]
Type=Application
Name=Cats
Exec=/usr/bin/true
Categories="Development;IDE;TextEditor;"
)"));

    DesktopEntry e = lookup_desktop_entry("aurum.test.categories");
    QVERIFY(e.isValid());
    QCOMPARE(e.categories.size(), 3);
    QCOMPARE(e.categories[0], QStringLiteral("Development"));
    QCOMPARE(e.categories[1], QStringLiteral("IDE"));
    QCOMPARE(e.categories[2], QStringLiteral("TextEditor"));
}

void TestDesktopEntry::honors_no_display() {
    writeEntry("aurum.test.nodisplay", QStringLiteral(R"([Desktop Entry]
Type=Application
Name=Hidden From Menu
Exec=/usr/bin/true
NoDisplay=true
)"));

    // lookup_desktop_entry returns the parsed entry regardless of NoDisplay
    // (it's the *scanner* that filters); we just want to confirm the field
    // round-trips through QSettings.
    DesktopEntry e = lookup_desktop_entry("aurum.test.nodisplay");
    QVERIFY(e.isValid());
    QVERIFY(e.noDisplay);
}

void TestDesktopEntry::lookup_returns_invalid_for_missing() {
    DesktopEntry e = lookup_desktop_entry(QStringLiteral("aurum.test.does-not-exist-xyzzy"));
    QVERIFY(!e.isValid());
    QVERIFY(e.id.isEmpty());
}

void TestDesktopEntry::lookup_finds_by_id() {
    writeEntry("aurum.test.findme", QStringLiteral(R"([Desktop Entry]
Type=Application
Name=Findable
Exec=/usr/bin/echo hello
)"));

    DesktopEntry e = lookup_desktop_entry("aurum.test.findme");
    QVERIFY(e.isValid());
    QCOMPARE(e.id, QStringLiteral("aurum.test.findme"));
    QCOMPARE(e.name, QStringLiteral("Findable"));
}

QTEST_GUILESS_MAIN(TestDesktopEntry)
#include "test_desktop_entry.moc"
