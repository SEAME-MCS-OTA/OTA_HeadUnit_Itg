#include "ViewModel.h"

#include <QStringList>

namespace {
const std::unordered_map<std::string, ViewModel::TimerId> kTimerNameToId = {
    {"drive_mode", ViewModel::TimerId::DriveMode},
    {"ambient_light", ViewModel::TimerId::AmbientLight},
    {"music_playback", ViewModel::TimerId::MusicPlayback},
};

const QStringList kDriveModes = {
    QStringLiteral("NEUTRAL"),
    QStringLiteral("DRIVE"),
    QStringLiteral("REVERSE"),
    QStringLiteral("PARKING"),
};
} // namespace

ViewModel::ViewModel(QObject* parent)
    : QObject(parent) {
}

QString ViewModel::driveMode() const {
    return driveMode_;
}

int ViewModel::ambientLightLevel() const {
    return ambientLightLevel_;
}

bool ViewModel::musicPlaying() const {
    return musicPlaying_;
}

void ViewModel::receiveTimeout(const std::string& timerName) {
    const auto it = kTimerNameToId.find(timerName);
    if (it == kTimerNameToId.end()) {
        return;
    }

    switch (it->second) {
    case TimerId::DriveMode:
        handleDriveModeTick();
        break;
    case TimerId::AmbientLight:
        handleAmbientLightTick();
        break;
    case TimerId::MusicPlayback:
        handleMusicTick();
        break;
    }
}

void ViewModel::handleDriveModeTick() {
    const int currentIndex = kDriveModes.indexOf(driveMode_);
    const int nextIndex = (currentIndex + 1) % kDriveModes.size();
    driveMode_ = kDriveModes.at(nextIndex);
    emit driveModeChanged();
}

void ViewModel::handleAmbientLightTick() {
    ambientLightLevel_ = (ambientLightLevel_ + 10) % 110;
    emit ambientLightLevelChanged();
}

void ViewModel::handleMusicTick() {
    musicPlaying_ = !musicPlaying_;
    emit musicPlayingChanged();
}
