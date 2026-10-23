# Terrain history capture - 2026-10-23

The native history check applies 2,048 distributed 2.5 m excavations in a
2,000 m square, sampling at 0/64/256/1,024/2,048. It verifies exact archive
restore at every checkpoint. See retained runs and source hashes. This is a
short CPU/data check, not rendered mining, disk publication, full-world save,
selective residency, thermal headroom or endurance qualification.

At 6,612 edited pages the terrain payload is 81,274,752 bytes. The initial
legacy capture measured 211.652 ms; the paired run before reservation measured
196.595 ms legacy / 128.019 ms median CRC capture. Reserving the known output
size once measured 146.509 ms legacy / 70.083 ms median CRC capture, with
104.534 / 44.197 ms restore. Legacy capture is one sample, CRC is three warm
samples, in a fixed order; these are diagnostic observations, not unbiased
benchmark estimates. Recent edit median/p95 were 0.457/1.097 ms at that point;
control queries stayed around 0.02 ms. Do not infer visible interaction latency
from native arithmetic alone.

Production terrain saves now request format 3 (CRC32C, reflected Castagnoli
polynomial, initial/final inversion). x86_64 Clang builds select the hardware
instruction only after CPUID SSE4.2 admission; the portable implementation has
exact parity across alignments and tails. Default native command 4 still writes
format 2; command 4 with option 3 explicitly requests format 3. Formats 1 and 2
remain readable. Format 3 changes no page payload, material, seed, generator,
revision or edit semantics. It requires the updated native reader; an older
binary cannot open a format 3 save. Compound SHA-256 framing remains unchanged.
CRC32C is accidental-corruption detection, not a security signature.

The standalone native probe verifies the published CRC32C golden vector,
portable/hardware equivalence, actual edited pages, all three archive formats,
bit flips/truncation/semantic corruption rejecting atomically, command framing,
and allocation denial. The real backend test migrates a raw format 2 save,
retains its exact backup, writes a compound format 3 archive, and opens it in a
fresh worker with identical terrain and generator 19. Async publication/barrier
checks and legacy generator checks pass. The first backend harness failed:
it wrote the fixture without explicitly closing its file before starting the
reader. The corrected test closes it before admission; both logs are retained.

Still required in this rewrite: terrain regional checkpoints, selective paging,
bounded residency and recovery, dirty-region-only publication, combined save
cost under history, and the failed first-visible mining-arrival gate. The
16,384-page resident limit and monolithic terrain allocation are unchanged.
Return immediately to these storage requirements after this capture change;
closure requires edited travel/capacity, recovery, exact save/reopen, retained
distant edits and rendered latency evidence, not this checksum test.

The broader world_persistence test was rerun on this build (075205102867Z).
It reproduces the two historical failures: shutdown of a pending lake definition
is rejected as an invalid addon capture, and deleted lake IDs can be reused.
Ordinary combined save/reopen, unknown addon retention, legacy backup migration
and malformed addon protection pass. These two failures remain open; investigate
provider capture/drain and ID cursor persistence before broad persistence closure.
