#include "backend/weather/weather_service.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QtMath>
#include <QScopeGuard>
#include <QSslError>

namespace {
constexpr auto kForecastTemplate =
    "http://api.open-meteo.com/v1/forecast?latitude=%1&longitude=%2"
    "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,precipitation"
    "&timezone=auto";
constexpr auto kIpLookupUrl = "http://ip-api.com/json";

QUrl buildForecastUrl(double latitude, double longitude) {
    return QUrl(QString::fromLatin1(kForecastTemplate)
                    .arg(latitude, 0, 'f', 4)
                    .arg(longitude, 0, 'f', 4));
}
} // namespace

WeatherService::WeatherService(QObject* parent)
    : QObject(parent) {
}

QString WeatherService::condition() const {
    return condition_;
}

QString WeatherService::icon() const {
    return icon_;
}

double WeatherService::temperature() const {
    return temperature_;
}

double WeatherService::humidity() const {
    return humidity_;
}

double WeatherService::windSpeed() const {
    return windSpeed_;
}

double WeatherService::precipitation() const {
    return precipitation_;
}

QDateTime WeatherService::lastUpdated() const {
    return lastUpdated_;
}

double WeatherService::latitude() const {
    return latitude_;
}

double WeatherService::longitude() const {
    return longitude_;
}

void WeatherService::fetchWeather() {
    if (pendingReply_) {
        pendingReply_->deleteLater();
        pendingReply_ = nullptr;
    }
    if (pendingLocationReply_) {
        pendingLocationReply_->deleteLater();
        pendingLocationReply_ = nullptr;
    }

    if (!locationResolved_) {
        requestLocation();
    } else {
        requestForecast();
    }
}

void WeatherService::handleWeatherReply() {
    if (!pendingReply_) {
        return;
    }

    auto reply = pendingReply_;
    pendingReply_ = nullptr;

    const auto cleanup = qScopeGuard([reply]() {
        reply->deleteLater();
    });

    if (reply->error() != QNetworkReply::NoError) {
        emit errorOccurred(reply->errorString());
        return;
    }

    const QByteArray payload = reply->readAll();
    updateFromPayload(payload);
}

void WeatherService::handleLocationReply() {
    if (!pendingLocationReply_) {
        return;
    }

    auto reply = pendingLocationReply_;
    pendingLocationReply_ = nullptr;

    const auto cleanup = qScopeGuard([reply]() {
        reply->deleteLater();
    });

    if (reply->error() != QNetworkReply::NoError) {
        emit errorOccurred(tr("Location lookup failed: %1").arg(reply->errorString()));
        return;
    }

    const auto payload = reply->readAll();
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isObject()) {
        emit errorOccurred(tr("Malformed IP geo payload"));
        return;
    }

    const QJsonObject obj = doc.object();
    const QString status = obj.value(QStringLiteral("status")).toString();
    if (status.compare(QStringLiteral("success"), Qt::CaseInsensitive) != 0) {
        const QString message = obj.value(QStringLiteral("message")).toString();
        emit errorOccurred(tr("Geo lookup failed: %1").arg(message));
        return;
    }

    const double lat = obj.value(QStringLiteral("lat")).toDouble(qQNaN());
    const double lon = obj.value(QStringLiteral("lon")).toDouble(qQNaN());
    if (qIsNaN(lat) || qIsNaN(lon)) {
        emit errorOccurred(tr("Geo lookup returned invalid coordinates"));
        return;
    }

    bool changed = false;
    if (!qFuzzyCompare(latitude_, lat)) {
        latitude_ = lat;
        changed = true;
    }
    if (!qFuzzyCompare(longitude_, lon)) {
        longitude_ = lon;
        changed = true;
    }
    locationResolved_ = true;

    if (changed) {
        emit locationChanged();
    }

    requestForecast();
}

void WeatherService::updateFromPayload(const QByteArray& payload) {
    const QJsonDocument doc = QJsonDocument::fromJson(payload);
    if (!doc.isObject()) {
        emit errorOccurred(QStringLiteral("Malformed weather payload"));
        return;
    }

    const QJsonObject root = doc.object();
    const QJsonObject current = root.value(QStringLiteral("current")).toObject();

    const double newTemp = current.value(QStringLiteral("temperature_2m")).toDouble(qQNaN());
    if (!qFuzzyCompare(temperature_, newTemp)) {
        temperature_ = newTemp;
        emit temperatureChanged();
    }

    const double newHumidity = current.value(QStringLiteral("relative_humidity_2m")).toDouble(qQNaN());
    if (!qFuzzyCompare(humidity_, newHumidity)) {
        humidity_ = newHumidity;
        emit humidityChanged();
    }

    const double newWind = current.value(QStringLiteral("wind_speed_10m")).toDouble(qQNaN());
    if (!qFuzzyCompare(windSpeed_, newWind)) {
        windSpeed_ = newWind;
        emit windSpeedChanged();
    }

    const double newPrecip = current.value(QStringLiteral("precipitation")).toDouble(qQNaN());
    if (!qFuzzyCompare(precipitation_, newPrecip)) {
        precipitation_ = newPrecip;
        emit precipitationChanged();
    }

    const int weatherCode = current.value(QStringLiteral("weather_code")).toInt();
    const QString description = descriptionForCode(weatherCode);
    if (condition_ != description) {
        condition_ = description;
        emit conditionChanged();
    }

    const QString icon = iconForCode(weatherCode);
    if (icon_ != icon) {
        icon_ = icon;
        emit iconChanged();
    }

    const QString timeStr = current.value(QStringLiteral("time")).toString();
    QDateTime parsed = QDateTime::fromString(timeStr, Qt::ISODate);
    if (!parsed.isValid()) {
        parsed = QDateTime::currentDateTime();
    }
    if (lastUpdated_ != parsed) {
        lastUpdated_ = parsed;
        emit lastUpdatedChanged();
    }
}

QString WeatherService::iconForCode(int code) const {
    // Mapping based on WMO weather interpretation codes
    switch (code) {
    case 0: return QStringLiteral("☀️");
    case 1:
    case 2: return QStringLiteral("🌤");
    case 3: return QStringLiteral("☁️");
    case 45:
    case 48: return QStringLiteral("🌫");
    case 51:
    case 53:
    case 55: return QStringLiteral("🌦");
    case 56:
    case 57: return QStringLiteral("🌨");
    case 61:
    case 63:
    case 65: return QStringLiteral("🌧");
    case 66:
    case 67: return QStringLiteral("🌧");
    case 71:
    case 73:
    case 75: return QStringLiteral("❄️");
    case 77: return QStringLiteral("🌨");
    case 80:
    case 81:
    case 82: return QStringLiteral("🌧");
    case 85:
    case 86: return QStringLiteral("❄️");
    case 95: return QStringLiteral("⛈");
    case 96:
    case 99: return QStringLiteral("🌩");
    default: return QStringLiteral("🌡");
    }
}

QString WeatherService::descriptionForCode(int code) const {
    switch (code) {
    case 0: return tr("Clear");
    case 1: return tr("Mainly clear");
    case 2: return tr("Partly cloudy");
    case 3: return tr("Overcast");
    case 45:
    case 48: return tr("Foggy");
    case 51:
    case 53:
    case 55: return tr("Drizzle");
    case 56:
    case 57: return tr("Freezing drizzle");
    case 61:
    case 63:
    case 65: return tr("Rain");
    case 66:
    case 67: return tr("Freezing rain");
    case 71:
    case 73:
    case 75: return tr("Snowfall");
    case 77: return tr("Snow grains");
    case 80:
    case 81:
    case 82: return tr("Rain showers");
    case 85:
    case 86: return tr("Snow showers");
    case 95: return tr("Thunderstorm");
    case 96:
    case 99: return tr("Thunderstorm with hail");
    default: return tr("Unknown");
    }
}

void WeatherService::requestLocation() {
    QNetworkRequest request(QUrl(QString::fromLatin1(kIpLookupUrl)));
    pendingLocationReply_ = manager_.get(request);
    pendingLocationReply_->setParent(this);

    connect(pendingLocationReply_, &QNetworkReply::finished,
            this, &WeatherService::handleLocationReply);

#if QT_CONFIG(ssl)
    connect(pendingLocationReply_, qOverload<const QList<QSslError>&>(&QNetworkReply::sslErrors), this,
            [this](const QList<QSslError>& errors) {
                QStringList descriptions;
                descriptions.reserve(errors.size());
                for (const auto& err : errors) {
                    descriptions << err.errorString();
                }
                emit errorOccurred(descriptions.join(QStringLiteral("; ")));
            });
#endif
}

void WeatherService::requestForecast() {
    if (!locationResolved_ || qIsNaN(latitude_) || qIsNaN(longitude_)) {
        emit errorOccurred(tr("Location not resolved"));
        return;
    }

    QNetworkRequest request(buildForecastUrl(latitude_, longitude_));
    pendingReply_ = manager_.get(request);
    pendingReply_->setParent(this);

    connect(pendingReply_, &QNetworkReply::finished, this, &WeatherService::handleWeatherReply);

#if QT_CONFIG(ssl)
    connect(pendingReply_, qOverload<const QList<QSslError>&>(&QNetworkReply::sslErrors),
            this, [this](const QList<QSslError>& errors) {
                QStringList descriptions;
                descriptions.reserve(errors.size());
                for (const auto& err : errors) {
                    descriptions << err.errorString();
                }
                emit errorOccurred(descriptions.join(QStringLiteral("; ")));
            });
#endif
}
