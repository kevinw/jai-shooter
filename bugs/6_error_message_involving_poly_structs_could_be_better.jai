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

        // Values union
        print_to_builder(*builder, "    values: union {\n");
        for * member: info.members {
            name := copy_string(member.name);
            print_to_builder(*builder, "        % : %;\n", name, get_type_name(member.type));
        }
        print_to_builder(*builder, "    };\n");


        // TypeTag enum
        print_to_builder(*builder, "    TagType :: enum {\n");
        for * member: info.members {
            type_name := get_type_name(member.type);
            print_to_builder(*builder, "        _%;\n", type_name);
        }
        print_to_builder(*builder, "    };\n");
        print_to_builder(*builder, "    type: TagType;\n");

        // .set overloads
        for info.members {
            type_name := get_type_name(it.type);
            print_to_builder(*builder, "    set :: (this: $T, value: %) {\n", type_name);
            print_to_builder(*builder, "        this.values.% = value;\n", it.name);
            print_to_builder(*builder, "        this.type = TagType._%;\n", type_name);
            print_to_builder(*builder, "    };\n");
        }

        // .get
        print_to_builder(*builder, "    get :: (this: $T, $V: Type) -> V {\n");
        for info.members {
            type_name := get_type_name(it.type);
            print_to_builder(*builder, "        #if V == % {\n", type_name);
            print_to_builder(*builder, "            assert(this.type == TagType._%);\n", type_name);
            print_to_builder(*builder, "            return this.values.%;\n", it.name);
            print_to_builder(*builder, "        }\n");
        }
        print_to_builder(*builder, "    assert(false, \"This sum type does not that type.\");\n");
        print_to_builder(*builder, "    }\n");

        return builder_to_string(*builder);
    }
}


main :: () {
    Foo :: Sum_Type(union {
        i: int;
        f: float;
    });

    f: Foo;
    Foo.set(*f, 33.0);
    assert(f.type == Foo.TagType._float, "expected Foo to have a float tag");
    assert(Foo.get(*f, float) == 33.0);

    Foo.set(*f, 42);
    assert(Foo.get(*f, int) == 42);

    //assert(Foo.get(*f, bool) == true); // panics--sum type doesn't have 'bool'

    bool_val, ok := Foo.try_get(*f, *val);
    assert(!ok);

    int_val, ok := Foo.try_get(*f, *val);
    assert(ok);
    assert(int_val == 42);

    print("f:\n");
    print("%\n", f);

}