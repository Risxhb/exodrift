"""Build a Godot-ready ship PBR pack from a generated base-color source.

The output convention is:
  *_base_color.png  sRGB color
  *_normal.png      tangent-space OpenGL normal
  *_orm.png         R=AO, G=roughness, B=metallic
  *_emission.png    optional grayscale emission mask

This tool provides a reproducible baseline. Authored masks can be supplied for
final materials instead of deriving roughness variation from base color.
"""

from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def _unit_float(image: Image.Image) -> np.ndarray:
    return np.asarray(image, dtype=np.float32) / 255.0


def _load_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return _unit_float(image.convert("RGB"))


def _load_mask(path: Path | None, size: tuple[int, int], default: float) -> np.ndarray:
    if path is None:
        return np.full((size[1], size[0]), default, dtype=np.float32)
    with Image.open(path) as image:
        if image.size != size:
            raise ValueError(f"mask {path} is {image.size}, expected {size}")
        return _unit_float(image.convert("L"))


def _make_tileable(pixels: np.ndarray, band: int) -> np.ndarray:
    result = pixels.astype(np.float32, copy=True)
    height, width = result.shape[:2]
    band = max(0, min(band, width // 3, height // 3))
    if band == 0:
        return result
    for offset in range(band):
        weight = (1.0 - offset / band) ** 2
        average = (result[:, offset] + result[:, width - 1 - offset]) * 0.5
        result[:, offset] = result[:, offset] * (1.0 - weight) + average * weight
        result[:, width - 1 - offset] = result[:, width - 1 - offset] * (1.0 - weight) + average * weight
    for offset in range(band):
        weight = (1.0 - offset / band) ** 2
        average = (result[offset, :] + result[height - 1 - offset, :]) * 0.5
        result[offset, :] = result[offset, :] * (1.0 - weight) + average * weight
        result[height - 1 - offset, :] = result[height - 1 - offset, :] * (1.0 - weight) + average * weight
    return np.clip(result, 0.0, 1.0)


def _normal_map(base_color: np.ndarray, strength: float) -> np.ndarray:
    luma = base_color @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    blurred = _unit_float(
        Image.fromarray(np.uint8(np.clip(luma, 0.0, 1.0) * 255.0), mode="L").filter(
            ImageFilter.GaussianBlur(radius=2.0)
        )
    )
    height = np.clip(0.5 + (luma - blurred) * 1.8, 0.0, 1.0)
    gradient_x = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    gradient_y = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    normal = np.stack((-gradient_x, -gradient_y, np.ones_like(height)), axis=-1)
    normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)
    return normal * 0.5 + 0.5


def _seam_score(pixels: np.ndarray) -> float:
    horizontal = np.mean(np.abs(pixels[:, 0] - pixels[:, -1]))
    vertical = np.mean(np.abs(pixels[0, :] - pixels[-1, :]))
    return float(max(horizontal, vertical))


def build_pack(
    input_path: Path,
    output_dir: Path,
    name: str,
    roughness: float,
    metallic: float,
    normal_strength: float,
    seamless_blend: int,
    ao_mask_path: Path | None = None,
    roughness_mask_path: Path | None = None,
    metallic_mask_path: Path | None = None,
    emission_mask_path: Path | None = None,
) -> dict[str, str | float | int]:
    base_color = _make_tileable(_load_rgb(input_path), seamless_blend)
    height, width = base_color.shape[:2]
    size = (width, height)
    if width != height or width & (width - 1):
        raise ValueError(f"base color must be square and power-of-two, got {size}")

    normal = _normal_map(base_color, normal_strength)
    ao = _load_mask(ao_mask_path, size, 1.0)
    metallic_map = _load_mask(metallic_mask_path, size, metallic)
    if roughness_mask_path is not None:
        roughness_map = _load_mask(roughness_mask_path, size, roughness)
    else:
        luma = base_color @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
        local_average = _unit_float(
            Image.fromarray(np.uint8(luma * 255.0), mode="L").filter(ImageFilter.GaussianBlur(radius=3.0))
        )
        micro_variation = np.clip(np.abs(luma - local_average) * 1.2, 0.0, 0.18)
        roughness_map = np.clip(roughness + micro_variation, 0.02, 0.98)
    orm = np.stack((ao, roughness_map, metallic_map), axis=-1)

    output_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "base_color": output_dir / f"{name}_base_color.png",
        "normal": output_dir / f"{name}_normal.png",
        "orm": output_dir / f"{name}_orm.png",
    }
    Image.fromarray(np.uint8(base_color * 255.0), mode="RGB").save(paths["base_color"])
    Image.fromarray(np.uint8(normal * 255.0), mode="RGB").save(paths["normal"])
    Image.fromarray(np.uint8(orm * 255.0), mode="RGB").save(paths["orm"])
    if emission_mask_path is not None:
        emission = _load_mask(emission_mask_path, size, 0.0)
        paths["emission"] = output_dir / f"{name}_emission.png"
        Image.fromarray(np.uint8(emission * 255.0), mode="L").save(paths["emission"])

    metadata: dict[str, str | float | int] = {
        "source": str(input_path),
        "size": width,
        "roughness": roughness,
        "metallic": metallic,
        "normal_strength": normal_strength,
        "seamless_blend": seamless_blend,
        "seam_score": _seam_score(base_color),
        **{key: str(value) for key, value in paths.items()},
    }
    metadata_path = output_dir / f"{name}_material.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    metadata["metadata"] = str(metadata_path)
    return metadata


def _self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="exodrift-pbr-") as temp:
        root = Path(temp)
        y, x = np.mgrid[0:64, 0:64]
        source = np.zeros((64, 64, 3), dtype=np.uint8)
        source[..., 0] = 30 + ((x // 16 + y // 16) % 2) * 40
        source[..., 1] = 45 + ((x // 16 + y // 16) % 2) * 35
        source[..., 2] = 55 + ((x // 16 + y // 16) % 2) * 30
        source_path = root / "source.png"
        Image.fromarray(source, mode="RGB").save(source_path)
        metadata = build_pack(source_path, root / "output", "self_test", 0.42, 0.75, 2.0, 8)
        for key in ("base_color", "normal", "orm", "metadata"):
            if not Path(str(metadata[key])).exists():
                raise RuntimeError(f"self-test did not create {key}")
        with Image.open(str(metadata["orm"])) as orm:
            if orm.mode != "RGB" or orm.size != (64, 64):
                raise RuntimeError("self-test ORM output is invalid")
    print("PASS: ship PBR map builder")


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="Generated or authored square base-color source")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--name", default="ship_hull")
    parser.add_argument("--roughness", type=float, default=0.42)
    parser.add_argument("--metallic", type=float, default=0.72)
    parser.add_argument("--normal-strength", type=float, default=2.0)
    parser.add_argument("--seamless-blend", type=int, default=48)
    parser.add_argument("--ao-mask", type=Path)
    parser.add_argument("--roughness-mask", type=Path)
    parser.add_argument("--metallic-mask", type=Path)
    parser.add_argument("--emission-mask", type=Path)
    parser.add_argument("--self-test", action="store_true")
    return parser


def main() -> None:
    args = _parser().parse_args()
    if args.self_test:
        _self_test()
        return
    if args.input is None or args.output_dir is None:
        raise SystemExit("--input and --output-dir are required unless --self-test is used")
    metadata = build_pack(
        args.input,
        args.output_dir,
        args.name,
        float(np.clip(args.roughness, 0.0, 1.0)),
        float(np.clip(args.metallic, 0.0, 1.0)),
        max(0.0, args.normal_strength),
        max(0, args.seamless_blend),
        args.ao_mask,
        args.roughness_mask,
        args.metallic_mask,
        args.emission_mask,
    )
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
