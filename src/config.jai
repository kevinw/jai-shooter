#import "Text_File_Handler";
#import "Reflection";
Log :: #import "Log";

for_expansion :: (handler: *Text_File_Handler, body: Code, pointer: bool, reverse: bool) #expand {
    #assert(!pointer && !reverse);

    while true {
        line, found := consume_next_line(handler);
        if !found break;

        `it := line;
        #insert body;
    }
}


//
// parse a config file and write values from it into the `target` struct
//
parse_config_file :: (target: $T, config_filename: string) {
    handler: Text_File_Handler;
    defer deinit(*handler);

    start_file(*handler, "config", config_filename, "config parsing", false);
    if handler.failed {
        Log.error();
        Log.print("Could not find '%'\n", config_filename);
        return;
    }

    // TODO: recurse into sub-structs with "." or something?
    target_tinfo := type_info(type_of(<< target));

    for line: *handler {
        key_name, rhs := break_by_spaces(line);
        if !rhs {
            error(handler, "Expected a space after the key\n");
            continue;
        }

        //member := get_struct_field_info(target_tinfo, key_name);
        member := get_field(target_tinfo, key_name);
        if member == null {
            Log.error();
            Log.print("invalid config field '%'\n", key_name);
            continue;
        }

        any: Any;
        any.value_pointer = (cast(*u8)target) + member.offset_in_bytes;
        any.type = member.type;
        set_value_from_string(any, rhs);
    }
}
