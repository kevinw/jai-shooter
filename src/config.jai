#import "Text_File_Handler";
#import "Reflection";
Log :: #import "Log";

parse_config_file :: (settings: $T, config_filename: string) {
    handler: Text_File_Handler;
    defer deinit(*handler);

    start_file(*handler, "config", config_filename, "config parsing", false);
    if handler.failed {
        print("Could not find '%'\n", config_filename);
        return;
    }

    // TODO: recurse into sub-structs with "." or something?
    target_tinfo := type_info(type_of(<< settings));

    while true {
        line, found := consume_next_line(*handler);
        if !found break;

        key_name, rhs := break_by_spaces(line);
        if !rhs {
            error(handler, "Expected a space after the key\n");
            continue;
        }

        member := get_struct_field_info(target_tinfo, key_name);
        if member == null {
            Log.error();
            Log.print("invalid config field '%'\n", key_name);
            continue;
        }

        any: Any;
        any.value_pointer = (cast(*u8)settings) + member.offset_in_bytes;
        any.type = member.type;
        set_value_from_string(any, rhs);
    }
}
