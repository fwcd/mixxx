#pragma once

#include <QObject>
#include <memory>
#include <vector>

#include "analyzer/plugins/analyzerplugin.h"
#include "analyzer/plugins/buffering_utils.h"

class DetectionFunction;

namespace mixxx {

class AnalyzerQueenMaryBeats : public AnalyzerBeatsPlugin {
  public:
    static AnalyzerPluginInfo pluginInfo() {
        return AnalyzerPluginInfo(
                // Don't change this ID. It was auto generated by VAMP until
                // Mixxx 2.1 and we keep it for a compatible config.
                "qm-tempotracker:0",
                QObject::tr("Queen Mary University London"),
                QObject::tr("Queen Mary Tempo and Beat Tracker"),
                true);
    }

    AnalyzerQueenMaryBeats();
    ~AnalyzerQueenMaryBeats() override;

    AnalyzerPluginInfo info() const override {
        return pluginInfo();
    }

    bool initialize(mixxx::audio::SampleRate sampleRate) override;
    bool processSamples(const CSAMPLE* pIn, SINT iLen) override;
    bool finalize() override;

    bool supportsBeatTracking() const override {
        return true;
    }

    QVector<mixxx::audio::FramePos> getBeats() const override {
        return m_resultBeats;
    }

  private:
    std::unique_ptr<DetectionFunction> m_pDetectionFunction;
    DownmixAndOverlapHelper m_helper;
    mixxx::audio::SampleRate m_sampleRate;
    int m_windowSize;
    int m_stepSizeFrames;
    std::vector<double> m_detectionResults;
    QVector<mixxx::audio::FramePos> m_resultBeats;
};

} // namespace mixxx
