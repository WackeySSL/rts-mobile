// The sanitizer harness (ADR 0013 section 10, plan P57, qa-engineer): core/ compiled with no Godot header under
// AddressSanitizer and UBSan, run on the states that tests/sim/native/sanitizer/dump_states.gd dumps from the seed-42
// arena and on crafted cases. Build and run: scripts/ci/run-sanitizer-harness.sh (g++ -fsanitize=address,undefined
// -fno-sanitize-recover=all, no -fwrapv, the sanitizer job of .github/workflows/ci.yml). CI-only: it is the one test
// that is neither gdUnit4 nor under tests/. A later kernel adds its cases file and one pointer to KERNELS (cases.h).
//
// Usage: sanitizer_harness <dump file or folder of state_*.bin>...
// Exit:  0 ok; 1 a finding of the harness itself (a run that did not finish, or did nothing); 2 a bad argument, no
//        dump, an unreadable dump or a World.STATE_FORMAT it does not know. A sanitizer report aborts the process with
//        the sanitizer's own non-zero exit code.
// Known blind spots (ADR 0013 section 10, row P57): the sanitizers see core/ only. An Object* taken from a Variant that
// died, or memory read inside the engine, is bind/'s class of bug, and the harness has no Godot to show it. Next,
// ArrayView clamps an index outside its window (reads 0, writes nothing), so a lone index bug in core/ is a wrong
// answer that only the lockstep suites see and no report; the crafted case with a corrupted queue (flow_cases.cpp)
// is what shows the clamp itself failing. Last, no sanitizer here sees a read of memory that was never written
// (MemorySanitizer needs clang and an instrumented standard library, and the job is g++).
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <iterator>
#include <string>
#include <vector>

#include "cases.h"

namespace {

// One pointer per kernel with a cases file.
const KernelCases *const KERNELS[] = { &FLOW_CASES };

// The dump files of an argument: itself, or the state_*.bin files of a folder in name order.
std::vector<std::string> dump_files(const std::string &argument) {
	namespace fs = std::filesystem;
	std::vector<std::string> files;
	if (fs::is_directory(argument)) {
		for (const fs::directory_entry &entry : fs::directory_iterator(argument)) {
			const std::string name = entry.path().filename().string();
			if (name.rfind("state_", 0) == 0 && entry.path().extension() == ".bin") {
				files.push_back(entry.path().string());
			}
		}
		std::sort(files.begin(), files.end());
	} else {
		files.push_back(argument);
	}
	return files;
}

// The reader on a dump built in memory with records of every kind, empty arrays among them (a kernel whose input is
// empty at a dump tick, say an event list, writes one), and on a dump that stops inside a record.
void check_reader() {
	std::vector<uint8_t> bytes = { 'R', 'T', 'S', 'D' };
	const auto put = [&bytes](const void *from, size_t size) {
		const uint8_t *first = static_cast<const uint8_t *>(from);
		bytes.insert(bytes.end(), first, first + size);
	};
	const uint32_t header[] = { KNOWN_FORMATS[0], 7 };
	put(header, sizeof(header));
	const auto record = [&](char kind, const std::string &name, const std::vector<int64_t> &values, size_t unit) {
		const uint16_t name_size = static_cast<uint16_t>(name.size());
		const uint64_t count = values.size();
		put(&kind, 1);
		put(&name_size, sizeof(name_size));
		put(name.data(), name.size());
		put(&count, sizeof(count));
		for (const int64_t value : values) {
			put(&value, unit); // the low bytes of a little-endian int64, like the dump step's
		}
	};
	record('S', "scalar", { 5 }, 8);
	record('I', "no_ints", {}, 4);
	record('B', "no_bytes", {}, 1);
	record('I', "ints", { 1, -2, 3 }, 4);
	record('B', "bytes", { 9 }, 1);
	const Dump dump = Dump::parse(bytes, "in memory");
	if (dump.tick != 7 || dump.scalar("scalar") != 5 || !dump.ints("no_ints").empty() || !dump.bytes("no_bytes").empty() ||
			dump.ints("ints") != std::vector<int32_t>({ 1, -2, 3 }) || dump.bytes("bytes") != std::vector<uint8_t>({ 9 })) {
		throw Finding("the dump reader read a dump built in memory wrongly");
	}
	bytes.pop_back();
	try {
		Dump::parse(bytes, "in memory");
	} catch (const std::runtime_error &) {
		return;
	}
	throw Finding("the dump reader took a dump that stops inside a record");
}

} // namespace

int main(int argc, char **argv) {
	std::vector<std::string> files;
	for (int i = 1; i < argc; i++) {
		const std::vector<std::string> some = dump_files(argv[i]);
		files.insert(files.end(), some.begin(), some.end());
	}
	if (files.empty()) {
		std::fprintf(stderr, "sanitizer_harness: no dump (usage: sanitizer_harness <dump file or folder>...)\n");
		return 2;
	}
	try {
		check_reader();
		std::vector<Tally> on_dumps(std::size(KERNELS)), crafted(std::size(KERNELS));
		for (const std::string &file : files) {
			const Dump dump = Dump::read(file);
			for (size_t kernel = 0; kernel < std::size(KERNELS); kernel++) {
				KERNELS[kernel]->on_dump(dump, on_dumps[kernel]);
			}
		}
		for (size_t kernel = 0; kernel < std::size(KERNELS); kernel++) {
			KERNELS[kernel]->crafted(crafted[kernel]);
			std::printf("sanitizer_harness: %s: %zu dumps, %lld calls settling %lld; crafted, %lld calls settling %lld\n", KERNELS[kernel]->name, files.size(),
					static_cast<long long>(on_dumps[kernel].runs), static_cast<long long>(on_dumps[kernel].work), static_cast<long long>(crafted[kernel].runs),
					static_cast<long long>(crafted[kernel].work));
			// A clean run that did nothing proves nothing.
			if (on_dumps[kernel].work <= 0 || crafted[kernel].work <= 0) {
				throw Finding(std::string(KERNELS[kernel]->name) + ": the cases did no work, so a clean run says nothing");
			}
		}
	} catch (const Finding &finding) {
		std::fprintf(stderr, "sanitizer_harness: FINDING: %s\n", finding.what());
		return 1;
	} catch (const std::exception &error) {
		std::fprintf(stderr, "sanitizer_harness: %s\n", error.what());
		return 2;
	}
	std::printf("sanitizer_harness: OK\n");
	return 0;
}
