#!/usr/bin/env python3
"""PC-side analysis of a touch flight-recorder dump (docs/08 2.27): finds the INT stalls in notes/<date>-<label>/touch-trace-raw.txt.

Usage: python3 scripts/touch-trace-stalls.py <touch-trace-raw.txt> [--json]

The raw file is the recorder's trace (phone-touch-trace.sh dump, with the spi_transfer_stop records of the touch chip; EXTRA=1 adds the
irq_handler_entry and spi_transfer_start records, which this script does not need). What it counts:

  touch-downs   coordinate events with TCHSTA 1 (byte 0 = 0x40 / 0x44 ...) read by the IRQ thread
  kick          an 18-byte `87` read NOT made by the IRQ thread (the poll work of patch 0005: a kworker; or our poke: sh, dd), followed within
                KICK_WINDOW_US by a read of the IRQ thread. docs/08 2.22 to 2.26: after a stall the kick read itself returns no event, the chip then
                raises INT within about 200 us and the IRQ thread finds the queued events.
  STALL         a kick whose next IRQ read has left >= 1 (more than one event queued) and comes after at least SILENCE_MS without an IRQ read.
                A touch-down that merely happens to arrive right after a poll read has left = 0: counted as "coincidence", not as a stall.
  queue depth   left + 1 events; the withheld time is about (left) * 8.33 ms (the chip reports at 120 Hz)
  first event   what the queue started with (touch-down or a move: a stall that began mid-touch)
  idle gap      for a queue that starts with a touch-down: from the last release read to the touch-down (estimated from the queue depth)
"""
import json
import re
import sys

KICK_WINDOW_US = 2500
SILENCE_MS = 100
FRAME_MS = 8.33

LINE = re.compile(r"^\s*(.+?)-(\d+)\s+\[(\d+)\]\s+\S+\s+([0-9.]+):\s+spi_transfer_stop:(.*)$")
RX = re.compile(r"rx=\[([^\]]*)\]")
TX = re.compile(r"tx=\[([^\]]*)\]")


def parse(path):
    reads = []
    for line in open(path, errors="replace"):
        m = LINE.match(line)
        if not m:
            continue
        task, _pid, _cpu, ts, rest = m.groups()
        rx = RX.search(rest)
        tx = TX.search(rest)
        rxb = rx.group(1).split("-") if rx else []
        txb = tx.group(1).split("-") if tx else []
        reads.append({"t": float(ts), "task": task, "rx": rxb, "tx": txb})
    return reads


def event_of(r):
    """(key, left) of an 18-byte event read, else None."""
    rx = r["rx"]
    if len(rx) < 10 or not r["tx"] or r["tx"][0] != "87":
        return None
    try:
        key = int(rx[2], 16)
        left = int(rx[9], 16) & 31
    except ValueError:
        return None
    return key, left


def kind(key):
    if key == 0:
        return "empty"
    eid, tchsta = key & 3, key >> 6
    if eid != 0:
        return "other"
    return {1: "press", 2: "move", 3: "release"}.get(tchsta, "other")


def analyse(reads):
    irq = [r for r in reads if r["task"].startswith("irq/")]
    others = [r for r in reads if not r["task"].startswith("irq/") and event_of(r) is not None]
    out = {"irq_reads": len(irq), "kicks": 0, "stalls": [], "coincidences": 0, "poll_found_event": 0}
    counts = {"press": 0, "move": 0, "release": 0}
    for r in irq:
        e = event_of(r)
        if e:
            k = kind(e[0])
            if k in counts and (e[0] & 0x3c) == 0:  # touch id 0 only, like the notes of docs/08
                counts[k] += 1
    out["touch_downs"] = counts["press"]
    out["releases"] = counts["release"]
    out["moves"] = counts["move"]
    rel_times = []
    for r in irq:
        e = event_of(r)
        if e and kind(e[0]) == "release" and (e[0] & 0x3c) == 0:
            rel_times.append(r["t"])
    irq_t = [r["t"] for r in irq]
    import bisect
    for k in others:
        out["kicks"] += 1
        e = event_of(k)
        if e and e[0] != 0:
            out["poll_found_event"] += 1
        i = bisect.bisect_right(irq_t, k["t"])
        if i >= len(irq_t) or (irq_t[i] - k["t"]) * 1e6 > KICK_WINDOW_US:
            continue
        nxt = irq[i]
        ne = event_of(nxt)
        if not ne:
            continue
        prev_t = irq_t[i - 1] if i else None
        silence = (k["t"] - prev_t) * 1000 if prev_t else 1e9
        if ne[1] >= 1 and silence >= SILENCE_MS:
            first = kind(ne[0])
            prev_kind = "none"
            if i:
                pe = event_of(irq[i - 1])
                prev_kind = kind(pe[0]) if pe else "other"
            gap = None
            if first == "press":
                est = nxt["t"] - ne[1] * FRAME_MS / 1000
                j = bisect.bisect_right(rel_times, est) - 1
                gap = (est - rel_times[j]) * 1000 if j >= 0 else None
            out["stalls"].append({
                "t": round(nxt["t"], 6), "kick_task": k["task"], "delay_us": round((nxt["t"] - k["t"]) * 1e6),
                "silence_ms": round(silence), "queued": ne[1] + 1, "withheld_ms": round(ne[1] * FRAME_MS),
                "first_event": first, "before": prev_kind, "idle_gap_ms": None if gap is None else round(gap),
            })
        else:
            out["coincidences"] += 1
    return out


def report(o):
    n = len(o["stalls"])
    print("IRQ reads: %d   touch-downs: %d   releases: %d   moves: %d" % (o["irq_reads"], o["touch_downs"], o["releases"], o["moves"]))
    print("kick reads (poll or poke): %d   found an event themselves: %d" % (o["kicks"], o["poll_found_event"]))
    print("STALLS (a kick, then an IRQ read with left >= 1 after >= %d ms of silence): %d" % (SILENCE_MS, n))
    print("coincidences (an interrupt right after a kick, left = 0 or no silence): %d" % o["coincidences"])
    if o["touch_downs"]:
        print("stalls per 1000 touch-downs: %.2f" % (n * 1000.0 / o["touch_downs"]))
    for s in o["stalls"]:
        print("  stall at %.6f s: kicked by %s %d us before the IRQ read; silence %d ms; %d events queued (about %d ms withheld); "
              "queue starts with a %s, last read before it: %s; idle gap before that touch-down: %s" % (
                  s["t"], s["kick_task"], s["delay_us"], s["silence_ms"], s["queued"], s["withheld_ms"], s["first_event"], s["before"],
                  "%d ms" % s["idle_gap_ms"] if s["idle_gap_ms"] is not None else "n/a"))


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print(__doc__)
        return 2
    reads = parse(args[0])
    if not reads:
        print("no spi_transfer_stop records in %s" % args[0])
        return 3
    o = analyse(reads)
    if "--json" in argv:
        print(json.dumps(o, indent=1))
    else:
        report(o)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
