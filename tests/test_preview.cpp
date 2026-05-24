// Exercises libml-integrations preview() against a file path; prints JSON.
// Used by the production verification pass to validate the Quick Look
// pipeline without needing a running Finder.
#include <QFile>
#include <QJsonDocument>
#include <QString>
#include <iostream>

#include "ml_integrations.h"

int main(int argc, char* argv[]) {
    init_ml_integrations();
    if (argc < 2) {
        std::cerr << "usage: aurum-test-preview <path>\n";
        return 2;
    }
    const auto preview = aurum::ml::preview(QString::fromUtf8(argv[1]));
    std::cout << QJsonDocument(preview)
                     .toJson(QJsonDocument::Compact)
                     .toStdString()
              << '\n';
    return 0;
}
