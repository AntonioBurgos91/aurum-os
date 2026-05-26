#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

namespace aurum::installer {

// Lists physical block devices ≥ 8 GiB via `lsblk -J`. Filters out USB sticks
// only on a best-effort basis (rota=true is rotational HDD; usb is exposed in
// "tran"). The wizard pre-selects the largest disk that's NOT mounted at /,
// which on a Live ISO is the target disk.
class DiskLister : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList disks READ disks NOTIFY refreshed)

public:
    explicit DiskLister(QObject* parent = nullptr);

    QVariantList disks() const {
        return m_disks;
    }

    Q_INVOKABLE void refresh();

signals:
    void refreshed();

private:
    QVariantList m_disks;
};

}  // namespace aurum::installer
