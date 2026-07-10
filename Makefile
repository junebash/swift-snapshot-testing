SCHEME = swift-snapshot-testing-Package
PLATFORM_IOS = iOS Simulator,name=iPhone 17 Pro,OS=26.5

test-swift:
	swift test

test-macos:
	set -o pipefail && \
	xcodebuild test \
		-scheme $(SCHEME) \
		-destination platform="macOS"

# References were recorded on this exact simulator; other devices/OS versions will
# produce pixel drift.
test-ios:
	set -o pipefail && \
	xcodebuild test \
		-scheme $(SCHEME) \
		-destination platform="$(PLATFORM_IOS)"

test-linux:
	docker run \
		--rm \
		-v "$(PWD):$(PWD)" \
		-w "$(PWD)" \
		swift:6.2 \
		bash -c 'swift test'

format:
	swift format \
		--ignore-unparsable-files \
		--in-place \
		--recursive \
		./Package.swift ./Sources ./Tests

test-all: test-swift test-ios
