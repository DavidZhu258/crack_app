from __future__ import annotations

import numpy as np
from PIL import Image

from server.scripts.prepare_ascend_calibration import (
    prepare_image_windows,
    write_calibration_windows,
)


def test_prepare_image_windows_uses_chw_imagenet_normalization(tmp_path) -> None:
    image_path = tmp_path / "sample.png"
    Image.new("RGB", (2, 2), (255, 128, 0)).save(image_path)

    windows = prepare_image_windows(
        image_path,
        input_size=2,
        max_windows=1,
        overlap=0.25,
    )

    assert len(windows) == 1
    window = windows[0]
    assert window.shape == (1, 3, 2, 2)
    np.testing.assert_allclose(
        window[0, 0],
        np.full((2, 2), (1.0 - 0.485) / 0.229, dtype=np.float32),
        atol=1e-6,
    )
    np.testing.assert_allclose(
        window[0, 1],
        np.full((2, 2), ((128 / 255.0) - 0.456) / 0.224, dtype=np.float32),
        atol=1e-6,
    )
    np.testing.assert_allclose(
        window[0, 2],
        np.full((2, 2), (0.0 - 0.406) / 0.225, dtype=np.float32),
        atol=1e-6,
    )


def test_write_calibration_windows_limits_total_windows(tmp_path) -> None:
    first = tmp_path / "first.png"
    second = tmp_path / "second.png"
    output_dir = tmp_path / "calibration"
    Image.new("RGB", (4, 4), (10, 20, 30)).save(first)
    Image.new("RGB", (4, 4), (40, 50, 60)).save(second)

    written = write_calibration_windows(
        [first, second],
        output_dir,
        input_size=2,
        max_windows_per_image=4,
        max_total_windows=3,
    )

    assert len(written) == 3
    assert [path.suffix for path in written] == [".npy", ".npy", ".npy"]
    assert all(path.exists() for path in written)
    assert np.load(written[0]).shape == (1, 3, 2, 2)
