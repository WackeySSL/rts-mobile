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
// Known blind spot: the sanitizers see core/ only. An Object* taken from a Variant that died, or memory read inside
// the engine, is bind/'s class of bug (ADR 0013 section 10, row P57), and the harness has no Godot to show it.
#include <algorithm>
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
