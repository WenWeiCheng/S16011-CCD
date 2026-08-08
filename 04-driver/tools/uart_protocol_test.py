#!/usr/bin/env python3
"""
UART protocol regression test for the CCD controller.

Sends the full command set defined in
00-docs/embed-design/uart_protocol_design.md over a serial port and checks
the responses (OK / ERR <code> <message>). Covers:

  - info commands      LISTPARAMS (with group filter), GETINFO
  - parameter access   GETPARAM / SETPARAM round-trips, boundary & invalid values
  - acquisition        ACQ single / burst / fetch / abort, busy & capacity errors
  - control            RESET
  - lexical edge cases empty line, too many args, unknown verb/param, over-long line

Usage:
    pip install pyserial
    python uart_protocol_test.py [--port COM6] [--baud 115200] [--timeout 1.0] [--skip-acq]

Exit code is 0 when every test passes, 1 otherwise. The device must be running
the firmware and connected on the given port.

--skip-acq skips the acquisition-flow tests that need a real exposure and an
FX2 host connected to drain the frame cache (the ACQ error-code tests still run).
"""

import argparse
import sys
import time

import serial

DEFAULT_PORT = "COM6"
DEFAULT_BAUD = 115200
DEFAULT_TIMEOUT = 1.0
POLL_INTERVAL = 0.1


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default=DEFAULT_PORT, help="serial port (default COM6)")
    ap.add_argument("--baud", type=int, default=DEFAULT_BAUD, help="baud rate (default 115200)")
    ap.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT,
                    help="per-read timeout in seconds (default 1.0)")
    ap.add_argument("--skip-acq", action="store_true",
                    help="skip acquisition-flow tests that require a real exposure + FX2")
    return ap.parse_args()


class CcdProtocol:
    """Thin wrapper around pyserial for the line-based request/response protocol."""

    def __init__(self, port, baud, timeout):
        self._ser = serial.Serial(port, baud, timeout=timeout)
        self.timeout = timeout

    def close(self):
        self._ser.close()

    def flush_input(self):
        self._ser.reset_input_buffer()

    def _read_line(self):
        raw = self._ser.readline()
        if not raw:
            return None
        return raw.decode("ascii", errors="replace").rstrip("\r\n")

    def command(self, cmd, timeout=None):
        """Send one command line and return (ok, code, data).

        ok=True for 'OK ...', ok=False for 'ERR <code> <msg>' (code parsed),
        ok=None on timeout. Returns the first line that starts with OK/ERR.
        """
        deadline = time.monotonic() + (timeout if timeout is not None else self.timeout * 4)
        self._ser.flush()
        self._ser.write((cmd + "\r\n").encode("ascii"))
        self._ser.flush()
        while time.monotonic() < deadline:
            line = self._read_line()
            if line is None:
                continue
            if line.startswith("OK"):
                return True, 0, line[2:].strip()
            if line.startswith("ERR"):
                parts = line.split(None, 2)
                try:
                    code = int(parts[1])
                except (IndexError, ValueError):
                    code = -1
                msg = parts[2] if len(parts) > 2 else ""
                return False, code, msg
            # unrelated banner / stray output: keep reading
        return None, None, None

    def drain(self, quiet=0.15):
        """Read and discard pending lines until the link has been quiet.

        An over-long line (ERR 6) leaves a residual partial line on the device that
        is dispatched as a second (garbage) command, so one host send can produce two
        responses. Drain discards such stragglers before the next command.
        """
        saved = self._ser.timeout
        self._ser.timeout = 0.05
        end = time.monotonic() + quiet
        try:
            while time.monotonic() < end:
                if self._read_line() is None:
                    time.sleep(0.01)
        finally:
            self._ser.timeout = saved

    def get_param(self, name, timeout=None):
        """Return the value token of GETPARAM <name>, or None on error/timeout."""
        ok, code, data = self.command("GETPARAM %s" % name, timeout)
        if not ok:
            return None
        parts = data.split(None, 1)
        return parts[1] if len(parts) == 2 else ""

    def wait_for_param(self, name, predicate, timeout, interval=POLL_INTERVAL):
        """Poll GETPARAM <name> until predicate(value) is true; return the value or None."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            v = self.get_param(name)
            if v is not None and predicate(v):
                return v
            time.sleep(interval)
        return None


class Runner:
    def __init__(self, proto, skip_acq):
        self.proto = proto
        self.skip_acq = skip_acq
        self.results = []
        self.all_params = []

    def check(self, name, cond, detail=""):
        self.results.append((name, bool(cond)))
        tag = "PASS" if cond else "FAIL"
        line = "[%s] %s" % (tag, name)
        if not cond and detail:
            line += " -- %s" % detail
        print(line)
        return bool(cond)

    def expect_ok(self, cmd, name):
        ok, code, data = self.proto.command(cmd)
        return self.check(name, ok, "reply: %r" % data if not ok else "")

    def expect_err(self, cmd, code, name):
        ok, rc, msg = self.proto.command(cmd)
        return self.check(name, ok is False and rc == code,
                          "expected ERR %d, got %r %r" % (code, ok, msg))

    def run(self):
        tests = [
            self.test_lexical,
            self.test_verb_case_insensitive,
            self.test_listparams,
            self.test_getinfo,
            self.test_getparam_all,
            self.test_setparam_roundtrip,
            self.test_setparam_boundaries,
            self.test_setparam_errors,
            self.test_bool_synonyms,
            self.test_acq_bad_modes,
            self.test_acq_busy,
        ]
        if not self.skip_acq:
            tests += [
                self.test_acq_single_flow,
                self.test_acq_burst_flow,
                self.test_acq_fetch_insufficient,
            ]
        tests += [
            self.test_acq_burst_exceeds_cache,
            self.test_reset,
        ]
        for t in tests:
            try:
                t()
            except Exception as e:  # a broken test should not abort the whole run
                self.check(t.__name__, False, "exception: %r" % e)
        self.restore_defaults()

    # ------------------------------------------------------------------ info
    def test_lexical(self):
        self.expect_err("", 3, "empty line -> ERR 3")
        self.expect_err("A" * 300, 6, "over-long line -> ERR 6")
        # the tail of the over-long line stays in the device RX buffer and is
        # dispatched as a second command (ERR 1 unknown verb); drain it so it does
        # not leak into the next test
        self.proto.drain()
        self.expect_err("FOO", 1, "unknown verb -> ERR 1")
        self.expect_err("SETPARAM a b c d e", 3, "too many args -> ERR 3")

    def test_verb_case_insensitive(self):
        self.expect_ok("listparams", "verb case-insensitive (listparams)")

    def test_listparams(self):
        ok, _, data = self.proto.command("LISTPARAMS")
        names = [n for n in data.split(",") if n]
        self.check("LISTPARAMS returns params", ok and len(names) > 10,
                   "got %d names" % len(names))
        if ok and "exposure_time_us" in names and "sensor_temp" in names:
            self.all_params = names
            self.check("LISTPARAMS exposes exposure_time_us/sensor_temp", True)
        else:
            self.check("LISTPARAMS exposes exposure_time_us/sensor_temp", False,
                       "missing expected names")

        ok, _, data = self.proto.command("LISTPARAMS tec_*")
        tec = [n for n in data.split(",") if n]
        self.check("LISTPARAMS tec_* group filter", ok and all(n.startswith("tec_") for n in tec) and len(tec) >= 3,
                   "got %r" % data)

        ok, _, data = self.proto.command("LISTPARAMS zz_*")
        self.check("LISTPARAMS non-matching group -> bare OK", ok and data == "", repr(data))

    def test_getinfo(self):
        ok, _, data = self.proto.command("GETINFO exposure_time_us")
        fields = data.split()
        self.check("GETINFO exposure_time_us format",
                   ok and len(fields) >= 6 and fields[0] == "exposure_time_us"
                   and fields[1] == "int_range" and fields[2] == "RW",
                   repr(data))

        bad = 0
        for name in self.all_params:
            ok, _, data = self.proto.command("GETINFO %s" % name)
            if not (ok and data.split()[0] == name):
                bad += 1
        self.check("GETINFO every param echoes its name", bad == 0, "%d bad" % bad)

        self.expect_err("GETINFO nonexistent", 2, "GETINFO unknown param -> ERR 2")
        self.expect_err("GETINFO", 2, "GETINFO missing arg -> ERR 2")

    def test_getparam_all(self):
        bad = 0
        for name in self.all_params:
            ok, _, data = self.proto.command("GETPARAM %s" % name)
            if not (ok and data.split(None, 1)[0] == name):
                bad += 1
        self.check("GETPARAM every param echoes its name", bad == 0, "%d bad" % bad)
        self.expect_err("GETPARAM nonexistent", 2, "GETPARAM unknown param -> ERR 2")

    # ----------------------------------------------------------------- config
    def test_setparam_roundtrip(self):
        cases = [
            ("exposure_time_us", "1234", "1234"),
            ("read_mode", "image", "image"),
            ("freq_sel", "500k", "500k"),
            ("mock_mode", "1", "1"),
            ("cdsclk_delay", "7", "7"),
            ("image_width", "1024", "1024"),
            ("image_height", "4", "4"),
            ("bevel_left", "5", "5"),
            ("blank_right", "3", "3"),
            ("tec_kp", "0.5", "0.500"),
            ("tec_set_temp", "-10.2", "-10.2"),
            ("adc_gain_r", "63", "63"),
            ("adc_offset_b", "511", "511"),
            ("camera_name", '"my cam"', '"my cam"'),
        ]
        for param, value, expected in cases:
            orig = self.proto.get_param(param)
            ok, _, data = self.proto.command("SETPARAM %s %s" % (param, value))
            if not ok:
                self.check("SETPARAM %s %s" % (param, value), False, "reply %r" % data)
                continue
            got = self.proto.get_param(param)
            self.check("SETPARAM %s round-trip %s" % (param, value), got == expected,
                       "expected %r, got %r" % (expected, got))
            if orig is not None:
                self.proto.command("SETPARAM %s %s" % (param, orig))

    def test_setparam_boundaries(self):
        for value in ("1", "1000", "2147483647"):
            ok, _, data = self.proto.command("SETPARAM exposure_time_us %s" % value)
            got = self.proto.get_param("exposure_time_us") if ok else None
            self.check("SETPARAM exposure_time_us %s" % value, ok and got == value,
                       "got %r" % (got or data))

    def test_setparam_errors(self):
        self.expect_err("SETPARAM exposure_time_us 0", 3, "below min -> ERR 3")
        self.expect_err("SETPARAM exposure_time_us 2147483648", 3, "above max -> ERR 3")
        self.expect_err("SETPARAM exposure_time_us abc", 3, "non-numeric -> ERR 3")
        self.expect_err("SETPARAM tec_kp 11", 3, "float out of range -> ERR 3")
        self.expect_err("SETPARAM adc_gain_r 64", 3, "gain code out of range -> ERR 3")
        self.expect_err("SETPARAM image_width 0", 3, "image_width below min -> ERR 3")
        self.expect_err("SETPARAM cdsclk_delay 128", 3, "cdsclk_delay above max -> ERR 3")
        self.expect_err("SETPARAM sensor_temp 25.0", 4, "RO param -> ERR 4")
        self.expect_err("SETPARAM foo 1", 2, "unknown param -> ERR 2")

    def test_bool_synonyms(self):
        for tok, want in (("on", "1"), ("true", "1"), ("1", "1"),
                          ("off", "0"), ("false", "0"), ("0", "0")):
            ok, _, data = self.proto.command("SETPARAM mock_mode %s" % tok)
            got = self.proto.get_param("mock_mode") if ok else None
            self.check("bool synonym mock_mode %s" % tok, ok and got == want,
                       "want %r got %r (%r)" % (want, got, data))

    # ---------------------------------------------------------------- acq
    def test_acq_bad_modes(self):
        self.expect_err("ACQ", 3, "ACQ missing mode -> ERR 3")
        self.expect_err("ACQ foo", 3, "ACQ invalid mode -> ERR 3")
        self.expect_err("ACQ burst", 3, "ACQ burst missing n -> ERR 3")
        self.expect_err("ACQ burst 0", 3, "ACQ burst 0 -> ERR 3")
        self.expect_err("ACQ burst x", 3, "ACQ burst non-numeric -> ERR 3")

    def _set_exposure(self, us):
        self.proto.command("SETPARAM exposure_time_us %d" % us)

    def _set_short_exposure(self):
        self._set_exposure(1000)

    def test_acq_busy(self):
        self.proto.command("ACQ abort")
        self.proto.command("RESET")
        # long exposure keeps the acquisition active so the second ACQ reliably
        # hits the busy window (a 1 ms single could finish before it arrives)
        self._set_exposure(100000)
        self.expect_ok("ACQ single", "ACQ single starts")
        self.expect_err("ACQ single", 5, "ACQ during acquisition -> ERR 5 busy")
        self.expect_err("ACQ live", 5, "ACQ live during acquisition -> ERR 5 busy")
        self.expect_ok("ACQ abort", "ACQ abort returns to idle")

    def test_acq_single_flow(self):
        self.proto.command("ACQ abort")
        self.proto.command("RESET")
        self._set_short_exposure()
        self.expect_ok("ACQ single", "ACQ single starts")
        v = self.proto.wait_for_param("acq_state", lambda s: s == "idle", timeout=15)
        self.check("single -> acq_state idle", v == "idle", "got %r" % v)
        self.check("single -> frame_num_ready 1",
                   self.proto.get_param("frame_num_ready") == "1")
        self.expect_ok("ACQ fetch 1", "ACQ fetch 1 starts")
        v = self.proto.wait_for_param("frame_num_ready", lambda s: s == "0", timeout=15)
        self.check("fetch 1 drains cache", v == "0", "got %r" % v)

    def test_acq_burst_flow(self):
        self.proto.command("ACQ abort")
        self.proto.command("RESET")
        self._set_short_exposure()
        self.expect_ok("ACQ burst 100", "ACQ burst 100 starts")
        v = self.proto.wait_for_param("frame_num_ready", lambda s: s == "100", timeout=15)
        self.check("burst 100 -> frame_num_ready 100", v == "100", "got %r" % v)
        self.expect_ok("ACQ fetch 100", "ACQ fetch 100 starts")
        v = self.proto.wait_for_param("frame_num_ready", lambda s: s == "0", timeout=15)
        self.check("fetch 100 drains cache", v == "0", "got %r" % v)

    def test_acq_fetch_insufficient(self):
        self.proto.command("ACQ abort")
        self.proto.command("RESET")
        self._set_short_exposure()
        self.expect_ok("ACQ single", "ACQ single starts")
        self.proto.wait_for_param("acq_state", lambda s: s == "idle", timeout=15)
        ok, rc, msg = self.proto.command("ACQ fetch 3")
        self.check("fetch more than cached -> ERR 5", ok is False and rc == 5,
                   "got %r %r %r" % (ok, rc, msg))
        self.expect_ok("ACQ abort", "cleanup abort")

    def test_acq_burst_exceeds_cache(self):
        self.proto.command("ACQ abort")
        self.proto.command("RESET")
        cap = self.proto.get_param("frame_capacity")
        n = int(cap) + 1 if cap and cap.isdigit() else 2001
        ok, rc, msg = self.proto.command("ACQ burst %d" % n)
        self.check("burst exceeding cache -> ERR 3", ok is False and rc == 3,
                   "got %r %r %r" % (ok, rc, msg))

    def test_reset(self):
        self.expect_ok("RESET", "RESET -> OK")
        v = self.proto.get_param("acq_state")
        self.check("RESET returns to idle", v == "idle", "got %r" % v)

    # ------------------------------------------------------------------ final
    def restore_defaults(self):
        for param, value in (("exposure_time_us", "1000"), ("tec_enable", "0"),
                             ("mock_mode", "0"), ("camera_name", "ccd"),
                             ("read_mode", "line_binning"), ("freq_sel", "100k"),
                             ("image_width", "8"), ("image_height", "1")):
            self.proto.command("SETPARAM %s %s" % (param, value))

    def summary(self):
        passed = sum(1 for _, ok in self.results if ok)
        failed = len(self.results) - passed
        print()
        print("===== results: %d passed, %d failed (%d total) =====" % (passed, failed, len(self.results)))
        for name, ok in self.results:
            if not ok:
                print("  FAIL: %s" % name)
        return failed == 0


def main():
    args = parse_args()
    print("connecting to %s @ %d ..." % (args.port, args.baud))
    proto = CcdProtocol(args.port, args.baud, args.timeout)
    try:
        proto.flush_input()
        if args.skip_acq:
            print("skipping acquisition-flow tests (--skip-acq)")
        runner = Runner(proto, args.skip_acq)
        runner.run()
        sys.exit(0 if runner.summary() else 1)
    finally:
        proto.close()


if __name__ == "__main__":
    main()
