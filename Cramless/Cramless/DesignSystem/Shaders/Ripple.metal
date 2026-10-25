// A ripple through a view's pixels: a ring travelling out from `origin`, its strength falling away over time.
// Used by `CLRipple` (DesignSystem/Components/Ripple.swift) for the moment an answer lands.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]]
half4 Ripple(float2 position, SwiftUI::Layer layer, float2 origin, float time, float amplitude, float frequency,
             float decay, float speed) {
    float distance = length(position - origin);
    // The ring reaches this pixel after distance / speed seconds.
    float delay = distance / speed;
    float t = max(0.0, time - delay);
    float wave = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 direction = distance > 0.0 ? normalize(position - origin) : float2(0.0);
    half4 color = layer.sample(position + wave * direction);
    // A touch of light on the crest.
    color.rgb += half(0.18 * (wave / max(amplitude, 0.001))) * color.a;
    return color;
}
