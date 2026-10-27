// The reader of the dump files that tests/sim/native/sanitizer/dump_states.gd writes (the format is described
// there): a header with the World.STATE_FORMAT number and the tick, then named records, each a scalar, an int32
// array or a byte array. Plain C++17, no Godot header. MIT.
// Part of the CI-only sanitizer harness (ADR 0013 section 10), which compiles core/ under AddressSanitizer and UBSan.
#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

// The World.STATE_FORMAT numbers whose dump layout this harness reads. read() refuses every other number: a new
// layout adds its number here, with its reader, and never edits what an old number means. 2 (P65, ADR 0016, plan
// exception 10): fog.visible left the state hash; the dump holds the same records as 1 (the kernels still read the
// counts), so 1 stays known. 3 (P70, ADR 0017 section 7, plan exception 10): Phase 3's state joined the hash; the
// dump holds the same records as 1 and 2 (no kernel reads the new state), so both stay known. 4 (P109, ADR 0023
// section 10, plan exception 10): the strike columns joined the hash; the dump holds the same records as 1 to 3 (no
// kernel reads them), so all stay known.
inline constexpr uint32_t KNOWN_FORMATS[] = { 1, 2, 3, 4 };

class Dump {
public:
	// Reads a whole file. Throws std::runtime_error for a missing or short file, a bad magic, a format number
	// that is not in KNOWN_FORMATS or a record that runs past the end of the file.
	static Dump read(const std::string &path);
	// The same for bytes already in memory; `path` only names them in the error text.
	static Dump parse(const std::vector<uint8_t> &bytes, const std::string &path);

	uint32_t format = 0;
	uint32_t tick = 0;

	// A record by name. Each throws std::runtime_error when the dump has no such record of that kind.
	int64_t scalar(const std::string &name) const;
	std::vector<int32_t> ints(const std::string &name) const;
	std::vector<uint8_t> bytes(const std::string &name) const;

private:
	struct Record {
		char kind = 0; // 'S', 'I' or 'B'
		uint64_t count = 0;
		std::vector<uint8_t> payload;
	};
	std::map<std::string, Record> records_;

	const Record &find(const std::string &name, char kind) const;
};
