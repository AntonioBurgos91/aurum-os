#include "hypr_client.h"

#include <QByteArray>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QVariantMap>

namespace aurum::mc {

HyprClient::HyprClient(QObject* parent) : QObject(parent) {
    refresh();
}

QByteArray HyprClient::runHyprctl(const QStringList& args) const {
    QProcess p;
    // hyprctl locates the running compositor via the HYPRLAND_INSTANCE_SIGNATURE
    // env var. QProcess does NOT inherit the parent's environment by default
    // on every Qt build (it's documented as "implementation defined"), so
    // we explicitly propagate the full system environment. Without this the
    // child returned rc=1 with "Couldn't connect to socket".
    p.setProcessEnvironment(QProcessEnvironment::systemEnvironment());
    QStringList full = QStringList{"-j"} << args;
    p.start("hyprctl", full);
    if (!p.waitForFinished(500)) {
        qWarning() << "[mc] hyprctl timed out:" << args;
        return {};
    }
    if (p.exitCode() != 0) {
        qWarning() << "[mc] hyprctl rc=" << p.exitCode() << "args=" << args;
        return {};
    }
    return p.readAllStandardOutput();
}

void HyprClient::refresh() {
    m_workspaces.clear();
    m_clients.clear();

    // --- Workspaces ---------------------------------------------------------
    const auto ws_raw = runHyprctl({"workspaces"});
    const auto ws_arr = QJsonDocument::fromJson(ws_raw).array();
    for (const auto& v : ws_arr) {
        const auto w = v.toObject();
        m_workspaces << QVariantMap{
            {"id",         w.value("id").toInt()},
            {"name",       w.value("name").toString()},
            {"monitor",    w.value("monitor").toString()},
            {"windows",    w.value("windows").toInt()},
            {"hasfullscreen", w.value("hasfullscreen").toBool()},
        };
    }

    // --- Active workspace --------------------------------------------------
    const auto active_raw = runHyprctl({"activeworkspace"});
    const auto active_obj = QJsonDocument::fromJson(active_raw).object();
    m_active = active_obj.value("id").toInt(-1);

    // --- Clients -----------------------------------------------------------
    // Each entry includes: address, class, title, workspace.id, at, size, pid.
    const auto cl_raw = runHyprctl({"clients"});
    const auto cl_arr = QJsonDocument::fromJson(cl_raw).array();
    for (const auto& v : cl_arr) {
        const auto c = v.toObject();
        const auto ws = c.value("workspace").toObject().value("id").toInt(-1);
        const auto at = c.value("at").toArray();
        const auto sz = c.value("size").toArray();
        m_clients << QVariantMap{
            {"address",      c.value("address").toString()},
            {"class",        c.value("class").toString()},
            {"title",        c.value("title").toString()},
            {"workspaceId",  ws},
            {"x",            at.size() == 2 ? at.at(0).toInt() : 0},
            {"y",            at.size() == 2 ? at.at(1).toInt() : 0},
            {"width",        sz.size() == 2 ? sz.at(0).toInt() : 0},
            {"height",       sz.size() == 2 ? sz.at(1).toInt() : 0},
            {"focused",      c.value("focusHistoryID").toInt(-1) == 0},
        };
    }

    emit refreshed();
}

bool HyprClient::focus(const QString& address) {
    if (address.isEmpty()) return false;
    QProcess p;
    p.setProcessEnvironment(QProcessEnvironment::systemEnvironment());
    p.start("hyprctl", {"dispatch", "focuswindow", "address:" + address});
    if (!p.waitForFinished(400)) return false;
    return p.exitCode() == 0;
}

bool HyprClient::gotoWorkspace(int id) {
    QProcess p;
    p.setProcessEnvironment(QProcessEnvironment::systemEnvironment());
    p.start("hyprctl", {"dispatch", "workspace", QString::number(id)});
    if (!p.waitForFinished(400)) return false;
    return p.exitCode() == 0;
}

} // namespace aurum::mc
