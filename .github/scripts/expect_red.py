"""Gate for the R1 expected-red recovery suite.

Reads a `flutter test --file-reporter json:<path>` result and a manifest of
test names that MUST currently fail because of a known business defect.

Passes only when every listed test ran and failed for an assertion:
- plain tests: testDone result "failure" (a TestFailure);
- widget tests: flutter_test reports a failing `expect` as result "error" with
  "Test failed. See exception logs above."; accepted only if that test's logs
  contain "The following TestFailure was thrown" and no other caught exception.

Fails when a listed test passes (the defect is fixed: move the test to the
green suite in the same change), errors for any other reason (harness,
timeout, setup), is skipped, is missing, or when an unlisted test runs.
"""

import argparse
import json
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("results")
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()

    expected = []
    with open(args.manifest, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line and not line.startswith("#"):
                expected.append(line)

    names, results, skipped, logs = {}, {}, {}, {}
    with open(args.results, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith("{"):
                continue
            event = json.loads(line)
            kind = event.get("type")
            if kind == "testStart":
                names[event["test"]["id"]] = event["test"]["name"]
            elif kind == "print":
                logs.setdefault(event["testID"], []).append(event.get("message", ""))
            elif kind == "error":
                logs.setdefault(event["testID"], []).append(event.get("error", ""))
            elif kind == "testDone" and not event.get("hidden"):
                name = names[event["testID"]]
                skipped[name] = event.get("skipped", False)
                results[name] = (event["result"], event["testID"])

    problems, notices = [], []
    for name in expected:
        if name not in results:
            problems.append(f"missing: {name}")
            continue
        result, test_id = results[name]
        text = "\n".join(logs.get(test_id, []))
        if skipped.get(name):
            problems.append(f"skipped: {name}")
        elif result == "success":
            problems.append(f"now GREEN (move to green suite with its fix): {name}")
        elif result == "failure":
            notices.append(f"::notice title=expected red::{name}")
        elif (
            result == "error"
            and "The following TestFailure was thrown" in text
            and text.count("EXCEPTION CAUGHT") == text.count("The following TestFailure was thrown")
        ):
            notices.append(f"::notice title=expected red (widget)::{name}")
        else:
            problems.append(f"red for the WRONG reason ({result}): {name}")
    for name in results:
        if name not in expected:
            problems.append(f"unlisted test in red suite: {name}")

    # GitHub keeps only 10 notices per step: publish the summary first.
    summary = f"expected red: {len(expected)}, observed: {len(results)}, problems: {len(problems)}"
    print(f"::notice title=expected-red gate summary::{summary}")
    for problem in problems:
        print(f"::error title=expected-red gate::{problem}")
    for notice in notices:
        print(notice)
    print(summary)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
