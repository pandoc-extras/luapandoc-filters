LUA = $(wildcard filters/*.lua)
MD = $(patsubst %.lua,%.md,$(LUA))
NATIVE = $(patsubst %.lua,%.native,$(LUA))
TEST = $(patsubst filters/%.lua,test-%,$(LUA))

all: $(NATIVE)

test: $(TEST)

%.native: %.lua %.md
	pandoc --lua-filter=$< $*.md -t native > $@

test-%: filters/%.native filters/%.lua filters/%.md
	@if [[ -z $$(pandoc --lua-filter=filters/$*.lua filters/$*.md -t native | diff -q - $<) ]]; then echo "$* test passed."; exit 0; else echo "$* test failed"; exit 1; fi
