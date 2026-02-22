.PHONY: generate build clean open

generate:
	xcodegen generate

build: generate
	xcodebuild build \
		-project LLMLocalExample.xcodeproj \
		-scheme LLMLocalExample \
		-destination 'generic/platform=iOS Simulator'

clean:
	rm -rf DerivedData LLMLocalExample.xcodeproj

open: generate
	open LLMLocalExample.xcodeproj
