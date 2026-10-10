# CommandQueue autoload (ADR 0002 section 1). Node-side inbox where input and AI controllers
# submit Commands; the match runner drains it into the sim's ordered per-tick command list.
# API defined in Phase 2.
extends Node
