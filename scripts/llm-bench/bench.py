#!/usr/bin/env python3
"""Local LLM benchmark — coding quality per second, on this CPU-only laptop.

The question it answers (todo.md §4): which local model actually CODES well
enough to be worth waiting for? 6 tok/s is acceptable if the answers pass;
speed is the budget, not the goal. So every run records both: how many tasks
pass their tests, and how long it took.

Usage (ollama must be running — `sudo systemctl start ollama`):
    bench.py speed MODEL [--threads N] [--think]   # tokens/s on a fixed prompt
    bench.py code  MODEL [--threads N] [--think] [--only humaneval|local]
    bench.py report                                # table of everything so far

Tasks: 21 HumanEval problems (every 8th of 164, graded by the official tests)
plus 4 tasks drawn from this repo's real work (bash + Python). Model-written
code runs inside bubblewrap: read-only filesystem, no network, killed with the
parent, 20 s limit.

Results append to ~/.local/state/llm-bench/results.jsonl (outside the repo,
like the malware scanner's state), so runs on different days compare directly.
Stdlib only.
"""
import argparse
import gzip
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
if not HOST.startswith("http"):
    HOST = "http://" + HOST
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "llm-bench")
RESULTS = os.path.join(STATE, "results.jsonl")
HUMANEVAL_URL = "https://github.com/openai/human-eval/raw/master/data/HumanEval.jsonl.gz"
HUMANEVAL = os.path.join(STATE, "HumanEval.jsonl.gz")
CTX = 4096

# ─────────────────────────────────────────────────────────────────────────────
# Ollama
# ─────────────────────────────────────────────────────────────────────────────
def chat(model, prompt, think, threads, num_predict, system=None):
    msgs = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": prompt}]
    body = {
        "model": model, "messages": msgs, "stream": False, "think": think, "keep_alive": "5m",
        # temperature 0 + fixed seed: greedy decoding, so a re-run reproduces.
        "options": {"temperature": 0, "seed": 42, "num_ctx": CTX, "num_predict": num_predict},
    }
    if threads:
        body["options"]["num_thread"] = threads
    t0 = time.monotonic()
    try:
        resp = _post_chat(body)
    except urllib.error.HTTPError as e:
        # Models packaged without thinking support reject the `think` field
        # outright, even when it's false. Drop it and ask again.
        if e.code == 400 and "think" in e.read().decode(errors="replace").lower():
            body.pop("think")
            resp = _post_chat(body)
        else:
            raise
    resp["_wall"] = time.monotonic() - t0
    return resp


def _post_chat(body):
    req = urllib.request.Request(f"{HOST}/api/chat", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3600) as r:
        return json.load(r)


def unload_others(model):
    """Unload every other resident model before this one loads.

    ollama keeps a model in RAM for keep_alive after its last request, so
    back-to-back runs stacked models: on 2026-10-07 the 9b (5.65 GiB) and the
    2b were still resident when the 4b started loading, and the kernel
    OOM-killed ollama's runner. zram cannot help much here — quantized weights
    barely compress."""
    try:
        with urllib.request.urlopen(f"{HOST}/api/ps", timeout=10) as r:
            loaded = [m.get("name") for m in json.load(r).get("models", [])]
    except (urllib.error.URLError, OSError, ValueError):
        return
    for name in loaded:
        if name and name != model:
            unload(name)


def unload(name):
    req = urllib.request.Request(f"{HOST}/api/generate",
                                 data=json.dumps({"model": name, "keep_alive": 0}).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=120).read()
    except (urllib.error.URLError, OSError):
        pass


def free_gib():
    with open("/proc/meminfo") as f:
        return next(int(l.split()[1]) for l in f if l.startswith("MemAvailable:")) / 2**20


def cap_room_gib():
    """GiB left under the ollama service's MemoryMax (scripts/ollama.sh sets 9G).

    The cap binds before system RAM does for the biggest models: on 2026-10-08
    gemma4:12b-it-qat loaded at 7.9 GiB, its prompt cache grew ~0.25 GiB per
    prompt, and the kernel killed the runner mid-run at 9 GiB. Counts anonymous
    memory only: memory.current also includes page cache from reading the model
    file, which the kernel drops before it OOM-kills anything. None if the
    service has no cap or the cgroup isn't readable."""
    cg = "/sys/fs/cgroup/system.slice/ollama.service"
    try:
        with open(f"{cg}/memory.max") as f:
            cap = f.read().strip()
        with open(f"{cg}/memory.stat") as f:
            anon = next(int(l.split()[1]) for l in f if l.startswith("anon "))
    except (OSError, ValueError, StopIteration):
        return None
    return None if cap == "max" else (int(cap) - anon) / 2**30


def ensure_room(model):
    """Refuse to load a model the machine can't hold comfortably.

    Rule: free RAM (MemAvailable, after other models are unloaded) must cover
    the model file x 1.15 (runtime + 4k context) + 1.5 GiB headroom for the
    desktop. Better to skip a run than to let it push the desktop into swap
    or wake the OOM killer, which is what "freezing the laptop" looks like."""
    size = 0
    try:
        # Already loaded (e.g. a second run on the same model): it needs no new room,
        # and counting it again would refuse a run that is perfectly safe.
        with urllib.request.urlopen(f"{HOST}/api/ps", timeout=10) as r:
            if any(m.get("name") == model or m.get("model") == model for m in json.load(r).get("models", [])):
                return
        with urllib.request.urlopen(f"{HOST}/api/tags", timeout=10) as r:
            for m in json.load(r).get("models", []):
                if m.get("name") == model or m.get("model") == model:
                    size = m.get("size", 0)
    except (urllib.error.URLError, OSError, ValueError):
        return
    with open("/proc/meminfo") as f:
        avail = next(int(l.split()[1]) * 1024 for l in f if l.startswith("MemAvailable:"))
    need = size * 1.15 + 1.5 * 2**30
    if size and avail < need:
        sys.exit(f"not loading {model}: needs ~{need / 2**30:.1f} GiB free, have {avail / 2**30:.1f} GiB. "
                 "Close something (browser tabs) and re-run.")


def resident_gib(model):
    try:
        with urllib.request.urlopen(f"{HOST}/api/ps", timeout=10) as r:
            for m in json.load(r).get("models", []):
                if m.get("name") == model or m.get("model") == model:
                    return round(m.get("size", 0) / 2**30, 2)
    except (urllib.error.URLError, OSError, ValueError):
        pass
    return None


def rate(count, ns):
    return round(count / (ns / 1e9), 2) if ns else 0.0

# ─────────────────────────────────────────────────────────────────────────────
# Sandboxed execution
# ─────────────────────────────────────────────────────────────────────────────
def sandboxed(files, argv, timeout=20):
    """Write files into a temp dir, run argv inside bwrap with it at /tmp/work.
    Returns (passed, output tail)."""
    with tempfile.TemporaryDirectory(prefix="llm-bench-") as d:
        for name, text in files.items():
            with open(os.path.join(d, name), "w") as f:
                f.write(text)
        cmd = ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
               "--tmpfs", "/tmp", "--ro-bind", d, "/tmp/work", "--chdir", "/tmp/work",
               "--unshare-net", "--unshare-pid", "--die-with-parent", *argv]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return p.returncode == 0, (p.stdout + p.stderr)[-400:]
        except subprocess.TimeoutExpired:
            return False, "timeout"


def extract_code(text, langs):
    blocks = re.findall(r"```(\w*)[^\n]*\n(.*?)```", text, re.S)
    wanted = [b for lang, b in blocks if lang.lower() in langs] or [b for _, b in blocks]
    return wanted[0] if wanted else text

# ─────────────────────────────────────────────────────────────────────────────
# Tasks
# ─────────────────────────────────────────────────────────────────────────────
SYSTEM = "You are an expert programmer. Answer with code only, in one fenced code block."


def humaneval_tasks():
    if not os.path.exists(HUMANEVAL):
        os.makedirs(STATE, exist_ok=True)
        print(f"downloading HumanEval -> {HUMANEVAL}", file=sys.stderr)
        urllib.request.urlretrieve(HUMANEVAL_URL, HUMANEVAL)
    with gzip.open(HUMANEVAL, "rt") as f:
        probs = [json.loads(line) for line in f]
    tasks = []
    for p in probs[::8]:   # every 8th: 21 problems, fixed, spread across the set
        prompt = ("Complete the following Python function. Reply with the complete function "
                  "(signature, body and any imports it needs) in a single ```python block.\n\n"
                  f"```python\n{p['prompt']}```")

        def grade(answer, p=p):
            code = extract_code(answer, ("python", "py"))
            # The original prompt goes first: it carries imports and any helper
            # functions the target relies on; the model's version then overrides the stub.
            prog = f"{p['prompt']}\n\n{code}\n\n{p['test']}\ncheck({p['entry_point']})\n"
            return sandboxed({"prog.py": prog}, ["python3", "prog.py"])
        tasks.append({"id": p["task_id"], "suite": "humaneval", "prompt": prompt, "grade": grade})
    return tasks


BASH_HARNESS = r'''
source /tmp/work/solution.sh
fail=0
t() { if eval "$1"; then :; else echo "FAIL: $1"; fail=1; fi; }
'''

LOCAL = [
    {   # kvm.sh / win11.sh destroy guard
        "id": "local/confirm-yes", "lang": "bash",
        "prompt": "Write a bash function `confirm` that receives the script's arguments. If any argument is "
                  "`--yes` or `-y`, return 0 immediately without reading input. Otherwise print the prompt "
                  "`Type yes to continue: ` to stderr, read one line from stdin, and return 0 only if that line "
                  "is exactly `yes` — not `y`, not `YES`, and not with leading or trailing spaces. Return 1 in "
                  "every other case, including end of input. Reply with only the function in a ```bash block.",
        "test": r'''
t 'echo yes | confirm >/dev/null 2>&1'
t '! (echo y | confirm >/dev/null 2>&1)'
t '! (echo YES | confirm >/dev/null 2>&1)'
t '! (echo " yes" | confirm >/dev/null 2>&1)'
t '! (echo "yes " | confirm >/dev/null 2>&1)'
t '! (printf "" | confirm >/dev/null 2>&1)'
t 'printf "" | confirm --yes >/dev/null 2>&1'
t 'printf "" | confirm foo -y bar >/dev/null 2>&1'
t '! (echo no | confirm >/dev/null 2>&1)'
exit $fail
''',
    },
    {   # cliphist-store-image.sh
        "id": "local/clip-prune", "lang": "bash",
        "prompt": "`cliphist list` prints one entry per line, newest first, as `<id><TAB><preview>`. Image entries "
                  "have a preview that starts with `[[ binary data`, e.g. `[[ binary data 243 KiB png 721x821 ]]`; "
                  "every other entry is text, even if the text contains that phrase later on. Write a bash function "
                  "`old_images` that reads such lines on stdin and takes one argument N. It prints, one per line and "
                  "in the original order, the ids of every image entry except the newest N images. Text entries are "
                  "never printed. Reply with only the function in a ```bash block.",
        "test": r'''
input=$'9\t[[ binary data 1 KiB png 10x10 ]]\n8\thello world\n7\t[[ binary data 2 MiB jpeg 1920x1080 ]]\n6\t[[ binary data 5 KiB png 1x1 ]]\n5\tsome [[ binary data ]] text\n4\t[[ binary data 3 KiB png 2x2 ]]'
t '[ "$(printf "%s\n" "$input" | old_images 2)" = "$(printf "6\n4")" ]'
t '[ "$(printf "%s\n" "$input" | old_images 0)" = "$(printf "9\n7\n6\n4")" ]'
t '[ -z "$(printf "%s\n" "$input" | old_images 10)" ]'
exit $fail
''',
    },
    {   # profiles.ini section parser (Zen/Firefox)
        "id": "local/profiles-ini", "lang": "python",
        "prompt": "Write a Python function `default_profile(ini_text: str) -> str | None` for Firefox's profiles.ini. "
                  "If a section whose name starts with `Install` exists, return its `Default` value. Otherwise "
                  "return the `Path` of the first section whose name starts with `Profile` and that has `Default=1`. "
                  "Otherwise return None. Ignore blank lines and lines starting with `;` or `#`. Values may themselves "
                  "contain `=`. Reply with only code in a ```python block.",
        "test": r'''
a = """[General]
StartWithLastProfile=1

[Profile1]
Name=work
Path=abc.work
Default=1

[Install4F96D1932A9F858E]
Default=xyz.default-release
Locked=1
"""
b = """; comment
[Profile0]
Name=a
Path=p0.a

[Profile1]
Name=b
Path=p1.b=odd
Default=1
"""
c = """[Profile0]
Name=only
Path=p0.only
"""
assert default_profile(a) == "xyz.default-release", default_profile(a)
assert default_profile(b) == "p1.b=odd", default_profile(b)
assert default_profile(c) is None, default_profile(c)
assert default_profile("") is None
''',
    },
    {   # ufw/sysctl override hunt
        "id": "local/sysctl-parse", "lang": "python",
        "prompt": "Write a Python function `parse_sysctl(text: str) -> dict[str, str]` that parses sysctl "
                  "configuration text. Each non-blank, non-comment line is `key = value` or `key=value`; comments "
                  "start with `#` or `;`, possibly after leading spaces. Keys may use `/` or `.` as separators — "
                  "normalise them to `.` (so `net/ipv4/conf/all/rp_filter` becomes `net.ipv4.conf.all.rp_filter`). "
                  "Strip whitespace around keys and values, and remove a leading `-` from a key (it means "
                  "'ignore errors'). Values may contain `=`. Later lines override earlier ones. Reply with only "
                  "code in a ```python block.",
        "test": r'''
text = """# ufw style
net/ipv4/conf/all/rp_filter=1
  ; indented comment
kernel.sysrq = 0
-net.core.bpf_jit_harden = 2

vm.swappiness=60
vm.swappiness = 180
weird.key = a=b
"""
r = parse_sysctl(text)
assert r == {"net.ipv4.conf.all.rp_filter": "1", "kernel.sysrq": "0",
             "net.core.bpf_jit_harden": "2", "vm.swappiness": "180", "weird.key": "a=b"}, r
''',
    },
]


def local_tasks():
    tasks = []
    for t in LOCAL:
        if t["lang"] == "bash":
            def grade(answer, t=t):
                code = extract_code(answer, ("bash", "sh", "shell"))
                return sandboxed({"solution.sh": code, "test.sh": BASH_HARNESS + t["test"]}, ["bash", "test.sh"])
        else:
            def grade(answer, t=t):
                code = extract_code(answer, ("python", "py"))
                return sandboxed({"prog.py": f"{code}\n\n{t['test']}"}, ["python3", "prog.py"])
        tasks.append({"id": t["id"], "suite": "local", "prompt": t["prompt"], "grade": grade})
    return tasks

# ─────────────────────────────────────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────────────────────────────────────
def record(row):
    os.makedirs(STATE, exist_ok=True)
    row["when"] = time.strftime("%Y-%m-%d %H:%M")
    with open(RESULTS, "a") as f:
        f.write(json.dumps(row) + "\n")


SPEED_PROMPT = ("Write a bash script that lists the ten largest files under the current directory, "
                "with human-readable sizes, skipping .git directories. Explain each line briefly.")


def cmd_speed(a):
    unload_others(a.model)
    ensure_room(a.model)
    # First call loads the model (and warms caches); the second is the measurement.
    chat(a.model, "Say OK.", a.think, a.threads, 8)
    r = chat(a.model, SPEED_PROMPT, a.think, a.threads, 256)
    row = {"kind": "speed", "model": a.model, "think": a.think, "threads": a.threads,
           "prompt_tps": rate(r.get("prompt_eval_count", 0), r.get("prompt_eval_duration", 0)),
           "gen_tps": rate(r.get("eval_count", 0), r.get("eval_duration", 0)),
           "resident_gib": resident_gib(a.model)}
    record(row)
    print(json.dumps(row))


def cmd_code(a):
    tasks = []
    if a.only in (None, "humaneval"):
        tasks += humaneval_tasks()
    if a.only in (None, "local"):
        tasks += local_tasks()
    if a.ids:   # re-run just some tasks, e.g. last run's failures
        tasks = [t for t in tasks if t["id"] in a.ids]
    unload_others(a.model)
    ensure_room(a.model)
    chat(a.model, "Say OK.", a.think, a.threads, 8)   # load before timing
    cap = 6144 if a.think else 1024
    # Every answer is kept, so a failure can be explained afterwards (wrong
    # logic vs. ran out of tokens vs. no code block) rather than guessed at.
    run_dir = os.path.join(STATE, "answers", f"{time.strftime('%Y%m%d-%H%M')}-{re.sub(r'[:/]', '_', a.model)}"
                           f"{'-think' if a.think else ''}")
    os.makedirs(run_dir, exist_ok=True)
    passed, gen_tok, gen_ns, wall, fails, per_task = 0, 0, 0, 0.0, [], []
    for i, t in enumerate(tasks, 1):
        # The runner's prompt cache grows ~0.1 GiB per new prompt (llm-findings.md).
        # If free RAM runs low, or the service nears its MemoryMax, reload the
        # model to empty it — untimed — rather than let the run push the desktop
        # into swap or get the runner OOM-killed.
        room = cap_room_gib()
        if free_gib() < 2.0 or (room is not None and room < 0.75):
            why = f"free RAM {free_gib():.1f} GiB" if free_gib() < 2.0 else f"{room:.2f} GiB under ollama's MemoryMax"
            print(f"  ({why} — reloading {a.model} to clear its prompt cache)", flush=True)
            unload(a.model)
            chat(a.model, "Say OK.", a.think, a.threads, 8)
        r = chat(a.model, t["prompt"], a.think, a.threads, cap, system=SYSTEM)
        answer = r["message"].get("content", "")
        ok, out = t["grade"](answer)
        n = r.get("eval_count", 0)
        passed += ok
        gen_tok += n
        gen_ns += r.get("eval_duration", 0)
        wall += r["_wall"]
        if not ok:
            fails.append(t["id"])
        per_task.append({"id": t["id"], "ok": ok, "tokens": n, "secs": round(r["_wall"], 1), "hit_cap": n >= cap})
        with open(os.path.join(run_dir, t["id"].replace("/", "_") + ".md"), "w") as f:
            thinking = r["message"].get("thinking") or ""
            f.write(f"# {t['id']} — {'PASS' if ok else 'FAIL'} ({n} tokens, {r['_wall']:.1f}s)\n\n")
            if thinking:
                f.write(f"## thinking\n\n{thinking}\n\n")
            f.write(f"## answer\n\n{answer}\n\n## grader output\n\n```\n{out}\n```\n")
        print(f"[{i:2}/{len(tasks)}] {'PASS' if ok else 'fail'}  {t['id']:<22} "
              f"{n:5} tok  {r['_wall']:6.1f}s{'  (hit token cap)' if n >= cap else ''}", flush=True)
    row = {"kind": "code", "model": a.model, "think": a.think, "threads": a.threads, "only": a.only, "ids": a.ids,
           "passed": passed, "total": len(tasks), "wall_min": round(wall / 60, 1),
           "gen_tps": rate(gen_tok, gen_ns), "tokens_per_task": round(gen_tok / len(tasks)),
           "passes_per_hour": round(passed / (wall / 3600), 1) if wall else 0,
           "resident_gib": resident_gib(a.model), "failed": fails, "per_task": per_task,
           "answers": run_dir}
    record(row)
    print(json.dumps(row))


def cmd_report(_a):
    if not os.path.exists(RESULTS):
        print("no results yet")
        return
    rows = [json.loads(line) for line in open(RESULTS)]
    print(f"{'when':16} {'kind':5} {'model':26} {'think':5} {'thr':>3} {'gen t/s':>7} {'prompt t/s':>10} "
          f"{'RAM GiB':>7} {'pass':>7} {'min':>5} {'pass/h':>6}")
    for r in rows:
        score = f"{r['passed']}/{r['total']}" if r["kind"] == "code" else ""
        if r.get("ids") or r.get("only"):
            score += "*"   # subset run — not comparable with full runs
        print(f"{r['when']:16} {r['kind']:5} {r['model']:26} {str(r['think']):5} {str(r['threads'] or '-'):>3} "
              f"{r.get('gen_tps', ''):>7} {r.get('prompt_tps', ''):>10} {str(r.get('resident_gib') or ''):>7} "
              f"{score:>7} {str(r.get('wall_min', '')):>5} {str(r.get('passes_per_hour', '')):>6}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("speed", "code"):
        s = sub.add_parser(name)
        s.add_argument("model")
        s.add_argument("--threads", type=int, default=None, help="num_thread (default: ollama's choice)")
        s.add_argument("--think", action="store_true", help="enable the model's thinking mode")
        if name == "code":
            s.add_argument("--only", choices=("humaneval", "local"))
            s.add_argument("--ids", nargs="+", help="run only these task ids (e.g. HumanEval/32 local/clip-prune)")
    sub.add_parser("report")
    a = ap.parse_args()
    try:
        {"speed": cmd_speed, "code": cmd_code, "report": cmd_report}[a.cmd](a)
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach ollama at {HOST} ({e.reason}). Start it: sudo systemctl start ollama")


if __name__ == "__main__":
    main()
