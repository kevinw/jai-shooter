#import "Basic";

Sum_Type :: struct (T: Type) {

    #run_and_insert {
        info := type_info(T);
    
        builder: String_Builder;
        defer free_buffers(*builder);
        
        for * member: info.members {
            // name := copy_string(member.name); // TODO: without this, compiler hits a circular dependency
            print_to_builder(*builder, "    % := false;\n", name);
        }

        return builder_to_string(*builder);
    }
}

main :: () {

    print("Hello, Jai\n");
    Foo :: Sum_Type(union {
        i: int;
        f: float;
    });


    f: Foo;
    print("%\n", f);
    
}