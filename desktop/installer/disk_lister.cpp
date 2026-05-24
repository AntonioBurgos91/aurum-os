#include "disk_lister.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QVariantMap>

namespace aurum::installer {

namespace {

constexpr qulonglong kMinSize = 8ull * 1024ull * 1024ull * 1024ull; // 8 GiB

QString human_size(qulonglong bytes) {
    static const char* units[] = {"B", "KB", "MB", "GB", "TB"};
    double v = static_cast<double>(bytes);
    int i = 0;
    while (v >= 1024 && i < 4) { v /= 1024.0; ++i; }
    return QString("%1 %2").arg(v, 0, 'f', v < 10 ? 1 : 0).arg(units[i]);
}

} // namespace

DiskLister::DiskLister(QObject* parent) : QObject(parent) {
    refresh();
}

void DiskLister::refresh() {
    m_disks.clear();

    QProcess p;
    // -d: only physical disks (no partitions); -b: bytes; -J: JSON; -o: cols
    p.start("lsblk", {"-d", "-b", "-J", "-o", "NAME,SIZE,MODEL,TRAN,ROTA"});
    if (!p.waitForFinished(800)) {
        emit refreshed();
        return;
    }

    const auto doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    const auto arr = doc.object().value("blockdevices").toArray();
    for (const auto& v : arr) {
        const auto d = v.toObject();
        const qulonglong size_bytes = static_cast<qulonglong>(d.value("size").toDouble());
        if (size_bytes < kMinSize) continue;

        const auto name  = d.value("name").toString();
        const auto model = d.value("model").toString();
        const auto tran  = d.value("tran").toString();
        const bool rota  = d.value("rota").toBool();

        m_disks << QVariantMap{
            {"device",     "/dev/" + name},
            {"name",       name},
            {"sizeBytes",  static_cast<qulonglong>(size_bytes)},
            {"sizeHuman",  human_size(size_bytes)},
            {"model",      model.isEmpty() ? "Unknown disk" : model},
            {"transport",  tran},   // "nvme" | "sata" | "usb" | ...
            {"rotational", rota},
            {"warning",    tran == "usb" ? "Detected USB device — usually the install medium"
                                         : QString{}},
        };
    }
    emit refreshed();
}

} // namespace aurum::installer
