"""Retry a crashed Xcode build service once, without retrying ordinary failures.

Each attempt keeps its log and xcresult. The retry uses separate DerivedData;
no caches, processes or diagnostic bundles are deleted.
"""
import argparse
from pathlib import Path
import subprocess
import sys


SERVICE_CRASH = "unexpected service error: The Xcode build system has crashed"


def retry_command(command: list[str]) -> list[str]:
    result = list(command)
    for flag in ["-derivedDataPath", "-resultBundlePath"]:
        if flag not in result or result.index(flag) + 1 >= len(result):
            raise ValueError(f"{flag} is required for isolated retries")
        index = result.index(flag) + 1
        path = Path(result[index])
        result[index] = str(path.with_name(path.stem + "-retry" + path.suffix))
    return result


def run(command: list[str], log_prefix: Path) -> int:
    second = retry_command(command)
    log_prefix.parent.mkdir(parents=True, exist_ok=True)
    for attempt, args in enumerate([command, second], start=1):
        crashed = False
        log = log_prefix.with_name(log_prefix.name + f"-{attempt}.log")
        print(f"Xcode attempt {attempt}/2; log: {log}", flush=True)
        with log.open("w", encoding="utf-8") as stream:
            process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, encoding="utf-8", errors="replace", bufsize=1)
            for line in process.stdout:
                sys.stdout.write(line)
                stream.write(line)
                if SERVICE_CRASH in line:
                    crashed = True
            code = process.wait()
        if code == 0:
            return 0
        if not crashed or attempt == 2:
            return code
        print("Xcode service crashed. Retrying once with isolated DerivedData.", flush=True)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log-prefix", required=True, type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command[1:] if options.command[:1] == ["--"] else options.command
    if not command:
        parser.error("Supply an xcodebuild command after --")
    return run(command, options.log_prefix)


if __name__ == "__main__":
    sys.exit(main())
