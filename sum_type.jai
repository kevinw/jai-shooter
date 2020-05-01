#import "Basic";

// An experiment in creating a "sum type" of sorts, that generates a "TypeTag" enum and a
// struct with a union of values for the types you specify.
//
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
            name := it.name;
            type_name := get_type_name(it.type);
            print_to_builder(*builder, "    set :: inline (this: $T, value: %) {\n", type_name);
            print_to_builder(*builder, "        this.values.% = value;\n", it.name);
            print_to_builder(*builder, "        this.type = TagType._%;\n", type_name);
            print_to_builder(*builder, "    };\n");
        }

        // .get
        print_to_builder(*builder, "    get :: inline (this: $T, $V: Type) -> V {\n");
        for info.members {
            type_name := get_type_name(it.type);
            print_to_builder(*builder, "        #if V == % {\n", type_name);
            print_to_builder(*builder, "            assert(this.type == TagType._%);\n", type_name);
            print_to_builder(*builder, "            return this.values.%;\n", it.name);
            print_to_builder(*builder, "        }\n");
        }
        print_to_builder(*builder, "        assert(false, \"This sum type does not that type.\");\n");
        print_to_builder(*builder, "    }\n");

        // .try_get
        print_to_builder(*builder, "    try_get :: inline (this: $T, $V: Type) -> (V, bool) {\n");
        for info.members {
            type_name := get_type_name(it.type);
            print_to_builder(*builder, "        #if V == % {\n", type_name);
            print_to_builder(*builder, "            if this.type == TagType._% {\n", type_name);
            print_to_builder(*builder, "                return this.values.%, true;\n", it.name);
            print_to_builder(*builder, "            } else {\n");
            print_to_builder(*builder, "                ret_val: %;\n", type_name);
            print_to_builder(*builder, "                return ret_val, false;\n");
            print_to_builder(*builder, "            }\n");
            print_to_builder(*builder, "        }\n");
        }
        print_to_builder(*builder, "    }\n");

        return builder_to_string(*builder);
    }
}

// This is just an example struct.
My_Other_Struct :: struct {
    foo: int;
    bar: int;
}

main :: () {

    // Here we create a "sum type" by passing a union describing the types we want.
    // The names of the fields in the union are unimportant--what's generated is a struct
    // with a "values" field whose type is this union, and a "TagType" enum for keeping
    // track of which union member is the "active" one.

    // TODO: is there a way to forgo naming the members of a union?
    Foo :: Sum_Type(union {
        i: int;
        f: float;
        other: My_Other_Struct; 
    });

    f: Foo;

    // Use .set with one of the value types to simultaneously set the union
    // value, and the enum tag type.
    Foo.set(*f, 33.0);
    assert(f.type == Foo.TagType._float, "expected Foo to have a float tag");
    assert(Foo.get(*f, float) == 33.0);

    // Use .set to change the value, and the type.
    Foo.set(*f, 42);
    assert(Foo.get(*f, int) == 42);
    assert(f.type == Foo.TagType._int);

    // If you uncomment the line below, it will panic, since our Foo Sum_Type
    // doesn't have 'bool' as a "member type"
    // Foo.get(*f, bool);

    // You can use try_get, which will return an "ok" value if your sum_type had that type.
    int_val, ok := Foo.try_get(*f, int);
    assert(ok);
    assert(int_val == 42);

    // Here we should see 'ok' as false, since the sum type is holding an int currently.
    float_val, float_ok := Foo.try_get(*f, float);
    assert(!float_ok, "since Foo is currently containing an int, 'ok' should have returned false!"); 

    // Checking the generated type tag in an if switch:
    {
        using f.TagType;
        if f.type == {
            case _float; print("f is a float with value %\n", Foo.get(*f, float));
            case _int;   print("f is an int with value %\n", Foo.get(*f, int));
        }
    }

    print("f: %\n", f);
}

// TODO: this is broken and wrong. How to resolve the qualified names of types in a #run_and_expand
// macro? What happens if structs are in namespaces, etc? Does Program_Print have the answer?
get_type_name :: (tinfo: *Type_Info) -> string {
    using Type_Info_Tag;
    if tinfo.type == {
        case FLOAT; return "float";
        case INTEGER; return "int";
        case STRUCT;
            tinfo_struct := cast(*Type_Info_Struct)tinfo;
            return tinfo_struct.name;
    }

    print("ERROR: %\n", tinfo.type);
    assert(false);
    return "XXX";
}