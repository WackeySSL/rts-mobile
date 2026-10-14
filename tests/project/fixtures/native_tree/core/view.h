// Fixture of test_native_purity.gd: a view in one file (these files are scanned, never built).
class WorldView {
	const int32_t *pos_x;

public:
	int64_t pos_x_at(int64_t row) const { return pos_x[row]; }
};
