.PHONY: run test smoke soak tutorial audio shots dist install export clean

run:
	love .

# Pure Lua rules, persistence, economy, and archived contract regressions.
test:
	@lua5.4 test/test_graph.lua
	@lua5.4 test/test_contract.lua
	@lua5.4 test/test_city.lua
	@lua5.4 test/test_company.lua

# Input paths, driven through the real love callbacks.
smoke:
	@timeout -k 5 90 love . --smoke

# Runs more than 60 company days, rendering screens and checking save round trips.
soak:
	@timeout -k 5 180 love . --soak

# Walks the opening company actions through the real input callbacks.
tutorial:
	@timeout -k 5 90 love . --tut

# Peak and RMS of every synthesised sound.
audio:
	@timeout -k 5 120 love . --audio

shots:
	@timeout -k 5 120 love . --shot && echo "written to $$HOME/.local/share/love/net-profit/"

dist:
	@mkdir -p dist
	@zip -FS -9 -r dist/net-profit.love main.lua conf.lua src assets -x '*.git*' >/dev/null
	@echo "dist/net-profit.love"

install: dist
	@sh install-linux.sh

export: dist
	@git bundle create dist/net-profit.bundle --all
	@mkdir -p dist/portable/assets
	@cp dist/net-profit.love dist/portable/net-profit.love
	@cp README.md install-linux.sh dist/portable/
	@cp assets/net-profit.svg dist/portable/assets/
	@cd dist/portable && zip -9 -r ../net-profit-portable.zip . >/dev/null
	@echo "dist/net-profit-portable.zip (game + installer)"
	@echo "dist/net-profit.bundle (committed source + Git history)"

clean:
	rm -rf dist
