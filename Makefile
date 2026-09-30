.PHONY: run mac-run mac-install hooks test bench layout smoke soak tutorial audio shots dist install export clean

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

# Wires githooks/post-commit so the app in ~/Applications rebuilds itself
# after every commit instead of quietly drifting behind the checkout.
hooks:
	@git config core.hooksPath githooks
	@echo "post-commit will now run mac-install automatically"

# Pure Lua rules, persistence and economy.
test:
	@for f in main.lua conf.lua src/*.lua src/data/*.lua; do $(LUA) -e "assert(loadfile('$$f'))" || exit 1; done
	@$(LUA) test/test_graph.lua
	@$(LUA) test/test_city.lua
	@$(LUA) test/test_generation.lua
	@$(LUA) test/test_balance.lua
	@$(LUA) test/test_company.lua
	@$(LUA) test/test_experience.lua
	@$(LUA) test/test_comfort.lua
	@$(LUA) test/test_people.lua
	@$(LUA) test/test_save_location.lua
	@$(LUA) test/test_save_failures.lua
	@$(LUA) test/test_infrastructure.lua
	@$(LUA) test/test_resilience.lua
	@$(LUA) test/test_ideas.lua
	@$(LUA) test/test_terrain_life.lua
	@$(LUA) test/test_crew.lua

# What an endless map costs to solve. Kept out of `test` because it is a timing
# measurement and a loaded machine is not a regression, but watched in CI.
bench:
	@$(LUA) test/bench_flow.lua

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

# Every string the interface draws, and any two that land on the same pixels.
# A measurement, not a test: read the list and fix what is real.
layout:
	@$(TESTENV) timeout -k 5 180 $(LOVE) . --shot --audit 2>&1 | sed -n '/^layout:/,$$p'
	@$(TESTENV) timeout -k 5 180 $(LOVE) . --smoke --audit 2>&1 | sed -n '/^layout:/,$$p'

shots:
	@$(TESTENV) timeout -k 5 120 $(LOVE) . --shot

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
	@cp assets/net-profit.png dist/portable/assets/
	@cd dist/portable && zip -9 -r ../net-profit-portable.zip . >/dev/null
	@echo "dist/net-profit-portable.zip (game + installer)"
	@echo "dist/net-profit.bundle (committed source + Git history)"

clean:
	rm -rf dist
