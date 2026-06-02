from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from PIL import Image


MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def prepare_image_windows(
    image_path: str | Path,
    *,
    input_size: int = 256,
    max_windows: int = 20,
    overlap: float = 0.25,
) -> list[np.ndarray]:
    image = Image.open(image_path).convert("RGB")
    resized = _resize_like_app(image, input_size=input_size, max_windows=max_windows, overlap=overlap)
    padded = _reflect_pad_like_app(resized, input_size=input_size, overlap=overlap)
    stride = _stride(input_size, overlap)
    height, width = padded.shape[:2]
    n_h = max(1, (height - input_size) // stride + 1)
    n_w = max(1, (width - input_size) // stride + 1)

    windows: list[np.ndarray] = []
    for i in range(n_h):
        for j in range(n_w):
            y = min(i * stride, height - input_size)
            x = min(j * stride, width - input_size)
            window = padded[y : y + input_size, x : x + input_size]
            windows.append(_normalize_chw(window))
            if len(windows) >= max_windows:
                return windows
    return windows


def write_calibration_windows(
    image_paths: Iterable[str | Path],
    output_dir: str | Path,
    *,
    input_size: int = 256,
    max_windows_per_image: int = 20,
    max_total_windows: int | None = None,
    overlap: float = 0.25,
) -> list[Path]:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for image_index, image_path in enumerate(image_paths):
        windows = prepare_image_windows(
            image_path,
            input_size=input_size,
            max_windows=max_windows_per_image,
            overlap=overlap,
        )
        stem = Path(image_path).stem
        for window_index, window in enumerate(windows):
            if max_total_windows is not None and len(written) >= max_total_windows:
                return written
            target = output_dir / f"{image_index:04d}_{stem}_{window_index:03d}.npy"
            np.save(target, window)
            written.append(target)
    return written


def _resize_like_app(
    image: Image.Image,
    *,
    input_size: int,
    max_windows: int,
    overlap: float,
) -> Image.Image:
    width, height = image.size
    stride = _stride(input_size, overlap)
    windows_per_side = int(math.sqrt(max_windows))
    target_side = (windows_per_side - 1) * stride + input_size
    max_original = max(height, width)
    scale = min(1.0, target_side / max_original)
    new_height = max(input_size, int(height * scale))
    new_width = max(input_size, int(width * scale))
    if scale < 1.0 or new_width != width or new_height != height:
        return image.resize((new_width, new_height), Image.Resampling.BILINEAR)
    return image


def _reflect_pad_like_app(
    image: Image.Image,
    *,
    input_size: int,
    overlap: float,
) -> np.ndarray:
    array = np.asarray(image, dtype=np.uint8)
    height, width = array.shape[:2]
    stride = _stride(input_size, overlap)
    pad_h = (
        (stride - (height - input_size) % stride) % stride
        if height > input_size
        else input_size - height
    )
    pad_w = (
        (stride - (width - input_size) % stride) % stride
        if width > input_size
        else input_size - width
    )
    if pad_h == 0 and pad_w == 0:
        return array
    return np.pad(
        array,
        ((0, pad_h), (0, pad_w), (0, 0)),
        mode="reflect",
    )


def _normalize_chw(window: np.ndarray) -> np.ndarray:
    normalized = (window.astype(np.float32) / 255.0 - MEAN) / STD
    return np.transpose(normalized, (2, 0, 1))[np.newaxis, ...].astype(np.float32)


def _stride(input_size: int, overlap: float) -> int:
    return max(1, int(input_size * (1.0 - overlap)))


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare App-style NCHW .npy windows for Ascend INT8 calibration.",
    )
    parser.add_argument("--image-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--input-size", type=int, default=256)
    parser.add_argument("--max-windows-per-image", type=int, default=20)
    parser.add_argument("--max-total-windows", type=int, default=None)
    parser.add_argument("--overlap", type=float, default=0.25)
    parser.add_argument(
        "--glob",
        action="append",
        default=None,
        help="Image glob relative to image-dir. Defaults to *.jpg, *.jpeg, *.png.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> None:
    args = _parse_args(argv)
    image_dir = Path(args.image_dir)
    globs = args.glob or ["*.jpg", "*.jpeg", "*.png"]
    image_paths: list[Path] = []
    for pattern in globs:
        image_paths.extend(sorted(image_dir.glob(pattern)))
    written = write_calibration_windows(
        image_paths,
        args.output_dir,
        input_size=args.input_size,
        max_windows_per_image=args.max_windows_per_image,
        max_total_windows=args.max_total_windows,
        overlap=args.overlap,
    )
    print(f"wrote {len(written)} calibration windows to {Path(args.output_dir)}")


if __name__ == "__main__":
    main()
