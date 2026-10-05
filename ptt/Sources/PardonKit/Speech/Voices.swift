import Foundation

// MARK: - Voices

// Anything but a JSON array of voice ids yields nothing; invalid and repeated ids are dropped, and the menu
// gets at most maxVoices.
func parseVoices(_ data: Data) -> [String] {
    guard data.count <= maxVoicesBytes, let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
    var seen = Set<String>()
    return Array(list.compactMap { $0 as? String }.filter { isVoiceID($0) && seen.insert($0).inserted }.prefix(maxVoices))
}

// Second letter is the gender, first the accent; the accent is shown only to tell two same-named voices apart.
func voiceNames(_ ids: [String]) -> [(id: String, name: String)] {
    func parts(_ id: String) -> (accent: Character, gender: String?, name: String) {
        let chars = Array(id)
        let gender: String? = chars[1] == "f" ? "Female" : chars[1] == "m" ? "Male" : nil
        let name = id.split(separator: "_", maxSplits: 1).last.map(String.init) ?? id
        return (chars[0], gender, name.prefix(1).uppercased() + name.dropFirst())
    }
    func plain(_ id: String) -> String {
        guard isVoiceID(id) else { return id }
        let p = parts(id)
        return p.gender.map { "\(p.name) (\($0))" } ?? id
    }
    let plains = ids.map(plain)
    return zip(ids, plains).map { id, name in
        guard isVoiceID(id), plains.filter({ $0 == name }).count > 1 else { return (id, name) }
        let p = parts(id)
        guard let gender = p.gender else { return (id, name) }
        let accent: String? = p.accent == "a" ? "American" : p.accent == "b" ? "British" : nil
        return (id, accent.map { "\(p.name) (\($0), \(gender))" } ?? id)
    }
}
