import Foundation
import Testing
@testable import PardonKit

@Suite struct VoicesTests {
    @Test func parsing() {
        func parse(_ s: String) -> [String] { parseVoices(Data(s.utf8)) }
        check("voices: valid list", parse(#"["am_adam","bf_emma","bm_fable"]"#) == ["am_adam", "bf_emma", "bm_fable"])
        check("voices: empty array", parse("[]") == [])
        check("voices: an object is not a list", parse(#"{"voices": ["bf_emma"]}"#) == [])
        check("voices: a bare string is not a list", parse(#""bf_emma""#) == [])
        check("voices: garbage", parse("not json") == [] && parseVoices(Data()) == [])
        check("voices: mixed junk keeps only valid ids", parse(#"["bf_emma", 3, null, "$(id)", "BF_X", "bf_emma; rm", ["am_adam"], "am_adam"]"#)
              == ["bf_emma", "am_adam"])
        check("voices: repeats dropped", parse(#"["bf_emma","bf_emma","am_adam"]"#) == ["bf_emma", "am_adam"])
        check("constants: maxVoicesBytes is 16 KB", maxVoicesBytes == 16_384)
        let big = "[" + Array(repeating: #""bf_emma""#, count: 2000).joined(separator: ",") + "]"
        check("voices: oversized reply refused", Data(big.utf8).count > maxVoicesBytes && parse(big) == [])
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        let many: [String] = (0..<150).map { (i: Int) -> String in "zz_" + String([alphabet[i / 26], alphabet[i % 26]]) }
        let quoted: [String] = many.map { (id: String) -> String in "\"" + id + "\"" }
        let manyJSON = "[" + quoted.joined(separator: ",") + "]"
        check("voices: at most the first 100 valid ids", maxVoices == 100 && Data(manyJSON.utf8).count <= maxVoicesBytes
              && parse(manyJSON) == Array(many.prefix(100)))
        let withJunk = "[\"x\"," + quoted.prefix(100).joined(separator: ",") + "]"
        check("voices: the cap counts valid ids only", parse(withJunk) == Array(many.prefix(100)))
    }

    @Test func names() {
        func names(_ ids: [String]) -> [String] { voiceNames(ids).map { $0.name } }
        check("names: female", names(["bf_emma"]) == ["Emma (Female)"])
        check("names: male", names(["bm_fable"]) == ["Fable (Male)"])
        check("names: ids kept in order", voiceNames(["bm_fable", "af_bella"]).map { $0.id } == ["bm_fable", "af_bella"])
        check("names: unknown gender shows the raw id", names(["bx_emma", "af_bella"]) == ["bx_emma", "Bella (Female)"])
        check("names: collision shows the accent", names(["af_emma", "bf_emma", "bm_fable"])
              == ["Emma (American, Female)", "Emma (British, Female)", "Fable (Male)"])
        check("names: same name, other gender, no collision", names(["af_sky", "am_sky"]) == ["Sky (Female)", "Sky (Male)"])
        check("names: collision with an unknown accent shows the raw id", names(["zf_emma", "bf_emma"]) == ["zf_emma", "Emma (British, Female)"])
        check("names: unknown gender ids never collide into accents", names(["ax_emma", "bx_emma"]) == ["ax_emma", "bx_emma"])
        check("names: an invalid id passes through", names(["x", ""]) == ["x", ""])
        check("names: empty list", voiceNames([]).isEmpty)
    }
}
