"""
Silero VAD (MIT, snakers4/silero-vad) over onnxruntime: trims silence and says
when there is no speech at all, so the recogniser never runs on an empty clip.
"""
import numpy as np
import onnxruntime as ort

SAMPLE_RATE = 16_000
CHUNK = 512             # samples per VAD step at 16 kHz
CONTEXT = 64            # tail of the previous chunk the model expects in front
THRESHOLD = 0.5
PAD = SAMPLE_RATE * 200 // 1000


class Vad:
    def __init__(self, path):
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        self.session = ort.InferenceSession(str(path), opts, providers=["CPUExecutionProvider"])

    def speech(self, audio: np.ndarray) -> np.ndarray | None:
        """The speech-bounded slice of `audio` (+200 ms each side), or None."""
        x = np.pad(np.asarray(audio, dtype=np.float32), (0, -len(audio) % CHUNK))
        # Input names and the (2, 1, 128) state are Silero v5's, the tag pinned in stt/Dockerfile.
        state = np.zeros((2, 1, 128), dtype=np.float32)
        context = np.zeros(CONTEXT, dtype=np.float32)
        sr = np.array(SAMPLE_RATE, dtype=np.int64)
        hits = []
        for start in range(0, len(x), CHUNK):
            chunk = x[start:start + CHUNK]
            prob, state = self.session.run(
                None, {"input": np.concatenate([context, chunk])[None], "state": state, "sr": sr}
            )
            context = chunk[-CONTEXT:]
            if float(prob.reshape(-1)[0]) > THRESHOLD:
                hits.append(start)
        if not hits:
            return None
        return audio[max(0, hits[0] - PAD): hits[-1] + CHUNK + PAD]
