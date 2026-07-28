import hashlib
import json
import struct
from pathlib import Path

import numpy as np
import torch


SHA256_HEX_LENGTH = 64


def canonical_json_sha256(value):
    encoded = json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def file_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def model_state_sha256(state):
    """Stable digest of tensor names, dtypes, shapes, and canonical bytes."""
    if not isinstance(state, dict) or not state:
        raise ValueError("checkpoint model state is missing")
    hasher = hashlib.sha256()
    hasher.update(b"swingarc-tensor-state-v1\0")
    for name in sorted(state):
        tensor = state[name]
        if not isinstance(name, str) or not name:
            raise ValueError("checkpoint model state has an invalid tensor name")
        if not torch.is_tensor(tensor):
            raise ValueError("checkpoint model state contains a non-tensor")
        tensor = tensor.detach().cpu().contiguous()
        array = tensor.numpy()
        if array.dtype.byteorder == ">" or (
            array.dtype.byteorder == "=" and not np.little_endian
        ):
            array = array.byteswap().newbyteorder("<")
        dtype = array.dtype.str
        if dtype.startswith("="):
            dtype = "<" + dtype[1:]
        name_bytes = name.encode("utf-8")
        dtype_bytes = dtype.encode("ascii")
        shape_bytes = json.dumps(
            list(array.shape), separators=(",", ":")
        ).encode("ascii")
        payload = array.tobytes(order="C")
        for value in (name_bytes, dtype_bytes, shape_bytes, payload):
            hasher.update(struct.pack(">Q", len(value)))
            hasher.update(value)
    return hasher.hexdigest()


def package_tree_sha256(package_path):
    """Hash a package tree without filesystem metadata or traversal ambiguity."""
    root = Path(package_path)
    if not root.is_dir():
        raise ValueError("Core ML package tree is missing")
    if any(path.is_symlink() for path in root.rglob("*")):
        raise ValueError("Core ML package tree contains a symbolic link")
    files = sorted(
        path for path in root.rglob("*")
        if path.is_file() and not path.is_symlink()
    )
    if not files:
        raise ValueError("Core ML package tree is empty")
    hasher = hashlib.sha256()
    hasher.update(b"swingarc-package-tree-v1\0")
    for path in files:
        relative = path.relative_to(root).as_posix().encode("utf-8")
        payload = path.read_bytes()
        hasher.update(struct.pack(">Q", len(relative)))
        hasher.update(relative)
        hasher.update(struct.pack(">Q", len(payload)))
        hasher.update(payload)
    return hasher.hexdigest()
