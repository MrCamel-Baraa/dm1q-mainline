#!/usr/bin/env python3
"""Build a deterministic ath12k board-2.bin with one named BDF entry."""

import argparse
import struct
from pathlib import Path


MAGIC = b"QCA-ATH12K-BOARD\0"
IE_BOARD = 0
IE_BOARD_NAME = 0
IE_BOARD_DATA = 1


def align4(data: bytes) -> bytes:
    return data + bytes((-len(data)) & 3)


def ie(ie_id: int, payload: bytes) -> bytes:
    return struct.pack("<II", ie_id, len(payload)) + align4(payload)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("board_name", help="exact ath12k board name")
    parser.add_argument("bdf", type=Path, help="BDF including its ELF wrapper")
    parser.add_argument("output", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    name = args.board_name.encode("ascii")
    bdf = args.bdf.read_bytes()
    if not bdf.startswith(b"\x7fELF"):
        raise SystemExit("BDF must retain its ELF wrapper")

    group = ie(IE_BOARD_NAME, name) + ie(IE_BOARD_DATA, bdf)
    blob = align4(MAGIC) + ie(IE_BOARD, group)
    args.output.write_bytes(blob)

    # Parse the result once so format regressions fail at generation time.
    off = len(align4(MAGIC))
    outer_id, outer_len = struct.unpack_from("<II", blob, off)
    assert outer_id == IE_BOARD and outer_len == len(group)
    sub = off + 8
    name_id, name_len = struct.unpack_from("<II", blob, sub)
    assert name_id == IE_BOARD_NAME
    assert blob[sub + 8:sub + 8 + name_len] == name
    sub += 8 + ((name_len + 3) & ~3)
    data_id, data_len = struct.unpack_from("<II", blob, sub)
    assert data_id == IE_BOARD_DATA and data_len == len(bdf)
    assert blob[sub + 8:sub + 8 + data_len] == bdf

    print(f"wrote {len(blob)} bytes: {args.output}")
    print(f"board name: {args.board_name}")
    print(f"BDF ELF: {len(bdf)} bytes")


if __name__ == "__main__":
    main()
