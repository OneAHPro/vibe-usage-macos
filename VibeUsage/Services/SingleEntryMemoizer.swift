final class SingleEntryMemoizer<Key: Equatable, Value> {
    private var cached: (key: Key, value: Value)?

    func value(for key: Key, make: () -> Value) -> Value {
        if let cached, cached.key == key {
            return cached.value
        }

        let value = make()
        cached = (key, value)
        return value
    }

    func removeAll() {
        cached = nil
    }
}
