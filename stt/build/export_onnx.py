"""
Throwaway build-time script: convert NVIDIA's Parakeet TDT 0.6B v2 to ONNX.

Runs ONLY inside the `convert` stage of stt/Dockerfile. It downloads the original
.nemo checkpoint from NVIDIA's Hugging Face repo, restores it with NVIDIA's own
NeMo, exports encoder / decoder / joiner with NeMo's own exporter (the recipe
sherpa-onnx publishes, Apache-2.0), quantises them to int8 with onnxruntime, and
refuses to hand anything to the runtime image unless every gate in verify.py
passes. Candidates are written as *.unverified and renamed only after G0-G4;
G5 then reloads --out as the container will. Any failure deletes every file in
--out. Only int8 ships: if it misses the accuracy bar the build fails.

No model-derived constant is hardcoded in app/: every one the runtime needs is
read off the restored model into config.json, and the mel filterbank and STFT
window are NeMo's own tensors, saved as-is.

Outputs (in --out):
  {encoder,decoder,joiner}.int8.onnx   the model
  config.json        features, TDT durations, decoder state shape, ONNX io, file names
  vocab.txt          sentencepiece pieces in id order; blank = vocab_size, not listed
  mel_basis.npy      NeMo's mel filterbank, (n_mels, n_fft // 2 + 1)
  window.npy         NeMo's STFT window, (win_length,)
  silero_vad.onnx    Silero VAD, as pinned by sha256 in the deps stage
  convert-freeze.txt `pip freeze` of this stage, so the versions can be pinned
  manifest.json      SHA-256 of every input and output, resolved HF commit, versions,
                     export settings; written only after every gate has passed
"""
from __future__ import annotations

import argparse
import gc
import hashlib
import importlib.metadata
import json
import pathlib
import re
import shutil
import subprocess
import sys

import numpy as np
import torch
from huggingface_hub import hf_hub_download
from nemo.collections.asr.models import ASRModel
from onnxruntime.quantization import QuantType, quantize_dynamic

import server
import verify
from decode import Transducer
from features import LogMel
from vad import Vad
from verify import GateFailed

REPO = "nvidia/parakeet-tdt-0.6b-v2"
NEMO_FILE = "parakeet-tdt-0.6b-v2.nemo"
OPSET = 17
PARTS = ("encoder", "decoder", "joiner")
QUANT = {"encoder": QuantType.QUInt8, "decoder": QuantType.QInt8, "joiner": QuantType.QInt8}


def sha256(path: str | pathlib.Path) -> str:
    """Hex SHA-256 of a file, read in 1 MiB chunks."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def runtime_config(model: ASRModel) -> dict:
    """Everything app/ needs, read off the restored model."""
    fz = model.preprocessor.featurizer
    pre = model.cfg.preprocessor
    # What NeMo's own transcribe() sets, so G1 compares like with like.
    fz.dither, fz.pad_to = 0.0, 0
    assert fz.pad_to == 0, "app/features.py does not pad to a multiple of frames"
    assert fz.stft_pad_amount is None, "exact_pad=True framing is not implemented in app/features.py"
    assert fz.log and fz.log_zero_guard_type == "add", "app/features.py implements log(x + guard) only"
    assert getattr(fz, "frame_splicing", 1) == 1, "frame splicing is not implemented in app/features.py"
    sample_rate, hop = int(pre.sample_rate), int(fz.hop_length)
    subsampling = int(model.cfg.encoder.subsampling_factor)
    return {
        "sample_rate": sample_rate,
        "features": {
            "n_fft": int(fz.n_fft), "win_length": int(fz.win_length), "hop_length": hop,
            "n_mels": int(fz.fb.shape[-2]),
            "preemph": float(fz.preemph or 0.0), "mag_power": float(fz.mag_power),
            "log_guard": float(fz.log_zero_guard_value_fn(torch.zeros(1))),
            "normalize": str(fz.normalize),
            # torch.stft(center=True, pad_mode="constant") inside FilterbankFeatures
            "pad_mode": "constant",
        },
        "vocab_size": len(model.joint.vocabulary),
        "blank_id": len(model.joint.vocabulary),
        "durations": [int(d) for d in model.cfg.model_defaults.tdt_durations],
        "max_symbols_per_step": int(model.cfg.decoding.greedy.get("max_symbols", 10)),
        "pred_rnn_layers": int(model.decoder.pred_rnn_layers),
        "pred_hidden": int(model.decoder.pred_hidden),
        "enc_dim": int(model.cfg.encoder.d_model),
        "subsampling_factor": subsampling,
        "frame_s": hop * subsampling / sample_rate,
    }


def nemo_reference(model: ASRModel, audio: np.ndarray, fixture: pathlib.Path) -> dict:
    """NeMo's own features, encoder output and transcribe() text for the fixture."""
    with torch.no_grad():
        feats, feat_len = model.preprocessor(
            input_signal=torch.from_numpy(audio)[None], length=torch.tensor([len(audio)])
        )
        enc, enc_len = model.encoder(audio_signal=feats, length=feat_len)
    out = model.transcribe([str(fixture)], batch_size=1)
    if isinstance(out, tuple):          # some NeMo versions return (best, all)
        out = out[0]
    return {
        "features": feats[:, :, : int(feat_len[0])].numpy(),
        "encoder": enc[:, :, : int(enc_len[0])].numpy(),
        "text": getattr(out[0], "text", out[0]),
    }


def main() -> None:
    """Fetch, export, quantise and gate the model into --out; a gate failure empties it."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--revision", default="main")
    ap.add_argument("--weights-sha256", default="")
    ap.add_argument("--fixture", required=True)
    ap.add_argument("--vad", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out, fixture, vad_path = pathlib.Path(a.out), pathlib.Path(a.fixture), pathlib.Path(a.vad)
    fp32_dir = pathlib.Path("fp32").resolve()
    out.mkdir(parents=True, exist_ok=True)
    fp32_dir.mkdir(exist_ok=True)
    manifest = {"source_repo": REPO, "revision": a.revision, "inputs": {}, "outputs": {}}

    # --- 1. fetch NVIDIA's original checkpoint -------------------------------
    nemo_path = hf_hub_download(REPO, NEMO_FILE, revision=a.revision)
    manifest["inputs"][NEMO_FILE] = sha256(nemo_path)
    manifest["inputs"]["fixture.wav"] = sha256(fixture)
    manifest["inputs"]["silero_vad.onnx"] = sha256(vad_path)
    snapshot = pathlib.Path(nemo_path).parent      # hub cache: .../snapshots/<commit>/<file>
    hub = snapshot.parent.name == "snapshots" and re.fullmatch(r"[0-9a-f]{40}", snapshot.name)
    commit = snapshot.name if hub else None
    manifest["resolved_commit"] = commit
    got = manifest["inputs"][NEMO_FILE]
    print(f"[convert] weights sha256 {got} commit {commit}")
    if a.weights_sha256 and got != a.weights_sha256:
        # The .nemo is a pickle: refuse it before restore_from can unpickle anything.
        sys.exit(f"[convert] FAIL weights sha256 {got}, PARAKEET_SHA256 expects {a.weights_sha256}")
    if not a.weights_sha256:
        print(f"[convert] weights sha256 NOT enforced: pin PARAKEET_REVISION={commit} PARAKEET_SHA256={got}")

    # --- 2. restore with NeMo; dump what the runtime needs -------------------
    model = ASRModel.restore_from(nemo_path, map_location=torch.device("cpu")).eval()
    cfg = runtime_config(model)
    vocab = [str(p) for p in model.joint.vocabulary]
    assert not any("\n" in p for p in vocab), "vocab.txt is one piece per line"
    mel_basis = model.preprocessor.featurizer.fb.detach().cpu().numpy().reshape(cfg["features"]["n_mels"], -1)
    window = model.preprocessor.featurizer.window.detach().cpu().numpy()
    (out / "vocab.txt").write_text("\n".join(vocab) + "\n", encoding="utf-8")
    np.save(out / "mel_basis.npy", mel_basis.astype(np.float32))
    np.save(out / "window.npy", window.astype(np.float32))
    print(f"[convert] vocab={len(vocab)} durations={cfg['durations']} mel_basis={mel_basis.shape} "
          f"window={window.shape} features={cfg['features']}")

    # --- 3. NeMo's own answers, before export can touch the model ------------
    audio = server.read_wav(fixture.read_bytes())
    ref = nemo_reference(model, audio, fixture)
    print(f"[convert] fixture {len(audio) / cfg['sample_rate']:.2f} s, NeMo says {ref['text']!r}")

    # --- 4. export fp32 (NeMo's exporter, as the sherpa-onnx recipe), free torch
    for part, module in zip(PARTS, (model.encoder, model.decoder, model.joint)):
        module.export(str(fp32_dir / f"{part}.onnx"), onnx_opset_version=OPSET)
        print(f"[convert] exported {part}.onnx")
    del model
    gc.collect()

    # --- 5. dynamic int8, encoder QUInt8 and the rest QInt8 as the recipe does
    fp32_paths = {p: fp32_dir / f"{p}.onnx" for p in PARTS}
    candidates = {p: out / f"{p}.int8.onnx.unverified" for p in PARTS}
    for part in PARTS:
        quantize_dynamic(
            model_input=str(fp32_paths[part]), model_output=str(candidates[part]),
            weight_type=QUANT[part],
        )
        print(f"[convert] quantised {part} ({candidates[part].stat().st_size / 1e6:.0f} MB)")

    # --- 6. gates on the candidates, then on --out as the container loads it
    mel = LogMel(cfg, mel_basis, window)
    vad = Vad(vad_path)
    try:
        fp32 = Transducer(fp32_paths, cfg, vocab)
        cfg["io"] = {p: verify.describe(s) for p, s in zip(PARTS, (fp32.encoder, fp32.decoder, fp32.joiner))}
        int8 = verify.gate_g0_structure(candidates, cfg, vocab)
        verify.gate_g1_parity(ref, fp32, int8, mel, audio)
        full_text = verify.gate_g2_wer(vad, mel, int8, audio, ref["text"])
        verify.gate_g3_silence(vad, mel, int8, audio)
        verify.gate_g4_latency(vad, mel, {"int8": int8, "fp32": fp32}, audio)
        del fp32, int8
        gc.collect()

        cfg["files"] = {p: f"{p}.int8.onnx" for p in PARTS}
        for part in PARTS:
            candidates[part].replace(out / cfg["files"][part])
        shutil.copyfile(vad_path, out / "silero_vad.onnx")
        (out / "config.json").write_text(json.dumps(cfg, indent=2), encoding="utf-8")
        verify.gate_g5_artefact(out, audio, full_text)
        verify.gate_g6_http()
    except GateFailed as exc:
        for path in out.iterdir():
            if path.is_file():
                path.unlink()
        sys.exit(f"[convert] FAIL {exc}")

    # --- 7. record the environment so it can be pinned next time -------------
    freeze = subprocess.run(
        [sys.executable, "-m", "pip", "freeze"], capture_output=True, text=True, check=True
    ).stdout
    (out / "convert-freeze.txt").write_text(freeze, encoding="utf-8")

    # --- 8. manifest ---------------------------------------------------------
    manifest["versions"] = {
        p: importlib.metadata.version(p) for p in ("torch", "nemo_toolkit", "onnx", "onnxruntime", "numpy")
    }
    manifest["export"] = {
        "opset": OPSET, "precision": "int8", "quantization": {p: QUANT[p].name for p in PARTS},
    }
    for p in sorted(out.rglob("*")):
        if p.is_file() and p.name != "manifest.json":
            manifest["outputs"][str(p.relative_to(out))] = sha256(p)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print("[convert] OK — all gates passed, shipping int8")


if __name__ == "__main__":
    main()
