// The reader of the dump files: see dump.h. MIT.
#include "dump.h"

#include <cstring>
#include <fstream>
#include <iterator>
#include <stdexcept>

namespace {

// A cursor over the file's bytes that throws instead of reading past the end.
class Reader {
public:
	explicit Reader(const std::vector<uint8_t> &bytes) :
			bytes_(bytes) {}

	template <typename T>
	T take() {
		T value;
		take_into(&value, sizeof(T));
		return value;
	}
	void take_into(void *to, uint64_t size) {
		need(size);
		// An empty record is legal, and an empty std::vector has no data(): memcpy takes no null pointer, even for 0 bytes.
		if (size > 0) {
			std::memcpy(to, bytes_.data() + at_, size);
		}
		at_ += size;
	}
	uint64_t left() const {
		return bytes_.size() - at_;
	}

private:
	void need(uint64_t size) const {
		if (size > left()) {
			throw std::runtime_error("the file ends inside a record");
		}
	}
	const std::vector<uint8_t> &bytes_;
	uint64_t at_ = 0;
};

} // namespace

Dump Dump::read(const std::string &path) {
	std::ifstream in(path, std::ios::binary);
	if (!in) {
		throw std::runtime_error("cannot open " + path);
	}
	const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
	return parse(bytes, path);
}

Dump Dump::parse(const std::vector<uint8_t> &bytes, const std::string &path) {
	Reader reader(bytes);
	try {
		char magic[4];
		reader.take_into(magic, sizeof(magic));
		if (std::memcmp(magic, "RTSD", sizeof(magic)) != 0) {
			throw std::runtime_error("not a state dump (the magic is not RTSD)");
		}
		Dump dump;
		dump.format = reader.take<uint32_t>();
		bool known = false;
		for (const uint32_t format : KNOWN_FORMATS) {
			known = known || format == dump.format;
		}
		if (!known) {
			throw std::runtime_error("World.STATE_FORMAT " + std::to_string(dump.format) + " is a layout this harness does not know");
		}
		dump.tick = reader.take<uint32_t>();
		while (reader.left() > 0) {
			Record record;
			record.kind = reader.take<char>();
			const uint16_t name_size = reader.take<uint16_t>();
			std::string name(name_size, '\0');
			reader.take_into(&name[0], name_size);
			record.count = reader.take<uint64_t>();
			const uint64_t unit = record.kind == 'B' ? 1 : (record.kind == 'I' ? 4 : 8);
			if (record.kind != 'S' && record.kind != 'I' && record.kind != 'B') {
				throw std::runtime_error("record " + name + " has an unknown kind");
			}
			if (record.count > reader.left() / unit) {
				throw std::runtime_error("record " + name + " is longer than the file");
			}
			record.payload.resize(record.count * unit);
			reader.take_into(record.payload.data(), record.payload.size());
			dump.records_[name] = std::move(record);
		}
		return dump;
	} catch (const std::runtime_error &error) {
		throw std::runtime_error(path + ": " + error.what());
	}
}

const Dump::Record &Dump::find(const std::string &name, char kind) const {
	const auto found = records_.find(name);
	if (found == records_.end() || found->second.kind != kind) {
		throw std::runtime_error("the dump has no " + std::string(1, kind) + " record named " + name);
	}
	return found->second;
}

int64_t Dump::scalar(const std::string &name) const {
	const Record &record = find(name, 'S');
	if (record.count != 1) {
		throw std::runtime_error("the scalar " + name + " does not hold exactly one value");
	}
	int64_t value = 0;
	std::memcpy(&value, record.payload.data(), sizeof(value));
	return value;
}

std::vector<int32_t> Dump::ints(const std::string &name) const {
	const Record &record = find(name, 'I');
	std::vector<int32_t> values(record.count);
	if (!record.payload.empty()) {
		std::memcpy(values.data(), record.payload.data(), record.payload.size());
	}
	return values;
}

std::vector<uint8_t> Dump::bytes(const std::string &name) const {
	return find(name, 'B').payload;
}
