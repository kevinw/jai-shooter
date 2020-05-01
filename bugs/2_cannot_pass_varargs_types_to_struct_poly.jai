#import "Basic";

Sum_Type :: struct (types: ..Type) {

    #run_and_insert {
        info := type_info(T);
    
        builder: String_Builder;
        defer free_buffers(*builder);
        
        /*
        for * member: info.members {
            name := copy_string(member.name);
            print_to_builder(*builder, "    % := false;\n", name);
        }
        */

        for types {
            print_to_builder(*builder, "    %_value: %\n", it.name, it.name);
        }

        return builder_to_string(*builder);
    }
}

main :: () {

    print("Hello, Jai\n");
    Foo :: Sum_Type(int, float);

    f: Foo;
    print("%\n", f);
    
}