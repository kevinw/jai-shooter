#import "Basic";

Test :: struct (T: Type) {
    #run_and_insert {
        info := type_info(T);
    
        builder: String_Builder;
        defer free_buffers(*builder);

        this.isnt.right; // XXX: This should throw an error, but doesn't!

        return builder_to_string(*builder);
    }
}

main :: () {
    Foo :: Test(struct {});
    f: Foo;
    print("f: %\n", f);
}