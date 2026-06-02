# Ascend INT8 Conversion Notes

## Source Of Truth

Use the App model as the only source model:

```text
assets/models/savss_256.onnx
```

The App loads this same model from `CrackDetectionService` with input
`input: [1,3,256,256]` and output `output: [1,1,512,512]`. Do not substitute
the server `crackscan` PyTorch checkpoint for this device conversion path.

## Current Status

As of 2026-05-13, the Orange Pi AI Pro has both:

```text
/opt/crack_app/models/savss_256_fp16.om
/opt/crack_app/models/savss_256_int8.om
```

The INT8 model is runnable and faster in a smoke check, but it is not yet an
accuracy acceptance pass. On 20 finite validation windows, INT8 versus App ONNX
had `meanAbs=0.5268400311470032`, `maxAbs=9.95321273803711`, and
`worstMaskIouLogitGt0=0.6266944229279628`. Keep FP16 as the conservative board
deployment model until larger calibration/validation and NaN-window behavior
are resolved.

The original App ONNX has 13 `Resize` nodes with
`coordinate_transformation_mode=half_pixel`. The Orange Pi AI Pro `atc`
conversion previously failed on this attribute before FP16/INT8 conversion
could start. The `pytorch_half_pixel` rewrite is the successful ATC path.

The local rewrite tool is:

```powershell
python server\scripts\ascend_onnx_rewrite.py --input assets\models\savss_256.onnx --inspect-only
```

It generated two candidates:

```text
artifacts/ascend/savss_256_resize_pytorch_half_pixel.onnx
artifacts/ascend/savss_256_resize_asymmetric.onnx
```

Use `savss_256_resize_pytorch_half_pixel.onnx` first. Local ONNX Runtime
comparison against the original App ONNX on one deterministic random input
returned `maxAbsDiff=0.0` and `meanAbsDiff=0.0`.

Use `savss_256_resize_asymmetric.onnx` only if the board-side CANN/ATC version
still rejects `pytorch_half_pixel`. That fallback loaded locally, but changed
model output on the same random input with `maxAbsDiff=3.01016902923584` and
`meanAbsDiff=0.40618082880973816`, so mask-level acceptance must be rechecked.

## Rebuild Candidates

Install the conversion-only Python dependencies:

```powershell
python -m pip install -r server\requirements-ascend.txt
```

Build the parity-first candidate:

```powershell
python server\scripts\ascend_onnx_rewrite.py `
  --input assets\models\savss_256.onnx `
  --output artifacts\ascend\savss_256_resize_pytorch_half_pixel.onnx `
  --target-mode pytorch_half_pixel `
  --fail-if-no-changes
```

Build the ATC fallback candidate:

```powershell
python server\scripts\ascend_onnx_rewrite.py `
  --input assets\models\savss_256.onnx `
  --output artifacts\ascend\savss_256_resize_asymmetric.onnx `
  --target-mode asymmetric `
  --fail-if-no-changes
```

## FP16 OM Gate

INT8 should not be attempted until an FP16 or FP32 `.om` compiles and matches
the App ONNX output closely enough.

On the Orange Pi AI Pro, after copying the candidate ONNX to
`/opt/crack_app/models/`, run:

```bash
source /usr/local/Ascend/ascend-toolkit/set_env.sh
atc \
  --model=/opt/crack_app/models/savss_256_resize_pytorch_half_pixel.onnx \
  --framework=5 \
  --output=/opt/crack_app/models/savss_256_fp16 \
  --input_format=NCHW \
  --input_shape="input:1,3,256,256" \
  --soc_version=Ascend310B4 \
  --precision_mode=allow_fp32_to_fp16
```

Huawei's CANN quick-start documents the ONNX-to-OM shape of this command with
`--framework=5`, `--input_shape`, and `--soc_version`; the `soc_version` value
comes from `npu-smi info` with the `Ascend` prefix added.

If ATC reports another unsupported operator after Resize is fixed, inspect the
next failing op before changing the model again. This graph also contains ops
such as `GridSample` and `Einsum`, so Resize may not be the only CANN blocker.

## Calibration Windows For INT8

The model input is a normalized 256x256 App window. Generate representative
calibration inputs from real mine images with:

```powershell
python server\scripts\prepare_ascend_calibration.py `
  --image-dir path\to\real_mine_images `
  --output-dir artifacts\ascend\calibration_windows `
  --max-windows-per-image 20 `
  --max-total-windows 200
```

The helper writes `.npy` arrays shaped `[1,3,256,256]`, `float32`, using the
same CHW ImageNet normalization used by the App.

For this workspace, calibration windows were generated from `assets/images/test`.
The expanded 33-window set exposed a model issue: 13 App ONNX outputs contained
NaN values, and AMCT IFMR calibration fails on those tensors. The successful
INT8 build used the 20 finite-output windows recorded under:

```text
artifacts/ascend/calibration_bins_int8_finite/
```

This is still only a tooling/diagnostic set. Use a larger and more
representative crack-image set for final INT8 calibration, and deliberately
decide how to handle NaN-producing windows.

## AMCT Workaround Used

Official Huawei AMCT download access remained blocked by Uniportal permission.
The user-provided GitHub raw tarball URL returned 404, and the repository's AMCT
package folder contained only `.gitkeep`. The working workaround was:

```text
registry.cn-hangzhou.aliyuncs.com/hexchip/ascend-dev:arm64-cann8.0.0-310b-pytorch2.1.0-mindie1.0.0
```

That image contains installed `amct_onnx-0.19.3`. The extracted local package is:

```text
artifacts/ascend/amct_onnx_0.19.3_from_hexchip_cann800_arm64.tar.gz
```

On the board it was installed under `/opt/crack_app/amct_pydeps`, with AMCT
library paths added for calibration:

```bash
export PYTHONPATH=/opt/crack_app/amct_pydeps:${PYTHONPATH:-}
export LD_LIBRARY_PATH=/opt/crack_app/amct_pydeps/amct_onnx/lib:/opt/crack_app/amct_pydeps/amct_onnx/custom_op:${LD_LIBRARY_PATH:-}
```

## INT8 Order

1. Convert the parity-first ONNX to FP16 `.om`.
2. Run OM inference and compare against App ONNX Runtime output on fixed
   calibration/test windows and on mask-level image diagnostics.
3. Use AMCT ONNX post-training quantization with the calibration windows.
   Huawei's AMCT ONNX uniform quantization guide describes calibrating by
   running forward passes on a representative dataset, saving quantization
   factors, and saving a deployable quantized model.
4. Convert the AMCT deployable model with ATC using the same input shape and
   `--soc_version=Ascend310B4`.
5. Compare INT8 `.om` against the App ONNX and the FP16 `.om`. Accept only if
   crack mask IoU, crack ratio, and visual overlays stay within the product
   tolerance.

The 2026-05-13 run completed steps 1-5 mechanically. Step 5 is a runtime pass
but not yet an accuracy pass for INT8.

## References

- Huawei CANN ONNX to OM quick start:
  <https://www.hiascend.com/document/detail/zh/CANNCommunityEdition/82RC1alpha001/quickstart/quickstart_18_0010.html>
- Huawei ATC command options:
  <https://www.hiascend.com/document/detail/en/canncommercial/800/devaids/atc/atlasatc_16_0039.html>
- Huawei AMCT ONNX uniform quantization:
  <https://www.hiascend.com/document/detail/en/canncommercial/800/devaids/amct/atlasamct_16_0143.html>
