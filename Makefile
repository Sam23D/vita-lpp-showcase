# lpp-vita showcase - build, test, run.
#   make            assets + mock test (safe & unsafe) + both VPKs
#   make test       headless run of the whole app against the lpp-vita mock
#   make vpk        dist/lpp-showcase.vpk           (safe eboot)
#   make vpk-unsafe dist/lpp-showcase-unsafe.vpk    (unsafe eboot: Registry, plugins, installApp...)
#   make api        regenerate tools/mock/lpp_api.lua from a lpp-vita checkout (LPP_SRC=path)
#   make send VITA=192.168.1.x   upload the VPK to ux0:/data via VitaShell's FTP (port 1337)

PY      ?= python3
LUAJIT  ?= luajit
LPP_SRC ?= .lpp-vita-src
VITA    ?=

.PHONY: all assets stage test test-safe test-unsafe vpk vpk-unsafe api send clean

all: test vpk vpk-unsafe

assets:
	$(PY) tools/make_assets.py

stage:
	$(PY) tools/build.py --stage-only
	$(PY) tools/build.py --stage-only --unsafe

test: stage test-safe test-unsafe

test-safe:
	$(LUAJIT) tools/mock/run.lua --quiet 2>build/run_safe.err | tail -6

test-unsafe:
	$(LUAJIT) tools/mock/run.lua --unsafe --quiet 2>build/run_unsafe.err | tail -6

vpk:
	$(PY) tools/build.py

vpk-unsafe:
	$(PY) tools/build.py --unsafe

api:
	$(PY) tools/gen_api.py $(LPP_SRC)

send: vpk
	@test -n "$(VITA)" || (echo "usage: make send VITA=<vita-ip>  (start FTP in VitaShell with SELECT)"; exit 1)
	curl -T dist/lpp-showcase.vpk ftp://$(VITA):1337/ux0:/data/

clean:
	rm -rf build dist
