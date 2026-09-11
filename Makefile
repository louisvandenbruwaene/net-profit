.PHONY: run test smoke soak tutorial audio shots dist clean

run:
	love .

# Graph algorithms and the contract rules, both headless under lua5.4.
test:
	@lua5.4 test/test_graph.lua
	@lua5.4 test/test_contract.lua

# Input paths, driven through the real love callbacks.
smoke:
	@timeout -k 5 90 love . --smoke

# Plays a whole campaign with the reference solver, every screen rendered.
soak:
	@timeout -k 5 180 love . --soak

# Every tutorial step, walked through the real input callbacks.
tutorial:
	@timeout -k 5 90 love . --tut

# Peak and RMS of every synthesised sound.
audio:
	@timeout -k 5 120 love . --audio

shots:
	@timeout -k 5 120 love . --shot && echo "written to $$HOME/.local/share/love/augment/"

dist:
	@mkdir -p dist
	@zip -9 -r dist/augment.love main.lua conf.lua src -x '*.git*' >/dev/null
	@echo "dist/augment.love  ($$(du -h dist/augment.love | cut -f1))"

clean:
	rm -rf dist
