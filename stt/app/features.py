"""
Audio -> log-mel features, matching NeMo's FilterbankFeatures at inference.

Every acoustic constant comes from config.json; the mel basis and the window are
NeMo's own tensors (mel_basis.npy, window.npy), not recomputed here.
"""
import numpy as np


class LogMel:
    def __init__(self, cfg: dict, mel_basis: np.ndarray, window: np.ndarray):
        c = cfg["features"]
        self.n_fft, self.hop, self.pad_mode = c["n_fft"], c["hop_length"], c["pad_mode"]
        self.preemph, self.power, self.guard = c["preemph"], c["mag_power"], c["log_guard"]
        self.normalize = c["normalize"]
        left = (self.n_fft - len(window)) // 2          # torch.stft centres a short window
        self.window = np.pad(window, (left, self.n_fft - len(window) - left)).astype(np.float32)
        self.basis = mel_basis.reshape(-1, self.n_fft // 2 + 1).astype(np.float32)

    def __call__(self, audio: np.ndarray) -> tuple[np.ndarray, int]:
        """float32 mono in [-1, 1] -> ((1, n_mels, n + 1) float32, n valid frames)."""
        x = np.asarray(audio, dtype=np.float32)
        n = len(x) // self.hop                          # NeMo get_seq_len: the centred STFT's last frame is not valid
        if n < 2:
            raise ValueError("audio too short")
        if self.preemph:
            x = np.concatenate([x[:1], x[1:] - self.preemph * x[:-1]])
        x = np.pad(x, self.n_fft // 2, mode=self.pad_mode)
        frames = np.lib.stride_tricks.sliding_window_view(x, self.n_fft)[:: self.hop]
        spec = np.abs(np.fft.rfft(frames * self.window, axis=-1)) ** self.power
        mel = np.log(self.basis @ spec.T + self.guard)
        if self.normalize == "per_feature":
            # NeMo: statistics over the valid frames only, unbiased std, +1e-5 after the sqrt
            valid = mel[:, :n]
            mel = (mel - valid.mean(1, keepdims=True)) / (valid.std(1, ddof=1, keepdims=True) + 1e-5)
        mel[:, n:] = 0.0                                # NeMo pad_value
        return mel[None].astype(np.float32), n
