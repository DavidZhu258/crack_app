from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from PIL import Image

from server.app.inference import CrackscanInferenceRunner


def test_crackscan_runner_invokes_predict_script_and_reads_safe_outputs(
    tmp_path,
    monkeypatch,
):
    conda_sh = tmp_path / "conda.sh"
    test_dir = tmp_path / "test_runtime"
    output_base = tmp_path / "cloud_results"
    input_base = tmp_path / "cloud_inputs"
    output_dir = output_base / "2026-05-07_input"
    test_dir.mkdir()
    (test_dir / "checkpoints" / "weights").mkdir(parents=True)
    output_dir.mkdir(parents=True)
    conda_sh.write_text("# conda", encoding="utf-8")
    (test_dir / "predict_with_ruler.py").write_text("# script", encoding="utf-8")
    (test_dir / "checkpoints" / "weights" / "checkpoint_best.pth").write_bytes(b"model")

    mask = Image.new("L", (3, 2), 0)
    mask.putpixel((0, 0), 255)
    mask.putpixel((1, 0), 255)
    mask.putpixel((2, 1), 255)
    mask.save(output_dir / "input_crack_clean.png")
    Image.new("RGB", (3, 2), (10, 20, 30)).save(
        output_dir / "input_visualization_all.jpg",
    )

    commands: list[str] = []

    def fake_run(args, **kwargs):
        commands.append(args[-1])
        assert kwargs["capture_output"] is True
        assert kwargs["check"] is False
        return SimpleNamespace(
            returncode=0,
            stdout=f"所有结果已保存到: {output_dir}\n",
            stderr="",
        )

    monkeypatch.setattr("server.app.inference.subprocess.run", fake_run)
    monkeypatch.setenv("CRACK_CONDA_SH", str(conda_sh))
    monkeypatch.setenv("CRACK_CRACKSCAN_TEST_DIR", str(test_dir))
    monkeypatch.setenv("CRACK_CRACKSCAN_OUTPUT_BASE_DIR", str(output_base))
    monkeypatch.setenv("CRACK_CRACKSCAN_INPUT_DIR", str(input_base))
    monkeypatch.setenv("CRACK_CRACKSCAN_MODEL_PATH", "checkpoints/weights/checkpoint_best.pth")
    monkeypatch.setenv("CRACK_CRACKSCAN_DEVICE", "cpu")

    result = CrackscanInferenceRunner().infer(
        b"image-bytes",
        threshold=0.4,
        server_version="server-test",
        model_version="fallback-model",
    )

    assert result["inferenceBackend"] == "crackscan"
    assert result["binaryMask"] == [[True, True, False], [False, False, True]]
    assert result["crackRatio"] == 50
    assert result["detectionCount"] == 2
    assert result["originalWidth"] == 3
    assert result["originalHeight"] == 2
    assert result["resultImage"]
    assert result["outputDir"] == str(output_dir)
    assert commands
    assert "conda activate crackscan" in commands[0]
    assert "--output_base_dir" in commands[0]
    assert str(output_base) in commands[0]
    assert str(Path("/home/crack/app/test/data/two-step-result")) not in commands[0]
