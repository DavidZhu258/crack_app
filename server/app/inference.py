from __future__ import annotations

import base64
import os
import re
import shlex
import subprocess
import tempfile
import time
from collections import deque
from pathlib import Path
from typing import Any


class InferenceError(RuntimeError):
    """Raised when a configured inference backend cannot produce a result."""


def run_inference(
    raw: bytes,
    *,
    threshold: float,
    max_windows: int,
    server_version: str,
    model_version: str,
) -> dict[str, Any]:
    backend = os.environ.get("CRACK_INFERENCE_BACKEND", "fallback").lower()
    if backend == "crackscan":
        return CrackscanInferenceRunner().infer(
            raw,
            threshold=threshold,
            server_version=server_version,
            model_version=model_version,
        )
    return fallback_inference(
        raw,
        threshold=threshold,
        max_windows=max_windows,
        server_version=server_version,
        model_version=model_version,
    )


def fallback_inference(
    raw: bytes,
    *,
    threshold: float,
    max_windows: int,
    server_version: str,
    model_version: str,
) -> dict[str, Any]:
    bytes_for_mask = raw or b"\x00"
    columns = max(1, min(8, len(bytes_for_mask)))
    rows: list[list[bool]] = []
    current: list[bool] = []
    cutoff = max(0, min(255, int(threshold * 255)))
    for value in bytes_for_mask[: max(1, min(len(bytes_for_mask), max_windows * 8))]:
        current.append(value > cutoff)
        if len(current) == columns:
            rows.append(current)
            current = []
    if current:
        current.extend([False] * (columns - len(current)))
        rows.append(current)

    crack_pixels = sum(1 for row in rows for pixel in row if pixel)
    total_pixels = sum(len(row) for row in rows) or 1
    crack_ratio = crack_pixels / total_pixels * 100
    return {
        "crackRatio": crack_ratio,
        "inferenceTime": 0,
        "detectionCount": max(1, crack_pixels),
        "resultImage": base64.b64encode(raw).decode("ascii"),
        "binaryMask": rows,
        "originalWidth": columns,
        "originalHeight": len(rows),
        "modelVersion": model_version,
        "serverVersion": server_version,
        "inferenceBackend": "fallback",
    }


class CrackscanInferenceRunner:
    def __init__(self) -> None:
        self.conda_sh = Path(
            os.environ.get(
                "CRACK_CONDA_SH",
                "/root/anaconda3/etc/profile.d/conda.sh",
            ),
        )
        self.conda_env = os.environ.get("CRACK_CRACKSCAN_ENV", "crackscan")
        self.test_dir = Path(
            os.environ.get("CRACK_CRACKSCAN_TEST_DIR", "/home/crack/app/test"),
        )
        self.model_path = os.environ.get(
            "CRACK_CRACKSCAN_MODEL_PATH",
            "checkpoints/weights/checkpoint_best.pth",
        )
        self.output_base_dir = Path(
            os.environ.get(
                "CRACK_CRACKSCAN_OUTPUT_BASE_DIR",
                "/home/crack/app/cloud_dev/crackscan_results",
            ),
        )
        self.input_dir = Path(
            os.environ.get(
                "CRACK_CRACKSCAN_INPUT_DIR",
                "/home/crack/app/cloud_dev/crackscan_inputs",
            ),
        )
        self.timeout_seconds = int(
            os.environ.get("CRACK_CRACKSCAN_TIMEOUT_SECONDS", "600"),
        )
        self.device = os.environ.get("CRACK_CRACKSCAN_DEVICE", "")
        self.enhance = os.environ.get("CRACK_CRACKSCAN_ENHANCE", "false").lower() in {
            "1",
            "true",
            "yes",
        }

    def infer(
        self,
        raw: bytes,
        *,
        threshold: float,
        server_version: str,
        model_version: str,
    ) -> dict[str, Any]:
        self._validate_runtime()
        self.output_base_dir.mkdir(parents=True, exist_ok=True)
        self.input_dir.mkdir(parents=True, exist_ok=True)
        started = time.perf_counter()
        with tempfile.TemporaryDirectory(
            prefix="crackscan_",
            dir=str(self.input_dir),
        ) as temp_dir:
            image_path = Path(temp_dir) / "input.jpg"
            image_path.write_bytes(raw)
            command = self._command(image_path, threshold=threshold)
            completed = subprocess.run(
                ["bash", "-lc", command],
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                check=False,
            )
        if completed.returncode != 0:
            raise InferenceError(
                "crackscan inference failed: "
                + (completed.stderr.strip() or completed.stdout.strip()),
            )

        output_dir = self._find_output_dir(completed.stdout)
        mask_path = _first_existing(
            output_dir,
            ["*_crack_clean.png", "*_crack_prediction.png"],
        )
        result_path = _first_existing(
            output_dir,
            [
                "*_visualization_all.jpg",
                "*_visualization_roi.jpg",
                "*_crack_prediction.png",
                "*_original.jpg",
            ],
        )
        if mask_path is None:
            raise InferenceError(f"crackscan mask output not found in {output_dir}")
        if result_path is None:
            raise InferenceError(f"crackscan result image not found in {output_dir}")

        mask = _read_binary_mask(mask_path)
        crack_pixels = sum(1 for row in mask for pixel in row if pixel)
        total_pixels = sum(len(row) for row in mask) or 1
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        return {
            "crackRatio": crack_pixels / total_pixels * 100,
            "inferenceTime": elapsed_ms,
            "detectionCount": _connected_components(mask),
            "resultImage": base64.b64encode(result_path.read_bytes()).decode("ascii"),
            "binaryMask": mask,
            "originalWidth": len(mask[0]) if mask else 0,
            "originalHeight": len(mask),
            "modelVersion": f"crackscan:{Path(self.model_path).name or model_version}",
            "serverVersion": server_version,
            "inferenceBackend": "crackscan",
            "outputDir": str(output_dir),
        }

    def _validate_runtime(self) -> None:
        if not self.conda_sh.exists():
            raise InferenceError(f"conda activation script not found: {self.conda_sh}")
        if not self.test_dir.exists():
            raise InferenceError(f"crackscan test dir not found: {self.test_dir}")
        predict_script = self.test_dir / "predict_with_ruler.py"
        if not predict_script.exists():
            raise InferenceError(f"predict script not found: {predict_script}")
        model_path = Path(self.model_path)
        model_candidate = model_path if model_path.is_absolute() else self.test_dir / model_path
        if not model_candidate.exists():
            raise InferenceError(f"crackscan model not found: {model_candidate}")

    def _command(self, image_path: Path, *, threshold: float) -> str:
        setup = [
            "set -e",
            f". {shlex.quote(str(self.conda_sh))}",
            f"conda activate {shlex.quote(self.conda_env)}",
            f"cd {shlex.quote(str(self.test_dir))}",
        ]
        args = [
            "python predict_with_ruler.py",
            f"--image_path {shlex.quote(str(image_path))}",
            f"--model_path {shlex.quote(self.model_path)}",
            f"--output_base_dir {shlex.quote(str(self.output_base_dir))}",
            f"--threshold {threshold}",
            "--calculate_rqd",
            "--detect_valid_region",
            "--pad_to_multiple",
        ]
        if self.device:
            args.append(f"--device {shlex.quote(self.device)}")
        if self.enhance:
            args.append("--enhance")
        return " && ".join([*setup, " ".join(args)])

    def _find_output_dir(self, stdout: str) -> Path:
        matches = re.findall(r"(?:所有结果已保存到|输出目录):\s*(.+)", stdout)
        for value in reversed(matches):
            candidate = Path(value.strip())
            if not candidate.is_absolute():
                candidate = self.test_dir / candidate
            if candidate.exists():
                return candidate
        directories = [item for item in self.output_base_dir.iterdir() if item.is_dir()]
        if directories:
            return max(directories, key=lambda item: item.stat().st_mtime)
        raise InferenceError("crackscan output directory not found")


def _first_existing(base_dir: Path, patterns: list[str]) -> Path | None:
    for pattern in patterns:
        matches = sorted(base_dir.glob(pattern))
        if matches:
            return matches[0]
    return None


def _read_binary_mask(path: Path) -> list[list[bool]]:
    try:
        from PIL import Image
    except ImportError as exc:
        raise InferenceError("Pillow is required to read crackscan masks") from exc
    with Image.open(path) as image:
        gray = image.convert("L")
        max_pixels = int(os.environ.get("CRACK_MAX_MASK_PIXELS", "0") or "0")
        if max_pixels > 0 and gray.width * gray.height > max_pixels:
            scale = (max_pixels / (gray.width * gray.height)) ** 0.5
            width = max(1, int(gray.width * scale))
            height = max(1, int(gray.height * scale))
            gray = gray.resize((width, height), Image.Resampling.NEAREST)
        rows: list[list[bool]] = []
        for y in range(gray.height):
            rows.append([gray.getpixel((x, y)) > 0 for x in range(gray.width)])
        return rows


def _connected_components(mask: list[list[bool]]) -> int:
    if not mask or not mask[0]:
        return 0
    height = len(mask)
    width = len(mask[0])
    visited = [[False for _ in range(width)] for _ in range(height)]
    count = 0
    for y in range(height):
        for x in range(width):
            if not mask[y][x] or visited[y][x]:
                continue
            count += 1
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[y][x] = True
            while queue:
                current_x, current_y = queue.popleft()
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if (
                        0 <= next_x < width
                        and 0 <= next_y < height
                        and mask[next_y][next_x]
                        and not visited[next_y][next_x]
                    ):
                        visited[next_y][next_x] = True
                        queue.append((next_x, next_y))
    return count
