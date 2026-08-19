# Production visual asset provenance

## AOVOPRO ES80 side profile

- App asset: `NembraApp/Resources/Assets.xcassets/ES80Side.imageset/es80-side.png`
- SHA-256: `95111ad1482d157780458f5d1016aeed74b7c7b49a295a764221f28a717c47d3`
- Raster: 500×500 RGBA; asset catalog currently assigns it as the universal `2x` rendition only.
- Subject: AOVOPRO ES80 side-profile product image with its background removed.
- Product reference: https://www.aovopro.com/product/aovopro-es80-electric-scooter-350w-10-5-ah-long-range-high-speed-foldable-electric-scooter/
- Introduced in repository commit: `f7c6269270661a2c791aa1c65722e1e894dfa6e9`.
- Current status: **temporary presentation asset; not production-cleared for final 1.0 artwork**.

Known provenance gaps:

- the exact original image URL and original-file hash are not retained;
- retrieval date, background-removal/masking steps, region/unit variant, author,
  license, and written reproduction permission are not retained;
- the 500-pixel source is upscaled when displayed as an approximately 304–320pt
  hero on an iPhone 12 @3x screen and is visibly too soft for final use;
- the official source plausibly supports the black/red pictured configuration,
  but does not authorize recoloring physical details gold.

Production replacement requirement:

- obtain a user-owned/commissioned high-resolution side photograph of the actual
  ES80 configuration, or written AOVOPRO media/license permission for a specific
  high-resolution source;
- retain original URL/source, retrieval date, author/license/permission,
  original hash, deterministic masking/grading steps, transformed hash, and
  exported 2x/3x dimensions;
- preserve truthful ES80 geometry and physically required regional/unit details;
  warm gold may be scene lighting, not invented hardware;
- do not AI-upscale or generate a replacement that invents material detail.

Until that proof exists, the current asset may be used only as a clearly
temporary functional-layout silhouette with restrained grading. It cannot close
the Home 1.0 visual-acceptance gate.

This is a presentation asset, not hardware identity or protocol evidence. It may
be shown only for an explicitly selected ES80 vehicle profile; it must not be
used to classify an unknown connected accessory as an ES80.
