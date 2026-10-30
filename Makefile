.PHONY: all test clean
all: build/tesmart-hid-block

build/tesmart-hid-block: src/main.m
	mkdir -p build
	xcrun clang -fobjc-arc -Wall -Wextra -Werror -O2 -framework Foundation -framework IOKit -framework IOUSBHost $< -o $@
	codesign --force --sign - $@

test: all
	./build/tesmart-hid-block --self-test
	./build/tesmart-hid-block --help
	! ./build/tesmart-hid-block --capture --duration invalid
	! ./build/tesmart-hid-block --capture --duration -1
	! ./build/tesmart-hid-block --unknown
	bash -n scripts/install.sh scripts/uninstall.sh scripts/status.sh
	plutil -lint launchd/net.steinbok.tesmart-hid-block.plist

clean:
	rm -f build/tesmart-hid-block
