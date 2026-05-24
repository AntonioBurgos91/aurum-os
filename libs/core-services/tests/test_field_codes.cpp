// Locks in the behaviour of strip_field_codes() — the XDG Exec field-code
// scrubber that runs on every dock-icon launch. The regex covers
// %[fFuUickdDnNvm]; .simplified() collapses any whitespace runs the removal
// leaves behind.
#include <QtTest>

#include "core_services.h"

using namespace aurum::core;

class TestFieldCodes : public QObject {
    Q_OBJECT
private slots:
    void strips_single_url_code();
    void strips_multi_file_code();
    void strips_inline_icon_code();
    void leaves_clean_command_unchanged();
    void empty_input_yields_empty();
    void strips_all_known_codes();
    void preserves_intermediate_args();
};

void TestFieldCodes::strips_single_url_code() {
    // The trailing "%u" plus space collapses cleanly via simplified().
    QCOMPARE(strip_field_codes(QStringLiteral("firefox %u")),
             QStringLiteral("firefox"));
}

void TestFieldCodes::strips_multi_file_code() {
    QCOMPARE(strip_field_codes(QStringLiteral("code --new-window %F")),
             QStringLiteral("code --new-window"));
}

void TestFieldCodes::strips_inline_icon_code() {
    // %i sits between two literals; removing it leaves a double space which
    // simplified() squashes to one.
    QCOMPARE(strip_field_codes(QStringLiteral("sh -c 'foo %i bar'")),
             QStringLiteral("sh -c 'foo bar'"));
}

void TestFieldCodes::leaves_clean_command_unchanged() {
    QCOMPARE(strip_field_codes(QStringLiteral("app")),
             QStringLiteral("app"));
}

void TestFieldCodes::empty_input_yields_empty() {
    QCOMPARE(strip_field_codes(QString()), QString());
    QCOMPARE(strip_field_codes(QStringLiteral("")), QString());
}

void TestFieldCodes::strips_all_known_codes() {
    // Every code listed in the regex character class, in one go. After
    // removal we're left with "app" plus a run of spaces that simplified()
    // collapses to nothing trailing.
    QCOMPARE(strip_field_codes(
                 QStringLiteral("app %f %u %F %U %i %c %k %d %D %n %N %v %m")),
             QStringLiteral("app"));
}

void TestFieldCodes::preserves_intermediate_args() {
    // Regression guard: the regex must not nibble at non-code "%" usage that
    // happens to precede a code character. We *do* still strip the codes; we
    // just want the surrounding tokens intact.
    QCOMPARE(strip_field_codes(QStringLiteral("zen --foo=bar %U baz")),
             QStringLiteral("zen --foo=bar baz"));
}

QTEST_GUILESS_MAIN(TestFieldCodes)
#include "test_field_codes.moc"
