import re
from dataclasses import dataclass, field
from pathlib import Path

import ansible_runner

PROJECT_DIR = Path(__file__).parent
PRIVATE_DATA_DIR = PROJECT_DIR / ".runner"


@dataclass
class ScriptResult:
    host: str
    script: str
    rc: int
    stdout: str
    stderr: str


@dataclass
class RunReport:
    results: list[ScriptResult] = field(default_factory=list)
    failed: bool = False

    def search(self, pattern: str, flags: int = 0) -> list[ScriptResult]:
        """Return results whose stdout matches the given regex pattern."""
        regex = re.compile(pattern, flags)
        return [r for r in self.results if regex.search(r.stdout)]


def run_script(
    script_path: str,
    host_pattern: str = "computes",
    inventory: str = "../inventory.yaml",
    executable: str | None = None,
) -> RunReport:
    """Run a single local script on the matched hosts via the ansible script module."""
    script_abs = str((PROJECT_DIR / script_path).resolve())
    inventory_abs = str((PROJECT_DIR / inventory).resolve())
    module_args = script_abs if executable is None else f"{script_abs} executable={executable}"

    PRIVATE_DATA_DIR.mkdir(exist_ok=True)
    runner = ansible_runner.run(
        private_data_dir=str(PRIVATE_DATA_DIR),
        inventory=inventory_abs,
        host_pattern=host_pattern,
        module="script",
        module_args=module_args,
        quiet=True,
    )

    report = RunReport(failed=runner.rc != 0)
    for event in runner.events:
        event_data = event.get("event_data", {})
        res = event_data.get("res")
        if res is None:
            continue
        report.results.append(
            ScriptResult(
                host=event_data.get("host", "unknown"),
                script=script_path,
                rc=res.get("rc", -1),
                stdout=res.get("stdout", ""),
                stderr=res.get("stderr", ""),
            )
        )
    return report


def run_scripts(
    script_paths: list[str],
    host_pattern: str = "computes",
    inventory: str = "../inventory.yaml",
    executables: dict[str, str] | None = None,
) -> RunReport:
    """Run multiple local scripts on the matched hosts and combine the results."""
    executables = executables or {}
    combined = RunReport()
    for script_path in script_paths:
        report = run_script(
            script_path,
            host_pattern=host_pattern,
            inventory=inventory,
            executable=executables.get(script_path),
        )
        combined.results.extend(report.results)
        combined.failed = combined.failed or report.failed
    return combined


def main():
    report = run_scripts(
        ["test.py"],
        executables={"test.py": "python3"},
    )

    for result in report.results:
        print(f"[{result.host}] {result.script} (rc={result.rc})")
        print(result.stdout.strip())

    matches = report.search(r"test \w+ script")
    print(f"\n{len(matches)} script(s) matched pattern")


if __name__ == "__main__":
    main()
