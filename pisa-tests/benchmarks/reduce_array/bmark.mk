reduce_array_c_src = \
	reduce_array.c \

reduce_array_pisa_src = \

reduce_array_run_files = \

reduce_array_c_objs     = $(patsubst %.c, reduce_array/%.o, $(reduce_array_c_src))
reduce_array_pisa_objs = $(patsubst %.S, reduce_array/%.o, $(reduce_array_pisa_src))

reduce_array_pisa_bin = reduce_array/reduce_array.pisa
$(reduce_array_pisa_bin) : $(reduce_array_c_objs) $(reduce_array_pisa_objs)
	$(PISA_LINK) $(reduce_array_c_objs) $(reduce_array_pisa_objs) -o $(reduce_array_pisa_bin) $(PISA_LINK_OPTS)

.PHONY: reduce_array_pisa_install
reduce_array_pisa_install: $(reduce_array_pisa_bin)
	mkdir -p reduce_array/install
	cp -f $(reduce_array_pisa_bin) $(reduce_array_run_files) reduce_array/install

junk += $(reduce_array_c_objs) $(reduce_array_pisa_objs) \
        $(reduce_array_pisa_bin) reduce_array/install
