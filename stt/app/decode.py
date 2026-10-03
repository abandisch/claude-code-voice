"""
Token-and-Duration Transducer (TDT) greedy decode over three onnxruntime sessions.

The joiner scores vocab + blank and, separately, how many encoder frames to skip.
Blank is the last token id; it is also the start symbol for the prediction network.
"""
import numpy as np
import onnxruntime as ort

_DTYPE = {"tensor(float)": np.float32, "tensor(int32)": np.int32, "tensor(int64)": np.int64}
_CPU = ["CPUExecutionProvider"]


def feed(session: ort.InferenceSession, *arrays) -> dict:
    # Inputs are bound positionally; gate G0 pins the order.
    return {i.name: np.asarray(a, dtype=_DTYPE[i.type]) for i, a in zip(session.get_inputs(), arrays)}


class Transducer:
    def __init__(self, paths: dict, cfg: dict, vocab: list[str], threads: int = 4):
        enc_opts = ort.SessionOptions()
        enc_opts.intra_op_num_threads = threads
        enc_opts.enable_mem_pattern = False             # input length differs on every request
        step_opts = ort.SessionOptions()
        step_opts.intra_op_num_threads = 1              # one token / one frame per call: too small to split
        self.encoder = ort.InferenceSession(str(paths["encoder"]), enc_opts, providers=_CPU)
        self.decoder, self.joiner = (
            ort.InferenceSession(str(paths[k]), step_opts, providers=_CPU) for k in ("decoder", "joiner")
        )
        self.vocab = vocab
        self.blank = cfg["blank_id"]
        self.durations = cfg["durations"]
        self.max_symbols = cfg["max_symbols_per_step"]
        self.zero_state = np.zeros((cfg["pred_rnn_layers"], 1, cfg["pred_hidden"]), dtype=np.float32)

    def _predict(self, token: int, h: np.ndarray, c: np.ndarray):
        out, _length, h, c = self.decoder.run(None, feed(self.decoder, [[token]], [1], h, c))
        return out, h, c

    def encode(self, features: np.ndarray, n: int) -> np.ndarray:
        enc, enc_len = self.encoder.run(None, feed(self.encoder, features, [n]))
        return np.ascontiguousarray(enc[:, :, : int(enc_len[0])])     # (1, D, T)

    def greedy(self, enc: np.ndarray) -> str:
        h = c = self.zero_state
        dec, h_next, c_next = self._predict(self.blank, h, c)
        tokens = []
        t = emitted = 0
        while t < enc.shape[2]:
            frame = np.ascontiguousarray(enc[:, :, t:t + 1])
            logits = self.joiner.run(None, feed(self.joiner, frame, dec))[0].reshape(-1)
            token = int(np.argmax(logits[: self.blank + 1]))
            skip = self.durations[int(np.argmax(logits[self.blank + 1:]))]
            if token != self.blank:
                tokens.append(token)
                h, c = h_next, c_next
                dec, h_next, c_next = self._predict(token, h, c)
                emitted += 1
            if skip == 0 and (token == self.blank or emitted >= self.max_symbols):
                skip = 1
            if skip:
                t, emitted = t + skip, 0
        return "".join(self.vocab[i] for i in tokens).replace("▁", " ").strip()

    def decode(self, features: np.ndarray, n: int) -> str:
        return self.greedy(self.encode(features, n))
