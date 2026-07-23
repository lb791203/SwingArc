import io
import json
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import Dataset
from torchvision.transforms import functional as transforms

from model import LANDMARK_NAMES


MANIFEST_LANDMARK_NAMES = {
    "grip": ("grip",),
    "shaft_start": ("shaftStart", "shaft_start"),
    "shaft_end": ("shaftEnd", "shaft_end"),
    "clubhead": ("clubhead",),
    "ball": ("ball",),
}
ALLOWED_VISIBILITY = {"visible", "occluded", "out-of-frame"}


class ReviewedTrainingLabelsRequired(ValueError):
    pass


@dataclass(frozen=True)
class GolfFrameSample:
    clip_id: str
    video_path: Path
    source_frame_index: int
    source_frame_rate: float
    coordinates: torch.Tensor
    visibility: torch.Tensor


class GolfKeypointDataset(Dataset):
    def __init__(
        self,
        manifest_path,
        video_root,
        split,
        image_loader=None,
    ):
        self.manifest_path = Path(manifest_path)
        self.video_root = Path(video_root)
        self.split = split
        self.image_loader = image_loader or self._load_video_frame
        self.samples = self._read_samples()
        if not self.samples:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required for split '{split}'"
            )

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        sample = self.samples[index]
        image = self.image_loader(sample).convert("RGB")
        image, coordinates = self._aspect_fit(image, sample.coordinates)
        image_tensor = transforms.to_tensor(image)
        return image_tensor, coordinates, sample.visibility.clone()

    @staticmethod
    def _aspect_fit(image, coordinates, target_size=256):
        scale = min(target_size / image.width, target_size / image.height)
        content_width = max(1, round(image.width * scale))
        content_height = max(1, round(image.height * scale))
        offset_x = (target_size - content_width) // 2
        offset_y = (target_size - content_height) // 2
        resized = transforms.resize(
            image,
            [content_height, content_width],
            antialias=True,
        )
        canvas = Image.new("RGB", (target_size, target_size), "black")
        canvas.paste(resized, (offset_x, offset_y))
        transformed = coordinates.clone()
        transformed[:, 0] = (
            coordinates[:, 0] * content_width + offset_x
        ) / target_size
        transformed[:, 1] = (
            coordinates[:, 1] * content_height + offset_y
        ) / target_size
        return canvas, transformed

    def _read_samples(self):
        if not self.manifest_path.is_file():
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: manifest not found at {self.manifest_path}"
            )
        try:
            clips = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: invalid manifest: {error}"
            ) from error
        if not isinstance(clips, list):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: manifest root must be a list"
            )

        samples = []
        for clip in clips:
            if clip.get("split") != self.split:
                continue
            if clip.get("authorization") != "training-allowed":
                continue
            clip_id = str(clip.get("clipID", "")).strip()
            file_name = str(clip.get("fileName", "")).strip()
            frame_rate = float(clip.get("sourceFrameRate", 0))
            if not clip_id or not file_name or not math.isfinite(frame_rate) or frame_rate <= 0:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: clip metadata is incomplete"
                )
            for frame in clip.get("frameLabels", []):
                if not frame.get("reviewed") or not str(frame.get("reviewer", "")).strip():
                    raise ReviewedTrainingLabelsRequired(
                        "reviewed training labels required: "
                        f"{clip_id} frame {frame.get('sourceFrameIndex')} is unreviewed"
                    )
                coordinates, visibility = self._decode_landmarks(
                    clip_id,
                    frame.get("sourceFrameIndex"),
                    frame.get("landmarks", {}),
                )
                samples.append(GolfFrameSample(
                    clip_id=clip_id,
                    video_path=self.video_root / file_name,
                    source_frame_index=int(frame["sourceFrameIndex"]),
                    source_frame_rate=frame_rate,
                    coordinates=coordinates,
                    visibility=visibility,
                ))
        return samples

    @staticmethod
    def _decode_landmarks(clip_id, source_frame_index, landmarks):
        coordinates = []
        visibility = []
        for model_name in LANDMARK_NAMES:
            aliases = MANIFEST_LANDMARK_NAMES[model_name]
            label = next((landmarks[name] for name in aliases if name in landmarks), None)
            if label is None:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} is missing {aliases[0]}"
                )
            x = float(label.get("x", math.nan))
            y = float(label.get("y", math.nan))
            if not math.isfinite(x) or not math.isfinite(y) or not (0 <= x <= 1 and 0 <= y <= 1):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} has invalid {aliases[0]} coordinates"
                )
            coordinates.append([x, y])
            label_visibility = label.get("visibility")
            if label_visibility not in ALLOWED_VISIBILITY:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} has invalid "
                    f"{aliases[0]} visibility"
                )
            visibility.append(1.0 if label_visibility == "visible" else 0.0)
        return (
            torch.tensor(coordinates, dtype=torch.float32),
            torch.tensor(visibility, dtype=torch.float32),
        )

    @staticmethod
    def _load_video_frame(sample):
        if not sample.video_path.is_file():
            raise FileNotFoundError(f"video not found: {sample.video_path}")
        seconds = sample.source_frame_index / sample.source_frame_rate
        command = [
            "ffmpeg", "-v", "error", "-ss", f"{seconds:.9f}",
            "-i", str(sample.video_path), "-frames:v", "1",
            "-f", "image2pipe", "-vcodec", "png", "pipe:1",
        ]
        try:
            completed = subprocess.run(command, check=True, capture_output=True)
        except FileNotFoundError as error:
            raise RuntimeError("ffmpeg is required to extract labelled video frames") from error
        except subprocess.CalledProcessError as error:
            detail = error.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(
                f"failed to extract {sample.clip_id} frame {sample.source_frame_index}: {detail}"
            ) from error
        return Image.open(io.BytesIO(completed.stdout)).convert("RGB")
