#include "ReverbDSP.h"
#include "../../ThirdParty/SignalsmithReverb/Reverb.h"

#include <algorithm>
#include <cmath>
#include <new>

using namespace piano_reverb;

static float bound(float value, float minimum, float maximum, float fallback) {
    return std::isfinite(value) ? std::clamp(value, minimum, maximum) : fallback;
}

struct PRReverbDSP {
    signalsmith::basics::ReverbSTFX<Base> core;
    double rate;
    unsigned maxFrames;
    Config config;
    PRReverbParameters target{.35f, 1, 2.2f, 1.f / 3, 18, .5f, 1, .2f, 1.2f};
    PRReverbParameters current = target;
    std::vector<float> preL, preR;
    std::vector<float> scratchL, scratchR;
    std::vector<float> inputL, inputR;
    unsigned write = 0;
    double room = 60, oldRoom = 60, pendingRoom = 60;
    double pre = 18, oldPre = 18, pendingPre = 18;
    double fade = 1;
    bool started = false;

    PRReverbDSP(double sampleRate, unsigned frames)
        : rate(sampleRate), maxFrames(frames), config{sampleRate},
          preL(unsigned(sampleRate * .101) + 8), preR(preL.size()),
          scratchL(frames), scratchR(frames), inputL(frames), inputR(frames) {
        core.configureSTFX(config);
        reset();
    }

    void setCore(bool snap) {
        auto set = [&](Parameter& parameter, double value) {
            if (snap) parameter.snap(value);
            else parameter = value;
        };
        set(core.dry, 0);
        set(core.wet, 1);
        set(core.rt20, current.decaySeconds / 3.);
        set(core.early, current.early);
        set(core.detune, current.modulation * 10);
        set(core.lowCutHz, 120);
        set(core.lowDampRate, 1.5);
        set(core.highCutHz, std::min(4000 * std::pow(4., current.tone), rate * .45));
        set(core.highDampRate, 4 - 2.5 * current.tone);
        core.roomMs.previous = oldRoom + (room - oldRoom) * fade;
        core.roomMs.value = core.roomMs.previous;
    }

    void reset() {
        current = target;
        current.mix = target.enabled ? target.mix : 0;
        room = oldRoom = pendingRoom = 10 + 150 * current.size;
        pre = oldPre = pendingPre = current.preDelayMs;
        fade = 1;
        write = 0;
        started = false;
        std::fill(preL.begin(), preL.end(), 0);
        std::fill(preR.begin(), preR.end(), 0);
        core.reset();
        setCore(true);
    }

    float delayed(std::vector<float>& buffer, double milliseconds) {
        double position = write - milliseconds * .001 * rate;
        while (position < 0) position += buffer.size();
        unsigned index = unsigned(position) % buffer.size();
        float fraction = position - std::floor(position);
        return buffer[index] * (1 - fraction)
            + buffer[(index + 1) % buffer.size()] * fraction;
    }
};

extern "C" PRReverbDSP* pr_reverb_create(double rate, unsigned frames) {
    if (!std::isfinite(rate) || rate < 8000 || rate > 192000
        || frames == 0 || frames > 65536) {
        return nullptr;
    }
    try {
        return new PRReverbDSP(rate, frames);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void pr_reverb_destroy(PRReverbDSP* dsp) {
    delete dsp;
}

extern "C" void pr_reverb_set_parameters(PRReverbDSP* dsp, PRReverbParameters parameters) {
    if (!dsp) return;
    parameters.mix = bound(parameters.mix, 0, 1, .35);
    parameters.enabled = !!parameters.enabled;
    parameters.decaySeconds = bound(parameters.decaySeconds, .3, 20, 2.2);
    parameters.size = bound(parameters.size, 0, 1, 1.f / 3);
    parameters.preDelayMs = bound(parameters.preDelayMs, 0, 100, 18);
    parameters.tone = bound(parameters.tone, 0, 1, .5);
    parameters.width = bound(parameters.width, 0, 1, 1);
    parameters.modulation = bound(parameters.modulation, 0, 1, .2);
    parameters.early = bound(parameters.early, 0, 2.5, 1.2);
    dsp->target = parameters;
    dsp->pendingRoom = 10 + 150 * parameters.size;
    dsp->pendingPre = parameters.preDelayMs;
}

extern "C" void pr_reverb_reset(PRReverbDSP* dsp) {
    if (dsp) dsp->reset();
}

extern "C" void pr_reverb_process(PRReverbDSP* dsp, const float* left, const float* right,
                                  float* outputLeft, float* outputRight, unsigned frames) {
    if (!dsp || !left || !right || !outputLeft || !outputRight || frames > dsp->maxFrames) return;

    // Small control blocks keep smoothing independent of the host buffer size.
    for (unsigned offset = 0; offset < frames;) {
        unsigned count = std::min(32u, frames - offset);
        bool update = !dsp->started;

        // Finish the current delay crossfade, then accept the most recent target.
        if (dsp->fade >= 1 && (dsp->room != dsp->pendingRoom || dsp->pre != dsp->pendingPre)) {
            dsp->oldRoom = dsp->room;
            dsp->oldPre = dsp->pre;
            dsp->room = dsp->pendingRoom;
            dsp->pre = dsp->pendingPre;
            dsp->fade = 0;
            update = true;
        }
        float smoothing = std::min(1., count / (dsp->rate * .03));
        auto ramp = [&](float& value, float target) {
            value += (target - value) * smoothing;
        };
        float oldMix = dsp->current.mix;
        ramp(dsp->current.mix, dsp->target.enabled ? dsp->target.mix : 0);
        ramp(dsp->current.decaySeconds, dsp->target.decaySeconds);
        ramp(dsp->current.tone, dsp->target.tone);
        ramp(dsp->current.width, dsp->target.width);
        ramp(dsp->current.modulation, dsp->target.modulation);
        ramp(dsp->current.early, dsp->target.early);
        dsp->setCore(!dsp->started);
        dsp->core.roomMs.value = dsp->oldRoom + (dsp->room - dsp->oldRoom)
            * std::min(1., dsp->fade + count / (dsp->rate * .1));

        // Stop admitting new notes while bypassed; existing reflections keep decaying.
        for (unsigned i = 0; i < count; ++i) {
            float gate = dsp->target.enabled ? 1 : 0;
            dsp->preL[dsp->write] = left[offset + i] * gate;
            dsp->preR[dsp->write] = right[offset + i] * gate;
            double fade = std::min(1., dsp->fade + i / (dsp->rate * .1));
            dsp->inputL[i] = dsp->delayed(dsp->preL, dsp->oldPre) * (1 - fade)
                + dsp->delayed(dsp->preL, dsp->pre) * fade;
            dsp->inputR[i] = dsp->delayed(dsp->preR, dsp->oldPre) * (1 - fade)
                + dsp->delayed(dsp->preR, dsp->pre) * fade;
            dsp->write = (dsp->write + 1) % dsp->preL.size();
        }
        float* input[2] = {dsp->inputL.data(), dsp->inputR.data()};
        float* output[2] = {dsp->scratchL.data(), dsp->scratchR.data()};
        Io io{input, output};
        Block block{int(count), dsp->fade, 1 / (dsp->rate * .1), update, dsp->room * .001 * dsp->rate};
        dsp->core.processSTFX(io, dsp->config, block);
        dsp->started = true;

        // Width only changes the wet stereo image; the dry signal remains untouched.
        for (unsigned i = 0; i < count; ++i) {
            float wet = oldMix + (dsp->current.mix - oldMix) * float(i + 1) / count;
            float mid = (output[0][i] + output[1][i]) * .5f;
            float side = (output[0][i] - output[1][i]) * .5f * dsp->current.width;
            outputLeft[offset + i] = left[offset + i] * (1 - wet) + (mid + side) * wet;
            outputRight[offset + i] = right[offset + i] * (1 - wet) + (mid - side) * wet;
        }
        dsp->fade = std::min(1., dsp->fade + count / (dsp->rate * .1));
        offset += count;
    }
}
