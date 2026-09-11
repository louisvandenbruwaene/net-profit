.PHONY: run test smoke soak tutorial audio sim tune shots dist clean

run:
	love .

# Graph algorithms, hand-computed expectations.
test:
	@lua5.4 test/test_graph.lua

# Input layer, driven through the real love callbacks.
smoke:
	@love . --smoke

# Every tutorial step, walked through the real input callbacks.
tutorial:
	@love . --tut

# Peak and RMS of every synthesised sound.
audio:
	@love . --audio

# Plays whole runs to collapse with every screen rendered.
soak:
	@love . --soak

# Balance telemetry: how far does the reference bot survive?
sim:
	@lua5.4 test/sim.lua 40 verbose

# Parameter sweep over the economy.
tune:
	@lua5.4 test/tune.lua

# Screenshots into the love save directory.
shots:
	@love . --shot && echo "written to $$HOME/.local/share/love/augment/"

dist:
	@mkdir -p dist
	@zip -9 -r dist/augment.love main.lua conf.lua src test -x '*.git*' >/dev/null
	@echo "dist/augment.love  ($$(du -h dist/augment.love | cut -f1))"

clean:
	rm -rf dist
