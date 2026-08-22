"""
Monkeypatches applied to hexgrad's `kokoro` package before the ONNX export.

Build-time only; nothing here reaches the runtime image. Every patch below
exists for a reason, and the reason matters more than the code — read it before
you trust the exported graph.

WHY EACH PATCH EXISTS
---------------------
1. `TextEncoder.forward` / `DurationEncoder.forward` (kokoro/modules.py) wrap
   their LSTMs in `pack_padded_sequence` / `pad_packed_sequence`. We only ever
   run batch size 1, where nothing is padded, so the packing is an identity
   wrapper — but the ONNX exporter turns the packed length into the LSTM's
   `sequence_lens` input, and tracing risks baking the *trace* length into the
   graph as a constant. A graph that silently truncates every sentence to the
   trace length is the worst kind of bug: it exports, it runs, it sounds wrong.
   We replace both forwards with pack-free equivalents. THIS MAKES THE EXPORT
   BATCH-SIZE-1 ONLY, which is all `app/server.py` ever asks for.
   (Gate C in verify.py independently proves no LSTM got a constant
   `sequence_lens`, so this patch is checked rather than trusted.)

2. `AdainResBlk1d.forward` (kokoro/istftnet.py) scales by
   `torch.rsqrt(torch.tensor(2))`. Building a tensor inside forward gives the
   tracer a device-bound integer constant to fold; a plain Python float is the
   same number with none of the ceremony.

3. Weight normalisation is a training-time reparametrisation
   (`weight = g * v/||v||`). Left in place it exports as a live norm/divide
   subgraph recomputed on every inference. kokoro uses the legacy hook-based
   `torch.nn.utils.weight_norm`, so `remove_weight_norm` folds it into the
   plain weight (the parametrize API is tried second, in case upstream
   migrates) — identical maths, smaller and faster graph.

4. ALBERT (the prosody BERT) is asked for eager attention. Transformers'
   SDPA/flash paths export badly (or not at all) under the legacy exporter;
   eager attention is plain matmul + softmax, which opset 17 handles exactly.

5. `AdaIN1d` keeps `affine=True` on its `InstanceNorm1d`. That looks redundant
   next to the learned gamma/beta, but it is the model author's deliberate
   exporter workaround and the trained weights depend on it. LEAVE IT ALONE.

DETERMINISM (make_deterministic)
--------------------------------
Kokoro's vocoder is stochastic BY DESIGN. `SineGen._f02sine` seeds each
harmonic with a random initial phase (`torch.rand`) and `SineGen.forward` adds
excitation noise (`torch.randn_like`). Two PyTorch runs on identical input
therefore differ, and so do two ONNX runs (the exporter emits `RandomNormalLike`
with no seed). Pointwise torch-vs-ONNX comparison of the shipping model is
meaningless — it can only ever measure the noise.

`make_deterministic()` builds a *twin* with both random sites removed, so we can
still demand strict numerical parity from the surrounding 99% of the graph
(everything that actually carries the speech). The twin is exported to a
throwaway file, checked, and deleted; it is never shipped. The shipping model
keeps its noise and is judged distributionally instead (Gate B).

Only `SineGen` needs patching: `SourceModuleHnNSF.forward` also draws
`torch.randn_like(uv)`, but `Generator.forward` discards that return value.
"""
from __future__ import annotations

import math
from typing import Callable

import torch
import torch.nn.functional as F
from torch.nn.utils import parametrize

from kokoro.istftnet import AdainResBlk1d, SineGen
from kokoro.modules import AdaLayerNorm, DurationEncoder, TextEncoder

# 1/sqrt(2), the value torch.rsqrt(torch.tensor(2)) computes at runtime.
_RSQRT2 = 0.7071067811865476


# --- 1. pack-free LSTM wrappers (batch size 1 only) -------------------------
def _text_encoder_forward(self, x, input_lengths, m):
    """kokoro.modules.TextEncoder.forward without pack/pad_packed_sequence.

    `input_lengths` is accepted and ignored: at batch 1 it is always the full
    sequence length, which is exactly what a plain LSTM call assumes. The
    original's trailing `x_pad` re-pad is likewise a no-op here.
    """
    x = self.embedding(x).transpose(1, 2)
    m = m.unsqueeze(1)
    x = x.masked_fill(m, 0.0)
    for c in self.cnn:
        x = c(x)
        x = x.masked_fill(m, 0.0)
    x = x.transpose(1, 2)
    x, _ = self.lstm(x)
    x = x.transpose(-1, -2)
    return x.masked_fill(m, 0.0)


def _duration_encoder_forward(self, x, style, text_lengths, m):
    """kokoro.modules.DurationEncoder.forward without pack/pad_packed_sequence.

    The original also calls `F.dropout(..., training=False)`, which is the
    identity, and re-pads to the mask length, which at batch 1 is a no-op.
    """
    masks = m
    x = x.permute(2, 0, 1)
    s = style.expand(x.shape[0], x.shape[1], -1)
    x = torch.cat([x, s], axis=-1)
    x = x.masked_fill(masks.unsqueeze(-1).transpose(0, 1), 0.0)
    x = x.transpose(0, 1).transpose(-1, -2)
    for block in self.lstms:
        if isinstance(block, AdaLayerNorm):
            x = block(x.transpose(-1, -2), style).transpose(-1, -2)
            x = torch.cat([x, s.permute(1, 2, 0)], axis=1)
            x = x.masked_fill(masks.unsqueeze(-1).transpose(-1, -2), 0.0)
        else:
            x = x.transpose(-1, -2)
            x, _ = block(x)
            x = x.transpose(-1, -2)
    return x.transpose(-1, -2)


# --- 2. constant instead of a traced tensor ---------------------------------
def _adain_resblk_forward(self, x, s):
    return (self._residual(x, s) + self._shortcut(x)) * _RSQRT2


# --- 3./4. graph hygiene ----------------------------------------------------
def _strip_weight_norm(model: torch.nn.Module) -> int:
    # kokoro uses the legacy hook-based `torch.nn.utils.weight_norm` (the build
    # log says so: "WeightNorm.apply ... is deprecated"). Try that API first,
    # then the newer parametrize API in case upstream migrates.
    removed = 0
    for module in model.modules():
        for remover in (torch.nn.utils.remove_weight_norm, _remove_parametrized_weight):
            try:
                remover(module)
                removed += 1
                break
            except (ValueError, AttributeError, RuntimeError, KeyError):
                pass  # module simply is not weight-normalised this way
    return removed


def _remove_parametrized_weight(module: torch.nn.Module) -> None:
    parametrize.remove_parametrizations(module, "weight")


def _use_eager_attention(bert: torch.nn.Module) -> None:
    bert.config._attn_implementation = "eager"
    setter = getattr(bert, "set_attn_implementation", None)
    if callable(setter):
        setter("eager")
    # transformers <= 4.5x binds ALBERT's attention class in AlbertLayer.__init__
    # (ALBERT_ATTENTION_CLASSES[config._attn_implementation]), so changing the
    # config after construction is too late. Newer versions dispatch at forward
    # time and no longer define AlbertSdpaAttention, in which case the config
    # change above is sufficient.
    try:
        from transformers.models.albert.modeling_albert import (
            AlbertAttention, AlbertSdpaAttention,
        )
    except ImportError:
        return
    AlbertSdpaAttention.forward = AlbertAttention.forward
    print("[patch] transformers binds attention at construction; SDPA forward rerouted to eager")


def patch_for_export(model: torch.nn.Module) -> None:
    """Apply every export-safety patch. Call once, before tracing."""
    TextEncoder.forward = _text_encoder_forward
    DurationEncoder.forward = _duration_encoder_forward
    AdainResBlk1d.forward = _adain_resblk_forward
    _use_eager_attention(model.bert)
    removed = _strip_weight_norm(model)
    assert removed > 0, "no weight_norm was removed — patch 3 did nothing; check torch API"
    print("[patch] pack-free LSTM wrappers installed (batch size 1 only)")
    print(f"[patch] rsqrt(2) -> {_RSQRT2}, eager ALBERT attention")
    print(f"[patch] weight_norm folded into {removed} modules")


# --- determinism twin -------------------------------------------------------
def _f02sine_det(self, f0_values):
    """SineGen._f02sine with the random initial phase removed.

    `flag_for_pulse` is False for the vocoder's SineGen, so only the non-pulse
    branch of the original is reproduced here.
    """
    rad = (f0_values / self.sampling_rate) % 1
    rad = F.interpolate(
        rad.transpose(1, 2), scale_factor=1 / self.upsample_scale, mode="linear"
    ).transpose(1, 2)
    phase = torch.cumsum(rad, dim=1) * 2 * math.pi
    phase = F.interpolate(
        phase.transpose(1, 2) * self.upsample_scale,
        scale_factor=self.upsample_scale,
        mode="linear",
    ).transpose(1, 2)
    return torch.sin(phase)


def _sinegen_forward_det(self, f0):
    """SineGen.forward with the additive excitation noise removed."""
    harmonics = torch.arange(
        1, self.harmonic_num + 2, dtype=f0.dtype, device=f0.device
    ).view(1, 1, -1)
    sine_waves = self._f02sine(f0 * harmonics) * self.sine_amp
    uv = self._f02uv(f0)
    return sine_waves * uv, uv, torch.zeros_like(sine_waves)


def make_deterministic() -> Callable[[], None]:
    """Strip both random sites from SineGen. Returns a restore callable.

    Used only to build the throwaway parity twin (Gate A). The caller MUST
    restore before judging the shipping model, whose noise is intentional.
    """
    original_f02sine, original_forward = SineGen._f02sine, SineGen.forward
    SineGen._f02sine = _f02sine_det
    SineGen.forward = _sinegen_forward_det

    def restore() -> None:
        SineGen._f02sine = original_f02sine
        SineGen.forward = original_forward

    return restore
