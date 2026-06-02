# Model Assets

This directory is intentionally kept without proprietary pretrained weights.

The mobile offline inference path expects an ONNX model named:

```text
assets/models/savss_256.onnx
```

For public/open-source releases, the pretrained model is not included. To run
offline inference, place your own compatible ONNX model at that path and rebuild
the app.

The server inference workflow can be used without adding a local model, as long
as the app is configured with a reachable API endpoint.
