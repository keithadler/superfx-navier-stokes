DEMO  = ns
ROM   = build/$(DEMO).sfc
CA65  = ca65 --cpu 65816 -I build --bin-include-dir build
LD65  = ld65

all: $(ROM)
	cp $(ROM) web/rom.sfc

src/font.inc: tools/mkfont.py
	python3 tools/mkfont.py

src/tables.inc: tools/gentables.py
	python3 tools/gentables.py

src/ns_tables.inc: tools/nsmodel.py
	python3 tools/nsmodel.py

build/%.bin build/%.inc: src/%.gsu tools/gsuasm.py
	@mkdir -p build
	python3 tools/gsuasm.py $< build/$*.bin build/$*.inc

build/main.o: src/main.s src/font.inc src/tables.inc build/cube.bin build/cube.inc lorom.cfg
	$(CA65) -g -o $@ src/main.s

build/ns.o: src/ns.s src/font.inc src/ns_tables.inc build/ns.bin build/ns.inc lorom.cfg
	$(CA65) -g -o $@ src/ns.s

src/sprites.inc: tools/sprites.py
	python3 tools/sprites.py

src/bg.inc: tools/bgmap.py
	python3 tools/bgmap.py

build/game.o: src/game.s src/font.inc src/ns_tables.inc src/sprites.inc src/bg.inc build/ns.bin build/ns.inc lorom.cfg
	$(CA65) -g -o $@ src/game.s

build/cube.sfc: build/main.o
	$(LD65) -C lorom.cfg -Ln build/cube.lbl -m build/cube.map -o $@ $<
	python3 tools/fixsum.py $@

build/ns.sfc: build/ns.o
	$(LD65) -C lorom.cfg -Ln build/ns.lbl -m build/ns.map -o $@ $<
	python3 tools/fixsum.py $@

build/game.sfc: build/game.o
	$(LD65) -C lorom.cfg -Ln build/game.lbl -m build/game.map -o $@ $<
	python3 tools/fixsum.py $@

serve:
	python3 serve.py 8794

clean:
	rm -rf build web/rom.sfc

.PHONY: all serve clean
