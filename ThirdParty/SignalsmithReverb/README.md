# Piano Room Signalsmith adaptation

The reverb algorithm is adapted from Signalsmith Basics `reverb.h` at
`369e906e03760ec219d07b06fa06dc4fd099f377` (MIT).
DSP helpers are vendored from Signalsmith DSP v1.7.1,
`2d20161915e733f117545c6be8cd3275a739a1e3` (MIT).

Piano Room changes: independent C++ support in place of STFX; C ABI;
parameter validation; parameter smoothing; queued delay crossfades;
wet-only predelay and stereo width; complete reset including delay4;
initialized old/new delay offsets. Processing owns all mutable DSP state.
Memory allocation happens during creation, never in the render call.

`Support.h` is original Piano Room code. No STFX wrapper is included.
Original author notices and MIT licenses are retained.
