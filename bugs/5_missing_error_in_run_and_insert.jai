#import "Basic";

get_type_name :: (tinfo: *Type_Info) -> string {
    using Type_Info_Tag;
    if tinfo.type == {
        case FLOAT; return "float";
        case INTEGER; return "int";
    }

    return "XXX";
}

Sum_Type :: struct (T: Type) {
    #run_and_insert {
        info := type_info(T);

        builder: String_Builder;
        defer free_buffers(*builder);

        // Values enum
        
        print_to_builder(*builder, "    values: union {\n");
        for * member: info.members {
            name := copy_string(member.name);
            print_to_builder(*builder, "        % : %;\n", name, get_type_name(member.type));
        }
        print_to_builder(*builder, "    };\n");


        // Type enum
        print_to_builder(*builder, "    TagType :: enum {\n");
        for * member: info.members {
            type_name := get_type_name(member.type);
            print_to_builder(*builder, "        _%;\n", type_name);
        }
        print_to_builder(*builder, "    };\n");
        print_to_builder(*builder, "    type: TagType;\n");

        print_to_builder(*builder, "    set :: (this: $T, value: $V) {\n");

        for * member: info.members {
            pfdasjlfdasp(*builder, "// foo\n");
        }

        print_to_builder(*builder, "    }\n");


        return builder_to_string(*builder);
    }
}

set_val :: (sum_type: $T, value: $V) {
    actual_struct_tinfo := cast(*Type_Info_Struct)type_info(T).pointer_to;

    print("?? %", <<actual_struct_tinfo);
    for member: actual_struct_tinfo.members {
        if member.name == "TagType" {
            enum_type := cast(*Type_Info_Enum)member.type;
            print("  member: % %\n", <<enum_type, member);
        }
    }
    print("polymorph_source_struct %", <<actual_struct_tinfo.polymorph_source_struct);
}

main :: () {
    Foo :: Sum_Type(union {
        int_value: int;
        float_value: float;
    });

    f: Foo;
    Foo.set(*f, 33.0);
    assert(f.type == Foo.TagType._float, "expected Foo to have a float tag");

    print("f:\n");
    print("%\n", f);

}