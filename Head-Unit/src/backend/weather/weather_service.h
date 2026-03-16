#ifndef BACKEND_WEATHER_WEATHER_SERVICE_H
#define BACKEND_WEATHER_WEATHER_SERVICE_H

#include <QObject>
#include <QDateTime>
#include <QNetworkAccessManager>
#include <QtMath>

class QNetworkReply;

class WeatherService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString condition READ condition NOTIFY conditionChanged)
    Q_PROPERTY(QString icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(double temperature READ temperature NOTIFY temperatureChanged)
    Q_PROPERTY(double humidity READ humidity NOTIFY humidityChanged)
    Q_PROPERTY(double windSpeed READ windSpeed NOTIFY windSpeedChanged)
    Q_PROPERTY(double precipitation READ precipitation NOTIFY precipitationChanged)
    Q_PROPERTY(QDateTime lastUpdated READ lastUpdated NOTIFY lastUpdatedChanged)
    Q_PROPERTY(double latitude READ latitude NOTIFY locationChanged)
    Q_PROPERTY(double longitude READ longitude NOTIFY locationChanged)

public:
    explicit WeatherService(QObject* parent = nullptr);

    QString condition() const;
    QString icon() const;
    double temperature() const;
    double humidity() const;
    double windSpeed() const;
    double precipitation() const;
    QDateTime lastUpdated() const;
    double latitude() const;
    double longitude() const;

    Q_INVOKABLE void fetchWeather();

signals:
    void conditionChanged();
    void iconChanged();
    void temperatureChanged();
    void humidityChanged();
    void windSpeedChanged();
    void precipitationChanged();
    void lastUpdatedChanged();
    void errorOccurred(const QString& message);
    void locationChanged();

private slots:
    void handleWeatherReply();
    void handleLocationReply();

private:
    void updateFromPayload(const QByteArray& payload);
    QString iconForCode(int code) const;
    QString descriptionForCode(int code) const;
    void requestLocation();
    void requestForecast();

    QNetworkAccessManager manager_;
    QNetworkReply* pendingReply_ = nullptr;
    QNetworkReply* pendingLocationReply_ = nullptr;

    QString condition_;
    QString icon_;
    double temperature_ = qQNaN();
    double humidity_ = qQNaN();
    double windSpeed_ = qQNaN();
    double precipitation_ = qQNaN();
    QDateTime lastUpdated_;

    double latitude_ = qQNaN();
    double longitude_ = qQNaN();
    bool locationResolved_ = false;
};

#endif // BACKEND_WEATHER_WEATHER_SERVICE_H
