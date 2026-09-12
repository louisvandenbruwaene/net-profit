.PHONY: run mac-run mac-install test smoke soak tutorial audio shots dist install export clean

# The headless suites are plain Lua and run under whatever interpreter is here:
# 5.4 if it is installed, otherwise 5.3, plain lua, or LuaJIT.
LUA := $(shell command -v lua5.4 || command -v lua5.3 || command -v lua || command -v luajit)

# LOVE is on PATH on Linux and inside the app bundle on macOS.
LOVE := $(shell command -v love || echo /Applications/love.app/Contents/MacOS/love)

# Test runs are silent and open their window offscreen (see conf.lua), so a
# suite can be run without taking over the desktop.
TESTENV := SDL_AUDIODRIVER=dummy

run:
	@$(LOVE) .

mac-run:
	@open -a "LOVE" "$(CURDIR)"

mac-install:
	@sh macos/install.sh

# Pure Lua rules, persistence, economy, and archived contract regressions.
test:
	@$(LUA) test/test_graph.lua
	@$(LUA) test/test_contract.lua
	@$(LUA) test/test_city.lua
	@$(LUA) test/test_generation.lua
	@$(LUA) test/test_company.lua
	@$(LUA) test/test_experience.lua
	@$(LUA) test/test_save_location.lua

# Input paths, driven through the real love callbacks.
smoke:
	@$(TESTENV) timeout -k 5 90 $(LOVE) . --smoke

# Runs more than 60 company days, rendering screens and checking save round trips.
soak:
	@$(TESTENV) timeout -k 5 180 $(LOVE) . --soak

# Walks the opening company actions through the real input callbacks.
tutorial:
	@$(TESTENV) timeout -k 5 90 $(LOVE) . --tut

# Peak and RMS of every synthesised sound.
audio:
	@$(TESTENV) timeout -k 5 120 $(LOVE) . --audio

shots:
	@$(TESTENV) timeout -k 5 120 $(LOVE) . --shot && echo "written to $$HOME/.local/share/love/net-profit/"

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
