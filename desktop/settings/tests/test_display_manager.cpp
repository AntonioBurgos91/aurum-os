// Unit tests for DisplayManager's pure helpers — the logic that decides what
// commands get sent to hyprctl and how monitor JSON is parsed. These run
// without a compositor or real displays (the I/O methods are not exercised
// here; they're thin QProcess/sysfs wrappers around this logic).
#include <QtTest>

#include "display_manager.h"

using namespace aurum::settings;

class TestDisplayManager : public QObject {
    Q_OBJECT
private slots:
    void parse_empty_or_garbage_is_empty();
    void parse_two_monitors();
    void build_keyword_format();
    void kelvin_labels();
    void clamp_percent_bounds();
};

void TestDisplayManager::parse_empty_or_garbage_is_empty() {
    QVERIFY(DisplayManager::parse_monitors(QByteArray()).isEmpty());
    QVERIFY(DisplayManager::parse_monitors("not json").isEmpty());
    QVERIFY(DisplayManager::parse_monitors("{}").isEmpty());  // object, not array
    QVERIFY(DisplayManager::parse_monitors("[]").isEmpty());
}

void TestDisplayManager::parse_two_monitors() {
    // Shape mirrors `hyprctl monitors -j`.
    const QByteArray json = R"([
      {"name":"eDP-1","description":"Laptop panel","width":2560,"height":1600,
       "refreshRate":90.0,"x":0,"y":0,"scale":1.5,"disabled":false,"focused":true},
      {"name":"DP-1","description":"Dell U2720Q","width":3840,"height":2160,
       "refreshRate":60.0,"x":2560,"y":0,"scale":1.0,"disabled":false,"focused":false}
    ])";
    const auto mons = DisplayManager::parse_monitors(json);
    QCOMPARE(mons.size(), 2);

    const auto m0 = mons[0].toMap();
    QCOMPARE(m0.value("name").toString(), QStringLiteral("eDP-1"));
    QCOMPARE(m0.value("width").toInt(), 2560);
    QCOMPARE(m0.value("height").toInt(), 1600);
    QCOMPARE(m0.value("refresh").toDouble(), 90.0);
    QCOMPARE(m0.value("scale").toDouble(), 1.5);
    QCOMPARE(m0.value("focused").toBool(), true);
    QCOMPARE(m0.value("active").toBool(), true);

    const auto m1 = mons[1].toMap();
    QCOMPARE(m1.value("name").toString(), QStringLiteral("DP-1"));
    QCOMPARE(m1.value("x").toInt(), 2560);
    QCOMPARE(m1.value("active").toBool(), true);
}

void TestDisplayManager::build_keyword_format() {
    // NAME,WIDTHxHEIGHT@REFRESH,XxY,SCALE
    QCOMPARE(DisplayManager::build_monitor_keyword("DP-1", 2560, 1440, 144.0, 0, 0, 1.0),
             QStringLiteral("DP-1,2560x1440@144,0x0,1"));
    QCOMPARE(DisplayManager::build_monitor_keyword("eDP-1", 1920, 1080, 60.0, 2560, 0, 1.25),
             QStringLiteral("eDP-1,1920x1080@60,2560x0,1.25"));
}

void TestDisplayManager::kelvin_labels() {
    QCOMPARE(DisplayManager::kelvin_to_label(6500), QStringLiteral("Neutral"));
    QCOMPARE(DisplayManager::kelvin_to_label(5500), QStringLiteral("Cool"));
    QCOMPARE(DisplayManager::kelvin_to_label(4200), QStringLiteral("Soft"));
    QCOMPARE(DisplayManager::kelvin_to_label(3400), QStringLiteral("Warm"));
    QCOMPARE(DisplayManager::kelvin_to_label(1800), QStringLiteral("Very warm"));
}

void TestDisplayManager::clamp_percent_bounds() {
    QCOMPARE(DisplayManager::clamp_percent(-10), 0);
    QCOMPARE(DisplayManager::clamp_percent(0), 0);
    QCOMPARE(DisplayManager::clamp_percent(55), 55);
    QCOMPARE(DisplayManager::clamp_percent(100), 100);
    QCOMPARE(DisplayManager::clamp_percent(250), 100);
}

QTEST_MAIN(TestDisplayManager)
#include "test_display_manager.moc"
