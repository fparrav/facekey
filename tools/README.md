# Converting ArcFace to Core ML

`convert_arcface.py` turns InsightFace's official `w600k_mbf` ArcFace weights
(ONNX) into `facekey/Models/ArcFace.mlpackage`, ready for `ArcFaceEmbedder.swift`
to load. Run this yourself — it downloads ~2GB of Python tooling (torch,
coremltools) and ~13MB of model weights from InsightFace's own hosting.

## Run it

```bash
cd /path/to/facekey
python3 -m venv .venv
source .venv/bin/activate
pip install -r tools/requirements.txt
python tools/convert_arcface.py
```

First run downloads the InsightFace `buffalo_s` model pack to
`~/.insightface/models/` (cached for next time). The script then:

1. Converts ONNX → torch → Core ML, baking preprocessing (RGB, `(px-127.5)/127.5`)
   into the model so Swift only ever hands over a raw 112×112 image.
2. **Verifies numerical parity**: runs the same random input through the
   original ONNX graph and the converted Core ML model and checks the
   outputs agree (cosine similarity > 0.999). This is the real check —
   a channel-order or scale mistake would silently produce a broken model
   that loads fine and returns plausible-looking garbage. If this check
   fails, the script exits with an error and **the model is not usable** —
   do not wire it in.
3. Saves `facekey/Models/ArcFace.mlpackage`.

Expect it to take a few minutes, mostly the one-time package installs.

## After it succeeds

Add `facekey/Models/ArcFace.mlpackage` to the Xcode project if it doesn't
show up automatically (the `facekey/` folder is a file-system-synchronized
group, so it should auto-appear — if not, drag it into Xcode and make sure
"Copy items if needed" + the `facekey` target are checked).

The model is committed to git (see the repo's `.gitignore` — only the
*compiled* `.mlmodelc` is excluded, since that's derived from the
`.mlpackage` at build time).

## If auto-download fails

InsightFace's model hosting occasionally moves. If `FaceAnalysis(...).prepare()`
fails, download `w600k_mbf.onnx` yourself from the InsightFace model zoo and
run:

```bash
python tools/convert_arcface.py --onnx-path /path/to/w600k_mbf.onnx
```

## Model contract (what Swift expects)

| | |
|---|---|
| Input | `input_image`, 112×112 RGB image (CVPixelBuffer/CGImage) |
| Output | `embedding`, 512 floats, **not** L2-normalized — Swift normalizes it |
| Preprocessing | Baked in: `(pixel - 127.5) / 127.5`, RGB channel order |

If you ever swap in a different ArcFace variant (e.g. `w600k_r50` via
`--variant w600k_r50`), this contract stays the same — only the file size
and latency change.

# Probing the AutoFill popup

`autofill_keystroke_spike.swift` is the throwaway spike for the
`unlock-passwords-autofill-panel` change. It waits for the AutoFill popup's
secure password field to take the focus, asks for the focused element through
the system, the focused application, the frontmost app and the panel service,
and types the dummy text `facekey` (never the Mac password, no Return) only
when the field's owner is `com.apple.AutoFillPanelService` or
`com.apple.SafariPlatformSupport.Helper`. It never reads a field's value.

```bash
swiftc -O tools/autofill_keystroke_spike.swift -o /tmp/autofill_keystroke_spike
/tmp/autofill_keystroke_spike [--seconds N] [--no-type]   # default 60 s
```

Exit codes: 0 typed (or accepted with `--no-type`), 1 bad arguments, 2 timed
out, 3 Accessibility not granted, 4 the focused secure field is not an allowed
owner (nothing typed). `--no-type` only reports the decision, which is how to
check that a login field in a web page is rejected.

# Probing the Passwords lock UI

`passwords_lock_probe.swift` is a standalone, **read-only** probe for the
Passwords app (`com.apple.Passwords`), used by the `unlock-passwords-app`
spike to record what the lock UI looks like in the Accessibility (AX)
hierarchy. Given the running app it prints to stdout:

- whether the process is the frontmost app,
- its windows (title, role, subrole, frame),
- a depth-limited tree of the AX hierarchy of the first window — for every
  element: role, subrole, title, description, value kind, enabled, focused
  and the AX actions,
- the app's currently focused UI element.

It only reads: it performs no AX actions, writes no attributes, posts no
events and never prints the value of a secure text field (a secure field
shows `value=secure (hidden)`).

## Run it

```bash
cd /path/to/facekey
swiftc -O tools/passwords_lock_probe.swift -o /tmp/passwords_lock_probe
/tmp/passwords_lock_probe [--depth N] [--delay S]   # default depth 8
```

The terminal that runs it needs Accessibility permission (System Settings
> Privacy & Security > Accessibility). Without it the probe exits 3 and
says so.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | tree printed |
| 1 | bad arguments (`--help` always exits 0) |
| 2 | Passwords is not running |
| 3 | Accessibility not granted — enable it in System Settings > Privacy & Security > Accessibility for the terminal, then run again |
