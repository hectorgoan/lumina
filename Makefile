.PHONY: build app run clean

build:
	swift build

app:
	scripts/build-app.sh release

run: app
	-pkill -x Lumina
	@while pgrep -x Lumina >/dev/null; do sleep 0.1; done
	open build/Lumina.app

clean:
	rm -rf .build build
