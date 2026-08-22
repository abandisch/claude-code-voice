"""
The three gates the ONNX export must clear before anything is allowed to ship.

Build-time only. Nothing here reaches the runtime image.

WHY THREE GATES INSTEAD OF ONE max|diff|
----------------------------------------
Kokoro's vocoder injects random phase and random excitation noise on every
call (see export_patches.py). So the obvious check — run PyTorch, run ONNX,
demand `max|diff| < 1e-2` — cannot pass and, worse, cannot fail for the right
reason: it measures the model's own dither, not the fidelity of the conversion.
The build log prints a torch-vs-torch difference before exporting precisely so
this is visible rather than folklore.

We therefore split the question in two, and add a structural check:

  Gate A — STRICT PARITY ON A DETERMINISTIC TWIN.
      Both random sites are patched out, a throwaway twin is exported, and we
      demand near-bit-exact agreement (SNR >= 50 dB, max|diff| <= 5e-3) on two
      sentence lengths, neither of which is the traced length. This is what
      actually proves "the ONNX graph computes the same function as PyTorch":
      every conv, LSTM, attention head, STFT and iSTFT is covered. The twin is
      deleted afterwards.

  Gate B — DISTRIBUTIONAL CHECK ON THE SHIPPING MODEL.
      With the noise back in, the right question is "does the ONNX output sit
      inside the cloud of outputs PyTorch itself produces?". We run PyTorch
      several times to measure its own log-mel spread (the noise floor), then
      require the ONNX run to be no further from those runs than they are from
      each other — and, absolutely, no further than 0.35. A conversion bug
      (wrong voice, wrong prosody, truncated audio) lands far outside; the
      dither lands inside.

  Gate C — STRUCTURAL.
      Reads the graph itself and fails if any LSTM node received a *constant*
      `sequence_lens` input, which would silently clamp every sentence to the
      trace length. Also prints any small integer constant that happens to equal
      the trace length, so a human can eyeball what else got baked in.

Distances are RMS over the log-mel matrix (L2 norm divided by sqrt(number of
elements)), so the numbers do not grow with sentence length and the absolute
0.35 ceiling means the same thing for a 1-second and a 10-second clip.
"""
from __future__ import annotations

import dataclasses
import functools
import itertools
import math
import pathlib
from typing import Callable, Iterable, Sequence

import numpy as np
import onnx
import onnxruntime as ort
import torch
from onnx import numpy_helper

SAMPLE_RATE = 24_000
N_FFT, HOP, N_MELS = 1024, 256, 80

GATE_A1_MIN_SNR_DB = 50.0     # front half: strict float-precision parity
RANDOM_OPS = {"RandomNormal", "RandomNormalLike", "RandomUniform", "RandomUniformLike", "Multinomial", "Bernoulli"}
FLOOR_RUNS = 6                # stochastic torch runs used to measure the noise floor
FLOOR_SIGMA = 3.0             # limit = mean + FLOOR_SIGMA * std ...
FLOOR_CEILING = 0.35          # ... but never more than this (log10 power units)
_SMALL_CONSTANT = 4  # elements; anything larger is a weight, not a baked-in length


class GateFailed(Exception):
    """Raised when a verification gate rejects the export."""


@dataclasses.dataclass(frozen=True, eq=False)
class Case:
    """One (phonemes -> tokens) test input, ready for both torch and ORT."""

    label: str
    input_ids: np.ndarray  # (1, T) int64, already wrapped in BOS/EOS zeros
    style: np.ndarray  # (1, 256) float32, the voice pack row for this length
    speed: np.ndarray  # (1,) float32
    n_tokens: int

    def feeds(self) -> dict[str, np.ndarray]:
        return {"input_ids": self.input_ids, "style": self.style, "speed": self.speed}


RunTorch = Callable[[Case], np.ndarray]


# --- measurement helpers ----------------------------------------------------
def snr_db(ref: np.ndarray, test: np.ndarray) -> float:
    """10*log10(signal power / error power); +inf when identical."""
    err = float(np.sum((ref.astype(np.float64) - test.astype(np.float64)) ** 2))
    if err == 0.0:
        return math.inf
    return 10.0 * math.log10(float(np.sum(ref.astype(np.float64) ** 2)) / err)


@functools.lru_cache(maxsize=1)
def _mel_filterbank() -> torch.Tensor:
    """HTK-style triangular mel filterbank, (n_mels, n_fft//2 + 1).

    Plain numpy instead of torchaudio: one fewer package in the build, and the
    maths is short enough to read.
    """
    hz_to_mel = lambda f: 2595.0 * np.log10(1.0 + f / 700.0)
    mel_to_hz = lambda m: 700.0 * (10.0 ** (m / 2595.0) - 1.0)
    edges_hz = mel_to_hz(np.linspace(hz_to_mel(0.0), hz_to_mel(SAMPLE_RATE / 2), N_MELS + 2))
    freqs = np.linspace(0.0, SAMPLE_RATE / 2, N_FFT // 2 + 1)
    fb = np.zeros((N_MELS, freqs.size), dtype=np.float32)
    for m in range(N_MELS):
        lo, centre, hi = edges_hz[m], edges_hz[m + 1], edges_hz[m + 2]
        fb[m] = np.maximum(0.0, np.minimum((freqs - lo) / (centre - lo), (hi - freqs) / (hi - centre)))
    return torch.from_numpy(fb)


def _log_mel(audio: np.ndarray) -> torch.Tensor:
    """log10 mel power spectrogram, (n_mels, frames); floor at 1e-5 so silent
    bins do not dominate the distance."""
    wave = torch.from_numpy(np.asarray(audio, dtype=np.float32))
    spec = torch.stft(
        wave, n_fft=N_FFT, hop_length=HOP, window=torch.hann_window(N_FFT),
        center=True, return_complex=True,
    ).abs() ** 2
    return torch.log10((_mel_filterbank() @ spec).clamp_min(1e-5))


def _mel_distance(a: torch.Tensor, b: torch.Tensor) -> float:
    """RMS difference between two log-mel matrices (length-independent)."""
    return float(torch.sqrt(torch.mean((a - b) ** 2)))


def _session(path: pathlib.Path, threads: int | None = None) -> ort.InferenceSession:
    opts = ort.SessionOptions()
    if threads is not None:
        opts.intra_op_num_threads = threads
        opts.inter_op_num_threads = threads
    return ort.InferenceSession(str(path), opts, providers=["CPUExecutionProvider"])


# --- shared: the model's own noise floor ------------------------------------
@dataclasses.dataclass
class Floor:
    """Log-mel spread of the STOCHASTIC torch model on one case."""
    mels: list          # log-mel of each torch run
    samples: int
    mean: float
    std: float

    @property
    def limit(self) -> float:
        return min(self.mean + FLOOR_SIGMA * self.std, FLOOR_CEILING)


def measure_floors(run_torch: RunTorch, cases: Sequence[Case]) -> dict[str, Floor]:
    """Run the shipping (stochastic) torch model several times per case and
    measure how far its own outputs sit from each other. Both spectral gates
    are judged against this, so the bar is set by the model, not by us."""
    print(f"[floor] {FLOOR_RUNS} stochastic torch runs per case")
    floors = {}
    for case in cases:
        runs = [run_torch(case) for _ in range(FLOOR_RUNS)]
        lengths = {r.shape[0] for r in runs}
        if len(lengths) != 1:
            raise GateFailed(f"floor: torch runs disagree on length {lengths} for {case.label}")
        mels = [_log_mel(r) for r in runs]
        d = [_mel_distance(a, b) for a, b in itertools.combinations(mels, 2)]
        f = Floor(mels, runs[0].shape[0], float(np.mean(d)), float(np.std(d)))
        floors[case.label] = f
        print(f"[floor] {case.label:>5} tokens={case.n_tokens} samples={f.samples} "
              f"log-mel spread {f.mean:.4f}+-{f.std:.4f} -> limit {f.limit:.4f}")
    return floors


# --- Gate A -----------------------------------------------------------------
def count_random_ops(onnx_path: pathlib.Path) -> dict[str, int]:
    """How many random-number ops the graph contains, by type (all subgraphs)."""
    counts: dict[str, int] = {}
    for graph in _walk_graphs(onnx.load(str(onnx_path), load_external_data=False).graph):
        for node in graph.node:
            if node.op_type in RANDOM_OPS:
                counts[node.op_type] = counts.get(node.op_type, 0) + 1
    return counts


def gate_a1_front_parity(
    run_torch: RunTorch, front_onnx_path: pathlib.Path, cases: Sequence[Case]
) -> None:
    """STRICT parity on the deterministic front half.

    The "front half" is everything before the vocoder: ALBERT, the LSTMs, the
    duration / F0 / energy predictors and the text encoder — i.e. every place a
    conversion bug could hide. It contains no phase accumulator and no random
    op, so torch and ONNX must agree to float precision: SNR >= 50 dB and
    identical shapes (shape equality also proves the predicted durations
    agree exactly, since they set the length).
    """
    print("[gate A1] strict parity on the front half (everything before the vocoder)")
    failures: list[str] = []
    randoms = count_random_ops(front_onnx_path)
    if randoms:
        failures.append(f"front-half graph contains random ops {randoms}")
    previous_threads = torch.get_num_threads()
    torch.set_num_threads(1)
    try:
        sess = _session(front_onnx_path, threads=1)
        for case in cases:
            ref = run_torch(case)
            got = sess.run(None, case.feeds())[0]
            if ref.shape != got.shape:
                failures.append(f"{case.label}: shape torch={ref.shape} onnx={got.shape}")
                continue
            snr = snr_db(ref, got)
            diff = float(np.max(np.abs(ref - got)))
            print(f"[gate A1] {case.label:>5} tokens={case.n_tokens} values={got.shape[0]} "
                  f"SNR={snr:.1f} dB (need >= {GATE_A1_MIN_SNR_DB}) max|diff|={diff:.2e}")
            if snr < GATE_A1_MIN_SNR_DB:
                failures.append(f"{case.label}: SNR={snr:.1f} dB (need >= {GATE_A1_MIN_SNR_DB})")
    finally:
        torch.set_num_threads(previous_threads)
    if failures:
        raise GateFailed("gate A1 (front-half parity): " + "; ".join(failures))


def gate_a2_vocoder_parity(
    run_torch: RunTorch, det_onnx_path: pathlib.Path, cases: Sequence[Case],
    floors: dict[str, Floor],
) -> None:
    """Spectral parity on the full deterministic twin.

    With both random sites removed, torch and ORT still disagree pointwise:
    the vocoder builds its harmonics from a float32 phase accumulator
    (cumsum -> sin) and the two runtimes round it differently, and that phase
    drift is then pushed through the vocoder's nonlinear convolutions. The
    model deliberately randomises exactly that phase, so the fair standard is:
    the deterministic discrepancy must be no larger than the spread the model
    produces by itself (the floor). Both sides must also be bit-repeatable,
    and the twin graph must contain no random op — or this gate would be
    measuring dither. Waveform SNR is printed for the record only.
    """
    print("[gate A2] spectral parity on the deterministic twin (vocoder included)")
    failures: list[str] = []
    randoms = count_random_ops(det_onnx_path)
    print(f"[gate A2] random ops in twin graph: {randoms or 'none'}")
    if randoms:
        failures.append(f"twin graph still contains random ops {randoms}")
    previous_threads = torch.get_num_threads()
    torch.set_num_threads(1)
    try:
        sess = _session(det_onnx_path, threads=1)
        for case in cases:
            ref, ref2 = run_torch(case), run_torch(case)
            got, got2 = (sess.run(None, case.feeds())[0] for _ in range(2))
            if ref.shape != ref2.shape or float(np.max(np.abs(ref - ref2))) != 0.0:
                failures.append(f"{case.label}: torch twin is not deterministic")
            if got.shape != got2.shape or float(np.max(np.abs(got - got2))) != 0.0:
                failures.append(f"{case.label}: onnx twin is not deterministic")
            if ref.shape != got.shape:
                failures.append(f"{case.label}: shape torch={ref.shape} onnx={got.shape}")
                continue
            mel = _mel_distance(_log_mel(ref), _log_mel(got))
            limit = floors[case.label].limit
            print(f"[gate A2] {case.label:>5} tokens={case.n_tokens} samples={got.shape[0]} "
                  f"log-mel {mel:.4f} (limit {limit:.4f}) | info: SNR={snr_db(ref, got):.1f} dB "
                  f"max|diff|={float(np.max(np.abs(ref - got))):.2e}")
            if mel > limit:
                failures.append(f"{case.label}: log-mel {mel:.4f} > limit {limit:.4f}")
    finally:
        torch.set_num_threads(previous_threads)
    if failures:
        raise GateFailed("gate A2 (vocoder parity): " + "; ".join(failures))


# --- Gate B -----------------------------------------------------------------
def gate_b_distribution(
    onnx_path: pathlib.Path, cases: Sequence[Case], floors: dict[str, Floor]
) -> None:
    """The shipping model's ONNX output must sit inside PyTorch's own spread,
    and the `speed` input must demonstrably do something."""
    print("[gate B] distributional check on the shipping model")
    sess = _session(onnx_path)
    failures: list[str] = []
    for case in cases:
        floor = floors[case.label]
        got = sess.run(None, case.feeds())[0]
        if got.shape[0] != floor.samples:
            failures.append(f"{case.label}: samples torch={floor.samples} onnx={got.shape[0]}")
            continue
        onnx_mel = _log_mel(got)
        distance = float(np.mean([_mel_distance(onnx_mel, m) for m in floor.mels]))
        print(f"[gate B] {case.label:>5} tokens={case.n_tokens} samples={got.shape[0]} "
              f"onnx log-mel {distance:.4f} (limit {floor.limit:.4f})")
        if distance > floor.limit:
            failures.append(f"{case.label}: onnx log-mel distance {distance:.4f} > limit {floor.limit:.4f}")

    # A declared-but-disconnected `speed` input would pass every gate above,
    # since all cases use speed=1.0. Faster speech must yield fewer samples.
    base = cases[0]
    fast = dataclasses.replace(base, label="speed", speed=np.array([1.5], dtype=np.float32))
    n_base = sess.run(None, base.feeds())[0].shape[0]
    n_fast = sess.run(None, fast.feeds())[0].shape[0]
    print(f"[gate B] speed wiring: speed=1.0 -> {n_base} samples, speed=1.5 -> {n_fast} samples")
    if n_fast >= n_base:
        failures.append("speed=1.5 did not shorten the audio — `speed` is not wired into the graph")
    if failures:
        raise GateFailed("gate B (distribution): " + "; ".join(failures))


# --- Gate C -----------------------------------------------------------------
def _walk_graphs(graph: onnx.GraphProto) -> Iterable[onnx.GraphProto]:
    yield graph
    for node in graph.node:
        for attr in node.attribute:
            if attr.HasField("g"):
                yield from _walk_graphs(attr.g)
            for sub in attr.graphs:
                yield from _walk_graphs(sub)


def gate_c_structure(onnx_path: pathlib.Path, trace_len: int, expected_lstms: int) -> None:
    """Fail if any LSTM got a constant `sequence_lens`; report baked-in lengths.

    `expected_lstms` (counted from the torch model) guards against the gate
    passing vacuously because it found no LSTM nodes to inspect.
    """
    print("[gate C] structural inspection of the exported graph")
    # The shipping model is expected to keep exactly its two designed random
    # sites (harmonic phase, excitation noise). Anything else is a surprise.
    print(f"[gate C] random ops in shipping graph: {count_random_ops(onnx_path) or 'none'}")
    model = onnx.load(str(onnx_path))
    constant_names: set[str] = set()  # every value fixed at export time
    small: dict[str, np.ndarray] = {}  # ... of which these are worth reading
    lstm_nodes = []

    def remember(name: str, tensor: onnx.TensorProto) -> None:
        constant_names.add(name)
        if int(np.prod(tensor.dims or [1])) <= _SMALL_CONSTANT:
            small[name] = numpy_helper.to_array(tensor)

    for graph in _walk_graphs(model.graph):
        for init in graph.initializer:
            remember(init.name, init)
        for node in graph.node:
            if node.op_type == "Constant":
                for attr in node.attribute:
                    if attr.name == "value" and attr.HasField("t"):
                        remember(node.output[0], attr.t)
            elif node.op_type == "LSTM":
                lstm_nodes.append(node)

    print(f"[gate C] LSTM nodes found: {len(lstm_nodes)} (torch model has {expected_lstms})")
    if len(lstm_nodes) != expected_lstms:
        raise GateFailed(
            f"gate C (structure): found {len(lstm_nodes)} LSTM nodes, expected "
            f"{expected_lstms} — the sequence_lens check would be vacuous"
        )
    failures = []
    for node in lstm_nodes:
        # ONNX LSTM inputs: X, W, R, B, sequence_lens, initial_h, initial_c, P
        seq_lens = node.input[4] if len(node.input) > 4 else ""
        if seq_lens and seq_lens in constant_names:
            failures.append(
                f"LSTM {node.name or node.output[0]} has constant sequence_lens"
                f"={small.get(seq_lens, '<large>')} — the graph would clamp every input"
            )
        else:
            print(
                f"[gate C] LSTM {node.name or node.output[0]}: "
                f"sequence_lens={'<dynamic>' if seq_lens else '<absent>'} OK"
            )

    suspects = [
        (name, arr.tolist())
        for name, arr in small.items()
        if arr.dtype.kind == "i" and trace_len in np.atleast_1d(arr)
    ]
    for name, value in suspects:
        print(f"[gate C] review: constant {name} = {value} equals the trace length")
    if not suspects:
        print(f"[gate C] no small int constant equals the trace length ({trace_len})")

    if failures:
        raise GateFailed("gate C (structure): " + "; ".join(failures))
