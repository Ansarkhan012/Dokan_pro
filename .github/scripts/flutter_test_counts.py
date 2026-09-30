"""Summarise and gate a `flutter test --file-reporter json:...` result file.

Fails when any test failed or errored, when fewer than --min-passed tests
passed, or when more than --max-skipped tests were skipped. Emits a GitHub
Actions notice with the exact counts so they are visible without log access.
"""

import argparse
import json
import re
import sys

_SECRETS = re.compile(r"(eyJ[A-Za-z0-9._-]{10,}|sb_(secret|publishable)_[A-Za-z0-9_-]+)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--label", required=True)
    parser.add_argument("--min-passed", type=int, required=True)
    parser.add_argument("--max-skipped", type=int, required=True)
    args = parser.parse_args()

    passed = skipped = failed = 0
    names, errors, failures = {}, {}, []
    with open(args.path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith("{"):
                continue
            event = json.loads(line)
            kind = event.get("type")
            if kind == "testStart":
                names[event["test"]["id"]] = event["test"]["name"]
                continue
            if kind == "error":
                errors.setdefault(event["testID"], event.get("error", ""))
                continue
            if kind != "testDone":
                continue
            if event.get("hidden"):
                # Suite load failures (compile errors, setUpAll) surface here.
                if event.get("result") != "success":
                    failed += 1
                    failures.append(event["testID"])
                continue
            if event.get("skipped"):
                skipped += 1
            elif event.get("result") == "success":
                passed += 1
            else:
                failed += 1
                failures.append(event["testID"])

    summary = f"{args.label}: {passed} passed, {skipped} skipped, {failed} failed"
    print(summary)
    print(f"::notice title={args.label}::{summary}")
    for test_id in failures:
        detail = " | ".join(errors.get(test_id, "no error text").strip().splitlines()[:4])
        detail = _SECRETS.sub("[redacted]", detail)[:600]
        print(f"::error title={args.label} failed::{names.get(test_id, test_id)} :: {detail}")
    problems = []
    if failed:
        problems.append(f"{failed} failed")
    if passed < args.min_passed:
        problems.append(f"passed {passed} < baseline {args.min_passed}")
    if skipped > args.max_skipped:
        problems.append(f"skipped {skipped} > baseline {args.max_skipped}")
    if problems:
        print(f"::error title={args.label}::" + "; ".join(problems))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
