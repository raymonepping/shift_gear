# Article screenshots

These images were captured from the running Shift Gear console with Playwright and browser TLS verification enabled. The Ada lab persona was used. Images are direct browser captures, without mocked responses, redaction overlays or image retouching.

Desktop views use a 1440-pixel viewport. Phone views use a 390-pixel viewport at CSS scale. The ownership detail is an actual Terraform-filtered section; the audit detail is a request-filtered viewport excerpt. The complete pages remain available beside those excerpts.

The article uses linked images so each figure opens its full capture. The original two figures under `docs/screenshots/ui/` remain separate, explicitly earlier captures. Current screenshots do not replace historical rebuild timings or acceptance receipts.

`captures.json` records routes, capture timestamps, viewport or filter context, dimensions, SHA-256 hashes, source digest and the last convergence identity. It contains no browser session state or credentials.

Capture checks: both main viewport journeys and the ownership/audit detail journeys passed; every captured page showed `Seal chain 3/3`. The main journeys also checked document containment, the ownership provenance, an empty plan in Layers and the selected OpenTelemetry metric view.
