#pragma once

#include <algorithm>
#include <array>
#include <vector>

// Piano Room support code, MIT. Written independently of STFX.
namespace piano_reverb {

struct Parameter {
    double previous = 0;
    double value = 0;

    Parameter(double v = 0) : previous(v), value(v) {}

    operator double() const { return value; }

    Parameter& operator=(double v) {
        previous = value;
        value = v;
        return *this;
    }

    double from() const { return previous; }
    double to() const { return value; }

    void snap(double v) {
        previous = value = v;
    }
};

struct Base {
    using Sample = float;
    using ParamRange = Parameter;
    using ParamStepped = int;
};

struct Config {
    double sampleRate;
    int inputChannels = 2;
    int outputChannels = 2;
    std::vector<int> auxInputs;
    std::vector<int> auxOutputs;

    explicit Config(double r) : sampleRate(r) {}
};

struct Block {
    int length;
    double position;
    double step;
    bool update;
    double roomTargetSamples;

    bool fading() const { return position < 1; }

    template<class Fn>
    void setupFade(Fn fn) {
        if (update) fn();
    }

    float fade(int i) const {
        return std::min(1., position + i * step);
    }

    struct Linear {
        double a;
        double b;
        int n;

        float at(int i) const {
            return a + (b - a) * (i + 1) / n;
        }
    };

    Linear smooth(double a, double b) const {
        return {a, b, length};
    }

    Linear smooth(Parameter& p) const {
        return smooth(p.from(), p.to());
    }

    template<class F>
    Linear smooth(Parameter& p, F f) const {
        return smooth(f(p.from()), f(p.to()));
    }
};

struct Io {
    float** input;
    float** output;
};

} // namespace piano_reverb
