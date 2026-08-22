"""
Throwaway build-time script: convert hexgrad's Kokoro-82M (PyTorch) to ONNX.

Runs ONLY inside the `convert` Docker stage. It downloads the original weights
from the model author's Hugging Face repo, loads them with the author's own
`kokoro` package, patches the handful of things that do not survive tracing
(see export_patches.py), exports to ONNX, and then refuses to hand anything to
the runtime image unless three independent verification gates pass
(see verify.py).

WHAT THE READER SHOULD KNOW BEFORE TRUSTING THIS
------------------------------------------------
* The model is STOCHASTIC by design. Its vocoder adds random harmonic phase and
  random excitation noise on every call, so two PyTorch runs on the same input
  are not equal — the build log prints exactly how unequal, before exporting.
  A naive `max|diff|` comparison against ONNX is therefore not a test of the
  conversion; it is a test of the dither. Gates A and B replace it.
* The export is traced at batch size 1 with a token count that is deliberately
  different from every count used in the checks, so a graph that had baked in
  the trace length would fail rather than pass by coincidence.
* Only the token axis is dynamic. `app/server.py` sends one sentence at a time,
  which is the only shape this graph promises to compute correctly.

Outputs (in --out):
  kokoro.onnx          the model (fp32)
  vocab.json           phoneme -> token id map (from the author's config.json)
  voices/<name>.npy    voice style packs as plain NumPy arrays (no torch at runtime)
  convert-freeze.txt   `pip freeze` of this stage, so the versions can be pinned
  manifest.json        SHA-256 of every input and output, for your records
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile

import numpy as np
import onnx
import torch
from huggingface_hub import hf_hub_download
from kokoro import KModel

import verify
from export_patches import make_deterministic, patch_for_export
from verify import Case, GateFailed

REPO = "hexgrad/Kokoro-82M"

# Phonemes, not text: this stage has no phonemiser. The trace length must differ
# from both check lengths, which is asserted below rather than hoped for.
# Written in Kokoro's own symbols (Q=əʊ, W=aʊ, ʤ=dʒ, I=aɪ ...), i.e. what
# app/phonemize.py emits, so the gates exercise the same token ids the server will.
TRACE_PHONEMES = "ðə kwˈɪk bɹˈWn fˈɒks ʤˈʌmps ˌQvə"
CHECK_PHONEMES = {
    "short": "həlˈQ wˈɜːld",
    "long": "ɡˈʊd ˈiːvnɪŋ sˈɜː, ˈɔːl sˈɪstəmz ɑːɹ ˈɒnlIn ænd ɹˈʌnɪŋ nˈɔːməli.",
}

INPUT_NAMES = ["input_ids", "style", "speed"]
DYNAMIC_AXES = {"input_ids": {1: "tokens"}, "audio": {0: "samples"}}
OPSET = 17


def sha256(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Exportable(torch.nn.Module):
    """Fixed (input_ids, style, speed) -> audio signature for the ONNX graph."""

    def __init__(self, model: KModel):
        super().__init__()
        self.model = model

    def forward(self, input_ids, style, speed):
        audio, _durations = self.model.forward_with_tokens(input_ids, style, speed)
        return audio


def make_case(label: str, phonemes: str, vocab: dict, pack: np.ndarray) -> Case:
    ids = [vocab[c] for c in phonemes if c in vocab]
    if not ids:
        sys.exit(f"[convert] FAIL {label!r} produced no tokens")
    return Case(
        label=label,
        input_ids=np.array([[0, *ids, 0]], dtype=np.int64),
        style=pack[len(ids) - 1].astype(np.float32),
        speed=np.array([1.0], dtype=np.float32),
        n_tokens=len(ids),
    )


def torch_runner(wrapper: Exportable):
    def run(case: Case) -> np.ndarray:
        with torch.no_grad():
            audio = wrapper(
                torch.from_numpy(case.input_ids),
                torch.from_numpy(case.style),
                torch.from_numpy(case.speed),
            )
        return audio.numpy()

    return run


def export(wrapper: Exportable, case: Case, path: pathlib.Path) -> None:
    """Legacy (non-dynamo) exporter: the only one that handles this graph today."""
    args = (
        torch.from_numpy(case.input_ids),
        torch.from_numpy(case.style),
        torch.from_numpy(case.speed),
    )
    with torch.no_grad():
        torch.onnx.export(
            wrapper,
            args,
            str(path),
            input_names=INPUT_NAMES,
            output_names=["audio"],
            dynamic_axes=DYNAMIC_AXES,
            opset_version=OPSET,
            do_constant_folding=True,
            dynamo=False,
        )
    onnx.checker.check_model(str(path))
    print(f"[convert] exported {path.name} ({path.stat().st_size / 1e6:.0f} MB)")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--revision", default="main")
    ap.add_argument("--voices", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    (out / "voices").mkdir(parents=True, exist_ok=True)
    manifest = {"source_repo": REPO, "revision": a.revision, "inputs": {}, "outputs": {}}

    # --- 1. fetch the author's original files -------------------------------
    cfg_path = hf_hub_download(REPO, "config.json", revision=a.revision)
    pth_path = hf_hub_download(REPO, "kokoro-v1_0.pth", revision=a.revision)
    manifest["inputs"]["config.json"] = sha256(cfg_path)
    manifest["inputs"]["kokoro-v1_0.pth"] = sha256(pth_path)
    print(f"[convert] weights sha256 {manifest['inputs']['kokoro-v1_0.pth']}")

    vocab = json.loads(pathlib.Path(cfg_path).read_text(encoding="utf-8"))["vocab"]
    (out / "vocab.json").write_text(json.dumps(vocab, ensure_ascii=False, indent=0), encoding="utf-8")

    # --- 2. voice packs -> numpy --------------------------------------------
    packs = {}
    for name in a.voices:
        p = hf_hub_download(REPO, f"voices/{name}.pt", revision=a.revision)
        manifest["inputs"][f"voices/{name}.pt"] = sha256(p)
        arr = torch.load(p, map_location="cpu", weights_only=True).numpy().astype(np.float32)
        assert arr.shape == (510, 1, 256), f"{name}: unexpected shape {arr.shape}"
        np.save(out / "voices" / f"{name}.npy", arr)
        packs[name] = arr
        print(f"[convert] voice {name} {arr.shape}")

    # --- 3. load the author's architecture and make it exportable -----------
    # disable_complex=True swaps the complex-valued STFT for a real-valued one
    # that the ONNX exporter understands; output is numerically equivalent.
    model = KModel(repo_id=REPO, config=cfg_path, model=pth_path, disable_complex=True).eval()
    patch_for_export(model)
    wrapper = Exportable(model).eval()
    run_torch = torch_runner(wrapper)

    pack = packs[a.voices[0]]
    trace_case = make_case("trace", TRACE_PHONEMES, vocab, pack)
    cases = [make_case(k, v, vocab, pack) for k, v in CHECK_PHONEMES.items()]
    check_lengths = {c.n_tokens for c in cases}
    assert trace_case.n_tokens not in check_lengths, (
        f"trace length {trace_case.n_tokens} must differ from check lengths "
        f"{sorted(check_lengths)} or a baked-in length could pass unnoticed"
    )
    print(
        f"[convert] trace tokens={trace_case.n_tokens} "
        f"check tokens={sorted(check_lengths)}"
    )

    # --- 4. show the reader that the model is stochastic ---------------------
    first, second = run_torch(trace_case), run_torch(trace_case)
    print(
        "[convert] torch-vs-torch on identical input: "
        f"max|diff|={float(np.max(np.abs(first - second))):.2e} "
        "(random phase + excitation noise; this is the model, not a bug)"
    )

    # --- 5. export the shipping model ---------------------------------------
    # Exported under a temporary name; only a graph that clears every gate is
    # renamed to kokoro.onnx, so nothing half-verified can ever be picked up.
    onnx_path = out / "kokoro.onnx"
    candidate = out / "kokoro.onnx.unverified"
    export(wrapper, trace_case, candidate)

    try:
        # The model's own spread sets the bar for both spectral gates.
        floors = verify.measure_floors(run_torch, cases)

        with tempfile.TemporaryDirectory() as tmp:
            # --- Gate A1: strict parity on the front half. The decoder (the
            # vocoder) is temporarily replaced by "return my inputs", so the
            # exported twin yields asr / F0 / energy instead of audio.
            decoder_forward = model.decoder.forward
            model.decoder.forward = lambda asr, f0, energy, style: torch.cat(
                [asr.reshape(-1), f0.reshape(-1), energy.reshape(-1)]
            )
            try:
                front_path = pathlib.Path(tmp) / "kokoro.front.onnx"
                export(wrapper, trace_case, front_path)
                verify.gate_a1_front_parity(run_torch, front_path, cases)
            finally:
                model.decoder.forward = decoder_forward

            # --- Gate A2: the full deterministic twin, judged spectrally.
            restore = make_deterministic()
            try:
                det_path = pathlib.Path(tmp) / "kokoro.det.onnx"
                export(wrapper, trace_case, det_path)
                verify.gate_a2_vocoder_parity(run_torch, det_path, cases, floors)
            finally:
                restore()

        # --- Gate B: the shipping model, noise and all.
        verify.gate_b_distribution(candidate, cases, floors)

        # --- Gate C: what actually ended up in the graph. The graph's sequence
        # length is the token count plus the two boundary tokens.
        n_lstm = sum(1 for m in model.modules() if isinstance(m, torch.nn.LSTM))
        verify.gate_c_structure(candidate, int(trace_case.input_ids.shape[1]), n_lstm)
    except GateFailed as exc:
        candidate.unlink(missing_ok=True)
        sys.exit(f"[convert] FAIL {exc}")
    candidate.replace(onnx_path)

    # --- 6. record the environment so it can be pinned next time -------------
    freeze = subprocess.run(
        [sys.executable, "-m", "pip", "freeze"], capture_output=True, text=True, check=True
    ).stdout
    (out / "convert-freeze.txt").write_text(freeze, encoding="utf-8")

    # --- 7. manifest ---------------------------------------------------------
    for p in sorted(out.rglob("*")):
        if p.is_file() and p.name != "manifest.json":
            manifest["outputs"][str(p.relative_to(out))] = sha256(p)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print("[convert] OK — all gates passed")


if __name__ == "__main__":
    main()
