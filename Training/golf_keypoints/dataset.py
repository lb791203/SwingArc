import hashlib
import io
import json
import math
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import Dataset
from torchvision.transforms import functional as transforms

from contracts import (
    HEATMAP_SIZE,
    IGNORE_VISIBILITY,
    INPUT_SIZE,
    INPUT_TRANSFORM_VERSION,
    LANDMARK_NAMES,
    MANIFEST_NAMES,
    VISIBILITY_INDEX,
    ReviewedTrainingLabelsRequired,
    aspect_fit_transform,
    canvas_to_source,
    input_transform_sha256,
    require_finite_number,
    source_to_canvas,
)
from heatmaps import gaussian_heatmap


SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
ALLOWED_SPLITS = {"training", "validation", "held-out"}
EXPECTED_STAGES = tuple(f"P{number}" for number in range(1, 9))
ROI_FIELDS = (
    "a", "b", "c", "d", "tx", "ty",
    "invA", "invB", "invC", "invD", "invTx", "invTy",
)
TRANSFORM_FLOAT_FIELDS = ("scaleX", "scaleY", "translateX", "translateY")


@dataclass(frozen=True)
class GolfFrameSample:
    clip_id: str
    golfer_id: str
    video_path: Path
    media_sha256: str
    source_frame_index: int
    source_time: float
    oriented_width: int
    oriented_height: int
    view: str
    handedness: str
    stage_codes: tuple[str, ...]
    queue_reasons: tuple[str, ...]
    annotation_roi_transform: dict[str, float]
    training_input_transform: dict
    landmarks: dict[str, dict]


class GolfHeatmapDataset(Dataset):
    def __init__(
        self,
        export_path,
        video_root,
        split,
        expected_manifest_sha256,
        image_loader=None,
    ):
        self.manifest_path = self._resolve_manifest_path(export_path)
        self.video_root = Path(video_root)
        self.split = str(split)
        if self.split not in ALLOWED_SPLITS:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: invalid split {self.split!r}"
            )
        self.expected_manifest_sha256 = self._require_sha256(
            expected_manifest_sha256,
            "expected manifest SHA-256",
        )
        self._verified_media = set()
        self.image_loader = image_loader or self._load_video_frame
        manifest_data = self._read_bytes(self.manifest_path, "manifest")
        self.manifest_sha256 = self._verify_manifest_hash(manifest_data)
        manifest = self._decode_json(manifest_data, "manifest")
        self.samples = self._read_samples(manifest)
        if not self.samples:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required for split '{self.split}'"
            )

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, item_index):
        sample = self.samples[item_index]
        image = self.image_loader(sample).convert("RGB")
        if image.size != (sample.oriented_width, sample.oriented_height):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                f"{sample.clip_id} decoded size {image.size} does not match "
                f"oriented media identity "
                f"{(sample.oriented_width, sample.oriented_height)}"
            )
        image = self._render_full_frame(image, sample.training_input_transform)
        image_tensor = transforms.to_tensor(image)

        heatmaps = torch.zeros(
            len(LANDMARK_NAMES),
            HEATMAP_SIZE,
            HEATMAP_SIZE,
            dtype=torch.float32,
        )
        visibility_targets = torch.full(
            (len(LANDMARK_NAMES),),
            IGNORE_VISIBILITY,
            dtype=torch.long,
        )
        coordinate_mask = torch.zeros(len(LANDMARK_NAMES), dtype=torch.bool)
        canvas_points = {}
        round_trip_errors = {}
        for landmark_index, model_name in enumerate(LANDMARK_NAMES):
            export_name = MANIFEST_NAMES[model_name]
            label = sample.landmarks.get(export_name)
            if label is None:
                continue
            visibility = label["visibility"]
            visibility_targets[landmark_index] = VISIBILITY_INDEX[visibility]
            if visibility != "visible":
                continue
            point = label["point"]
            canvas_x, canvas_y = source_to_canvas(
                point["x"],
                point["y"],
                sample.training_input_transform,
            )
            source_x, source_y = canvas_to_source(
                canvas_x,
                canvas_y,
                sample.training_input_transform,
            )
            error = (
                abs(source_x - point["x"]),
                abs(source_y - point["y"]),
            )
            if max(error) > 1e-9:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    "full-frame input transform round trip exceeded 1e-9"
                )
            heatmaps[landmark_index] = gaussian_heatmap(canvas_x, canvas_y)
            coordinate_mask[landmark_index] = True
            canvas_points[export_name] = {"x": canvas_x, "y": canvas_y}
            round_trip_errors[export_name] = {"x": error[0], "y": error[1]}

        transform = sample.training_input_transform
        metadata = {
            "clip_id": sample.clip_id,
            "golfer_id": sample.golfer_id,
            "view": sample.view,
            "handedness": sample.handedness,
            "source_frame_index": sample.source_frame_index,
            "source_time": sample.source_time,
            "stage_codes": list(sample.stage_codes),
            "queue_reasons": list(sample.queue_reasons),
            "manifest_sha256": self.manifest_sha256,
            "input_transform_version": transform["version"],
            "content_rect": {
                "width": transform["contentWidth"],
                "height": transform["contentHeight"],
                "offset_x": transform["offsetX"],
                "offset_y": transform["offsetY"],
            },
            "canvas_points": canvas_points,
            "round_trip_errors": round_trip_errors,
        }
        return (
            image_tensor,
            heatmaps,
            visibility_targets,
            coordinate_mask,
            metadata,
        )

    @staticmethod
    def _resolve_manifest_path(export_path):
        path = Path(export_path)
        if path.is_dir():
            path = path / "manifest.json"
        if not path.is_file():
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                f"manifest not found at {path}"
            )
        return path

    def _verify_manifest_hash(self, manifest_data):
        actual = hashlib.sha256(manifest_data).hexdigest()
        if actual != self.expected_manifest_sha256:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: manifest SHA-256 mismatch "
                f"(expected {self.expected_manifest_sha256}, got {actual})"
            )
        return actual

    def _read_samples(self, manifest):
        self._validate_document_contract(manifest, "manifest")
        manifest_clips = self._manifest_clips(manifest)

        labels_file = manifest.get("resolvedLabelsFile")
        if (
            not isinstance(labels_file, str)
            or not labels_file
            or Path(labels_file).name != labels_file
        ):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: invalid resolvedLabelsFile"
            )
        labels_path = self.manifest_path.parent / labels_file
        if not labels_path.is_file():
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: resolved labels not found"
            )
        expected_labels_sha = self._require_sha256(
            manifest.get("resolvedLabelsSHA256"),
            "resolved labels SHA-256",
        )
        labels_data = self._read_bytes(labels_path, "resolved labels")
        actual_labels_sha = hashlib.sha256(labels_data).hexdigest()
        if actual_labels_sha != expected_labels_sha:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                "resolved labels SHA-256 mismatch"
            )
        labels = self._decode_json(labels_data, "resolved labels")
        self._validate_document_contract(labels, "resolved labels")
        for field in (
            "datasetID",
            "roiAlgorithmVersion",
            "inputTransformVersion",
            "inputWidth",
            "inputHeight",
        ):
            if labels.get(field) != manifest.get(field):
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: {field} mismatch"
                )

        golfer_splits = self._golfer_splits(labels)
        clips = labels.get("clips")
        if not isinstance(clips, list):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: clips must be a list"
            )
        label_clip_ids = [
            clip.get("clipID") for clip in clips if isinstance(clip, dict)
        ]
        if (
            len(label_clip_ids) != len(clips)
            or len(set(label_clip_ids)) != len(label_clip_ids)
            or set(label_clip_ids) != set(manifest_clips)
        ):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                "manifest/labels clip set mismatch"
            )

        samples = []
        for clip in clips:
            clip_id = self._nonempty_string(clip.get("clipID"), "clipID")
            manifest_clip = manifest_clips[clip_id]
            self._validate_clip_identity(clip, manifest_clip, golfer_splits)
            if clip["split"] != self.split:
                continue
            if clip["authorization"] != "training-allowed":
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} is not training-allowed"
                )
            samples.extend(self._decode_clip_samples(clip, manifest_clip))
        return samples

    def _decode_clip_samples(self, clip, manifest_clip):
        clip_id = clip["clipID"]
        frame_count = self._positive_int(clip.get("frameCount"), "frameCount")
        oriented_width = self._positive_int(
            clip.get("orientedWidth"), "orientedWidth"
        )
        oriented_height = self._positive_int(
            clip.get("orientedHeight"), "orientedHeight"
        )
        self._positive_int(clip.get("sourceTimescale"), "sourceTimescale")
        file_name = self._nonempty_string(clip.get("fileName"), "fileName")
        if Path(file_name).name != file_name:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} has unsafe fileName"
            )
        input_transform = self._validate_input_transform(
            clip.get("trainingInputTransform"),
            oriented_width,
            oriented_height,
            manifest_clip.get("trainingInputTransformSHA256"),
        )
        stage_by_frame = self._validate_p_point_truth(
            clip.get("pPointTruth"), frame_count, clip_id
        )
        frames = clip.get("frames")
        if not isinstance(frames, list):
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} frames must be a list"
            )
        seen_frames = set()
        samples = []
        for frame in frames:
            if not isinstance(frame, dict):
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: invalid frame in {clip_id}"
                )
            source_frame_index = self._nonnegative_int(
                frame.get("sourceFrameIndex"), "sourceFrameIndex"
            )
            if source_frame_index >= frame_count:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} is out of range"
                )
            if source_frame_index in seen_frames:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} has duplicate frame {source_frame_index}"
                )
            seen_frames.add(source_frame_index)
            source_time = require_finite_number(
                frame.get("sourceTime"), "sourceTime"
            )
            if source_time < 0:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: sourceTime is negative"
                )
            annotation_transform = self._validate_annotation_roi_transform(
                frame.get("annotationROITransform"),
                clip_id,
                source_frame_index,
            )
            landmarks = self._decode_landmarks(
                clip_id,
                source_frame_index,
                frame.get("landmarks"),
            )
            queue_reasons = frame.get("queueReasons")
            if (
                not isinstance(queue_reasons, list)
                or not all(isinstance(value, str) for value in queue_reasons)
                or queue_reasons != sorted(set(queue_reasons))
            ):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} has "
                    "non-canonical queueReasons"
                )
            samples.append(GolfFrameSample(
                clip_id=clip_id,
                golfer_id=clip["golferID"],
                video_path=self.video_root / file_name,
                media_sha256=clip["mediaSHA256"],
                source_frame_index=source_frame_index,
                source_time=source_time,
                oriented_width=oriented_width,
                oriented_height=oriented_height,
                view=clip["view"],
                handedness=clip["handedness"],
                stage_codes=tuple(stage_by_frame.get(source_frame_index, [])),
                queue_reasons=tuple(queue_reasons),
                annotation_roi_transform=annotation_transform,
                training_input_transform=input_transform,
                landmarks=landmarks,
            ))
        expected_frame_indexes = set(stage_by_frame)
        if seen_frames != expected_frame_indexes:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                f"{clip_id} resolved frame set does not match P1-P8 truth"
            )
        return samples

    @staticmethod
    def _read_bytes(path, description):
        try:
            return path.read_bytes()
        except OSError as error:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"cannot read {description}: {error}"
            ) from error

    @staticmethod
    def _decode_json(data, description):
        try:
            value = json.loads(data)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"invalid {description}: {error}"
            ) from error
        if not isinstance(value, dict):
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"{description} root must be an object"
            )
        return value

    @classmethod
    def _validate_document_contract(cls, document, description):
        if document.get("schemaVersion") != 2:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"unsupported {description} schema"
            )
        if document.get("inputTransformVersion") != INPUT_TRANSFORM_VERSION:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: input transform version mismatch"
            )
        if (
            document.get("inputWidth") != INPUT_SIZE
            or document.get("inputHeight") != INPUT_SIZE
        ):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: input dimensions mismatch"
            )
        cls._nonempty_string(document.get("datasetID"), "datasetID")
        cls._nonempty_string(
            document.get("roiAlgorithmVersion"), "roiAlgorithmVersion"
        )

    @classmethod
    def _manifest_clips(cls, manifest):
        clips = manifest.get("clips")
        if not isinstance(clips, list):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: manifest clips must be a list"
            )
        result = {}
        for clip in clips:
            if not isinstance(clip, dict):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: invalid manifest clip"
                )
            clip_id = cls._nonempty_string(clip.get("clipID"), "clipID")
            if clip_id in result:
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: duplicate clip {clip_id}"
                )
            result[clip_id] = clip
        return result

    @classmethod
    def _golfer_splits(cls, labels):
        golfers = labels.get("golfers")
        if not isinstance(golfers, list) or not golfers:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: golfer registry is missing"
            )
        result = {}
        for golfer in golfers:
            if not isinstance(golfer, dict):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: invalid golfer record"
                )
            golfer_id = cls._nonempty_string(
                golfer.get("golferID"), "golferID"
            )
            split = golfer.get("split")
            if split not in ALLOWED_SPLITS:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: invalid golfer split"
                )
            if golfer_id in result:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: duplicate golfer record"
                )
            result[golfer_id] = split
        return result

    @classmethod
    def _validate_clip_identity(cls, clip, manifest_clip, golfer_splits):
        clip_id = clip["clipID"]
        string_fields = (
            "golferID",
            "predictionRunID",
            "revisionID",
            "fileName",
            "mediaSHA256",
            "timelineSHA256",
            "pPointTruthSHA256",
        )
        exact_fields = (
            "split",
            "view",
            "handedness",
            "revisionCompletedAt",
            "authorization",
            "frameCount",
            "orientedWidth",
            "orientedHeight",
            "sourceTimescale",
        )
        for field in string_fields:
            cls._nonempty_string(clip.get(field), field)
        for field in ("mediaSHA256", "timelineSHA256", "pPointTruthSHA256"):
            cls._require_sha256(clip.get(field), field)
        cls._require_sha256(
            manifest_clip.get("predictionProvenanceHash"),
            "predictionProvenanceHash",
        )
        for field in string_fields + exact_fields:
            if clip.get(field) != manifest_clip.get(field):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} {field} identity mismatch"
                )
        if not cls._completed_value(clip.get("revisionCompletedAt")):
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} revision is incomplete"
            )
        if clip.get("authorization") != "training-allowed":
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} is not training-allowed"
            )
        if clip.get("split") not in ALLOWED_SPLITS:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} split is invalid"
            )
        golfer_id = clip["golferID"]
        if golfer_splits.get(golfer_id) != clip["split"]:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: golfer split leakage"
            )
        if clip.get("view") not in {"dtl", "face-on"}:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} view is invalid"
            )
        if clip.get("handedness") not in {"right", "left"}:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {clip_id} handedness is invalid"
            )
        frames = clip.get("frames")
        if (
            not isinstance(frames, list)
            or manifest_clip.get("resolvedFrameCount") != len(frames)
        ):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: resolved frame count mismatch"
            )

    @classmethod
    def _validate_input_transform(
        cls,
        transform,
        source_width,
        source_height,
        declared_sha256,
    ):
        if not isinstance(transform, dict):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: training input transform is missing"
            )
        expected = aspect_fit_transform(source_width, source_height)
        integer_fields = (
            "sourceOrientedWidth",
            "sourceOrientedHeight",
            "canvasWidth",
            "canvasHeight",
            "contentWidth",
            "contentHeight",
            "offsetX",
            "offsetY",
        )
        if transform.get("version") != expected["version"]:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: input transform version mismatch"
            )
        for field in integer_fields:
            if transform.get(field) != expected[field]:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"input transform {field} mismatch"
                )
        for direction in ("forward", "inverse"):
            audit = transform.get(direction)
            if not isinstance(audit, dict):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"input transform {direction} audit is missing"
                )
            for field in TRANSFORM_FLOAT_FIELDS:
                actual = require_finite_number(
                    audit.get(field),
                    f"trainingInputTransform.{direction}.{field}",
                )
                if abs(actual - expected[direction][field]) > 1e-12:
                    raise ReviewedTrainingLabelsRequired(
                        "reviewed training labels required: "
                        f"input transform {direction}.{field} mismatch"
                    )
        expected_sha = input_transform_sha256(expected)
        if cls._require_sha256(
            declared_sha256, "training input transform SHA-256"
        ) != expected_sha:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                "training input transform SHA-256 mismatch"
            )
        return expected

    @classmethod
    def _validate_p_point_truth(cls, truth, frame_count, clip_id):
        if not isinstance(truth, list) or len(truth) != len(EXPECTED_STAGES):
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"{clip_id} P1-P8 truth is incomplete"
            )
        stage_by_frame = {}
        seen = set()
        for item in truth:
            if not isinstance(item, dict):
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: "
                    f"{clip_id} P-point truth is invalid"
                )
            stage = item.get("stage")
            if stage not in EXPECTED_STAGES or stage in seen:
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: "
                    f"{clip_id} P-point stage is invalid"
                )
            seen.add(stage)
            frame = cls._nonnegative_int(
                item.get("sourceFrameIndex"), "P-point sourceFrameIndex"
            )
            if frame >= frame_count:
                raise ReviewedTrainingLabelsRequired(
                    f"reviewed training labels required: "
                    f"{clip_id} P-point frame is out of range"
                )
            stage_by_frame.setdefault(frame, []).append(stage)
        if tuple(item["stage"] for item in truth) != EXPECTED_STAGES:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: "
                f"{clip_id} P1-P8 truth is not canonical"
            )
        return stage_by_frame

    @classmethod
    def _decode_landmarks(cls, clip_id, source_frame_index, labels):
        if not isinstance(labels, list):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                f"{clip_id} frame {source_frame_index} landmarks must be a list"
            )
        result = {}
        allowed_names = set(MANIFEST_NAMES.values())
        for label in labels:
            if not isinstance(label, dict):
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: invalid landmark"
                )
            name = label.get("landmark")
            if name not in allowed_names or name in result:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} landmark is invalid"
                )
            visibility = label.get("visibility")
            if visibility not in VISIBILITY_INDEX:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{clip_id} frame {source_frame_index} has invalid visibility"
                )
            point = label.get("point")
            if visibility == "visible":
                if not isinstance(point, dict):
                    raise ReviewedTrainingLabelsRequired(
                        "reviewed training labels required: visible point is missing"
                    )
                point = {
                    "x": require_finite_number(point.get("x"), "point.x"),
                    "y": require_finite_number(point.get("y"), "point.y"),
                }
                if not (
                    0 <= point["x"] <= 1
                    and 0 <= point["y"] <= 1
                ):
                    raise ReviewedTrainingLabelsRequired(
                        "reviewed training labels required: "
                        "full-frame visible point is invalid"
                    )
            elif point is not None:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: hidden point has coordinates"
                )
            result[name] = {"visibility": visibility, "point": point}
        return result

    @classmethod
    def _validate_annotation_roi_transform(cls, transform, clip_id, frame_index):
        if not isinstance(transform, dict):
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                f"{clip_id} frame {frame_index} annotation ROI transform is missing"
            )
        values = {
            field: require_finite_number(
                transform.get(field), f"annotationROITransform.{field}"
            )
            for field in ROI_FIELDS
        }
        determinant = values["a"] * values["d"] - values["b"] * values["c"]
        if abs(determinant) <= 1e-12:
            raise ReviewedTrainingLabelsRequired(
                "reviewed training labels required: "
                "annotation ROI transform is singular"
            )
        expected = {
            "invA": values["d"] / determinant,
            "invB": -values["b"] / determinant,
            "invC": -values["c"] / determinant,
            "invD": values["a"] / determinant,
        }
        expected["invTx"] = -(
            expected["invA"] * values["tx"]
            + expected["invC"] * values["ty"]
        )
        expected["invTy"] = -(
            expected["invB"] * values["tx"]
            + expected["invD"] * values["ty"]
        )
        for field, expected_value in expected.items():
            if abs(values[field] - expected_value) > 1e-9:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    "annotation ROI transform inverse is inconsistent"
                )
        return values

    @staticmethod
    def _render_full_frame(image, transform):
        resized = image.resize(
            (transform["contentWidth"], transform["contentHeight"]),
            resample=Image.Resampling.BILINEAR,
        )
        canvas = Image.new("RGB", (INPUT_SIZE, INPUT_SIZE), (0, 0, 0))
        canvas.paste(resized, (transform["offsetX"], transform["offsetY"]))
        return canvas

    def _load_video_frame(self, sample):
        if not sample.video_path.is_file():
            raise FileNotFoundError(f"video not found: {sample.video_path}")
        if sample.video_path not in self._verified_media:
            actual_sha = self._file_sha256(sample.video_path)
            if actual_sha != sample.media_sha256:
                raise ReviewedTrainingLabelsRequired(
                    "reviewed training labels required: "
                    f"{sample.clip_id} media SHA-256 mismatch"
                )
            self._verified_media.add(sample.video_path)
        command = [
            "ffmpeg",
            "-v",
            "error",
            "-autorotate",
            "-ss",
            f"{sample.source_time:.12f}",
            "-i",
            str(sample.video_path),
            "-frames:v",
            "1",
            "-f",
            "image2pipe",
            "-vcodec",
            "png",
            "pipe:1",
        ]
        try:
            completed = subprocess.run(
                command,
                check=True,
                capture_output=True,
            )
        except FileNotFoundError as error:
            raise RuntimeError(
                "ffmpeg is required to extract labelled video frames"
            ) from error
        except subprocess.CalledProcessError as error:
            detail = error.stderr.decode(
                "utf-8", errors="replace"
            ).strip()
            raise RuntimeError(
                f"failed to extract {sample.clip_id} frame "
                f"{sample.source_frame_index}: {detail}"
            ) from error
        return Image.open(io.BytesIO(completed.stdout)).convert("RGB")

    @staticmethod
    def _file_sha256(path):
        digest = hashlib.sha256()
        with Path(path).open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    @staticmethod
    def _require_sha256(value, field):
        if not isinstance(value, str) or not SHA256_PATTERN.fullmatch(value):
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {field} is invalid"
            )
        return value

    @staticmethod
    def _nonempty_string(value, field):
        if not isinstance(value, str) or not value or value.strip() != value:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {field} is invalid"
            )
        return value

    @staticmethod
    def _positive_int(value, field):
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {field} is invalid"
            )
        return value

    @staticmethod
    def _nonnegative_int(value, field):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ReviewedTrainingLabelsRequired(
                f"reviewed training labels required: {field} is invalid"
            )
        return value

    @staticmethod
    def _completed_value(value):
        return (
            isinstance(value, str) and bool(value.strip())
        ) or (
            isinstance(value, (int, float))
            and not isinstance(value, bool)
            and math.isfinite(value)
        )


# Task 3 migrates train/evaluate to the five-value item. Keep imports stable
# during Task 1 without retaining the legacy manifest behavior.
GolfKeypointDataset = GolfHeatmapDataset
