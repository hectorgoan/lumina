.PHONY: build app run clean

build:
	swift build

app:
	scripts/build-app.sh release

run: app
	-pkill -x Lumina
	open build/Lumina.app

clean:
	rm -rf .build build
