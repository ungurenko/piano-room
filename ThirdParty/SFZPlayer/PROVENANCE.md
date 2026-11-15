Upstream: https://github.com/stevefolta/sfzq
Pinned commit: 1d99193bd0e5fbbf37b4b3d6ba56232f95ec48e0
License: MIT, see LICENSE.

Only the WAV reader and packed PCM buffer utilities and their direct dependencies are retained. PianoDSP contains Piano Room's own bounded sampler, strict normalized-SFZ parser, cubic interpolation, controller conditions and dynamic release envelopes. Upstream WAVReader changes validate channel count, initialize truncated reads, handle RIFF padding and reject negative chunk sizes.
