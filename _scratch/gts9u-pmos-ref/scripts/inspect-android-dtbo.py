#!/usr/bin/env python3
"""Inspect Android DT table entries and direct root properties without dtc."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


DT_TABLE_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9


def align4(value: int) -> int:
    return (value + 3) & ~3


def c_string(blob: bytes, offset: int) -> str:
    end = blob.index(b"\0", offset)
    return blob[offset:end].decode("ascii", "replace")


def format_property(name: str, value: bytes) -> str:
    if name in {"model", "compatible", "label", "status"}:
        return repr(value.rstrip(b"\0").decode("ascii", "replace").replace("\0", ", "))
    if len(value) % 4 == 0:
        cells = struct.unpack(f">{len(value) // 4}I", value)
        return "<" + " ".join(f"0x{cell:x}" for cell in cells) + ">"
    return value.hex()


def root_properties(dtb: bytes) -> dict[str, bytes]:
    header = struct.unpack_from(">10I", dtb, 0)
    magic, total, off_struct, off_strings = header[:4]
    if magic != FDT_MAGIC or total > len(dtb):
        raise ValueError("invalid FDT")
    size_strings = header[8]
    strings = dtb[off_strings : off_strings + size_strings]
    cursor = off_struct
    depth = 0
    result: dict[str, bytes] = {}
    while True:
        token = struct.unpack_from(">I", dtb, cursor)[0]
        cursor += 4
        if token == FDT_BEGIN_NODE:
            cursor = align4(dtb.index(b"\0", cursor) + 1)
            depth += 1
        elif token == FDT_END_NODE:
            depth -= 1
        elif token == FDT_PROP:
            length, name_offset = struct.unpack_from(">II", dtb, cursor)
            cursor += 8
            value = dtb[cursor : cursor + length]
            cursor = align4(cursor + length)
            if depth == 1:
                result[c_string(strings, name_offset)] = value
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            return result
        else:
            raise ValueError(f"unknown FDT token {token:#x}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    blob = args.image.read_bytes()
    header = struct.unpack_from(">8I", blob, 0)
    magic, total, header_size, entry_size, count, entries_offset, page_size, version = header
    if magic != DT_TABLE_MAGIC:
        raise SystemExit(f"not an Android DT table: magic={magic:#x}")
    print(
        f"total={total} header={header_size} entry_size={entry_size} "
        f"entries={count} offset={entries_offset} page={page_size} version={version}"
    )
    for index in range(count):
        offset = entries_offset + index * entry_size
        values = struct.unpack_from(">8I", blob, offset)
        dt_size, dt_offset, entry_id, rev, *custom = values
        dtb = blob[dt_offset : dt_offset + dt_size]
        print(
            f"\nentry[{index}] size={dt_size} offset={dt_offset} "
            f"id={entry_id:#x} rev={rev:#x} custom={[hex(x) for x in custom]}"
        )
        for name, value in root_properties(dtb).items():
            print(f"  {name} = {format_property(name, value)}")


if __name__ == "__main__":
    main()
