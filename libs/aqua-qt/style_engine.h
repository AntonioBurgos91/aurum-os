#pragma once

#include <QColor>
#include <QFont>
#include <QPalette>
#include <QString>

namespace aurum::aqua {

// Color tokens lifted from macOS Sequoia Dark. Keep this in sync with
// /etc/aurum/hypr/aurum.conf if you change border/shadow values there.
struct Tokens {
    QColor windowBg       { 28,  28,  30  };
    QColor surface        { 38,  38,  40  };
    QColor surfaceRaised  { 50,  50,  54  };
    QColor textPrimary    {255, 255, 255  };
    QColor textSecondary  {142, 142, 147  };
    QColor border         { 60,  60,  64  };
    QColor accent         { 10, 132, 255  };  // macOS systemBlue
    QColor accentText     {255, 255, 255  };
    QColor success        { 48, 209,  88  };
    QColor warning        {255, 159,  10  };
    QColor danger         {255,  69,  58  };

    int    cornerRadius   = 12;
    int    cornerRadiusSm =  8;
    int    strokeWidth    =  1;
};

const Tokens& tokens();

// Build the Qt palette derived from `tokens()`. Use this for both QApplication
// and individual widgets.
QPalette aqua_dark_palette();

// Default UI font (Inter, then SF-equivalents, then sans-serif).
QFont aqua_default_font();

// Default monospace font (FiraCode → SF Mono → fallback).
QFont aqua_mono_font();

} // namespace aurum::aqua

// Global init kept at C linkage so existing main.cpp callers compile unchanged.
// Sets the Fusion style (which honors palettes — the platform style on some
// distros ignores them), applies the AurumOS palette, and registers fonts.
// Idempotent.
extern "C" void init_aqua_style();

// Legacy helpers kept for source compatibility with the original API. New
// code should call the aurum::aqua functions directly.
QPalette get_aqua_dark_palette();
QFont    get_aqua_default_font();
